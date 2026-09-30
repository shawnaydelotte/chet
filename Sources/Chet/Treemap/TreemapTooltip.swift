import CoreGraphics

enum TreemapTooltip {
    static let width: CGFloat = 180
    static let height: CGFloat = 90
    static let offset: CGFloat = 16
    static let padding: CGFloat = 8
    static let lineHeight: CGFloat = 12
    static let lineSpacing: CGFloat = 2

    enum ContentMode: Equatable {
        case compact
        case standard
        case full
    }

    struct Placement {
        let center: CGPoint
        let effectiveSize: CGSize
        let contentMode: ContentMode
    }

    static func boundingRect(center: CGPoint, size: CGSize) -> CGRect {
        CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    static func isFullyContained(center: CGPoint, size: CGSize, in canvas: CGSize) -> Bool {
        let rect = boundingRect(center: center, size: size)
        return rect.minX >= 0 && rect.maxX <= canvas.width
            && rect.minY >= 0 && rect.maxY <= canvas.height
    }

    static func lineCount(for mode: ContentMode) -> Int {
        switch mode {
        case .compact: 2
        case .standard: 3
        case .full: 5
        }
    }

    static func estimatedContentHeight(for mode: ContentMode) -> CGFloat {
        let lines = CGFloat(lineCount(for: mode))
        let gaps = max(0, lines - 1)
        return padding * 2 + lineHeight * lines + lineSpacing * gaps
    }

    static func contentMode(for effectiveSize: CGSize) -> ContentMode {
        let innerHeight = effectiveSize.height - padding * 2
        if innerHeight >= lineHeight * 5 + lineSpacing * 4 {
            return .full
        }
        if innerHeight >= lineHeight * 3 + lineSpacing * 2 {
            return .standard
        }
        return .compact
    }

    static func contentFits(in effectiveSize: CGSize) -> Bool {
        let mode = contentMode(for: effectiveSize)
        return estimatedContentHeight(for: mode) <= effectiveSize.height + 0.5
    }

    /// Returns a center and size guaranteed to fit entirely inside `canvas`.
    static func place(at point: CGPoint, in canvas: CGSize) -> Placement {
        let effectiveW = min(width, canvas.width)
        let effectiveH = min(height, canvas.height)
        let effectiveSize = CGSize(width: effectiveW, height: effectiveH)
        let halfW = effectiveW / 2
        let halfH = effectiveH / 2

        var x: CGFloat
        var y: CGFloat

        if canvas.width >= width {
            x = point.x + offset + halfW
            if x + halfW > canvas.width {
                x = point.x - offset - halfW
            }
            x = min(max(x, halfW), canvas.width - halfW)
        } else {
            x = canvas.width / 2
        }

        if canvas.height >= height {
            y = point.y + offset + halfH
            if y + halfH > canvas.height {
                y = point.y - offset - halfH
            }
            y = min(max(y, halfH), canvas.height - halfH)
        } else {
            y = canvas.height / 2
        }

        return Placement(
            center: CGPoint(x: x, y: y),
            effectiveSize: effectiveSize,
            contentMode: contentMode(for: effectiveSize)
        )
    }
}