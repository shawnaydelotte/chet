import Foundation

struct TreemapItem {
    let node: FileNode
    var rect: CGRect

    var area: CGFloat {
        rect.width * rect.height
    }
}
