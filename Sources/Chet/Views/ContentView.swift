import SwiftUI

struct ContentView: View {
    @Environment(ScanState.self) private var state

    var body: some View {
        Group {
            if state.rootNode != nil {
                NavigationSplitView {
                    SidebarView()
                } content: {
                    ZStack {
                        TreemapView()
                        if state.isScanning {
                            ScanProgressView()
                        }
                    }
                } detail: {
                    DetailView()
                }
            } else if state.isScanning {
                ScanProgressView()
            } else {
                WelcomeView()
            }
        }
        .toolbar {
            ToolbarView()
        }
        .sheet(isPresented: Binding(
            get: { state.showCleanupPanel },
            set: { state.showCleanupPanel = $0 }
        )) {
            CleanupPanelView()
        }
    }
}

struct WelcomeView: View {
    @Environment(ScanState.self) private var state

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "internaldrive")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Chet")
                .font(.largeTitle.bold())

            Text("Disk Space Analyzer")
                .font(.title3)
                .foregroundStyle(.secondary)

            Button(action: { state.chooseDirectoryAndScan() }) {
                Label("Open Directory", systemImage: "folder")
                    .font(.title3)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text("Or press \u{2318}O")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
