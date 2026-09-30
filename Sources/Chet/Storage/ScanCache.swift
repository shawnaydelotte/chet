import Foundation
import SQLite3

/// Persists the FileNode tree to SQLite for instant app launch.
/// Uses raw libsqlite3 C API — ships with macOS, zero dependencies.
final class ScanCache: @unchecked Sendable {
    private var db: OpaquePointer?

    static let shared = ScanCache()

    private static var dbURL: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = caches.appendingPathComponent("com.chet.diskanalyzer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("scans.db")
    }

    // MARK: - Open / Close

    func open() -> Bool {
        if db != nil { return true }
        let path = Self.dbURL.path(percentEncoded: false)
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            return false
        }
        // WAL mode for concurrent reads during background writes
        exec("PRAGMA journal_mode=WAL")
        exec("PRAGMA synchronous=NORMAL")
        exec("PRAGMA cache_size=-64000") // 64MB cache
        exec("PRAGMA temp_store=MEMORY")
        createTables()
        return true
    }

    func close() {
        if let db {
            sqlite3_close(db)
            self.db = nil
        }
    }

    deinit { close() }

    // MARK: - Schema

    private func createTables() {
        exec("""
            CREATE TABLE IF NOT EXISTS scan_meta (
                root_path TEXT PRIMARY KEY,
                scan_date REAL NOT NULL,
                fs_event_id INTEGER NOT NULL DEFAULT 0,
                total_files INTEGER DEFAULT 0,
                total_size INTEGER DEFAULT 0
            )
        """)

        exec("""
            CREATE TABLE IF NOT EXISTS nodes (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                parent_id INTEGER,
                path TEXT NOT NULL,
                name TEXT NOT NULL,
                is_directory INTEGER NOT NULL DEFAULT 0,
                category TEXT NOT NULL DEFAULT 'other',
                size INTEGER NOT NULL DEFAULT 0,
                logical_size INTEGER NOT NULL DEFAULT 0,
                file_count INTEGER NOT NULL DEFAULT 0,
                directory_count INTEGER NOT NULL DEFAULT 0,
                creation_date REAL,
                modification_date REAL,
                inode INTEGER DEFAULT 0,
                depth INTEGER NOT NULL DEFAULT 0,
                FOREIGN KEY(parent_id) REFERENCES nodes(id)
            )
        """)

        exec("CREATE INDEX IF NOT EXISTS idx_parent ON nodes(parent_id)")
        exec("CREATE UNIQUE INDEX IF NOT EXISTS idx_path ON nodes(path)")
        exec("CREATE INDEX IF NOT EXISTS idx_depth ON nodes(depth)")

        // Migrate: add depth column if missing (for DBs created before this change)
        exec("ALTER TABLE nodes ADD COLUMN depth INTEGER NOT NULL DEFAULT 0")
    }

    // MARK: - Save Tree

    /// Persist entire tree to DB in a single transaction. ~3-5s for 1M nodes.
    func saveTree(_ root: FileNode, rootPath: String, eventID: UInt64) {
        guard let db else { return }

        // Clear existing data for this root
        deleteNodes(withPathPrefix: rootPath)
        deleteScanMeta(rootPath: rootPath)

        exec("BEGIN TRANSACTION")

        // Insert metadata
        let metaSQL = "INSERT INTO scan_meta (root_path, scan_date, fs_event_id, total_files, total_size) VALUES (?, ?, ?, ?, ?)"
        var metaStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, metaSQL, -1, &metaStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(metaStmt, 1, rootPath, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(metaStmt, 2, Date().timeIntervalSince1970)
            sqlite3_bind_int64(metaStmt, 3, Int64(bitPattern: eventID))
            sqlite3_bind_int(metaStmt, 4, Int32(root.fileCount))
            sqlite3_bind_int64(metaStmt, 5, root.size)
            sqlite3_step(metaStmt)
        }
        sqlite3_finalize(metaStmt)

        // Prepare insert statement (reuse for all nodes)
        let insertSQL = """
            INSERT INTO nodes (parent_id, path, name, is_directory, category, size, logical_size,
                              file_count, directory_count, creation_date, modification_date, inode, depth)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        var insertStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &insertStmt, nil) == SQLITE_OK else {
            exec("ROLLBACK")
            return
        }
        defer { sqlite3_finalize(insertStmt) }

        // BFS traversal to insert in parent-first order (so parent_id is always valid)
        var queue: [(node: FileNode, parentDBID: Int64?, depth: Int)] = [(root, nil, 0)]
        var idx = 0

        while idx < queue.count {
            let (node, parentDBID, depth) = queue[idx]
            idx += 1

            sqlite3_reset(insertStmt)
            sqlite3_clear_bindings(insertStmt)

            if let pid = parentDBID {
                sqlite3_bind_int64(insertStmt, 1, pid)
            } else {
                sqlite3_bind_null(insertStmt, 1)
            }

            let nodePath = node.url.path(percentEncoded: false)
            sqlite3_bind_text(insertStmt, 2, nodePath, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(insertStmt, 3, node.name, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(insertStmt, 4, node.isDirectory ? 1 : 0)
            sqlite3_bind_text(insertStmt, 5, node.category.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(insertStmt, 6, node.size)
            sqlite3_bind_int64(insertStmt, 7, node.logicalSize)
            sqlite3_bind_int(insertStmt, 8, Int32(node.fileCount))
            sqlite3_bind_int(insertStmt, 9, Int32(node.directoryCount))

            if let cd = node.creationDate {
                sqlite3_bind_double(insertStmt, 10, cd.timeIntervalSince1970)
            } else {
                sqlite3_bind_null(insertStmt, 10)
            }
            if let md = node.modificationDate {
                sqlite3_bind_double(insertStmt, 11, md.timeIntervalSince1970)
            } else {
                sqlite3_bind_null(insertStmt, 11)
            }

            sqlite3_bind_int64(insertStmt, 12, 0)
            sqlite3_bind_int(insertStmt, 13, Int32(depth))

            sqlite3_step(insertStmt)
            let dbID = sqlite3_last_insert_rowid(db)

            for child in node.children {
                queue.append((child, dbID, depth + 1))
            }
        }

        exec("COMMIT")
    }

    // MARK: - Load Tree

    /// Reconstruct tree from DB. Loads all directories + files up to maxDepth.
    /// Returns (root, eventID) or nil if no cache.
    func loadTree(for rootPath: String, maxDepth: Int = 4) -> (FileNode, UInt64)? {
        guard let db else { return nil }

        // Load metadata
        var eventID: UInt64 = 0
        let metaSQL = "SELECT fs_event_id FROM scan_meta WHERE root_path = ?"
        var metaStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, metaSQL, -1, &metaStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(metaStmt, 1, rootPath, -1, SQLITE_TRANSIENT)
            if sqlite3_step(metaStmt) == SQLITE_ROW {
                eventID = UInt64(bitPattern: sqlite3_column_int64(metaStmt, 0))
            } else {
                sqlite3_finalize(metaStmt)
                return nil
            }
        }
        sqlite3_finalize(metaStmt)

        // Load only nodes up to maxDepth — typically ~6K-25K nodes.
        // Deeper nodes are loaded on demand via loadChildren().
        // Directories at maxDepth retain their aggregate sizes from scan.
        let loadSQL = """
            SELECT id, parent_id, path, name, is_directory, category,
                   size, logical_size, file_count, directory_count,
                   creation_date, modification_date
            FROM nodes
            WHERE (path = ? OR path LIKE ? ESCAPE '\\') AND depth <= ?
            ORDER BY id
        """
        var loadStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, loadSQL, -1, &loadStmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(loadStmt) }

        sqlite3_bind_text(loadStmt, 1, rootPath, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(loadStmt, 2, Self.descendantLikePattern(for: rootPath), -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(loadStmt, 3, Int32(maxDepth))

        var nodesById = [Int64: FileNode]()
        var root: FileNode?

        while sqlite3_step(loadStmt) == SQLITE_ROW {
            let dbID = sqlite3_column_int64(loadStmt, 0)
            let parentID: Int64? = sqlite3_column_type(loadStmt, 1) != SQLITE_NULL
                ? sqlite3_column_int64(loadStmt, 1) : nil
            let path = String(cString: sqlite3_column_text(loadStmt, 2))
            let name = String(cString: sqlite3_column_text(loadStmt, 3))
            let isDir = sqlite3_column_int(loadStmt, 4) != 0
            let catStr = String(cString: sqlite3_column_text(loadStmt, 5))
            let category = FileCategory(rawValue: catStr) ?? .other

            let node = FileNode(
                url: URL(fileURLWithPath: path, isDirectory: isDir),
                name: name,
                isDirectory: isDir,
                category: category
            )
            node.size = sqlite3_column_int64(loadStmt, 6)
            node.logicalSize = sqlite3_column_int64(loadStmt, 7)
            node.allocatedSize = node.size
            node.fileCount = Int(sqlite3_column_int(loadStmt, 8))
            node.directoryCount = Int(sqlite3_column_int(loadStmt, 9))

            if sqlite3_column_type(loadStmt, 10) != SQLITE_NULL {
                node.creationDate = Date(timeIntervalSince1970: sqlite3_column_double(loadStmt, 10))
            }
            if sqlite3_column_type(loadStmt, 11) != SQLITE_NULL {
                node.modificationDate = Date(timeIntervalSince1970: sqlite3_column_double(loadStmt, 11))
            }

            if let pid = parentID, let parentNode = nodesById[pid] {
                parentNode.children.append(node)
                node.parent = parentNode
            } else if root == nil {
                root = node
            }

            nodesById[dbID] = node
        }

        guard let rootNode = root else { return nil }
        FileNode.sortTreeChildrenBySize(from: rootNode)
        return (rootNode, eventID)
    }

    /// Load children of a specific directory from DB (for lazy expansion).
    func loadChildren(forPath dirPath: String) -> [FileNode] {
        guard let db else { return [] }

        // Find the parent's DB id
        var parentDBID: Int64?
        let findSQL = "SELECT id FROM nodes WHERE path = ?"
        var findStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, findSQL, -1, &findStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(findStmt, 1, dirPath, -1, SQLITE_TRANSIENT)
            if sqlite3_step(findStmt) == SQLITE_ROW {
                parentDBID = sqlite3_column_int64(findStmt, 0)
            }
        }
        sqlite3_finalize(findStmt)

        guard let pid = parentDBID else { return [] }

        let loadSQL = """
            SELECT path, name, is_directory, category, size, logical_size,
                   file_count, directory_count, creation_date, modification_date
            FROM nodes WHERE parent_id = ? ORDER BY size DESC
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, loadSQL, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, pid)

        var children = [FileNode]()
        while sqlite3_step(stmt) == SQLITE_ROW {
            let path = String(cString: sqlite3_column_text(stmt, 0))
            let name = String(cString: sqlite3_column_text(stmt, 1))
            let isDir = sqlite3_column_int(stmt, 2) != 0
            let catStr = String(cString: sqlite3_column_text(stmt, 3))
            let category = FileCategory(rawValue: catStr) ?? .other

            let node = FileNode(
                url: URL(fileURLWithPath: path, isDirectory: isDir),
                name: name,
                isDirectory: isDir,
                category: category
            )
            node.size = sqlite3_column_int64(stmt, 4)
            node.logicalSize = sqlite3_column_int64(stmt, 5)
            node.allocatedSize = node.size
            node.fileCount = Int(sqlite3_column_int(stmt, 6))
            node.directoryCount = Int(sqlite3_column_int(stmt, 7))

            if sqlite3_column_type(stmt, 8) != SQLITE_NULL {
                node.creationDate = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 8))
            }
            if sqlite3_column_type(stmt, 9) != SQLITE_NULL {
                node.modificationDate = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 9))
            }

            children.append(node)
        }
        return children
    }

    // MARK: - Incremental Updates

    func updateMeta(rootPath: String, eventID: UInt64) {
        guard let db else { return }
        let sql = "UPDATE scan_meta SET fs_event_id = ?, scan_date = ? WHERE root_path = ?"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, Int64(bitPattern: eventID))
            sqlite3_bind_double(stmt, 2, Date().timeIntervalSince1970)
            sqlite3_bind_text(stmt, 3, rootPath, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    func deleteNode(path: String) {
        guard let db else { return }
        let sql = "DELETE FROM nodes WHERE path = ?"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, path, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    func deleteSubtree(path: String) {
        guard let db else { return }
        let childPattern = Self.descendantLikePattern(for: path)

        let childSQL = "DELETE FROM nodes WHERE path LIKE ? ESCAPE '\\'"
        var childStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, childSQL, -1, &childStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(childStmt, 1, childPattern, -1, SQLITE_TRANSIENT)
            sqlite3_step(childStmt)
        }
        sqlite3_finalize(childStmt)

        let selfSQL = "DELETE FROM nodes WHERE path = ?"
        var selfStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, selfSQL, -1, &selfStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(selfStmt, 1, path, -1, SQLITE_TRANSIENT)
            sqlite3_step(selfStmt)
        }
        sqlite3_finalize(selfStmt)
    }

    func upsertNode(_ node: FileNode, parentPath: String?) {
        guard let db else { return }

        // Find parent_id
        var parentID: Int64?
        if let pp = parentPath {
            let findSQL = "SELECT id FROM nodes WHERE path = ?"
            var findStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, findSQL, -1, &findStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(findStmt, 1, pp, -1, SQLITE_TRANSIENT)
                if sqlite3_step(findStmt) == SQLITE_ROW {
                    parentID = sqlite3_column_int64(findStmt, 0)
                }
            }
            sqlite3_finalize(findStmt)
        }

        let nodePath = node.url.path(percentEncoded: false)
        let depth = node.depth
        let sql = """
            INSERT OR REPLACE INTO nodes
            (parent_id, path, name, is_directory, category, size, logical_size,
             file_count, directory_count, creation_date, modification_date, inode, depth)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        if let pid = parentID {
            sqlite3_bind_int64(stmt, 1, pid)
        } else {
            sqlite3_bind_null(stmt, 1)
        }
        sqlite3_bind_text(stmt, 2, nodePath, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, node.name, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 4, node.isDirectory ? 1 : 0)
        sqlite3_bind_text(stmt, 5, node.category.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 6, node.size)
        sqlite3_bind_int64(stmt, 7, node.logicalSize)
        sqlite3_bind_int(stmt, 8, Int32(node.fileCount))
        sqlite3_bind_int(stmt, 9, Int32(node.directoryCount))

        if let cd = node.creationDate {
            sqlite3_bind_double(stmt, 10, cd.timeIntervalSince1970)
        } else { sqlite3_bind_null(stmt, 10) }
        if let md = node.modificationDate {
            sqlite3_bind_double(stmt, 11, md.timeIntervalSince1970)
        } else { sqlite3_bind_null(stmt, 11) }

        sqlite3_bind_int64(stmt, 12, 0)
        sqlite3_bind_int(stmt, 13, Int32(depth))
        sqlite3_step(stmt)
    }

    /// Insert or update an entire subtree (parent-first BFS so parent_id resolves).
    func upsertSubtree(_ root: FileNode, parentPath: String) {
        var queue: [(node: FileNode, parentPath: String)] = [(root, parentPath)]
        var index = 0
        while index < queue.count {
            let (node, path) = queue[index]
            index += 1
            upsertNode(node, parentPath: path)
            let nodePath = node.url.path(percentEncoded: false)
            for child in node.children {
                queue.append((child, nodePath))
            }
        }
    }

    // MARK: - Helpers

    /// Descendants only (`path/...`), with `%`, `_`, and `\` escaped so sibling
    /// prefixes such as `/tmp/foo` vs `/tmp/foobar` or `a_b` vs `axb` do not match.
    static func descendantLikePattern(for path: String) -> String {
        var escaped = String()
        escaped.reserveCapacity(path.count + 2)
        let specials: Set<Character> = ["\\", "%", "_"]
        for character in path {
            if specials.contains(character) {
                escaped.append("\\")
            }
            escaped.append(character)
        }
        escaped.append("/%")
        return escaped
    }

    func removeCachedScan(rootPath: String) {
        deleteSubtree(path: rootPath)
        deleteScanMeta(rootPath: rootPath)
    }

    private func deleteNodes(withPathPrefix prefix: String) {
        guard let db else { return }
        let sql = "DELETE FROM nodes WHERE path = ? OR path LIKE ? ESCAPE '\\'"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, prefix, -1, SQLITE_TRANSIENT)
            let descendant = Self.descendantLikePattern(for: prefix)
            sqlite3_bind_text(stmt, 2, descendant, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    private func deleteScanMeta(rootPath: String) {
        guard let db else { return }
        let sql = "DELETE FROM scan_meta WHERE root_path = ?"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, rootPath, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    @discardableResult
    private func exec(_ sql: String) -> Bool {
        guard let db else { return false }
        return sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }

    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
