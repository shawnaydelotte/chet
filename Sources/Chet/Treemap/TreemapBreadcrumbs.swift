import Foundation

enum TreemapBreadcrumbs {
    static func path(from treemapRoot: FileNode, to scanRoot: FileNode) -> [FileNode] {
        var path: [FileNode] = []
        var node: FileNode? = treemapRoot
        while let current = node, current.id != scanRoot.id {
            path.insert(current, at: 0)
            node = current.parent
        }
        return path
    }
}