import Foundation

/// Cache mutations collected on the main actor and applied on a background thread.
struct DiffCacheWork: @unchecked Sendable {
    private(set) var upsertDirectories: [(node: FileNode, parentPath: String?)] = []

    private(set) var deleteNodes: [String] = []
    private(set) var deleteSubtrees: [String] = []
    private(set) var upsertNodes: [(node: FileNode, parentPath: String)] = []
    private(set) var upsertSubtrees: [(root: FileNode, parentPath: String)] = []

    mutating func recordDeleteNode(path: String) {
        deleteNodes.append(path)
    }

    mutating func recordDeleteSubtree(path: String) {
        deleteSubtrees.append(path)
    }

    mutating func recordUpsertDirectory(_ node: FileNode, parentPath: String?) {
        upsertDirectories.append((node, parentPath))
    }

    mutating func recordUpsertNode(_ node: FileNode, parentPath: String) {
        upsertNodes.append((node, parentPath))
    }

    mutating func recordUpsertSubtree(_ root: FileNode, parentPath: String) {
        upsertSubtrees.append((root, parentPath))
    }

    mutating func merge(_ other: DiffCacheWork) {
        upsertDirectories.append(contentsOf: other.upsertDirectories)
        deleteNodes.append(contentsOf: other.deleteNodes)
        deleteSubtrees.append(contentsOf: other.deleteSubtrees)
        upsertNodes.append(contentsOf: other.upsertNodes)
        upsertSubtrees.append(contentsOf: other.upsertSubtrees)
    }

    func persist() {
        let cache = ScanCache.shared
        _ = cache.open()
        for upsert in upsertDirectories {
            cache.upsertNode(upsert.node, parentPath: upsert.parentPath)
        }
        for path in deleteSubtrees {
            cache.deleteSubtree(path: path)
        }
        for path in deleteNodes {
            cache.deleteNode(path: path)
        }
        for item in upsertNodes {
            cache.upsertNode(item.node, parentPath: item.parentPath)
        }
        for item in upsertSubtrees {
            cache.upsertSubtree(item.root, parentPath: item.parentPath)
        }
    }
}