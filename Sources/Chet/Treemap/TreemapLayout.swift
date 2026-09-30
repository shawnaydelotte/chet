import Foundation

enum TreemapLayout {
    /// Minimum rectangle dimension (points) — ensures small items remain clickable
    private static let minSide: Double = 18

    static func layout(
        nodes: [FileNode],
        in rect: CGRect,
        hiddenCategories: Set<FileCategory> = []
    ) -> [TreemapItem] {
        let sorted = nodes
            .filter { $0.size > 0 && !hiddenCategories.contains($0.category) }
            .sorted { $0.size > $1.size }
        guard !sorted.isEmpty else { return [] }

        // Cap visible items so the smallest ones aren't sub-pixel slivers
        let totalArea = Double(rect.width * rect.height)
        let minArea = minSide * minSide
        let maxItems = max(1, Int(totalArea / minArea))
        let visible = Array(sorted.prefix(maxItems))

        let totalSize = visible.reduce(Int64(0)) { $0 + $1.size }
        guard totalSize > 0 else { return [] }

        // Proportional areas with a floor for clickability, then renormalize to fit the canvas.
        var areas = visible.map { Double($0.size) / Double(totalSize) * totalArea }
        for i in areas.indices {
            areas[i] = max(areas[i], minArea)
        }
        let areaSum = areas.reduce(0, +)
        if areaSum > 0, abs(areaSum - totalArea) > 0.5 {
            let scale = totalArea / areaSum
            areas = areas.map { $0 * scale }
        }

        let rects = squarify(areas: areas, in: rect)

        return zip(visible, rects).map { TreemapItem(node: $0, rect: $1) }
    }

    private static func squarify(areas: [Double], in bounds: CGRect) -> [CGRect] {
        guard !areas.isEmpty else { return [] }

        var result = [CGRect](repeating: .zero, count: areas.count)
        var remaining = bounds

        var i = 0
        while i < areas.count {
            let isWide = remaining.width >= remaining.height
            let side = isWide ? Double(remaining.height) : Double(remaining.width)

            guard side > 0 else { break }

            var row = [Int]()
            var rowArea: Double = 0
            var bestWorst = Double.infinity

            var j = i
            while j < areas.count {
                let candidate = areas[j]
                let newRowArea = rowArea + candidate
                var newRow = row
                newRow.append(j)

                let w = worstAspect(areas: areas, indices: newRow, rowArea: newRowArea, side: side)

                if w <= bestWorst {
                    row = newRow
                    rowArea = newRowArea
                    bestWorst = w
                    j += 1
                } else {
                    break
                }
            }

            if row.isEmpty {
                row = [i]
                rowArea = areas[i]
                j = i + 1
            }

            let rowLength = rowArea / side

            var offset: Double = 0
            for idx in row {
                let itemLength = areas[idx] / rowLength

                if isWide {
                    result[idx] = CGRect(
                        x: Double(remaining.minX),
                        y: Double(remaining.minY) + offset,
                        width: rowLength,
                        height: itemLength
                    )
                } else {
                    result[idx] = CGRect(
                        x: Double(remaining.minX) + offset,
                        y: Double(remaining.minY),
                        width: itemLength,
                        height: rowLength
                    )
                }
                offset += itemLength
            }

            if isWide {
                remaining = CGRect(
                    x: remaining.minX + CGFloat(rowLength),
                    y: remaining.minY,
                    width: remaining.width - CGFloat(rowLength),
                    height: remaining.height
                )
            } else {
                remaining = CGRect(
                    x: remaining.minX,
                    y: remaining.minY + CGFloat(rowLength),
                    width: remaining.width,
                    height: remaining.height - CGFloat(rowLength)
                )
            }

            i = j
        }

        return result
    }

    private static func worstAspect(
        areas: [Double],
        indices: [Int],
        rowArea: Double,
        side: Double
    ) -> Double {
        guard !indices.isEmpty, side > 0, rowArea > 0 else { return .infinity }

        let rowLength = rowArea / side
        guard rowLength > 0 else { return .infinity }

        var worst: Double = 0
        for idx in indices {
            let itemLength = areas[idx] / rowLength
            guard itemLength > 0 else { continue }
            let aspect = max(rowLength / itemLength, itemLength / rowLength)
            worst = max(worst, aspect)
        }
        return worst
    }
}
