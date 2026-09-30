import Foundation

enum PathNormalizer {
    /// Normalize a path for consistent cache key matching (strip trailing slash except root "/")
    static func normalize(_ path: String) -> String {
        var p = path
        if p.count > 1 && p.hasSuffix("/") { p = String(p.dropLast()) }
        return p
    }
}