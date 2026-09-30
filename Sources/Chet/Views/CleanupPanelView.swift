import SwiftUI

struct CleanupPanelView: View {
    @Environment(ScanState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let candidates = state.cleanupCandidates
        let reclaimable = CleanupPlanner.totalReclaimable(from: candidates)
        let selectedBytes = state.selectedCleanupBytes
        let selectionCount = state.collapsedSelectionCount
        let rawSelectionCount = state.selectedCleanupIDs.count

        NavigationStack {
            Group {
                if candidates.isEmpty {
                    ContentUnavailableView(
                        "No Quick Wins Found",
                        systemImage: "checkmark.circle",
                        description: Text("Scan a larger directory or drill into caches and build folders.")
                    )
                } else {
                    List(candidates) { candidate in
                        CleanupCandidateRow(
                            candidate: candidate,
                            isSelected: state.selectedCleanupIDs.contains(candidate.id),
                            isDisabled: state.isBatchCleaning
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard !state.isBatchCleaning else { return }
                            state.toggleCleanupSelection(candidate.id)
                        }
                        .contextMenu {
                            Button("Reveal in Finder") {
                                NSWorkspace.shared.selectFile(
                                    candidate.path,
                                    inFileViewerRootedAtPath: (candidate.path as NSString).deletingLastPathComponent
                                )
                            }
                            if let node = state.node(forPath: candidate.path) {
                                Button("Inspect") {
                                    state.selectedNode = node
                                    if node.isDirectory {
                                        state.drillInto(node)
                                    }
                                    dismiss()
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Reclaim Space")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .disabled(state.isBatchCleaning)
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if !candidates.isEmpty && !state.isBatchCleaning {
                        Menu {
                            ForEach(CleanupPreset.allCases) { preset in
                                Button {
                                    state.applyCleanupPreset(preset)
                                } label: {
                                    Label(preset.title, systemImage: preset.icon)
                                }
                            }
                            Divider()
                            Button("Select All") { state.selectAllCleanupCandidates() }
                            Button("Clear Selection") { state.clearCleanupSelection() }
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                        }
                        .help("Cleanup presets and selection")
                    }
                    Button("Refresh") { state.refreshCleanupCandidates() }
                        .disabled(state.isBatchCleaning)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !candidates.isEmpty {
                    bottomBar(
                        reclaimable: reclaimable,
                        selectedBytes: selectedBytes,
                        selectionCount: selectionCount,
                        rawSelectionCount: rawSelectionCount
                    )
                }
            }
            .overlay {
                if state.isBatchCleaning {
                    batchProgressOverlay
                }
            }
        }
        .frame(minWidth: 460, minHeight: 400)
        .onAppear {
            state.refreshCleanupCandidates()
        }
    }

    @ViewBuilder
    private func bottomBar(
        reclaimable: Int64,
        selectedBytes: Int64,
        selectionCount: Int,
        rawSelectionCount: Int
    ) -> some View {
        VStack(spacing: 10) {
            if let error = state.cleanupError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectionCount > 0 ? "Selected for reclaim" : "Potential reclaim")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(SizeFormatter.format(selectionCount > 0 ? selectedBytes : reclaimable))
                        .font(.headline.monospacedDigit())
                    if selectionCount > 0 {
                        let nestedNote = rawSelectionCount > selectionCount ? " (\(rawSelectionCount) selected, \(selectionCount) after nesting)" : ""
                        Text("\(selectionCount) item\(selectionCount == 1 ? "" : "s")\(nestedNote)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                if DeletionImpactAnalyzer.coreAIAvailable {
                    Label("Core AI", systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                Button("Move Selected to Trash") {
                    state.startBatchCleanup()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectionCount == 0 || state.isBatchCleaning)

                if selectionCount == 0 {
                    Text("Select items or use a preset above")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.bar)
    }

    private var batchProgressOverlay: some View {
        let progress = state.cleanupBatchProgress
        return ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.regular)
                Text("Moving to Trash")
                    .font(.headline)
                if !progress.currentName.isEmpty {
                    Text(progress.currentName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text("\(progress.completed) of \(progress.total)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if progress.bytesReclaimed > 0 {
                    Text("Reclaimed \(SizeFormatter.format(progress.bytesReclaimed))")
                        .font(.caption.monospacedDigit())
                }
                Button("Cancel", role: .cancel) {
                    state.cancelBatchCleanup()
                }
                .controlSize(.small)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

private struct CleanupCandidateRow: View {
    let candidate: CleanupCandidate
    let isSelected: Bool
    let isDisabled: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .font(.body)
                .opacity(isDisabled ? 0.5 : 1)

            Image(systemName: candidate.category.icon)
                .foregroundStyle(candidate.category.color)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(candidate.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(candidate.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(SizeFormatter.format(candidate.size))
                    .font(.callout.monospacedDigit())
                RiskBadge(level: candidate.riskLevel)
            }
        }
        .padding(.vertical, 2)
    }
}

struct RiskBadge: View {
    let level: CleanupRiskLevel

    var body: some View {
        Text(level.displayName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundColor.opacity(0.18), in: Capsule())
            .foregroundStyle(foregroundColor)
    }

    private var backgroundColor: Color {
        switch level {
        case .safe: .green
        case .caution: .orange
        case .risky: .red
        case .blocked: .gray
        }
    }

    private var foregroundColor: Color {
        switch level {
        case .safe: .green
        case .caution: .orange
        case .risky: .red
        case .blocked: .secondary
        }
    }
}