//
//  SyntaxHighlighter.swift
//  PiCode
//
//  A small, dependency-free highlighter for code blocks in the transcript, tool
//  output, and the file inspector. It is intentionally conservative: when a
//  language is unknown it falls back to plain monospaced text rather than
//  guessing wrong colors.
//
//  Colors are semantic (`Color(nsColor:)` on system colors) so light and dark
//  appearances both read correctly.
//

import AppKit
import SwiftUI

struct SyntaxLanguage: Hashable {
    enum Family: String {
        case swift, cLike, javascript, python, ruby, shell, json, yaml, toml, markup, css, sql, markdown, diff, plain
    }

    var family: Family
    var label: String

    init(family: Family, label: String) {
        self.family = family
        self.label = label
    }

    init(path: String) {
        self = SyntaxLanguage(identifier: path.pathExtensionLowercased)
    }

    init(identifier: String?) {
        let key = (identifier ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        switch key {
        case "swift": self.init(family: .swift, label: "Swift")
        case "c", "h", "cc", "cpp", "c++", "hpp", "hh", "m", "mm", "cs", "java", "kt", "kts", "go", "rs", "rust",
             "php", "scala", "dart", "gradle", "proto":
            self.init(family: .cLike, label: key.isEmpty ? "Code" : key)
        case "js", "jsx", "ts", "tsx", "mjs", "cjs", "javascript", "typescript", "vue", "svelte":
            self.init(family: .javascript, label: key)
        case "py", "python", "pyi": self.init(family: .python, label: "Python")
        case "rb", "ruby", "rake", "gemspec": self.init(family: .ruby, label: "Ruby")
        case "sh", "bash", "zsh", "fish", "shell", "console", "ksh", "command": self.init(family: .shell, label: "Shell")
        case "json", "jsonl", "json5", "geojson": self.init(family: .json, label: "JSON")
        case "yaml", "yml": self.init(family: .yaml, label: "YAML")
        case "toml", "ini", "cfg", "conf", "env", "properties": self.init(family: .toml, label: key)
        case "html", "htm", "xml", "svg", "xhtml", "plist", "pbxproj": self.init(family: .markup, label: key)
        case "css", "scss", "sass", "less", "styl": self.init(family: .css, label: key)
        case "sql", "graphql", "gql": self.init(family: .sql, label: key)
        case "md", "markdown", "mdx": self.init(family: .markdown, label: "Markdown")
        case "diff", "patch": self.init(family: .diff, label: "Diff")
        case "txt", "text", "log", "": self.init(family: .plain, label: key.isEmpty ? "Text" : "Text")
        default: self.init(family: .plain, label: key)
        }
    }

    static let plain = SyntaxLanguage(family: .plain, label: "Text")
    static let diff = SyntaxLanguage(family: .diff, label: "Diff")
    static let shell = SyntaxLanguage(family: .shell, label: "Shell")
}

/// Semantic syntax palette. Uses system colors so it adapts to appearance.
struct SyntaxTheme {
    var plain: Color
    var keyword: Color
    var type: Color
    var string: Color
    var number: Color
    var comment: Color
    var function: Color
    var attribute: Color
    var inserted: Color
    var deleted: Color

    static let standard = SyntaxTheme(
        plain: Color(nsColor: .labelColor),
        keyword: Color(nsColor: .systemPink),
        type: Color(nsColor: .systemTeal),
        string: Color(nsColor: .systemRed).opacity(0.85),
        number: Color(nsColor: .systemOrange),
        comment: Color(nsColor: .secondaryLabelColor),
        function: Color(nsColor: .systemPurple),
        attribute: Color(nsColor: .systemBrown),
        inserted: Color(nsColor: .systemGreen),
        deleted: Color(nsColor: .systemRed)
    )

    func color(for kind: TokenKind) -> Color {
        switch kind {
        case .keyword: return keyword
        case .type: return type
        case .string: return string
        case .number: return number
        case .comment: return comment
        case .function: return function
        case .attribute: return attribute
        case .inserted: return inserted
        case .deleted: return deleted
        case .plain: return plain
        }
    }
}

enum TokenKind: Hashable {
    case plain, keyword, type, string, number, comment, function, attribute, inserted, deleted
}

enum SyntaxHighlighter {
    /// Highlighting is pure, so its result is remembered. The key carries the family
    /// because two languages can share a text (`{}`) but not a tokenizer.
    ///
    /// Only the standard theme ships, so the theme is not part of the key; a caller
    /// that ever adds a second theme has to add it here, or the first theme's colors
    /// would be served for the second.
    private static let cache = RenderCache<AttributedString>(totalCostLimit: 3_000_000)

    static func highlight(_ code: String, language: SyntaxLanguage, theme: SyntaxTheme = .standard) -> AttributedString {
        cache.value(forKey: "\(language.family.rawValue)\u{1F}\(code)", cost: code.count) {
            highlightUncached(code, language: language, theme: theme)
        }
    }

    private static func highlightUncached(_ code: String, language: SyntaxLanguage, theme: SyntaxTheme) -> AttributedString {
        var attributed = AttributedString(code)
        attributed.font = .system(.body, design: .monospaced)

        if language.family == .diff {
            applyDiff(code, to: &attributed, theme: theme)
            return attributed
        }

        for token in tokens(in: code, language: language) {
            guard let range = Range(token.range, in: attributed) else { continue }
            attributed[range].foregroundColor = theme.color(for: token.kind)
        }
        return attributed
    }

    // MARK: - Tokenizer

    struct Token {
        var range: NSRange
        var kind: TokenKind
    }

    static func tokens(in code: String, language: SyntaxLanguage) -> [Token] {
        guard language.family != .plain else { return [] }
        let grammar = Grammar(family: language.family)
        let ns = code as NSString
        var tokens: [Token] = []
        var index = 0
        let length = ns.length

        func match(_ literal: String, at position: Int) -> Bool {
            guard position + literal.count <= length else { return false }
            return ns.substring(with: NSRange(location: position, length: literal.count)) == literal
        }

        while index < length {
            let character = ns.character(at: index)
            let scalar = UnicodeScalar(character) ?? " "

            // Line comments
            if grammar.lineComment.contains(where: { match($0, at: index) }) {
                let end = ns.range(of: "\n", options: [], range: NSRange(location: index, length: length - index))
                let stop = end.location == NSNotFound ? length : end.location
                tokens.append(Token(range: NSRange(location: index, length: stop - index), kind: .comment))
                index = stop
                continue
            }

            // Block comments
            if let pair = grammar.blockComment.first(where: { match($0.open, at: index) }) {
                let searchRange = NSRange(location: index + pair.open.count, length: length - index - pair.open.count)
                let close = ns.range(of: pair.close, options: [], range: searchRange)
                let stop = close.location == NSNotFound ? length : close.location + close.length
                tokens.append(Token(range: NSRange(location: index, length: stop - index), kind: .comment))
                index = stop
                continue
            }

            // Strings
            if let delimiter = grammar.stringDelimiters.first(where: { match($0, at: index) }) {
                var cursor = index + delimiter.count
                var closed = false
                while cursor < length {
                    if match("\\", at: cursor) { cursor += 2; continue }
                    if match(delimiter, at: cursor) { cursor += delimiter.count; closed = true; break }
                    if match("\n", at: cursor), delimiter.count == 1 { break }
                    cursor += 1
                }
                let stop = min(cursor, length)
                if closed || stop > index {
                    tokens.append(Token(range: NSRange(location: index, length: stop - index), kind: .string))
                }
                index = stop
                continue
            }

            // Numbers
            if (character >= 48 && character <= 57) || (scalar == "." && index + 1 < length && ns.character(at: index + 1) >= 48 && ns.character(at: index + 1) <= 57) {
                var cursor = index
                while cursor < length {
                    let value = ns.character(at: cursor)
                    let isDigit = (value >= 48 && value <= 57)
                    let isHex = (value >= 97 && value <= 102) || (value >= 65 && value <= 70)
                    let isDecoration = value == 46 || value == 95 || value == 120 || value == 88 || value == 98
                        || value == 111 || value == 79 || value == 101 || value == 69
                    // A sign only continues a number directly after an exponent marker.
                    let previousIsExponent = cursor > index
                        && (ns.character(at: cursor - 1) == 101 || ns.character(at: cursor - 1) == 69)
                    let isSignedExponent = previousIsExponent && (value == 43 || value == 45)
                    if isDigit || isHex || isDecoration || isSignedExponent { cursor += 1 } else { break }
                }
                tokens.append(Token(range: NSRange(location: index, length: cursor - index), kind: .number))
                index = cursor
                continue
            }

            // Attributes / decorators (`@MainActor`, `@dataclass`)
            if scalar == "@" || (grammar.attributePrefixes.contains(scalar) && grammar.usesAttributes) {
                var cursor = index + 1
                while cursor < length, isIdentifierCharacter(ns.character(at: cursor)) { cursor += 1 }
                if cursor > index + 1 {
                    tokens.append(Token(range: NSRange(location: index, length: cursor - index), kind: .attribute))
                    index = cursor
                    continue
                }
            }

            // Identifiers, keywords, types
            if isIdentifierStart(character) {
                var cursor = index
                while cursor < length, isIdentifierCharacter(ns.character(at: cursor)) { cursor += 1 }
                let word = ns.substring(with: NSRange(location: index, length: cursor - index))
                let kind: TokenKind
                if grammar.keywords.contains(word) {
                    kind = .keyword
                } else if grammar.builtinTypes.contains(word) {
                    kind = .type
                } else if let first = word.unicodeScalars.first, CharacterSet.uppercaseLetters.contains(first), grammar.typeIsUppercase {
                    kind = .type
                } else if cursor < length, ns.character(at: cursor) == 40, grammar.functionsFromCallSyntax {
                    kind = .function
                } else {
                    index = cursor
                    continue
                }
                tokens.append(Token(range: NSRange(location: index, length: cursor - index), kind: kind))
                index = cursor
                continue
            }

            index += 1
        }

        return tokens
    }

    private static func isIdentifierStart(_ value: unichar) -> Bool {
        (value >= 65 && value <= 90) || (value >= 97 && value <= 122) || value == 95 || value == 36
    }

    private static func isIdentifierCharacter(_ value: unichar) -> Bool {
        isIdentifierStart(value) || (value >= 48 && value <= 57)
    }

    private static func applyDiff(_ code: String, to attributed: inout AttributedString, theme: SyntaxTheme) {
        let ns = code as NSString
        var location = 0
        while location < ns.length {
            let lineRange = ns.lineRange(for: NSRange(location: location, length: 0))
            let line = ns.substring(with: lineRange)
            let color: Color?
            if line.hasPrefix("+") && !line.hasPrefix("+++") {
                color = theme.inserted
            } else if line.hasPrefix("-") && !line.hasPrefix("---") {
                color = theme.deleted
            } else if line.hasPrefix("@@") {
                color = theme.keyword
            } else if line.hasPrefix("diff ") || line.hasPrefix("index ") || line.hasPrefix("---") || line.hasPrefix("+++") {
                color = theme.comment
            } else {
                color = nil
            }
            if let color, let range = Range(lineRange, in: attributed) {
                attributed[range].foregroundColor = color
            }
            location = lineRange.location + max(lineRange.length, 1)
        }
    }

    // MARK: - Grammar

    struct Grammar {
        var lineComment: [String]
        var blockComment: [(open: String, close: String)]
        var stringDelimiters: [String]
        var keywords: Set<String>
        var builtinTypes: Set<String>
        var usesAttributes: Bool
        var attributePrefixes: Set<UnicodeScalar>
        var typeIsUppercase: Bool
        var functionsFromCallSyntax: Bool

        init(family: SyntaxLanguage.Family) {
            usesAttributes = false
            attributePrefixes = ["@"]
            typeIsUppercase = true
            functionsFromCallSyntax = false
            builtinTypes = []

            switch family {
            case .swift:
                lineComment = ["//"]
                blockComment = [("/*", "*/")]
                stringDelimiters = ["\"\"\"", "\""]
                keywords = Self.swiftKeywords
                builtinTypes = Self.swiftTypes
                usesAttributes = true
                attributePrefixes = ["@", "#"]
                functionsFromCallSyntax = true
            case .cLike:
                lineComment = ["//"]
                blockComment = [("/*", "*/")]
                stringDelimiters = ["\"", "'"]
                keywords = Self.cKeywords
                builtinTypes = Self.cTypes
                configureAttributes()
            case .javascript:
                lineComment = ["//"]
                blockComment = [("/*", "*/")]
                stringDelimiters = ["`", "\"", "'"]
                keywords = Self.jsKeywords
                builtinTypes = Self.jsTypes
            case .python:
                lineComment = ["#"]
                blockComment = []
                stringDelimiters = ["\"\"\"", "'''", "\"", "'"]
                keywords = Self.pythonKeywords
                builtinTypes = Self.pythonTypes
                usesAttributes = true
                attributePrefixes = ["@"]
            case .ruby:
                lineComment = ["#"]
                blockComment = []
                stringDelimiters = ["\"", "'"]
                keywords = Self.rubyKeywords
                builtinTypes = Self.rubyTypes
            case .shell:
                lineComment = ["#"]
                blockComment = []
                stringDelimiters = ["\"", "'"]
                keywords = Self.shellKeywords
                typeIsUppercase = false
            case .json:
                lineComment = ["//"]
                blockComment = []
                stringDelimiters = ["\""]
                keywords = []
                typeIsUppercase = false
            case .yaml:
                lineComment = ["#"]
                blockComment = []
                stringDelimiters = ["\"", "'"]
                keywords = ["true", "false", "null", "~", "yes", "no", "on", "off"]
                typeIsUppercase = false
            case .toml:
                lineComment = ["#"]
                blockComment = []
                stringDelimiters = ["\"\"\"", "\"", "'"]
                keywords = ["true", "false"]
                typeIsUppercase = false
            case .markup:
                lineComment = []
                blockComment = [("<!--", "-->")]
                stringDelimiters = ["\"", "'"]
                keywords = []
                typeIsUppercase = false
            case .css:
                lineComment = ["//"]
                blockComment = [("/*", "*/")]
                stringDelimiters = ["\"", "'"]
                keywords = []
                typeIsUppercase = false
            case .sql:
                lineComment = ["--"]
                blockComment = [("/*", "*/")]
                stringDelimiters = ["'", "\""]
                keywords = Self.sqlKeywords
                typeIsUppercase = false
            case .markdown:
                lineComment = []
                blockComment = []
                stringDelimiters = ["`"]
                keywords = []
                typeIsUppercase = false
            case .diff:
                lineComment = []
                blockComment = []
                stringDelimiters = []
                keywords = []
                typeIsUppercase = false
            case .plain:
                lineComment = []
                blockComment = []
                stringDelimiters = []
                keywords = []
                typeIsUppercase = false
            }
        }

        private mutating func configureAttributes() {
            usesAttributes = true
            attributePrefixes = ["@", "#"]
            functionsFromCallSyntax = true
        }
    }
}

private extension SyntaxHighlighter.Grammar {
    static let swiftKeywords: Set<String> = [
        "actor", "any", "as", "associatedtype", "async", "await", "borrowing", "break", "case", "catch", "class",
        "consume", "consuming", "continue", "convenience", "defer", "deinit", "didSet", "distributed", "do", "dynamic",
        "each", "else", "enum", "extension", "fallthrough", "false", "fileprivate", "final", "for", "func", "get",
        "guard", "if", "import", "in", "indirect", "infix", "init", "inout", "internal", "is", "isolated", "lazy",
        "let", "macro", "mutating", "nil", "nonisolated", "open", "operator", "optional", "override", "package",
        "postfix", "precedencegroup", "prefix", "private", "protocol", "public", "repeat", "required", "rethrows",
        "return", "self", "set", "some", "static", "struct", "subscript", "super", "switch", "throw", "throws",
        "true", "try", "typealias", "unowned", "var", "weak", "where", "while", "willSet"
    ]
    static let swiftTypes: Set<String> = [
        "Any", "AnyObject", "Array", "Bool", "Character", "Data", "Dictionary", "Double", "Error", "Float", "Int",
        "Never", "Optional", "Result", "Set", "String", "Substring", "UInt", "URL", "Void"
    ]
    static let cKeywords: Set<String> = [
        "auto", "break", "case", "catch", "class", "const", "constexpr", "continue", "default", "defer", "delete",
        "do", "else", "enum", "explicit", "export", "extern", "final", "for", "friend", "func", "goto", "if",
        "implements", "import", "in", "inline", "interface", "internal", "let", "mutable", "namespace", "new",
        "noexcept", "nullptr", "operator", "override", "package", "private", "protected", "public", "register",
        "return", "sealed", "sizeof", "static", "struct", "super", "switch", "template", "this", "throw", "throws",
        "try", "typedef", "typename", "union", "using", "var", "virtual", "volatile", "while", "async", "await",
        "fn", "impl", "match", "mod", "move", "mut", "pub", "ref", "trait", "type", "unsafe", "use", "where",
        "package", "defer", "go", "chan", "map", "range", "select", "nil", "true", "false"
    ]
    static let cTypes: Set<String> = [
        "bool", "char", "double", "float", "int", "long", "short", "size_t", "string", "uint", "uint8_t", "uint16_t",
        "uint32_t", "uint64_t", "int8_t", "int16_t", "int32_t", "int64_t", "void", "String", "Vec", "Option", "Result",
        "i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64", "f32", "f64", "usize", "bool", "str", "error"
    ]
    static let jsKeywords: Set<String> = [
        "as", "async", "await", "break", "case", "catch", "class", "const", "continue", "debugger", "default",
        "delete", "do", "else", "enum", "export", "extends", "false", "finally", "for", "from", "function", "get",
        "if", "implements", "import", "in", "instanceof", "interface", "let", "new", "null", "of", "package",
        "private", "protected", "public", "readonly", "return", "satisfies", "set", "static", "super", "switch",
        "this", "throw", "true", "try", "type", "typeof", "undefined", "var", "void", "while", "with", "yield"
    ]
    static let jsTypes: Set<String> = [
        "Array", "BigInt", "Boolean", "Date", "Error", "JSON", "Map", "Math", "Number", "Object", "Promise", "Record",
        "RegExp", "Set", "String", "Symbol", "any", "boolean", "never", "number", "string", "unknown", "void"
    ]
    static let pythonKeywords: Set<String> = [
        "and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del", "elif", "else", "except",
        "False", "finally", "for", "from", "global", "if", "import", "in", "is", "lambda", "None", "nonlocal", "not",
        "or", "pass", "raise", "return", "True", "try", "while", "with", "yield", "match", "case", "self"
    ]
    static let pythonTypes: Set<String> = [
        "bool", "bytes", "dict", "float", "frozenset", "int", "list", "object", "set", "str", "tuple", "type"
    ]
    static let rubyKeywords: Set<String> = [
        "alias", "and", "begin", "break", "case", "class", "def", "defined?", "do", "else", "elsif", "end", "ensure",
        "false", "for", "if", "in", "module", "next", "nil", "not", "or", "redo", "rescue", "retry", "return", "self",
        "super", "then", "true", "undef", "unless", "until", "when", "while", "yield", "require", "attr_accessor"
    ]
    static let rubyTypes: Set<String> = ["Array", "Hash", "Integer", "String", "Symbol", "Float"]
    static let shellKeywords: Set<String> = [
        "case", "do", "done", "elif", "else", "esac", "fi", "for", "function", "if", "in", "then", "until", "while",
        "export", "local", "readonly", "return", "set", "unset", "source", "alias", "sudo", "cd", "echo", "printf",
        "grep", "sed", "awk", "find", "xargs", "cat", "ls", "mkdir", "rm", "cp", "mv", "git", "npm", "pnpm", "yarn",
        "bun", "node", "python3", "pip", "swift", "xcodebuild", "curl", "chmod", "kill", "env", "which", "command"
    ]
    static let sqlKeywords: Set<String> = [
        "ALTER", "AND", "AS", "ASC", "BEGIN", "BETWEEN", "BY", "CASE", "CAST", "COMMIT", "CREATE", "DELETE", "DESC",
        "DISTINCT", "DROP", "ELSE", "END", "EXISTS", "FROM", "GROUP", "HAVING", "IF", "IN", "INDEX", "INNER",
        "INSERT", "INTO", "JOIN", "LEFT", "LIKE", "LIMIT", "NOT", "NULL", "OFFSET", "ON", "OR", "ORDER", "OUTER",
        "PRIMARY", "SELECT", "SET", "TABLE", "THEN", "UNION", "UPDATE", "VALUES", "WHEN", "WHERE",
        "select", "from", "where", "insert", "update", "delete", "create", "table", "join", "on", "group", "order",
        "by", "limit", "values", "and", "or", "not", "null", "as"
    ]
}
