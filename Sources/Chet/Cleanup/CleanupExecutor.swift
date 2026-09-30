import Foundation

enum CleanupExecutor {
    enum CleanupError: Error, Equatable {
        case protectedPath
        case blockedByRisk
        case trashFailed(String)
        case missingParent
    }

    static func moveToTrash(url: URL) throws -> URL {
        let path = url.path(percentEncoded: false)
        guard !DeletionImpactHeuristicAnalyzer.isProtectedSystemPath(path) else {
            throw CleanupError.protectedPath
        }

        var resultingURL: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
        guard let trashed = resultingURL as URL? else {
            throw CleanupError.trashFailed("Trash operation returned no URL.")
        }
        return trashed
    }
}