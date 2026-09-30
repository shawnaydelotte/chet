import Foundation
import CoreServices

/// Watches filesystem changes using macOS FSEvents kernel API.
/// Two modes: historical query (what changed since event ID?) and live stream.
final class FSEventsWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private var callback: (([String]) -> Void)?

    /// Query FSEvents for directories changed since a given event ID.
    /// Returns (changedPaths, currentEventID). If event ID is stale, returns nil (trigger full rescan).
    static func changedPaths(
        since eventID: UInt64,
        root: String
    ) -> (paths: [String], currentEventID: UInt64)? {
        let currentID = FSEventsGetCurrentEventId()

        // If stored ID is 0 or greater than current, it's invalid
        if eventID == 0 || eventID > currentID {
            return nil
        }

        var changedPaths = Set<String>()

        // Create a temporary stream to read historical events
        let pathsToWatch = [root] as CFArray
        var context = FSEventStreamContext()

        // We'll use a different approach: create a stream starting from the old event ID
        // and collect all paths that changed
        let semaphore = DispatchSemaphore(value: 0)
        let collectedPaths = UnsafeMutablePointer<Set<String>>.allocate(capacity: 1)
        collectedPaths.initialize(to: Set<String>())
        defer {
            collectedPaths.deinitialize(count: 1)
            collectedPaths.deallocate()
        }

        context.info = UnsafeMutableRawPointer(collectedPaths)

        let streamCallback: FSEventStreamCallback = { _, info, numEvents, eventPaths, _, _ in
            guard let info, let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }
            let collected = info.assumingMemoryBound(to: Set<String>.self)
            for path in paths {
                collected.pointee.insert(path)
            }
        }

        guard let historyStream = FSEventStreamCreate(
            nil,
            streamCallback,
            &context,
            pathsToWatch,
            eventID,
            0, // no latency — we want all historical events
            UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        ) else {
            return nil
        }

        let queue = DispatchQueue(label: "com.chet.fsevents.history")
        FSEventStreamSetDispatchQueue(historyStream, queue)
        FSEventStreamStart(historyStream)

        // Give it a moment to process historical events
        queue.async {
            // FSEvents processes historical events synchronously on start
            semaphore.signal()
        }
        semaphore.wait()

        // Small delay to ensure all events are delivered
        Thread.sleep(forTimeInterval: 0.1)

        FSEventStreamStop(historyStream)
        FSEventStreamInvalidate(historyStream)
        FSEventStreamRelease(historyStream)

        changedPaths = collectedPaths.pointee

        // Filter to only paths under root
        let filteredPaths = changedPaths.filter { $0.hasPrefix(root) }
        return (paths: Array(filteredPaths), currentEventID: currentID)
    }

    /// Get current FSEvents event ID (for storing with initial scan).
    static func currentEventID() -> UInt64 {
        FSEventsGetCurrentEventId()
    }

    // MARK: - Live Watching

    /// Start watching for filesystem changes under root. Callback fires on changes.
    func startWatching(root: String, latency: TimeInterval = 2.0, callback: @escaping ([String]) -> Void) {
        stopWatching()
        self.callback = callback

        let pathsToWatch = [root] as CFArray
        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        let streamCallback: FSEventStreamCallback = { _, info, numEvents, eventPaths, _, _ in
            guard let info, let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }
            let watcher = Unmanaged<FSEventsWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.callback?(paths)
        }

        stream = FSEventStreamCreate(
            nil,
            streamCallback,
            &context,
            pathsToWatch,
            FSEventsGetCurrentEventId(),
            latency,
            UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagFileEvents)
        )

        if let stream {
            FSEventStreamSetDispatchQueue(stream, DispatchQueue(label: "com.chet.fsevents.live"))
            FSEventStreamStart(stream)
        }
    }

    func stopWatching() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        callback = nil
    }

    deinit {
        stopWatching()
    }
}
