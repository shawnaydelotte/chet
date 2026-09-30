import Foundation

final class DiskScanner: Sendable {

    /// Scan a directory tree using fts(3) for fast C-level traversal.
    /// Sizes are aggregated bottom-up during the scan (no post-processing needed).
    /// Supports cancellation via Task.isCancelled.
    func scan(
        url: URL,
        onProgress: @Sendable @escaping (_ filesScanned: Int, _ currentPath: String) -> Void
    ) -> FileNode {
        var rootPath = url.standardizedFileURL.path(percentEncoded: false)
        if rootPath.count > 1 && rootPath.hasSuffix("/") {
            rootPath = String(rootPath.dropLast())
        }
        let rootName = url.lastPathComponent.isEmpty ? "/" : url.lastPathComponent
        let root = FileNode(url: url, name: rootName, isDirectory: true, category: .other)

        var nodeMap = [String: FileNode]()
        nodeMap[rootPath] = root

        // Track seen inodes to avoid double-counting hardlinked files
        // (common in Xcode simulator caches, Homebrew, etc.)
        var seenInodes = Set<UInt64>()

        var count = 0
        let progressInterval = 5000

        let pathCStr = rootPath.withCString { strdup($0) }!
        defer { free(pathCStr) }

        var paths: [UnsafeMutablePointer<CChar>?] = [pathCStr, nil]
        guard let ftsStream = fts_open(&paths, FTS_PHYSICAL | FTS_XDEV | FTS_NOCHDIR, nil) else {
            return root
        }
        defer { fts_close(ftsStream) }

        while let entry = fts_read(ftsStream) {
            if Task.isCancelled { break }

            let info = Int32(entry.pointee.fts_info)
            let entryPath = String(cString: entry.pointee.fts_path)

            switch info {
            case FTS_D:
                // Directory pre-order: skip root (already created)
                if entryPath == rootPath { continue }

                let name = extractName(entry)
                let dirURL = URL(fileURLWithPath: entryPath, isDirectory: true)
                let category = FileClassifier.classify(name: name, isDirectory: true)
                let node = FileNode(url: dirURL, name: name, isDirectory: true, category: category)

                if let stat = entry.pointee.fts_statp {
                    node.modificationDate = Date(timeIntervalSince1970: TimeInterval(stat.pointee.st_mtimespec.tv_sec))
                    node.creationDate = Date(timeIntervalSince1970: TimeInterval(stat.pointee.st_birthtimespec.tv_sec))
                }

                let parentPath = (entryPath as NSString).deletingLastPathComponent
                if let parentNode = nodeMap[parentPath] {
                    parentNode.children.append(node)
                    node.parent = parentNode
                }
                nodeMap[entryPath] = node

                count += 1
                if count % progressInterval == 0 {
                    onProgress(count, entryPath)
                }

            case FTS_DP:
                // Directory post-order: aggregate sizes from children (bottom-up)
                if entryPath == rootPath { continue }
                if let node = nodeMap[entryPath] {
                    aggregateFromChildren(node)
                }

            case FTS_F:
                // Regular file
                guard let stat = entry.pointee.fts_statp else { continue }

                // Skip hardlinked files we've already counted
                let inode = stat.pointee.st_ino
                if stat.pointee.st_nlink > 1 {
                    if seenInodes.contains(inode) { continue }
                    seenInodes.insert(inode)
                }

                let name = extractName(entry)
                let fileURL = URL(fileURLWithPath: entryPath, isDirectory: false)
                let category = FileClassifier.classify(name: name, isDirectory: false)
                let node = FileNode(url: fileURL, name: name, isDirectory: false, category: category)

                let logicalSize = Int64(stat.pointee.st_size)
                let physicalSize = Int64(stat.pointee.st_blocks) * 512
                // Use physical (allocated) size as primary — matches `du` behavior
                // and correctly handles APFS clones, sparse files, and compression
                node.size = physicalSize
                node.allocatedSize = physicalSize
                node.logicalSize = logicalSize
                node.modificationDate = Date(timeIntervalSince1970: TimeInterval(stat.pointee.st_mtimespec.tv_sec))
                node.creationDate = Date(timeIntervalSince1970: TimeInterval(stat.pointee.st_birthtimespec.tv_sec))
                node.fileCount = 1

                let parentPath = (entryPath as NSString).deletingLastPathComponent
                if let parentNode = nodeMap[parentPath] {
                    parentNode.children.append(node)
                    node.parent = parentNode
                }

                count += 1
                if count % progressInterval == 0 {
                    onProgress(count, entryPath)
                }

            case FTS_SL, FTS_SLNONE:
                break

            case FTS_DNR, FTS_ERR, FTS_NS:
                break

            default:
                break
            }
        }

        // Final aggregation for root, then establish sorted-children invariant
        aggregateFromChildren(root)
        FileNode.sortTreeChildrenBySize(from: root)
        return root
    }

    private func aggregateFromChildren(_ node: FileNode) {
        var totalSize: Int64 = 0
        var totalAllocated: Int64 = 0
        var totalLogical: Int64 = 0
        var totalFiles: Int = 0
        var totalDirs: Int = 0

        for child in node.children {
            totalSize += child.size
            totalAllocated += child.allocatedSize
            totalLogical += child.logicalSize
            totalFiles += child.fileCount
            if child.isDirectory {
                totalDirs += 1 + child.directoryCount
            }
        }

        node.size = totalSize
        node.allocatedSize = totalAllocated
        node.logicalSize = totalLogical
        node.fileCount = totalFiles
        node.directoryCount = totalDirs
        node.sortChildrenBySize()
    }

    /// Expand a shallow directory stub (from scanDirectory) into a full in-memory subtree.
    func expandDirectoryStub(_ stub: FileNode) {
        guard stub.isDirectory, stub.fileCount > 0 else { return }
        let scanned = scan(url: stub.url) { _, _ in }
        stub.children = scanned.children
        for child in stub.children {
            child.parent = stub
        }
        stub.size = scanned.size
        stub.allocatedSize = scanned.allocatedSize
        stub.logicalSize = scanned.logicalSize
        stub.fileCount = scanned.fileCount
        stub.directoryCount = scanned.directoryCount
        if let modified = scanned.modificationDate { stub.modificationDate = modified }
        if let created = scanned.creationDate { stub.creationDate = created }
        FileNode.sortTreeChildrenBySize(from: stub)
    }

    /// Shallow scan of a single directory — returns direct children only.
    /// Used for incremental updates when FSEvents reports a directory changed.
    func scanDirectory(at url: URL, seenInodes: inout Set<UInt64>) -> [FileNode] {
        var dirPath = url.standardizedFileURL.path(percentEncoded: false)
        if dirPath.count > 1 && dirPath.hasSuffix("/") {
            dirPath = String(dirPath.dropLast())
        }

        let pathCStr = dirPath.withCString { strdup($0) }!
        defer { free(pathCStr) }

        var paths: [UnsafeMutablePointer<CChar>?] = [pathCStr, nil]
        guard let ftsStream = fts_open(&paths, FTS_PHYSICAL | FTS_XDEV | FTS_NOCHDIR, nil) else {
            return []
        }
        defer { fts_close(ftsStream) }

        var children = [FileNode]()

        while let entry = fts_read(ftsStream) {
            let info = Int32(entry.pointee.fts_info)
            let entryPath = String(cString: entry.pointee.fts_path)

            // Skip the directory itself and its post-order visit
            if entryPath == dirPath { continue }

            // Only process direct children — skip into subdirectories
            let parentPath = (entryPath as NSString).deletingLastPathComponent
            if parentPath != dirPath {
                if info == FTS_D {
                    fts_set(ftsStream, entry, FTS_SKIP) // don't recurse
                }
                continue
            }

            switch info {
            case FTS_D:
                let name = extractName(entry)
                let childURL = URL(fileURLWithPath: entryPath, isDirectory: true)
                let category = FileClassifier.classify(name: name, isDirectory: true)
                let node = FileNode(url: childURL, name: name, isDirectory: true, category: category)
                if let stat = entry.pointee.fts_statp {
                    node.modificationDate = Date(timeIntervalSince1970: TimeInterval(stat.pointee.st_mtimespec.tv_sec))
                    node.creationDate = Date(timeIntervalSince1970: TimeInterval(stat.pointee.st_birthtimespec.tv_sec))
                }
                populateDirectoryTotals(node, seenInodes: &seenInodes)
                children.append(node)
                fts_set(ftsStream, entry, FTS_SKIP) // don't recurse into children

            case FTS_F:
                guard let stat = entry.pointee.fts_statp else { continue }
                let inode = stat.pointee.st_ino
                if stat.pointee.st_nlink > 1 {
                    if seenInodes.contains(inode) { continue }
                    seenInodes.insert(inode)
                }

                let name = extractName(entry)
                let childURL = URL(fileURLWithPath: entryPath, isDirectory: false)
                let category = FileClassifier.classify(name: name, isDirectory: false)
                let node = FileNode(url: childURL, name: name, isDirectory: false, category: category)
                node.size = Int64(stat.pointee.st_blocks) * 512
                node.allocatedSize = node.size
                node.logicalSize = Int64(stat.pointee.st_size)
                node.modificationDate = Date(timeIntervalSince1970: TimeInterval(stat.pointee.st_mtimespec.tv_sec))
                node.creationDate = Date(timeIntervalSince1970: TimeInterval(stat.pointee.st_birthtimespec.tv_sec))
                node.fileCount = 1
                children.append(node)

            default:
                break
            }
        }

        children.sort { $0.size > $1.size }
        return children
    }

    /// Measure recursive totals for a single directory subtree (used by shallow scan).
    private func populateDirectoryTotals(_ node: FileNode, seenInodes: inout Set<UInt64>) {
        var dirPath = node.url.standardizedFileURL.path(percentEncoded: false)
        if dirPath.count > 1 && dirPath.hasSuffix("/") {
            dirPath = String(dirPath.dropLast())
        }

        let pathCStr = dirPath.withCString { strdup($0) }!
        defer { free(pathCStr) }

        var paths: [UnsafeMutablePointer<CChar>?] = [pathCStr, nil]
        guard let ftsStream = fts_open(&paths, FTS_PHYSICAL | FTS_XDEV | FTS_NOCHDIR, nil) else {
            return
        }
        defer { fts_close(ftsStream) }

        var totalSize: Int64 = 0
        var totalAllocated: Int64 = 0
        var totalLogical: Int64 = 0
        var totalFiles = 0
        var totalDirs = 0

        while let entry = fts_read(ftsStream) {
            let info = Int32(entry.pointee.fts_info)
            let entryPath = String(cString: entry.pointee.fts_path)
            if entryPath == dirPath { continue }

            switch info {
            case FTS_F:
                guard let stat = entry.pointee.fts_statp else { continue }
                let inode = stat.pointee.st_ino
                if stat.pointee.st_nlink > 1 {
                    if seenInodes.contains(inode) { continue }
                    seenInodes.insert(inode)
                }
                let physical = Int64(stat.pointee.st_blocks) * 512
                totalSize += physical
                totalAllocated += physical
                totalLogical += Int64(stat.pointee.st_size)
                totalFiles += 1

            case FTS_D:
                totalDirs += 1

            default:
                break
            }
        }

        node.size = totalSize
        node.allocatedSize = totalAllocated
        node.logicalSize = totalLogical
        node.fileCount = totalFiles
        node.directoryCount = totalDirs
    }

    private func extractName(_ entry: UnsafeMutablePointer<FTSENT>) -> String {
        withUnsafePointer(to: &entry.pointee.fts_name) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.fts_namelen) + 1) {
                String(cString: $0)
            }
        }
    }
}
