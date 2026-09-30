import Foundation

enum CleanupSelection {
    /// Returns one candidate per collapsed path (parent wins over nested children).
    static func collapsed(from candidates: [CleanupCandidate], selectedIDs: Set<UUID>) -> [CleanupCandidate] {
        let selected = candidates.filter { selectedIDs.contains($0.id) }
        guard !selected.isEmpty else { return [] }

        let collapsedPaths = CleanupBatchExecutor.collapseNestedSelections(selected.map(\.path))
        var byPath = [String: CleanupCandidate]()
        for candidate in selected {
            byPath[PathNormalizer.normalize(candidate.path)] = candidate
        }
        return collapsedPaths.compactMap { byPath[$0] }
    }

    static func tallyBytes(from candidates: [CleanupCandidate], selectedIDs: Set<UUID>) -> Int64 {
        collapsed(from: candidates, selectedIDs: selectedIDs).reduce(0) { $0 + $1.size }
    }

    static func selectionCount(from candidates: [CleanupCandidate], selectedIDs: Set<UUID>) -> Int {
        collapsed(from: candidates, selectedIDs: selectedIDs).count
    }
}