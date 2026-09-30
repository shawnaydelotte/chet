import SwiftUI

enum ColorPalette {
    // Spread hues evenly across the wheel, boost saturation for distinction
    static let sourceCode       = Color(hue: 0.58, saturation: 0.75, brightness: 0.90) // Blue
    static let buildArtifacts   = Color(hue: 0.08, saturation: 0.85, brightness: 0.92) // Orange
    static let packageDeps      = Color(hue: 0.95, saturation: 0.75, brightness: 0.85) // Crimson/Rose
    static let versionControl   = Color(hue: 0.00, saturation: 0.00, brightness: 0.50) // Neutral gray
    static let documents        = Color(hue: 0.35, saturation: 0.65, brightness: 0.80) // Green
    static let images           = Color(hue: 0.50, saturation: 0.70, brightness: 0.85) // Cyan
    static let audioVideo       = Color(hue: 0.75, saturation: 0.65, brightness: 0.85) // Purple
    static let archives         = Color(hue: 0.15, saturation: 0.80, brightness: 0.92) // Gold/Amber
    static let vmContainer      = Color(hue: 0.83, saturation: 0.70, brightness: 0.80) // Magenta
    static let securityResearch = Color(hue: 0.02, saturation: 0.90, brightness: 0.80) // Red
    static let databaseData     = Color(hue: 0.45, saturation: 0.60, brightness: 0.78) // Teal
    static let logsCache        = Color(hue: 0.10, saturation: 0.45, brightness: 0.55) // Brown
    static let xcodeApple       = Color(hue: 0.62, saturation: 0.85, brightness: 0.95) // Indigo
    static let other            = Color(hue: 0.00, saturation: 0.00, brightness: 0.65) // Light gray
}
