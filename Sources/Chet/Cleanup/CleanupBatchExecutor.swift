import Foundation

struct CleanupBatchProgress: Sendable, Equatable {
    let completed: Int
    let total: Int
    let currentName: String
    let bytesReclaimed: Int64
    let failedCount: Int
}

struct CleanupBatchItemResult: Sendable {
    let path: String
    let bytes: Int64
    let success: Bool
    let error: String?
}

struct CleanupBatchResult: Sendable {
    let results: [CleanupBatchItemResult]
    let parentPathsToRefresh: [String]
    let bytesReclaimed: Int64
    let failedCount: Int
    let wasCancelled: Bool
}

enum CleanupBatchExecutor {
    /// Collapse nested selections so trashing a parent does not also try child paths.
    static func collapseNestedSelections(_ paths: [String]) -> [String] {
        let sorted = paths.map(PathNormalizer.normalize).sorted { $0.count < $1.count }
        var result = [String]()
        for path in sorted where !result.contains(where: { path.hasPrefix($0 + "/") }) {
            result.append(path)
        }
        return result
    }

    static func allowsBatchDeletion(riskLevel: CleanupRiskLevel) -> Bool {
        riskLevel == .safe || riskLevel == .caution
    }

    static func trashItems(
        candidates: [CleanupCandidate],
        nodesByPath: [String: FileNode],
        isCancelled: @Sendable () -> Bool,
        onProgress: @Sendable (CleanupBatchProgress) async -> Void
    ) async -> CleanupBatchResult {
        let workItems = candidates
        let total = workItems.count
        var results = [CleanupBatchItemResult]()
        var parentsToRefresh = Set<String>()
        var bytesReclaimed: Int64 = 0
        var failedCount = 0
        var cancelled = false

        for (index, candidate) in workItems.enumerated() {
            if isCancelled() {
                cancelled = true
                break
            }

            let path = candidate.path
            let normalized = PathNormalizer.normalize(path)

            await onProgress(CleanupBatchProgress(
                completed: index, total: total, currentName: candidate.name,
                bytesReclaimed: bytesReclaimed, failedCount: failedCount
            ))

            guard let node = nodesByPath[normalized] else {
                failedCount += 1
                results.append(CleanupBatchItemResult(path: path, bytes: 0, success: false, error: "Node not found."))
                await onProgress(CleanupBatchProgress(
                    completed: index + 1, total: total, currentName: candidate.name,
                    bytesReclaimed: bytesReclaimed, failedCount: failedCount
                ))
                continue
            }

            guard allowsBatchDeletion(riskLevel: candidate.riskLevel) else {
                failedCount += 1
                results.append(CleanupBatchItemResult(
                    path: path, bytes: candidate.size, success: false, error: candidate.reason
                ))
                await onProgress(CleanupBatchProgress(
                    completed: index + 1, total: total, currentName: candidate.name,
                    bytesReclaimed: bytesReclaimed, failedCount: failedCount
                ))
                continue
            }

            do {
                _ = try CleanupExecutor.moveToTrash(url: node.url)
                bytesReclaimed += candidate.size
                if let parent = node.parent {
                    parentsToRefresh.insert(PathNormalizer.normalize(parent.url.path(percentEncoded: false)))
                }
                results.append(CleanupBatchItemResult(path: path, bytes: candidate.size, success: true, error: nil))
            } catch {
                failedCount += 1
                results.append(CleanupBatchItemResult(
                    path: path, bytes: candidate.size, success: false, error: String(describing: error)
                ))
            }

            await onProgress(CleanupBatchProgress(
                completed: index + 1, total: total, currentName: candidate.name,
                bytesReclaimed: bytesReclaimed, failedCount: failedCount
            ))
        }

        return CleanupBatchResult(
            results: results,
            parentPathsToRefresh: parentsToRefresh.sorted(),
            bytesReclaimed: bytesReclaimed,
            failedCount: failedCount,
            wasCancelled: cancelled
        )
    }
}