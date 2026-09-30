import Foundation

enum DeletionImpactHeuristicAnalyzer {
    private static let protectedPrefixes = [
        "/System",
        "/Library",
        "/usr",
        "/bin",
        "/sbin",
        "/private/var",
    ]

    private static let safeDirectoryNames: Set<String> = [
        "DerivedData",
        "__pycache__",
        ".cache",
        "Caches",
        "logs",
        "Logs",
        ".npm",
        ".yarn",
        ".nuget",
        "target",
        "build",
        ".build",
        "dist",
        "out",
        "tmp",
        "temp",
        ".pytest_cache",
        ".mypy_cache",
        ".tox",
        "coverage",
    ]

    private static let cautionDirectoryNames: Set<String> = [
        "node_modules",
        "Pods",
        "vendor",
        "bower_components",
        "venv",
        ".venv",
        "env",
        ".gradle",
        ".m2",
    ]

    private static let riskyDirectoryNames: Set<String> = [
        ".git",
        ".svn",
        ".hg",
        "Documents",
        "Desktop",
        "Pictures",
        "Movies",
        "Music",
        "Downloads",
    ]

    static func analyze(node: FileNode, rootPath: String?) -> DeletionImpactAssessment {
        let path = node.url.path(percentEncoded: false)
        let normalizedRoot = rootPath.map(PathNormalizer.normalize)

        if let normalizedRoot, PathNormalizer.normalize(path) == normalizedRoot {
            return blocked(
                path: path,
                bytes: node.size,
                summary: "Cannot delete the scan root.",
                consequences: ["Removes the entire analyzed tree from disk."]
            )
        }

        if isProtectedSystemPath(path) {
            return blocked(
                path: path,
                bytes: node.size,
                summary: "System path — deletion blocked.",
                consequences: ["May break macOS or require admin privileges."]
            )
        }

        let name = node.name
        let category = node.isDirectory ? node.category : node.category
        var risk = baseRisk(for: node, category: category, name: name)
        var consequences = defaultConsequences(for: node, category: category, name: name)
        let recoverability = recoverabilityNote(for: node, category: category, name: name)
        let summary = summaryText(for: node, risk: risk, category: category, name: name)

        if riskyDirectoryNames.contains(name) && node.isDirectory {
            risk = max(risk, .risky)
            consequences.append("Personal or project data may be lost.")
        }

        if name == ".git" {
            risk = .risky
            consequences = ["Removes version history and branches for this project."]
        }

        return DeletionImpactAssessment(
            path: path,
            reclaimableBytes: node.size,
            riskLevel: risk,
            summary: summary,
            consequences: consequences,
            recoverability: recoverability,
            confidence: 0.85,
            source: .heuristic
        )
    }

    static func isProtectedSystemPath(_ path: String) -> Bool {
        let normalized = PathNormalizer.normalize(path)
        for prefix in protectedPrefixes where normalized == prefix || normalized.hasPrefix(prefix + "/") {
            if normalized.hasPrefix("/Users/") || normalized.hasPrefix("/System/Volumes/Data/Users/") {
                continue
            }
            return true
        }
        return false
    }

    private static func baseRisk(
        for node: FileNode,
        category: FileCategory,
        name: String
    ) -> CleanupRiskLevel {
        if safeDirectoryNames.contains(name) {
            return .safe
        }
        if cautionDirectoryNames.contains(name) {
            return .caution
        }

        switch category {
        case .logsCache, .buildArtifacts:
            return .safe
        case .packageDeps:
            return .caution
        case .versionControl, .documents, .images, .audioVideo, .databaseData, .securityResearch:
            return .risky
        case .archives, .vmContainer, .xcodeApple:
            return .caution
        case .sourceCode, .other:
            return node.isDirectory ? .caution : .risky
        }
    }

    private static func defaultConsequences(
        for node: FileNode,
        category: FileCategory,
        name: String
    ) -> [String] {
        if safeDirectoryNames.contains(name) || category == .logsCache || category == .buildArtifacts {
            return ["Frees \(SizeFormatter.format(node.size)) with low functional impact."]
        }
        if cautionDirectoryNames.contains(name) || category == .packageDeps {
            return ["Dependencies must be reinstalled before builds or runs succeed again."]
        }
        if category == .versionControl {
            return ["Git history and remotes metadata for this repo will be lost."]
        }
        return ["May remove user-created content that cannot be automatically restored."]
    }

    private static func recoverabilityNote(
        for node: FileNode,
        category: FileCategory,
        name: String
    ) -> String {
        if name == "DerivedData" || category == .buildArtifacts {
            return "Regenerated on next Xcode or project build."
        }
        if cautionDirectoryNames.contains(name) || category == .packageDeps {
            return "Reinstall with package manager (npm, pip, pod, etc.)."
        }
        if category == .logsCache {
            return "Usually recreated automatically by apps."
        }
        if category == .archives {
            return "Restore only if you still have the original archive elsewhere."
        }
        if node.isDirectory {
            return "No automatic recovery — check Time Machine or cloud backups."
        }
        return "Permanent unless restored from backup."
    }

    private static func summaryText(
        for node: FileNode,
        risk: CleanupRiskLevel,
        category: FileCategory,
        name: String
    ) -> String {
        let sizeText = SizeFormatter.format(node.size)
        switch risk {
        case .safe:
            return "Reclaim \(sizeText) — \(category.displayName) content that is typically safe to remove."
        case .caution:
            return "Reclaim \(sizeText) — removable but may require reinstall or rebuild steps."
        case .risky:
            return "Reclaim \(sizeText) — likely contains important \(category.displayName.lowercased()) data."
        case .blocked:
            return "Cannot delete \(name)."
        }
    }

    private static func blocked(
        path: String,
        bytes: Int64,
        summary: String,
        consequences: [String]
    ) -> DeletionImpactAssessment {
        DeletionImpactAssessment(
            path: path,
            reclaimableBytes: bytes,
            riskLevel: .blocked,
            summary: summary,
            consequences: consequences,
            recoverability: "Not applicable.",
            confidence: 1.0,
            source: .heuristic
        )
    }
}