import Foundation

/// Serializes live FSEvents path batches so none are dropped while a drain is in progress.
@MainActor
final class LiveUpdateQueue {
    typealias ProcessBatch = @MainActor ([String]) async -> Void

    private(set) var isDraining = false
    private(set) var pendingCount = 0

    private var pendingPaths = Set<String>()
    private let processBatch: ProcessBatch

    init(processBatch: @escaping ProcessBatch) {
        self.processBatch = processBatch
    }

    func enqueue(paths: [String]) {
        for path in paths {
            pendingPaths.insert(PathNormalizer.normalize(path))
        }
        pendingCount = pendingPaths.count
        scheduleDrain()
    }

    func cancel() {
        pendingPaths.removeAll()
        pendingCount = 0
    }

    private func scheduleDrain() {
        guard !isDraining else { return }
        Task { await drain() }
    }

    private func drain() async {
        guard !isDraining else { return }
        isDraining = true
        defer {
            isDraining = false
            pendingCount = pendingPaths.count
            if !pendingPaths.isEmpty {
                scheduleDrain()
            }
        }

        while !pendingPaths.isEmpty {
            if Task.isCancelled { break }

            let batch = Array(pendingPaths)
            pendingPaths.removeAll()
            pendingCount = pendingPaths.count

            await processBatch(batch)

            if Task.isCancelled { break }
        }
    }
}