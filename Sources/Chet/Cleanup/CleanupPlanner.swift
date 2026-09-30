import Foundation

enum CleanupPlanner {
    private static let minimumCandidateBytes: Int64 = 5_000_000
    private static let maxTraversalDepth = 6
    private static let maxChildrenPerDirectory = 40

    static func findCandidates(in root: FileNode, limit: Int = 15) -> [CleanupCandidate] {
        var results = [CleanupCandidate]()
        var stack: [(node: FileNode, depth: Int)] = [(root, 0)]

        while !stack.isEmpty {
            let (node, depth) = stack.removeLast()

            if depth > 0, node.size >= minimumCandidateBytes {
                let assessment = DeletionImpactHeuristicAnalyzer.analyze(node: node, rootPath: nil)
                if assessment.riskLevel == .safe || assessment.riskLevel == .caution {
                    results.append(
                        CleanupCandidate(
                            path: assessment.path,
                            name: node.name,
                            size: node.size,
                            category: node.isDirectory ? dominantCategory(of: node) : node.category,
                            riskLevel: assessment.riskLevel,
                            reason: assessment.summary
                        )
                    )
                }
            }

            guard node.isDirectory, depth < maxTraversalDepth else { continue }
            for child in node.sortedChildren.prefix(maxChildrenPerDirectory) {
                stack.append((child, depth + 1))
            }
        }

        return results
            .sorted {
                if $0.riskLevel != $1.riskLevel { return $0.riskLevel < $1.riskLevel }
                return $0.size > $1.size
            }
            .prefix(limit)
            .map { $0 }
    }

    static func totalReclaimable(from candidates: [CleanupCandidate]) -> Int64 {
        candidates.reduce(0) { $0 + $1.size }
    }

    private static func dominantCategory(of node: FileNode) -> FileCategory {
        node.categoryBreakdown().first?.category ?? node.category
    }
}