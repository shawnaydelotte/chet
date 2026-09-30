import SwiftUI

enum FileCategory: String, CaseIterable, Identifiable, Sendable {
    case sourceCode
    case buildArtifacts
    case packageDeps
    case versionControl
    case documents
    case images
    case audioVideo
    case archives
    case vmContainer
    case securityResearch
    case databaseData
    case logsCache
    case xcodeApple
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sourceCode:       "Source Code"
        case .buildArtifacts:   "Build Artifacts"
        case .packageDeps:      "Package Dependencies"
        case .versionControl:   "Version Control"
        case .documents:        "Documents"
        case .images:           "Images"
        case .audioVideo:       "Audio / Video"
        case .archives:         "Archives"
        case .vmContainer:      "VM / Container"
        case .securityResearch: "Security / Research"
        case .databaseData:     "Data Files"
        case .logsCache:        "Logs / Cache"
        case .xcodeApple:       "Xcode / Apple Dev"
        case .other:            "Other"
        }
    }

    var color: Color {
        switch self {
        case .sourceCode:       ColorPalette.sourceCode
        case .buildArtifacts:   ColorPalette.buildArtifacts
        case .packageDeps:      ColorPalette.packageDeps
        case .versionControl:   ColorPalette.versionControl
        case .documents:        ColorPalette.documents
        case .images:           ColorPalette.images
        case .audioVideo:       ColorPalette.audioVideo
        case .archives:         ColorPalette.archives
        case .vmContainer:      ColorPalette.vmContainer
        case .securityResearch: ColorPalette.securityResearch
        case .databaseData:     ColorPalette.databaseData
        case .logsCache:        ColorPalette.logsCache
        case .xcodeApple:       ColorPalette.xcodeApple
        case .other:            ColorPalette.other
        }
    }

    var icon: String {
        switch self {
        case .sourceCode:       "chevron.left.forwardslash.chevron.right"
        case .buildArtifacts:   "hammer"
        case .packageDeps:      "shippingbox"
        case .versionControl:   "arrow.triangle.branch"
        case .documents:        "doc.text"
        case .images:           "photo"
        case .audioVideo:       "film"
        case .archives:         "archivebox"
        case .vmContainer:      "desktopcomputer"
        case .securityResearch: "lock.shield"
        case .databaseData:     "cylinder"
        case .logsCache:        "doc.plaintext"
        case .xcodeApple:       "xmark.octagon"
        case .other:            "doc"
        }
    }
}
