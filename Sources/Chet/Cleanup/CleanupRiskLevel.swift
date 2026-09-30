import Foundation

enum CleanupRiskLevel: String, Sendable, CaseIterable, Comparable {
    case safe
    case caution
    case risky
    case blocked

    private var sortOrder: Int {
        switch self {
        case .safe: 0
        case .caution: 1
        case .risky: 2
        case .blocked: 3
        }
    }

    static func < (lhs: CleanupRiskLevel, rhs: CleanupRiskLevel) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    var displayName: String {
        switch self {
        case .safe: "Safe"
        case .caution: "Caution"
        case .risky: "Risky"
        case .blocked: "Blocked"
        }
    }

    var allowsDeletion: Bool {
        self != .blocked
    }
}

enum ImpactAnalysisSource: String, Sendable {
    case heuristic
    case coreAI
}