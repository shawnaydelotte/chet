import Foundation

struct DeletionImpactAssessment: Equatable, Sendable {
    let path: String
    let reclaimableBytes: Int64
    let riskLevel: CleanupRiskLevel
    let summary: String
    let consequences: [String]
    let recoverability: String
    let confidence: Double
    let source: ImpactAnalysisSource

    var allowsDeletion: Bool {
        riskLevel.allowsDeletion
    }
}

struct CleanupCandidate: Identifiable, Sendable {
    let id: UUID
    let path: String
    let name: String
    let size: Int64
    let category: FileCategory
    let riskLevel: CleanupRiskLevel
    let reason: String

    init(
        id: UUID = UUID(),
        path: String,
        name: String,
        size: Int64,
        category: FileCategory,
        riskLevel: CleanupRiskLevel,
        reason: String
    ) {
        self.id = id
        self.path = path
        self.name = name
        self.size = size
        self.category = category
        self.riskLevel = riskLevel
        self.reason = reason
    }
}