import Foundation

enum CleanupPreset: String, CaseIterable, Identifiable, Sendable {
    case caches
    case buildOutput
    case packageDeps

    var id: String { rawValue }

    var title: String {
        switch self {
        case .caches: "Clear Caches"
        case .buildOutput: "Clear Build Output"
        case .packageDeps: "Clear Package Deps"
        }
    }

    var icon: String {
        switch self {
        case .caches: "doc.plaintext"
        case .buildOutput: "hammer"
        case .packageDeps: "shippingbox"
        }
    }

    func matches(_ candidate: CleanupCandidate) -> Bool {
        switch self {
        case .caches:
            return candidate.category == .logsCache
                || candidate.riskLevel == .safe && Self.cacheDirectoryNames.contains(candidate.name)
        case .buildOutput:
            return candidate.category == .buildArtifacts
                || Self.buildDirectoryNames.contains(candidate.name)
        case .packageDeps:
            return candidate.category == .packageDeps
                || Self.packageDirectoryNames.contains(candidate.name)
        }
    }

    static func matchingIDs(in candidates: [CleanupCandidate], preset: CleanupPreset) -> Set<UUID> {
        Set(candidates.filter { preset.matches($0) }.map(\.id))
    }

    private static let cacheDirectoryNames: Set<String> = [
        ".cache", "Caches", "logs", "Logs", ".pytest_cache", ".mypy_cache", ".tox", "coverage",
    ]

    private static let buildDirectoryNames: Set<String> = [
        "DerivedData", "target", "build", ".build", "dist", "out", "tmp", "temp",
    ]

    private static let packageDirectoryNames: Set<String> = [
        "node_modules", "Pods", "vendor", "bower_components", "venv", ".venv", "env", ".gradle", ".m2",
    ]
}