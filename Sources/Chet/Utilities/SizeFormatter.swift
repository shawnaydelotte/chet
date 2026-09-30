import Foundation

enum SizeFormatter {
    private static let formatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    static func format(_ bytes: Int64) -> String {
        formatter.string(fromByteCount: bytes)
    }

    static func format(_ bytes: UInt64) -> String {
        format(Int64(clamping: bytes))
    }

    static func percentage(_ part: Int64, of whole: Int64) -> String {
        guard whole > 0 else { return "0%" }
        let pct = Double(part) / Double(whole) * 100
        if pct < 0.1 { return "<0.1%" }
        if pct >= 100 { return "100%" }
        return String(format: "%.1f%%", pct)
    }
}
