import SwiftUI

struct ToolbarView: ToolbarContent {
    @Environment(ScanState.self) private var state

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                state.drillUp()
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(state.displayRoot?.parent == nil)
            .help("Go back to parent directory")

            Button {
                state.drillToRoot()
            } label: {
                Image(systemName: "house")
            }
            .disabled(state.treemapRoot?.id == state.rootNode?.id)
            .help("Go to scan root")
        }

        ToolbarItem(placement: .principal) {
            if state.isScanning {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Scanning \(state.filesScanned.formatted()) items...")
                        .font(.callout)
                        .monospacedDigit()
                }
            } else if let root = state.displayRoot {
                VStack(spacing: 1) {
                    HStack(spacing: 4) {
                        Text("\(root.name) \u{2014} \(SizeFormatter.format(root.size))")
                            .font(.callout)
                        if state.isUpdating {
                            ProgressView()
                                .controlSize(.mini)
                        }
                    }
                    if state.volumeTotalCapacity > 0 {
                        Text("\(SizeFormatter.format(state.volumeAvailableCapacity)) free of \(SizeFormatter.format(state.volumeTotalCapacity))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Button("Home Directory") {
                    state.startScan(url: URL(fileURLWithPath: NSHomeDirectory()))
                }
                Button("Root Volume (/)") {
                    state.startScan(url: URL(fileURLWithPath: "/"))
                }
                Divider()
                Button("Choose Directory...") {
                    state.chooseDirectoryAndScan()
                }
            } label: {
                Image(systemName: "folder")
            }
            .help("Scan directory")

            if state.rootNode != nil {
                Button {
                    state.refreshCleanupCandidates()
                    state.showCleanupPanel = true
                } label: {
                    Image(systemName: "trash.circle")
                }
                .disabled(state.isScanning)
                .help("Find reclaimable space")

                Button {
                    if let url = state.rootNode?.url {
                        state.startScan(url: url)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(state.isScanning)
                .help("Rescan")
            }
        }
    }

}
