import Foundation

#if canImport(FoundationModels) && !CHET_DISABLE_CORE_AI
import FoundationModels

@available(macOS 26.0, *)
enum DeletionImpactCoreAIAnalyzer {
    @Generable(description: "Deletion risk assessment for a filesystem item")
    struct DeletionRiskScore {
        @Guide(description: "One of: safe, caution, risky, blocked")
        var risk: String

        @Guide(description: "One sentence describing what happens if this item is deleted")
        var summary: String

        @Guide(description: "Short phrase describing how recoverable the data is")
        var recoverability: String
    }

    static var isAvailable: Bool {
        switch SystemLanguageModel.default.availability {
        case .available:
            return true
        default:
            return false
        }
    }

    static func analyze(node: FileNode, rootPath: String?) async -> DeletionImpactAssessment? {
        guard isAvailable else { return nil }

        let heuristic = DeletionImpactHeuristicAnalyzer.analyze(node: node, rootPath: rootPath)
        guard heuristic.riskLevel != .blocked else { return heuristic }

        let path = node.url.path(percentEncoded: false)
        let prompt = """
        Assess deleting this filesystem item on macOS.
        Path: \(path)
        Name: \(node.name)
        Type: \(node.isDirectory ? "directory" : "file")
        Category: \(node.category.displayName)
        Size: \(SizeFormatter.format(node.size))
        Files: \(node.fileCount)
        Folders: \(node.directoryCount)
        Heuristic risk: \(heuristic.riskLevel.rawValue)

        Prefer safe for caches, build output, and regenerable dependencies.
        Prefer risky for documents, media, databases, and version control.
        Use blocked only for system paths.
        """

        let instructions = """
        You assess macOS disk cleanup risk. Respond only with structured fields.
        Do not claim to be a person or assistant brand. Keep summaries factual and brief.
        """

        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(
                to: prompt,
                generating: DeletionRiskScore.self,
                options: GenerationOptions(sampling: .greedy, maximumResponseTokens: 120)
            )
            let score = response.content
            let risk = parseRisk(score.risk, fallback: heuristic.riskLevel)
            let consequences = heuristic.consequences

            return DeletionImpactAssessment(
                path: path,
                reclaimableBytes: node.size,
                riskLevel: risk,
                summary: score.summary.trimmingCharacters(in: .whitespacesAndNewlines),
                consequences: consequences,
                recoverability: score.recoverability.trimmingCharacters(in: .whitespacesAndNewlines),
                confidence: 0.72,
                source: .coreAI
            )
        } catch {
            return nil
        }
    }

    private static func parseRisk(_ raw: String, fallback: CleanupRiskLevel) -> CleanupRiskLevel {
        let normalized = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.contains("blocked") { return .blocked }
        if normalized.contains("risky") { return .risky }
        if normalized.contains("caution") { return .caution }
        if normalized.contains("safe") { return .safe }
        return fallback
    }
}
#endif