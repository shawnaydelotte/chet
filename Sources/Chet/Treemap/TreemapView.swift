import SwiftUI

struct TreemapView: View {
    @Environment(ScanState.self) private var state
    @Environment(HoverState.self) private var hoverState

    var body: some View {
        let _ = state.lastTreeMutation

        VStack(spacing: 0) {
            breadcrumbs
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.bar)

            GeometryReader { geo in
                let items = layoutItems(in: geo.size)
                ZStack(alignment: .topLeading) {
                    Canvas { context, size in
                        drawTreemap(context: context, items: items)
                    }
                    .clipped()

                    // Invisible overlay for hit-testing
                    Color.clear
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let loc):
                                hoverState.hoverLocation = loc
                                hoverState.hoveredNode = items.first { $0.rect.contains(loc) }?.node
                            case .ended:
                                hoverState.hoveredNode = nil
                            }
                        }
                        .onTapGesture { loc in
                            if let item = items.first(where: { $0.rect.contains(loc) }) {
                                if item.node.isDirectory {
                                    state.drillInto(item.node)
                                } else {
                                    state.selectedNode = item.node
                                }
                            }
                        }

                    // Tooltip
                    if let node = hoverState.hoveredNode {
                        let placement = TreemapTooltip.place(
                            at: hoverState.hoverLocation,
                            in: geo.size
                        )
                        tooltip(for: node, placement: placement)
                            .frame(
                                width: placement.effectiveSize.width,
                                height: placement.effectiveSize.height,
                                alignment: .topLeading
                            )
                            .position(placement.center)
                            .allowsHitTesting(false)
                            .animation(.none, value: hoverState.hoveredNode?.id)
                    }
                }
            }

            CategoryLegend()
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.bar)
        }
    }

    @ViewBuilder
    private var breadcrumbs: some View {
        HStack(spacing: 4) {
            if let root = state.rootNode {
                Button(root.name) {
                    state.drillToRoot()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.link)
            }

            if let treemapRoot = state.treemapRoot,
               let scanRoot = state.rootNode,
               treemapRoot.id != scanRoot.id {
                ForEach(TreemapBreadcrumbs.path(from: treemapRoot, to: scanRoot), id: \.id) { node in
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if node.id == treemapRoot.id {
                        Text(node.name)
                            .fontWeight(.semibold)
                    } else {
                        Button(node.name) {
                            state.drillInto(node)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.link)
                    }
                }
            }

            Spacer()

            if let node = state.displayRoot {
                Text(SizeFormatter.format(node.size))
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
        .font(.callout)
    }

    private func layoutItems(in size: CGSize) -> [TreemapItem] {
        guard let root = state.displayRoot else { return [] }
        let children = root.sortedChildren
        let rect = CGRect(origin: .zero, size: size)
        return TreemapLayout.layout(
            nodes: children,
            in: rect,
            hiddenCategories: state.hiddenCategories
        )
    }

    private func drawTreemap(context: GraphicsContext, items: [TreemapItem]) {
        let gap: CGFloat = 1.5

        for item in items {
            let r = item.rect.insetBy(dx: gap, dy: gap)
            guard r.width > 1, r.height > 1 else { continue }

            let isHovered = item.node.id == hoverState.hoveredNode?.id
            let isSelected = item.node.id == state.selectedNode?.id
            let category = item.node.isDirectory ? dominantCategory(of: item.node) : item.node.category
            let baseColor = category.color

            let cornerRadius: CGFloat = min(4, min(r.width, r.height) / 4)
            let shape = RoundedRectangle(cornerRadius: cornerRadius).path(in: r)

            // Fill with gradient for depth
            let topColor = isHovered ? baseColor.opacity(0.95) : baseColor.opacity(0.75)
            let bottomColor = isHovered ? baseColor.opacity(0.80) : baseColor.opacity(0.55)
            context.fill(
                shape,
                with: .linearGradient(
                    Gradient(colors: [topColor, bottomColor]),
                    startPoint: CGPoint(x: r.midX, y: r.minY),
                    endPoint: CGPoint(x: r.midX, y: r.maxY)
                )
            )

            // Subtle border
            context.stroke(shape, with: .color(baseColor.opacity(0.3)), lineWidth: 0.5)

            if isSelected {
                context.stroke(shape, with: .color(.white), lineWidth: 2.5)
            }

            // Draw label if rect is large enough
            if r.width > 55 && r.height > 20 {
                let name = item.node.name
                let sizeStr = SizeFormatter.format(item.node.size)
                let fontSize = min(13, max(9, min(r.width / 10, r.height * 0.3)))
                let showSize = r.height > 36

                // Shadow text for readability
                let shadowText = Text(showSize ? "\(name)\n\(sizeStr)" : name)
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundStyle(.black.opacity(0.5))
                let labelText = Text(showSize ? "\(name)\n\(sizeStr)" : name)
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundStyle(.white)

                let textRect = CGRect(
                    x: r.minX + 5,
                    y: r.minY + 4,
                    width: r.width - 10,
                    height: r.height - 8
                )

                var clipped = context
                clipped.clip(to: RoundedRectangle(cornerRadius: cornerRadius).path(in: r))
                // Draw shadow
                let shadowRect = textRect.offsetBy(dx: 0.5, dy: 0.5)
                clipped.draw(clipped.resolve(shadowText), in: shadowRect)
                // Draw text
                clipped.draw(clipped.resolve(labelText), in: textRect)
            }
        }
    }

    private func dominantCategory(of node: FileNode) -> FileCategory {
        let breakdown = node.categoryBreakdown()
        return breakdown.first?.category ?? .other
    }

    @ViewBuilder
    private func tooltip(for node: FileNode, placement: TreemapTooltip.Placement) -> some View {
        VStack(alignment: .leading, spacing: TreemapTooltip.lineSpacing) {
            Text(node.name)
                .fontWeight(.semibold)
                .lineLimit(1)
                .frame(height: TreemapTooltip.lineHeight, alignment: .leading)
            Text(SizeFormatter.format(node.size))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(height: TreemapTooltip.lineHeight, alignment: .leading)

            if placement.contentMode != .compact {
                HStack(spacing: 4) {
                    Circle()
                        .fill(node.category.color)
                        .frame(width: 8, height: 8)
                    Text(node.category.displayName)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(height: TreemapTooltip.lineHeight, alignment: .leading)
            }

            if placement.contentMode == .full {
                if let parent = node.parent {
                    Text(SizeFormatter.percentage(node.size, of: parent.size) + " of parent")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(height: TreemapTooltip.lineHeight, alignment: .leading)
                }
                if node.isDirectory {
                    Text("\(node.fileCount) files, \(node.directoryCount) folders")
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .frame(height: TreemapTooltip.lineHeight, alignment: .leading)
                }
            }
        }
        .font(.caption)
        .padding(TreemapTooltip.padding)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 4)
    }
}