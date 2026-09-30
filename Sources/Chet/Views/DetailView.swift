import SwiftUI

struct DetailView: View {
    @Environment(ScanState.self) private var state

    var body: some View {
        let _ = state.lastTreeMutation

        Group {
            if let node = state.selectedNode {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        headerSection(node)
                        Divider()
                        sizeSection(node)
                        Divider()
                        metadataSection(node)

                        Divider()
                        cleanupImpactSection(node)

                        if node.isDirectory {
                            Divider()
                            categoryBreakdownSection(node)
                            Divider()
                            largestItemsSection(node)
                        }
                    }
                    .padding()
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "sidebar.right")
                        .font(.title)
                        .foregroundStyle(.tertiary)
                    Text("Select an item to inspect")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 250)
    }

    @ViewBuilder
    private func headerSection(_ node: FileNode) -> some View {
        HStack(spacing: 10) {
            Image(systemName: node.isDirectory ? "folder.fill" : node.category.icon)
                .font(.title2)
                .foregroundStyle(node.isDirectory ? .blue : node.category.color)

            VStack(alignment: .leading, spacing: 2) {
                Text(node.name)
                    .font(.headline)
                    .lineLimit(2)
                Text(node.url.path(percentEncoded: false))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
        }

        HStack(spacing: 8) {
            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile(
                    node.url.path(percentEncoded: false),
                    inFileViewerRootedAtPath: node.url.deletingLastPathComponent().path(percentEncoded: false)
                )
            }
            .controlSize(.small)

            if node.isDirectory {
                Button("Drill Into") {
                    state.drillInto(node)
                }
                .controlSize(.small)
            }

            Button("Move to Trash") {
                Task { await state.moveToTrash(node) }
            }
            .controlSize(.small)
            .disabled(state.isAnalyzingImpact)
        }
    }

    @ViewBuilder
    private func cleanupImpactSection(_ node: FileNode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Deletion Impact")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if DeletionImpactAnalyzer.coreAIAvailable {
                    Label("Core AI", systemImage: "sparkles")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Button("Analyze") {
                    state.analyzeDeletionImpact(for: node)
                }
                .controlSize(.mini)
                .disabled(state.isAnalyzingImpact)
            }

            if state.isAnalyzingImpact {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Analyzing impact...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let impact = state.deletionImpact, impact.path == node.url.path(percentEncoded: false) {
                HStack(spacing: 8) {
                    RiskBadge(level: impact.riskLevel)
                    Text(impact.summary)
                        .font(.caption)
                }

                DetailRow(label: "Reclaimable", value: SizeFormatter.format(impact.reclaimableBytes))
                DetailRow(label: "Recoverability", value: impact.recoverability)

                if !impact.consequences.isEmpty {
                    Text(impact.consequences.first ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Source: \(impact.source == .coreAI ? "Apple Intelligence" : "Heuristic rules")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Text("Analyze before deleting to estimate risk and recoverability.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = state.cleanupError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onAppear {
            if state.deletionImpact?.path != node.url.path(percentEncoded: false) {
                state.analyzeDeletionImpact(for: node)
            }
        }
        .onChange(of: node.id) {
            state.deletionImpact = nil
            state.cleanupError = nil
            state.analyzeDeletionImpact(for: node)
        }
    }

    @ViewBuilder
    private func sizeSection(_ node: FileNode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Size")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            DetailRow(label: "Disk Usage", value: SizeFormatter.format(node.size))
            DetailRow(label: "Logical Size", value: SizeFormatter.format(node.logicalSize))

            if let parent = node.parent {
                DetailRow(
                    label: "% of Parent",
                    value: SizeFormatter.percentage(node.size, of: parent.size)
                )
            }

            if let root = state.rootNode {
                DetailRow(
                    label: "% of Total",
                    value: SizeFormatter.percentage(node.size, of: root.size)
                )
            }

            if node.isDirectory {
                DetailRow(label: "Files", value: "\(node.fileCount)")
                DetailRow(label: "Subdirectories", value: "\(node.directoryCount)")
            }
        }
    }

    @ViewBuilder
    private func metadataSection(_ node: FileNode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Metadata")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if !node.isDirectory {
                DetailRow(label: "Category", value: node.category.displayName, color: node.category.color)
            }

            if let created = node.creationDate {
                DetailRow(label: "Created", value: created.formatted(date: .abbreviated, time: .shortened))
            }
            if let modified = node.modificationDate {
                DetailRow(label: "Modified", value: modified.formatted(date: .abbreviated, time: .shortened))
            }
        }
    }

    @ViewBuilder
    private func categoryBreakdownSection(_ node: FileNode) -> some View {
        let breakdown = node.categoryBreakdown()

        VStack(alignment: .leading, spacing: 8) {
            Text("Category Breakdown")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            let maxCategorySize = breakdown.first?.size ?? 0
            ForEach(breakdown.prefix(10), id: \.category) { item in
                HStack(spacing: 6) {
                    Circle()
                        .fill(item.category.color)
                        .frame(width: 8, height: 8)

                    Text(item.category.displayName)
                        .font(.caption)

                    Spacer()

                    Text(SizeFormatter.format(item.size))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)

                    Text(SizeFormatter.percentage(item.size, of: node.size))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .frame(width: 44, alignment: .trailing)
                }
                .padding(.vertical, 1)
                .background(alignment: .leading) {
                    GeometryReader { proxy in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(item.category.color.opacity(0.15))
                            .frame(
                                width: max(
                                    2,
                                    proxy.size.width * RelativeSizeScale.fraction(
                                        value: item.size,
                                        of: maxCategorySize
                                    )
                                )
                            )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func largestItemsSection(_ node: FileNode) -> some View {
        let largest = node.sortedChildren.prefix(10)

        VStack(alignment: .leading, spacing: 8) {
            Text("Largest Items")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(Array(largest), id: \.id) { child in
                HStack(spacing: 6) {
                    Image(systemName: child.isDirectory ? "folder.fill" : child.category.icon)
                        .font(.caption2)
                        .foregroundStyle(child.isDirectory ? .secondary : child.category.color)
                        .frame(width: 14)

                    Text(child.name)
                        .font(.caption)
                        .lineLimit(1)

                    Spacer()

                    Text(SizeFormatter.format(child.size))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 1)
                .background(alignment: .leading) {
                    GeometryReader { proxy in
                        let barColor = child.isDirectory ? Color.secondary : child.category.color
                        RoundedRectangle(cornerRadius: 2)
                            .fill(barColor.opacity(0.15))
                            .frame(width: max(2, proxy.size.width * child.relativeToSiblings))
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    state.selectedNode = child
                    if child.isDirectory {
                        state.drillInto(child)
                    }
                }
            }
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    var color: Color?

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if let color {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
            }
            Text(value)
                .font(.caption)
                .monospacedDigit()
        }
    }
}
