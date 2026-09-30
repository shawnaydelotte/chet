import Foundation

enum FileClassifier {
    private static let extensionMap: [String: FileCategory] = {
        var map = [String: FileCategory]()

        let sourceExts = [
            "swift", "py", "js", "ts", "tsx", "jsx", "go", "rs", "c", "cpp", "cc", "cxx",
            "h", "hpp", "hxx", "m", "mm", "java", "kt", "kts", "scala", "rb", "sh", "zsh",
            "bash", "fish", "pl", "pm", "lua", "zig", "asm", "s", "r", "jl", "ex", "exs",
            "erl", "hs", "ml", "mli", "fs", "fsx", "cs", "vb", "php", "dart", "v", "sv",
            "nim", "cr", "d", "pas", "ada", "f90", "f95", "lisp", "cl", "el", "clj", "cljs",
            "vue", "svelte", "sol", "move", "cairo", "wat", "wast"
        ]
        for ext in sourceExts { map[ext] = .sourceCode }

        let buildExts = [
            "o", "a", "dylib", "so", "dll", "lib", "framework", "app", "dSYM",
            "class", "jar", "war", "wasm", "bc", "ll", "pch", "gch",
            "exe", "msi", "deb", "rpm", "pkg"
        ]
        for ext in buildExts { map[ext] = .buildArtifacts }

        let docExts = [
            "pdf", "doc", "docx", "txt", "md", "markdown", "rtf", "pages",
            "odt", "tex", "latex", "rst", "adoc", "org", "epub"
        ]
        for ext in docExts { map[ext] = .documents }

        let imageExts = [
            "png", "jpg", "jpeg", "gif", "svg", "ico", "webp", "heic", "heif",
            "tiff", "tif", "bmp", "raw", "cr2", "nef", "arw", "dng", "psd",
            "ai", "sketch", "fig", "xcf", "exr", "hdr"
        ]
        for ext in imageExts { map[ext] = .images }

        let avExts = [
            "mp3", "mp4", "m4a", "m4v", "mov", "wav", "aac", "flac", "ogg",
            "opus", "wma", "avi", "mkv", "wmv", "flv", "webm", "3gp",
            "aif", "aiff", "alac", "mid", "midi"
        ]
        for ext in avExts { map[ext] = .audioVideo }

        let archiveExts = [
            "zip", "tar", "gz", "tgz", "bz2", "xz", "zst", "lz", "lz4",
            "7z", "rar", "dmg", "iso", "img", "cpio", "ar", "cab"
        ]
        for ext in archiveExts { map[ext] = .archives }

        let vmExts = [
            "vmdk", "qcow2", "vdi", "vhd", "vhdx", "ova", "ovf",
            "vagrant", "box", "parallels"
        ]
        for ext in vmExts { map[ext] = .vmContainer }

        let secExts = [
            "pcap", "pcapng", "bin", "elf", "macho", "pe", "hex", "srec",
            "ida", "idb", "i64", "bndb", "ghidra", "gzf",
            "yara", "yar", "sigma", "rule", "snort",
            "cap", "dmp", "core", "crash", "ips",
            "pem", "crt", "cer", "der", "p12", "pfx", "key", "csr", "jks"
        ]
        for ext in secExts { map[ext] = .securityResearch }

        let dataExts = [
            "db", "sqlite", "sqlite3", "realm", "json", "jsonl", "ndjson",
            "csv", "tsv", "xml", "yaml", "yml", "plist", "toml",
            "parquet", "avro", "orc", "arrow", "feather",
            "sql", "graphql", "gql", "proto", "protobuf"
        ]
        for ext in dataExts { map[ext] = .databaseData }

        let logExts = ["log", "tmp", "temp", "bak", "swp", "swo"]
        for ext in logExts { map[ext] = .logsCache }

        let xcodeExts = [
            "xcodeproj", "xcworkspace", "playground", "storyboard", "xib",
            "xcassets", "xcconfig", "entitlements", "pbxproj",
            "xcdatamodeld", "xcmappingmodel", "intentdefinition"
        ]
        for ext in xcodeExts { map[ext] = .xcodeApple }

        return map
    }()

    private static let directoryMap: [String: FileCategory] = [
        "node_modules": .packageDeps,
        "bower_components": .packageDeps,
        "vendor": .packageDeps,
        "Pods": .packageDeps,
        "venv": .packageDeps,
        ".venv": .packageDeps,
        "env": .packageDeps,
        ".gradle": .packageDeps,
        ".m2": .packageDeps,
        "target": .buildArtifacts,
        "build": .buildArtifacts,
        ".build": .buildArtifacts,
        "dist": .buildArtifacts,
        "out": .buildArtifacts,
        "DerivedData": .xcodeApple,
        ".git": .versionControl,
        ".svn": .versionControl,
        ".hg": .versionControl,
        "__pycache__": .logsCache,
        ".cache": .logsCache,
        ".npm": .logsCache,
        ".yarn": .logsCache,
        ".nuget": .logsCache,
        "Caches": .logsCache,
        "logs": .logsCache,
    ]

    static func classify(name: String, isDirectory: Bool) -> FileCategory {
        if isDirectory {
            if let cat = directoryMap[name] { return cat }
            return .other
        }
        let ext = (name as NSString).pathExtension.lowercased()
        if ext.isEmpty { return .other }
        return extensionMap[ext] ?? .other
    }
}
