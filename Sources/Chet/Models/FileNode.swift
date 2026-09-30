import Foundation

final class FileNode: Identifiable, @unchecked Sendable {
    let id = UUID()
    let url: URL
    let name: String
    let isDirectory: Bool
    var size: Int64 = 0          // Physical (allocated) size — what du reports
    var allocatedSize: Int64 = 0  // Same as size for consistency
    var logicalSize: Int64 = 0    // Logical size — what ls -l reports
    var category: FileCategory
    var children: [FileNode] = []
    weak var parent: FileNode?

    var fileCount: Int = 0
    var directoryCount: Int = 0

    var creationDate: Date?
    var modificationDate: Date?

    init(url: URL, name: String, isDirectory: Bool, category: FileCategory) {
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.category = category
    }

    /// Children are kept in descending size order; no per-access sort.
    var sortedChildren: [FileNode] {
        children
    }

    func sortChildrenBySize() {
        children.sort { $0.size > $1.size }
    }

    /// Post-order sort: every directory's children end up descending by size.
    static func sortTreeChildrenBySize(from root: FileNode) {
        for child in root.children {
            sortTreeChildrenBySize(from: child)
        }
        root.sortChildrenBySize()
    }

    static func makePathIndex(from root: FileNode) -> [String: FileNode] {
        var index = [String: FileNode]()
        var stack = [root]
        while let node = stack.popLast() {
            index[node.url.path(percentEncoded: false)] = node
            stack.append(contentsOf: node.children)
        }
        return index
    }

    /// Fraction of this node's size relative to its largest sibling (0...1).
    var relativeToSiblings: CGFloat {
        RelativeSizeScale.fractionAmongSiblings(for: self)
    }

    static func childrenAreSortedBySize(_ nodes: [FileNode]) -> Bool {
        guard nodes.count > 1 else { return true }
        for index in 1..<nodes.count {
            if nodes[index - 1].size < nodes[index].size {
                return false
            }
        }
        return true
    }

    /// Depth from scan root (0 for root, 1 for its children, etc.)
    var depth: Int {
        var d = 0
        var node = parent
        while let current = node {
            d += 1
            node = current.parent
        }
        return d
    }

    /// Category breakdown uses iterative stack to avoid deep recursion
    func categoryBreakdown() -> [(category: FileCategory, size: Int64)] {
        var totals = [FileCategory: Int64]()
        var stack: [FileNode] = [self]
        while let node = stack.popLast() {
            if node.isDirectory {
                stack.append(contentsOf: node.children)
            } else {
                totals[node.category, default: 0] += node.size
            }
        }
        return totals.sorted { $0.value > $1.value }
            .map { (category: $0.key, size: $0.value) }
    }
}
