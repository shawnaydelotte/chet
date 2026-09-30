import CoreGraphics
import Foundation

enum RelativeSizeScale {
    /// Normalized fraction of `value` relative to `maximum` (0...1).
    static func fraction(value: Int64, of maximum: Int64) -> CGFloat {
        guard maximum > 0 else { return 0 }
        return CGFloat(min(1.0, Double(value) / Double(maximum)))
    }

    /// Fraction of the largest sibling at the same tree level (0...1).
    static func fractionAmongSiblings(for node: FileNode) -> CGFloat {
        guard let parent = node.parent else { return 1 }
        guard let maxSize = parent.sortedChildren.map(\.size).max() else { return 0 }
        return fraction(value: node.size, of: maxSize)
    }

    /// Fraction of the node's parent total size (0...1).
    static func fractionOfParent(for node: FileNode) -> CGFloat {
        guard let parent = node.parent else { return 1 }
        return fraction(value: node.size, of: parent.size)
    }
}