// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Chet",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Chet",
            path: "Sources/Chet",
            swiftSettings: [
                .swiftLanguageMode(.v5),
                // FoundationModels @Generable macros require full Xcode; SPM/CLT builds use heuristics only.
                .define("CHET_DISABLE_CORE_AI"),
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)