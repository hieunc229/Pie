//
//  FileSystem.swift
//  PiCode
//
//  Small filesystem helpers shared by services and views.
//

import Foundation

extension String {
    /// Replaces the home directory prefix with `~` for display.
    var abbreviatingHomeDirectory: String {
        let home = NSHomeDirectory()
        guard hasPrefix(home) else { return self }
        return "~" + dropFirst(home.count)
    }

    var expandedTildePath: String {
        (self as NSString).expandingTildeInPath
    }

    var fileURL: URL {
        URL(fileURLWithPath: self)
    }

    var isAbsolutePath: Bool {
        hasPrefix("/")
    }

    var pathExtensionLowercased: String {
        (self as NSString).pathExtension.lowercased()
    }
}

enum FileClassification {
    /// Extensions treated as images that Pi can forward to a vision model.
    static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "bmp", "heic", "heif", "tiff"
    ]

    /// Extensions read as text and inlined into the prompt.
    static let textExtensions: Set<String> = [
        "txt", "md", "markdown", "json", "jsonl", "yaml", "yml", "toml", "xml", "csv", "tsv",
        "swift", "ts", "tsx", "js", "jsx", "mjs", "cjs", "py", "rb", "go", "rs", "java", "kt",
        "c", "h", "cc", "cpp", "hpp", "cs", "php", "sh", "bash", "zsh", "fish", "sql", "graphql",
        "html", "htm", "css", "scss", "sass", "less", "vue", "svelte", "env", "ini", "cfg", "conf",
        "diff", "patch", "log", "plist", "pbxproj", "gradle", "dockerfile", "makefile", "gitignore"
    ]

    static func isImage(path: String) -> Bool {
        imageExtensions.contains(path.pathExtensionLowercased)
    }

    static func isTextLike(path: String) -> Bool {
        let ext = path.pathExtensionLowercased
        if textExtensions.contains(ext) { return true }
        let name = (path as NSString).lastPathComponent.lowercased()
        return name == "dockerfile" || name == "makefile" || name == "license" || name.hasPrefix(".")
    }

    static func mimeType(for path: String) -> String {
        switch path.pathExtensionLowercased {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "bmp": return "image/bmp"
        case "heic": return "image/heic"
        case "heif": return "image/heif"
        case "tiff", "tif": return "image/tiff"
        case "json": return "application/json"
        case "md", "markdown": return "text/markdown"
        case "txt": return "text/plain"
        default: return "text/plain"
        }
    }
}

/// A read-only snapshot of one file used by the Files inspector preview.
struct FilePreview: Equatable {
    var path: String
    var text: String
    var truncated: Bool
    var byteSize: Int
    var modifiedAt: Date?
    var error: String?

    var language: SyntaxLanguage { SyntaxLanguage(path: path) }
}

enum FilePreviewLoader {
    /// Files above this size are truncated with an explicit "Show All" affordance.
    static let previewLimit = 512 * 1024

    static func load(path: String, limit: Int = previewLimit) -> FilePreview {
        let url = URL(fileURLWithPath: path)
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        let modified = attributes?[.modificationDate] as? Date

        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return FilePreview(
                path: path,
                text: "",
                truncated: false,
                byteSize: size,
                modifiedAt: modified,
                error: "Could not open the file."
            )
        }
        defer { try? handle.close() }

        let data: Data
        do {
            data = try handle.read(upToCount: limit) ?? Data()
        } catch {
            return FilePreview(
                path: path,
                text: "",
                truncated: false,
                byteSize: size,
                modifiedAt: modified,
                error: error.localizedDescription
            )
        }

        if data.contains(0) {
            return FilePreview(
                path: path,
                text: "",
                truncated: false,
                byteSize: size,
                modifiedAt: modified,
                error: "This looks like a binary file, so PiCode does not preview it."
            )
        }

        return FilePreview(
            path: path,
            text: String(data: data, encoding: .utf8) ?? "",
            truncated: size > limit,
            byteSize: size,
            modifiedAt: modified,
            error: nil
        )
    }

    static func loadFully(path: String) -> FilePreview {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        return load(path: path, limit: max(size, 1))
    }
}

/// One node in the Files inspector tree.
struct FileNode: Identifiable, Equatable, Hashable {
    var id: String { path }
    var path: String
    var name: String
    var isDirectory: Bool
    var byteSize: Int
    var children: [FileNode]?

    static func == (lhs: FileNode, rhs: FileNode) -> Bool {
        lhs.path == rhs.path && lhs.children?.count == rhs.children?.count
    }

    func hash(into hasher: inout Hasher) { hasher.combine(path) }
}

enum ProjectFileTree {
    /// Directories that would swamp the tree and are never useful in review.
    static let skippedDirectories: Set<String> = [
        ".git", "node_modules", ".build", "build", "DerivedData", ".venv", "venv",
        "__pycache__", ".next", ".turbo", "dist", ".cache", "Pods", ".idea", ".gradle"
    ]

    static func children(of directory: String, includeHidden: Bool = false) -> [FileNode] {
        let url = URL(fileURLWithPath: directory)
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .isSymbolicLinkKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: includeHidden ? [] : [.skipsHiddenFiles]
        ) else { return [] }

        return entries.compactMap { entry -> FileNode? in
            let values = try? entry.resourceValues(forKeys: Set(keys))
            let isDirectory = values?.isDirectory ?? false
            let size = values?.fileSize ?? 0
            if isDirectory, skippedDirectories.contains(entry.lastPathComponent) { return nil }
            return FileNode(
                path: entry.path,
                name: entry.lastPathComponent,
                isDirectory: isDirectory,
                byteSize: size,
                children: nil
            )
        }
        .sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    /// A flat, filtered view used when the user searches the tree.
    static func search(root: String, query: String, limit: Int = 400) -> [FileNode] {
        let needle = query.lowercased()
        var results: [FileNode] = []
        var stack = [root]
        while let directory = stack.popLast(), results.count < limit {
            for node in children(of: directory) {
                if node.isDirectory {
                    stack.append(node.path)
                } else if node.name.lowercased().contains(needle) || node.path.lowercased().contains(needle) {
                    results.append(node)
                }
            }
        }
        return results
    }

    /// Relative path used for compact display and prompt references.
    static func relativePath(of path: String, from root: String) -> String {
        guard path.hasPrefix(root) else { return path }
        var relative = String(path.dropFirst(root.count))
        if relative.hasPrefix("/") { relative.removeFirst() }
        return relative
    }
}
