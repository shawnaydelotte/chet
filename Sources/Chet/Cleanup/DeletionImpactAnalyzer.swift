import Foundation

enum DeletionImpactAnalyzer {
    static func analyze(node: FileNode, rootPath: String?) async -> DeletionImpactAssessment {
        #if canImport(FoundationModels) && !CHET_DISABLE_CORE_AI
        if #available(macOS 26.0, *) {
            if let coreAI = await DeletionImpactCoreAIAnalyzer.analyze(node: node, rootPath: rootPath) {
                return coreAI
            }
        }
        #endif
        return DeletionImpactHeuristicAnalyzer.analyze(node: node, rootPath: rootPath)
    }

    static var coreAIAvailable: Bool {
        #if canImport(FoundationModels) && !CHET_DISABLE_CORE_AI
        if #available(macOS 26.0, *) {
            return DeletionImpactCoreAIAnalyzer.isAvailable
        }
        #endif
        return false
    }
}