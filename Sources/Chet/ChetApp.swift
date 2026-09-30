import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["CHET_UNIT_TESTS"] == "1" {
            let failures = UnitTestRunner.runAll()
            exit(failures == 0 ? 0 : 1)
        }

        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct ChetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private let scanState = ScanState()
    private let hoverState = HoverState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(scanState)
                .environment(hoverState)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear {
                    guard ScanState.shouldAutoScanOnLaunch(
                        environment: ProcessInfo.processInfo.environment
                    ) else { return }
                    guard scanState.rootNode == nil && !scanState.isScanning else { return }
                    let homePath = ScanState.normalizePath(NSHomeDirectory())

                    // Try loading from cache first (instant launch)
                    if scanState.loadFromCache(rootPath: homePath) {
                        // Cache loaded — start incremental update in background
                        scanState.startIncrementalUpdate(rootPath: homePath)
                    } else {
                        // No cache — full scan
                        scanState.startScan(url: URL(fileURLWithPath: homePath))
                    }
                }
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Directory...") {
                    scanState.chooseDirectoryAndScan()
                }
                .keyboardShortcut("o", modifiers: .command)

                Divider()

                Button("Go Back") {
                    scanState.drillUp()
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(scanState.treemapRoot?.parent == nil)
            }
        }
    }

}
