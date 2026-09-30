import Foundation

/// Prioritized product enhancements for disk reclaim and intelligent cleanup.
///
/// **Shipped (v1 cleanup foundation)**
/// - Heuristic deletion-impact scoring by category and known directory names
/// - Optional Apple Intelligence overlay via FoundationModels on macOS 26+
/// - Cleanup candidate planner ranked by size and safety
/// - Move-to-trash with tree/cache/volume refresh through existing `applyDiff`
/// - Reclaim Space panel and per-item impact analysis in Detail
///
/// **Shipped (v2 faster reclaim workflows)**
/// - Multi-select queue with batch trash and running byte tally
/// - One-click presets: "Clear caches", "Clear build output", "Clear package deps"
/// - Background cleanup executor with progress UI and cancel
///
/// **Next — faster reclaim workflows**
/// - Duplicate/hardlink detection to surface redundant reclaim targets
///
/// **Next — smarter impact (Core AI)**
/// - Tool-calling session that reads `FileNode` metadata and parent context
/// - Multi-pass analysis: classify risk, then generate human consequences
/// - Project-aware prompts (Xcode, npm, Docker, Python venv) using path neighbors
/// - "What breaks if I delete this?" simulation cached per path hash
///
/// **Next — smoother UX**
/// - Cleanup mode overlay on treemap (risk color borders, hide risky categories)
/// - Undo stack via Trash restoration where macOS exposes it
/// - Scheduled incremental "reclaim report" notifications
/// - Space budget targets ("keep 50 GB free on this volume")
enum EnhancementRoadmap {
    static let currentPhase = "cleanup-workflows-v2"
}