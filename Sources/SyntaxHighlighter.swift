import AppKit

// MARK: - Theme

enum EditorTheme {
    static let background = NSColor(name: nil) { appearance in
        isDark(appearance) ? NSColor(hex: 0x1C1C1F) : NSColor(hex: 0xFCFCFD)
    }
    static let gutterBackground = NSColor(name: nil) { appearance in
        isDark(appearance) ? NSColor(hex: 0x202024) : NSColor(hex: 0xF5F5F7)
    }
    static let gutterText = NSColor(name: nil) { appearance in
        isDark(appearance) ? NSColor(hex: 0x77777F) : NSColor(hex: 0xA0A0A8)
    }
    static let gutterCurrentText = NSColor(name: nil) { appearance in
        isDark(appearance) ? NSColor(hex: 0xD5D5DC) : NSColor(hex: 0x4A4A52)
    }
    static let currentLine = NSColor(name: nil) { appearance in
        isDark(appearance) ? NSColor(white: 1, alpha: 0.045) : NSColor(white: 0, alpha: 0.032)
    }
    static let separator = NSColor(name: nil) { appearance in
        isDark(appearance) ? NSColor(white: 1, alpha: 0.08) : NSColor(white: 0, alpha: 0.08)
    }

    static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

private enum CodePalette {
    static let keyword = dynamic(0x9B2393, 0xFC5FA3)
    static let string = dynamic(0xC41A16, 0xFC6A5D)
    static let comment = dynamic(0x6C7986, 0x7F8C98)
    static let number = dynamic(0x1C00CF, 0xD0BF69)
    static let type = dynamic(0x0F68A0, 0x5DD8FF)
    static let attribute = dynamic(0x815F03, 0xD9C97C)
    static let tag = dynamic(0x9B2393, 0xFC5FA3)
    static let heading = dynamic(0x0F68A0, 0x5DD8FF)
    static let inserted = dynamic(0x1A7F37, 0x7EE787)
    static let deleted = dynamic(0xCF222E, 0xFF7B72)
    static let muted = dynamic(0x8C8C92, 0x8C8C92)

    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            EditorTheme.isDark(appearance) ? NSColor(hex: dark) : NSColor(hex: light)
        }
    }
}

private extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

private extension NSRange {
    func intersects(_ other: NSRange) -> Bool {
        location < NSMaxRange(other) && other.location < NSMaxRange(self)
    }
}

// MARK: - Highlighter

final class SyntaxHighlighter {
    var language: SyntaxLanguage
    var fontSize: CGFloat

    private struct Profile {
        var lineComments: [String] = []
        var blockComments: [(String, String)] = []
        var stringPatterns: [String] = []
        var keywords: [String] = []
        var types: [String] = []
        var caseInsensitive = false
    }

    private static let cLikeStrings = [
        "\"\"\"[\\s\\S]*?\"\"\"",
        "'''(?:[^'\\\\]|\\\\.)*'''",
        "\"(?:\\\\.|[^\"\\\\])*\"",
        "'(?:\\\\.|[^'\\\\])*'"
    ]

    private static let doubleQuoted = ["\"(?:\\\\.|[^\"\\\\])*\""]
    private static let singleAndDoubleQuoted = [
        "\"(?:\\\\.|[^\"\\\\])*\"",
        "'(?:\\\\.|[^'\\\\])*'"
    ]

    init(language: SyntaxLanguage, fontSize: CGFloat) {
        self.language = language
        self.fontSize = fontSize
    }

    func apply(to textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        guard !textView.hasMarkedText() else { return }
        let full = NSRange(location: 0, length: storage.length)
        guard full.length > 0 else {
            textView.typingAttributes = baseAttributes()
            return
        }
        let text = storage.string
        storage.beginEditing()
        storage.setAttributes(baseAttributes(), range: full)
        if full.length <= 500_000 {
            applySyntax(storage: storage, text: text, range: full)
        }
        storage.endEditing()
        textView.typingAttributes = baseAttributes()
        textView.needsDisplay = true
    }

    func baseAttributes() -> [NSAttributedString.Key: Any] {
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        paragraph.paragraphSpacing = 0
        paragraph.defaultTabInterval = fontSize * 0.62 * 4
        paragraph.tabStops = []
        return [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
    }

    private func applySyntax(storage: NSTextStorage, text: String, range: NSRange) {
        switch language {
        case .plainText:
            return
        case .json:
            applyJSON(storage: storage, text: text, range: range, allowComments: false)
        case .jsonc:
            applyJSON(storage: storage, text: text, range: range, allowComments: true)
        case .markdown:
            applyMarkdown(storage: storage, text: text, range: range)
        case .html, .xml, .plist, .vue, .svelte:
            applyMarkup(storage: storage, text: text, range: range)
        case .yaml:
            applyYAML(storage: storage, text: text, range: range)
        case .toml:
            applyTOML(storage: storage, text: text, range: range)
        case .ini:
            applyINI(storage: storage, text: text, range: range)
        case .diff:
            applyDiff(storage: storage, text: text, range: range)
        case .log:
            applyLog(storage: storage, text: text, range: range)
        case .latex:
            applyLaTeX(storage: storage, text: text, range: range)
        case .dockerfile:
            applyDockerfile(storage: storage, text: text, range: range)
        case .makefile:
            applyMakefile(storage: storage, text: text, range: range)
        case .shell, .powershell:
            applyShell(storage: storage, text: text, range: range)
        case .batch:
            applyBatch(storage: storage, text: text, range: range)
        case .csv:
            applyCSV(storage: storage, text: text, range: range)
        case .fortran77:
            applyFortran77(storage: storage, text: text, range: range)
        case .fortran90:
            applyFortran90(storage: storage, text: text, range: range)
        default:
            applyGeneric(storage: storage, text: text, range: range)
        }
    }

    // MARK: Generic languages

    private func applyGeneric(storage: NSTextStorage, text: String, range: NSRange) {
        let profile = profile(for: language)
        var stringRanges: [NSRange] = []
        for pattern in profile.stringPatterns {
            paint(pattern: pattern, options: [], attributes: [.foregroundColor: CodePalette.string],
                  text: text, range: range, excluding: [], storage: storage, collect: &stringRanges)
        }
        stringRanges = merge(stringRanges)

        var commentRanges: [NSRange] = []
        for token in profile.lineComments {
            let pattern = NSRegularExpression.escapedPattern(for: token) + "[^\\n]*"
            paint(pattern: pattern, options: [], attributes: [.foregroundColor: CodePalette.comment],
                  text: text, range: range, excluding: [stringRanges], storage: storage, collect: &commentRanges)
        }
        for (start, end) in profile.blockComments {
            let pattern = NSRegularExpression.escapedPattern(for: start) + "[\\s\\S]*?" +
                NSRegularExpression.escapedPattern(for: end)
            paint(pattern: pattern, options: [], attributes: [.foregroundColor: CodePalette.comment],
                  text: text, range: range, excluding: [stringRanges], storage: storage, collect: &commentRanges)
        }
        commentRanges = merge(commentRanges)
        let protected = [stringRanges, commentRanges]

        if !profile.keywords.isEmpty {
            paint(pattern: keywordPattern(profile.keywords),
                  options: profile.caseInsensitive ? [.caseInsensitive] : [],
                  attributes: [.foregroundColor: CodePalette.keyword],
                  text: text, range: range, excluding: protected, storage: storage)
        }
        if !profile.types.isEmpty {
            paint(pattern: keywordPattern(profile.types),
                  options: profile.caseInsensitive ? [.caseInsensitive] : [],
                  attributes: [.foregroundColor: CodePalette.type],
                  text: text, range: range, excluding: protected, storage: storage)
        }
        paint(pattern: "\\b(?:0[xX][0-9A-Fa-f_]+|0[bB][01_]+|\\d[\\d_]*(?:\\.[\\d_]+)?(?:[eE][+-]?\\d+)?)\\b",
              options: [], attributes: [.foregroundColor: CodePalette.number],
              text: text, range: range, excluding: protected, storage: storage)
    }

    private func keywordPattern(_ words: [String]) -> String {
        let escaped = words.map { NSRegularExpression.escapedPattern(for: $0) }
        return "\\b(?:" + escaped.joined(separator: "|") + ")\\b"
    }

    private func profile(for language: SyntaxLanguage) -> Profile {
        var p = Profile()
        switch language {
        case .swift:
            p.lineComments = ["//"]
            p.blockComments = [("/*", "*/")]
            p.stringPatterns = Self.cLikeStrings
            p.keywords = ["associatedtype", "class", "deinit", "enum", "extension", "fileprivate", "func", "import", "init", "inout", "internal", "let", "open", "operator", "private", "precedencegroup", "protocol", "public", "rethrows", "static", "struct", "subscript", "typealias", "var", "break", "case", "catch", "continue", "default", "defer", "do", "else", "fallthrough", "for", "guard", "if", "in", "repeat", "return", "throw", "switch", "where", "while", "as", "false", "is", "nil", "self", "Self", "super", "throws", "true", "try", "actor", "async", "await", "some", "any", "macro"]
            p.types = ["Int", "String", "Double", "Float", "Bool", "Array", "Dictionary", "Set", "Optional", "Result", "Void", "Any", "AnyObject", "Character", "Data", "Date", "URL", "Error", "Codable", "Equatable", "Hashable", "Sendable"]
        case .python:
            p.lineComments = ["#"]
            p.stringPatterns = Self.cLikeStrings
            p.keywords = ["False", "None", "True", "and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del", "elif", "else", "except", "finally", "for", "from", "global", "if", "import", "in", "is", "lambda", "nonlocal", "not", "or", "pass", "raise", "return", "try", "while", "with", "yield", "match", "case"]
            p.types = ["int", "str", "float", "bool", "list", "dict", "set", "tuple", "bytes", "bytearray", "object", "type", "None"]
        case .javascript, .typescript:
            p.lineComments = ["//"]
            p.blockComments = [("/*", "*/")]
            p.stringPatterns = Self.cLikeStrings + ["`(?:\\\\.|[^`\\\\])*`"]
            p.keywords = ["break", "case", "catch", "class", "const", "continue", "debugger", "default", "delete", "do", "else", "export", "extends", "finally", "for", "function", "if", "import", "in", "instanceof", "let", "new", "return", "super", "switch", "this", "throw", "try", "typeof", "var", "void", "while", "with", "yield", "async", "await", "of", "static", "get", "set", "from", "as", "true", "false", "null", "undefined"]
            if language == .typescript {
                p.keywords += ["interface", "type", "enum", "implements", "private", "public", "protected", "readonly", "declare", "namespace", "abstract", "keyof", "infer", "is", "satisfies"]
                p.types = ["string", "number", "boolean", "object", "symbol", "bigint", "unknown", "never", "any", "void", "Promise", "Array", "Record", "Partial", "Readonly"]
            } else {
                p.types = ["Promise", "Array", "Object", "Map", "Set", "Date", "RegExp"]
            }
        case .c:
            p.lineComments = ["//"]
            p.blockComments = [("/*", "*/")]
            p.stringPatterns = Self.doubleQuoted + ["'(?:\\\\.|[^'\\\\])'"]
            p.keywords = ["auto", "break", "case", "const", "continue", "default", "do", "else", "enum", "extern", "for", "goto", "if", "inline", "register", "return", "sizeof", "static", "struct", "switch", "typedef", "union", "volatile", "while", "restrict"]
            p.types = ["char", "double", "float", "int", "long", "short", "signed", "unsigned", "void", "size_t", "ssize_t", "int8_t", "int16_t", "int32_t", "int64_t", "uint8_t", "uint16_t", "uint32_t", "uint64_t", "bool"]
        case .cpp, .objectiveC, .java, .kotlin:
            p.lineComments = ["//"]
            p.blockComments = [("/*", "*/")]
            p.stringPatterns = Self.cLikeStrings
            var words = ["auto", "break", "case", "catch", "class", "const", "constexpr", "continue", "default", "delete", "do", "else", "enum", "explicit", "export", "extern", "false", "final", "for", "friend", "if", "inline", "namespace", "new", "noexcept", "nullptr", "operator", "override", "private", "protected", "public", "return", "sizeof", "static", "struct", "switch", "template", "this", "throw", "true", "try", "typedef", "typename", "union", "using", "virtual", "volatile", "while"]
            var types = ["bool", "char", "double", "float", "int", "long", "short", "signed", "unsigned", "void", "size_t", "string", "vector", "map", "set", "unique_ptr", "shared_ptr"]
            if language == .java {
                words = ["abstract", "assert", "break", "case", "catch", "class", "const", "continue", "default", "do", "else", "enum", "extends", "final", "finally", "for", "goto", "if", "implements", "import", "instanceof", "interface", "native", "new", "package", "private", "protected", "public", "return", "static", "strictfp", "super", "switch", "synchronized", "this", "throw", "throws", "transient", "try", "volatile", "while", "record", "sealed", "permits", "var", "true", "false", "null"]
                types = ["boolean", "byte", "char", "double", "float", "int", "long", "short", "void", "String", "Object", "List", "Map", "Set", "Optional", "Integer"]
            } else if language == .kotlin {
                words = ["as", "break", "class", "continue", "do", "else", "false", "for", "fun", "if", "in", "interface", "is", "null", "object", "package", "return", "super", "this", "throw", "true", "try", "typealias", "typeof", "val", "var", "when", "while", "by", "catch", "constructor", "delegate", "dynamic", "field", "file", "finally", "get", "import", "init", "param", "property", "receiver", "set", "setparam", "where", "actual", "abstract", "annotation", "companion", "const", "crossinline", "data", "enum", "expect", "external", "final", "infix", "inline", "inner", "internal", "lateinit", "noinline", "open", "operator", "out", "override", "private", "protected", "public", "reified", "sealed", "suspend", "tailrec", "vararg"]
                types = ["Int", "Long", "Short", "Byte", "Float", "Double", "Boolean", "Char", "String", "Unit", "Any", "Nothing", "List", "Map", "Set", "Array", "Sequence"]
            } else if language == .objectiveC {
                words += ["@interface", "@implementation", "@end", "@property", "@synthesize", "@dynamic", "@protocol", "@selector", "@try", "@catch", "@finally", "@autoreleasepool", "@synchronized", "id", "instancetype", "nonatomic", "strong", "weak", "copy", "readonly", "readwrite"]
                types += ["NSObject", "NSString", "NSArray", "NSDictionary", "NSNumber", "BOOL", "NSInteger", "NSUInteger", "CGFloat", "CGRect"]
            }
            p.keywords = words
            p.types = types
        case .rust:
            p.lineComments = ["//"]
            p.blockComments = [("/*", "*/")]
            p.stringPatterns = Self.cLikeStrings + ["r#*\"[\\s\\S]*?\"#*"]
            p.keywords = ["as", "async", "await", "break", "const", "continue", "crate", "dyn", "else", "enum", "extern", "false", "fn", "for", "if", "impl", "in", "let", "loop", "match", "mod", "move", "mut", "pub", "ref", "return", "self", "Self", "static", "struct", "super", "trait", "true", "type", "unsafe", "use", "where", "while", "abstract", "become", "box", "do", "final", "macro", "override", "priv", "typeof", "unsized", "virtual", "yield", "try"]
            p.types = ["i8", "i16", "i32", "i64", "i128", "isize", "u8", "u16", "u32", "u64", "u128", "usize", "f32", "f64", "bool", "char", "str", "String", "Vec", "Option", "Result", "Box", "Rc", "Arc"]
        case .go:
            p.lineComments = ["//"]
            p.blockComments = [("/*", "*/")]
            p.stringPatterns = Self.cLikeStrings + ["`[^`]*`"]
            p.keywords = ["break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough", "for", "func", "go", "goto", "if", "import", "interface", "map", "package", "range", "return", "select", "struct", "switch", "type", "var"]
            p.types = ["bool", "byte", "complex64", "complex128", "error", "float32", "float64", "int", "int8", "int16", "int32", "int64", "rune", "string", "uint", "uint8", "uint16", "uint32", "uint64", "uintptr", "any"]
        case .ruby:
            p.lineComments = ["#"]
            p.stringPatterns = Self.cLikeStrings
            p.keywords = ["BEGIN", "END", "alias", "and", "begin", "break", "case", "class", "def", "defined?", "do", "else", "elsif", "end", "ensure", "false", "for", "if", "in", "module", "next", "nil", "not", "or", "redo", "rescue", "retry", "return", "self", "super", "then", "true", "undef", "unless", "until", "when", "while", "yield", "require", "require_relative", "attr_accessor", "attr_reader", "attr_writer"]
            p.types = ["String", "Integer", "Float", "Array", "Hash", "Symbol", "Proc", "Time", "File", "IO"]
        case .php:
            p.lineComments = ["//", "#"]
            p.blockComments = [("/*", "*/")]
            p.stringPatterns = Self.cLikeStrings
            p.keywords = ["abstract", "and", "array", "as", "break", "callable", "case", "catch", "class", "clone", "const", "continue", "declare", "default", "do", "echo", "else", "elseif", "empty", "enddeclare", "endfor", "endforeach", "endif", "endswitch", "endwhile", "eval", "exit", "extends", "final", "finally", "fn", "for", "foreach", "function", "global", "goto", "if", "implements", "include", "include_once", "instanceof", "insteadof", "interface", "isset", "list", "match", "namespace", "new", "or", "print", "private", "protected", "public", "readonly", "require", "require_once", "return", "static", "switch", "throw", "trait", "try", "unset", "use", "var", "while", "xor", "yield", "true", "false", "null"]
            p.types = ["string", "int", "float", "bool", "array", "object", "mixed", "void", "never", "self", "static"]
        case .lua:
            p.lineComments = ["--"]
            p.blockComments = [("--[[", "]]")]
            p.stringPatterns = Self.singleAndDoubleQuoted + ["\\[\\[[\\s\\S]*?\\]\\]"]
            p.keywords = ["and", "break", "do", "else", "elseif", "end", "false", "for", "function", "goto", "if", "in", "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while"]
            p.types = ["string", "number", "table", "boolean", "function", "thread", "userdata"]
        case .r:
            p.lineComments = ["#"]
            p.stringPatterns = Self.singleAndDoubleQuoted
            p.keywords = ["if", "else", "repeat", "while", "function", "for", "in", "next", "break", "TRUE", "FALSE", "NULL", "Inf", "NaN", "NA", "library", "require", "return"]
            p.types = ["numeric", "character", "logical", "factor", "data.frame", "matrix", "list"]
        case .perl:
            p.lineComments = ["#"]
            p.stringPatterns = Self.singleAndDoubleQuoted
            p.keywords = ["my", "our", "local", "sub", "package", "use", "require", "if", "elsif", "else", "unless", "while", "until", "for", "foreach", "do", "last", "next", "redo", "return", "die", "warn", "eval", "print", "say", "open", "close", "defined", "undef", "and", "or", "not", "xor", "eq", "ne", "lt", "gt", "le", "ge"]
        case .haskell:
            p.lineComments = ["--"]
            p.blockComments = [("{-", "-}")]
            p.stringPatterns = Self.doubleQuoted + ["'(?:\\\\.|[^'\\\\])'"]
            p.keywords = ["case", "class", "data", "default", "deriving", "do", "else", "if", "import", "in", "infix", "infixl", "infixr", "instance", "let", "module", "newtype", "of", "then", "type", "where", "forall", "foreign", "qualified", "as", "hiding"]
            p.types = ["Int", "Integer", "Float", "Double", "Bool", "Char", "String", "Maybe", "Either", "IO", "List"]
        case .fortran77:
            p.lineComments = ["!"]
            p.stringPatterns = ["'(?:''|[^'])*'", "\"(?:\"\"|[^\"])*\""]
            p.keywords = ["PROGRAM", "SUBROUTINE", "FUNCTION", "BLOCK", "DATA", "COMMON", "DIMENSION", "EQUIVALENCE", "EXTERNAL", "INTRINSIC", "SAVE", "PARAMETER", "IMPLICIT", "NONE", "IF", "THEN", "ELSE", "ELSEIF", "ENDIF", "DO", "WHILE", "CONTINUE", "GO", "TO", "GOTO", "CALL", "RETURN", "STOP", "PAUSE", "READ", "WRITE", "PRINT", "OPEN", "CLOSE", "INQUIRE", "REWIND", "BACKSPACE", "ENDFILE", "FORMAT", "ASSIGN", "ENTRY", "END", "INCLUDE", "TRUE", "FALSE", "NOT", "AND", "OR", "EQ", "NE", "LT", "LE", "GT", "GE", "EQV", "NEQV"]
            p.types = ["INTEGER", "REAL", "DOUBLE", "PRECISION", "COMPLEX", "LOGICAL", "CHARACTER", "ABS", "SQRT", "SIN", "COS", "TAN", "ASIN", "ACOS", "ATAN", "ATAN2", "SINH", "COSH", "TANH", "EXP", "LOG", "LOG10", "ALOG", "ALOG10", "AEXP", "MOD", "SIGN", "MAX", "MIN", "MAX0", "MIN0", "AMAX0", "AMIN0", "AMAX1", "AMIN1", "AINT", "ANINT", "NINT", "INT", "IFIX", "IDINT", "FLOAT", "SNGL", "REAL", "DBLE", "DREAL", "CMPLX", "DCMPLX", "DPROD", "ICHAR", "CHAR", "LEN", "INDEX", "LGE", "LGT", "LLE", "LLT"]
            p.caseInsensitive = true
        case .fortran90:
            p.lineComments = ["!"]
            p.stringPatterns = ["'(?:''|[^'])*'", "\"(?:\"\"|[^\"])*\""]
            p.keywords = ["PROGRAM", "MODULE", "SUBMODULE", "USE", "ONLY", "CONTAINS", "INTERFACE", "ABSTRACT", "PROCEDURE", "GENERIC", "FINAL", "DEFERRED", "NON_OVERRIDABLE", "IMPORT", "SUBROUTINE", "FUNCTION", "RECURSIVE", "PURE", "IMPURE", "ELEMENTAL", "RESULT", "BLOCK", "ASSOCIATE", "DATA", "COMMON", "DIMENSION", "EQUIVALENCE", "EXTERNAL", "INTRINSIC", "SAVE", "PARAMETER", "IMPLICIT", "NONE", "INTENT", "IN", "OUT", "INOUT", "OPTIONAL", "ALLOCATABLE", "POINTER", "TARGET", "VALUE", "VOLATILE", "ASYNCHRONOUS", "CONTIGUOUS", "PROTECTED", "PUBLIC", "PRIVATE", "BIND", "IF", "THEN", "ELSE", "ELSEIF", "ENDIF", "DO", "WHILE", "CONTINUE", "SELECT", "CASE", "DEFAULT", "WHERE", "ELSEWHERE", "FORALL", "CYCLE", "EXIT", "GO", "TO", "GOTO", "CALL", "RETURN", "STOP", "ERROR", "PAUSE", "READ", "WRITE", "PRINT", "OPEN", "CLOSE", "INQUIRE", "REWIND", "BACKSPACE", "ENDFILE", "FORMAT", "ALLOCATE", "DEALLOCATE", "NULLIFY", "END", "INCLUDE", "TRUE", "FALSE", "NOT", "AND", "OR", "EQ", "NE", "LT", "LE", "GT", "GE", "EQV", "NEQV", "SYNC", "ALL", "IMAGE", "LOCK", "UNLOCK", "CRITICAL", "EVENT", "POST", "WAIT", "QUERY", "FORM", "TEAM", "COARRAY", "CODIMENSION"]
            p.types = ["INTEGER", "REAL", "DOUBLE", "PRECISION", "COMPLEX", "LOGICAL", "CHARACTER", "TYPE", "CLASS", "KIND", "LEN", "ABS", "SQRT", "SIN", "COS", "TAN", "ASIN", "ACOS", "ATAN", "ATAN2", "EXP", "LOG", "LOG10", "MOD", "SIGN", "MAX", "MIN", "AINT", "ANINT", "NINT", "INT", "REAL", "DBLE", "CMPLX", "ICHAR", "CHAR", "LEN_TRIM", "TRIM", "ADJUSTL", "ADJUSTR", "INDEX", "SCAN", "VERIFY", "ALLOCATED", "ASSOCIATED", "PRESENT", "SIZE", "SHAPE", "LBOUND", "UBOUND", "SUM", "PRODUCT", "MAXVAL", "MINVAL", "COUNT", "ANY", "ALL", "MATMUL", "TRANSPOSE", "DOT_PRODUCT", "PACK", "UNPACK", "RESHAPE", "SPREAD", "CSHIFT", "EOSHIFT", "NULL", "NEW_LINE"]
            p.caseInsensitive = true
        case .sql:
            p.lineComments = ["--"]
            p.blockComments = [("/*", "*/")]
            p.stringPatterns = ["'(?:''|[^'])*'", "\"(?:\"\"|[^\"])*\""]
            p.keywords = ["SELECT", "FROM", "WHERE", "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE", "CREATE", "TABLE", "DROP", "ALTER", "ADD", "COLUMN", "INDEX", "VIEW", "JOIN", "LEFT", "RIGHT", "INNER", "OUTER", "ON", "AS", "AND", "OR", "NOT", "NULL", "IS", "IN", "BETWEEN", "LIKE", "ORDER", "BY", "GROUP", "HAVING", "LIMIT", "OFFSET", "DISTINCT", "UNION", "ALL", "CASE", "WHEN", "THEN", "ELSE", "END", "PRIMARY", "KEY", "FOREIGN", "REFERENCES", "CONSTRAINT", "DEFAULT", "UNIQUE", "CHECK", "WITH", "RECURSIVE", "EXISTS", "BEGIN", "COMMIT", "ROLLBACK", "TRANSACTION", "GRANT", "REVOKE"]
            p.types = ["INT", "INTEGER", "BIGINT", "SMALLINT", "TEXT", "VARCHAR", "CHAR", "BOOLEAN", "DATE", "TIME", "TIMESTAMP", "REAL", "DOUBLE", "DECIMAL", "NUMERIC", "BLOB", "JSON", "UUID"]
            p.caseInsensitive = true
        case .shell:
            p.lineComments = ["#"]
            p.stringPatterns = Self.singleAndDoubleQuoted
            p.keywords = ["if", "then", "elif", "else", "fi", "for", "while", "until", "do", "done", "case", "esac", "function", "in", "select", "time", "coproc", "return", "exit", "break", "continue", "local", "declare", "typeset", "readonly", "export", "unset", "shift", "source", "alias", "set", "echo", "printf", "read", "cd", "pwd", "test", "eval", "exec", "trap", "wait", "true", "false"]
        case .powershell:
            p.lineComments = ["#"]
            p.blockComments = [("<#", "#>")]
            p.stringPatterns = Self.singleAndDoubleQuoted + ["@\"[\\s\\S]*?\"@", "@'[\\s\\S]*?'@"]
            p.keywords = ["begin", "break", "catch", "class", "continue", "data", "define", "do", "dynamicparam", "else", "elseif", "end", "enum", "exit", "filter", "finally", "for", "foreach", "from", "function", "if", "in", "param", "process", "return", "switch", "throw", "trap", "try", "until", "using", "var", "while", "workflow", "parallel", "sequence"]
            p.types = ["string", "int", "long", "double", "decimal", "bool", "datetime", "array", "hashtable", "pscustomobject"]
        case .graphql:
            p.lineComments = ["#"]
            p.stringPatterns = Self.doubleQuoted
            p.keywords = ["query", "mutation", "subscription", "fragment", "on", "type", "interface", "union", "enum", "input", "scalar", "schema", "extend", "directive", "implements", "true", "false", "null"]
            p.types = ["Int", "Float", "String", "Boolean", "ID"]
        case .protobuf:
            p.lineComments = ["//"]
            p.blockComments = [("/*", "*/")]
            p.stringPatterns = Self.cLikeStrings
            p.keywords = ["syntax", "package", "import", "option", "message", "enum", "service", "rpc", "returns", "stream", "repeated", "optional", "required", "reserved", "extensions", "extend", "oneof", "map", "group", "public", "weak"]
            p.types = ["double", "float", "int32", "int64", "uint32", "uint64", "sint32", "sint64", "fixed32", "fixed64", "sfixed32", "sfixed64", "bool", "string", "bytes"]
        case .css:
            p.blockComments = [("/*", "*/")]
            p.stringPatterns = Self.singleAndDoubleQuoted
            p.keywords = ["important", "media", "supports", "keyframes", "font-face", "import", "charset", "namespace", "page", "layer", "container"]
            p.types = ["color", "background", "display", "position", "margin", "padding", "border", "font", "flex", "grid", "width", "height", "top", "left", "right", "bottom", "opacity", "transform", "transition"]
        default:
            p.stringPatterns = Self.singleAndDoubleQuoted
        }
        return p
    }

    // MARK: Special languages

    /// FORTRAN 77 fixed-form comments live in column 1 (`C`, `c`, `*`).
    /// Start from the generic free-form rules, then paint those fixed-form
    /// comment lines last so they override any keyword/string colouring.
    private func applyFortran77(storage: NSTextStorage, text: String, range: NSRange) {
        applyGeneric(storage: storage, text: text, range: range)
        applyFortranTokens(storage: storage, text: text, range: range)
        paint(pattern: "(?mi)^[Cc*].*$", options: [],
              attributes: [.foregroundColor: CodePalette.comment],
              text: text, range: range, excluding: [], storage: storage)
    }

    private func applyFortran90(storage: NSTextStorage, text: String, range: NSRange) {
        applyGeneric(storage: storage, text: text, range: range)
        applyFortranTokens(storage: storage, text: text, range: range)
    }

    /// Common Fortran spellings that the generic C-style tokenizer does not know:
    /// `.TRUE.` / `.AND.` logical literals and operators, plus D-exponent reals.
    private func applyFortranTokens(storage: NSTextStorage, text: String, range: NSRange) {
        paint(pattern: "(?i)\\.(?:TRUE|FALSE|AND|OR|NOT|EQ|NE|LT|LE|GT|GE|EQV|NEQV)\\.",
              options: [], attributes: [.foregroundColor: CodePalette.keyword],
              text: text, range: range, excluding: [], storage: storage)
        paint(pattern: "\\b\\d+(?:\\.\\d*)?[dD][+-]?\\d+\\b",
              options: [], attributes: [.foregroundColor: CodePalette.number],
              text: text, range: range, excluding: [], storage: storage)
    }

    private func applyJSON(storage: NSTextStorage, text: String, range: NSRange, allowComments: Bool) {
        var protected: [NSRange] = []
        if allowComments {
            paint(pattern: "//[^\\n]*", options: [], attributes: [.foregroundColor: CodePalette.comment],
                  text: text, range: range, excluding: [], storage: storage, collect: &protected)
        }
        var keyRanges: [NSRange] = []
        paint(pattern: "\"(?:\\\\.|[^\"\\\\])*\"(?=\\s*:)", options: [],
              attributes: [.foregroundColor: CodePalette.attribute],
              text: text, range: range, excluding: [protected], storage: storage, collect: &keyRanges)
        var strings: [NSRange] = []
        paint(pattern: "\"(?:\\\\.|[^\"\\\\])*\"", options: [],
              attributes: [.foregroundColor: CodePalette.string],
              text: text, range: range, excluding: [protected, keyRanges], storage: storage, collect: &strings)
        paint(pattern: "\\b(?:true|false|null)\\b", options: [],
              attributes: [.foregroundColor: CodePalette.keyword],
              text: text, range: range, excluding: [protected, keyRanges, strings], storage: storage)
        paint(pattern: "\\b-?\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?\\b", options: [],
              attributes: [.foregroundColor: CodePalette.number],
              text: text, range: range, excluding: [protected, keyRanges, strings], storage: storage)
    }

    private func applyMarkdown(storage: NSTextStorage, text: String, range: NSRange) {
        let bold = NSFontManager.shared.convert(NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
                                                toHaveTrait: .boldFontMask)
        paint(pattern: "(?m)^#{1,6}\\s+.*$", options: [],
              attributes: [.foregroundColor: CodePalette.heading, .font: bold],
              text: text, range: range, excluding: [], storage: storage)
        paint(pattern: "````[\\s\\S]*?````|```[\\s\\S]*?```", options: [],
              attributes: [.foregroundColor: CodePalette.string],
              text: text, range: range, excluding: [], storage: storage)
        paint(pattern: "`[^`\\n]+`", options: [],
              attributes: [.foregroundColor: CodePalette.string],
              text: text, range: range, excluding: [], storage: storage)
        paint(pattern: "\\*\\*[^*\\n]+\\*\\*|__[^_\\n]+__", options: [],
              attributes: [.font: bold],
              text: text, range: range, excluding: [], storage: storage)
        paint(pattern: "(?m)^>\\s?.*$", options: [],
              attributes: [.foregroundColor: CodePalette.comment],
              text: text, range: range, excluding: [], storage: storage)
        paint(pattern: "(?m)^\\s*(?:[-*+]|\\d+\\.)\\s", options: [],
              attributes: [.foregroundColor: CodePalette.keyword],
              text: text, range: range, excluding: [], storage: storage)
        paint(pattern: "!?\\[[^\\]\\n]+\\]\\([^\\)\\n]+\\)", options: [],
              attributes: [.foregroundColor: CodePalette.type],
              text: text, range: range, excluding: [], storage: storage)
        paint(pattern: "(?m)^(?:---+|===+|\\*\\*\\*+)$", options: [],
              attributes: [.foregroundColor: CodePalette.muted],
              text: text, range: range, excluding: [], storage: storage)
    }

    private func applyMarkup(storage: NSTextStorage, text: String, range: NSRange) {
        var comments: [NSRange] = []
        paint(pattern: "<!--[\\s\\S]*?-->", options: [],
              attributes: [.foregroundColor: CodePalette.comment],
              text: text, range: range, excluding: [], storage: storage, collect: &comments)
        paint(pattern: "</?[A-Za-z][A-Za-z0-9:_-]*", options: [],
              attributes: [.foregroundColor: CodePalette.tag],
              text: text, range: range, excluding: [comments], storage: storage)
        paint(pattern: "\\b[A-Za-z_:][-A-Za-z0-9_:.]*(?=\\s*=)", options: [],
              attributes: [.foregroundColor: CodePalette.attribute],
              text: text, range: range, excluding: [comments], storage: storage)
        paint(pattern: "\"(?:\\\\.|[^\"\\\\])*\"|'(?:\\\\.|[^'\\\\])*'", options: [],
              attributes: [.foregroundColor: CodePalette.string],
              text: text, range: range, excluding: [comments], storage: storage)
        paint(pattern: "(?m)^\\s*<!DOCTYPE[^>]*>", options: [.caseInsensitive],
              attributes: [.foregroundColor: CodePalette.keyword],
              text: text, range: range, excluding: [comments], storage: storage)
    }

    private func applyYAML(storage: NSTextStorage, text: String, range: NSRange) {
        var strings: [NSRange] = []
        paint(pattern: "\"(?:\\\\.|[^\"\\\\])*\"|'[^']*'", options: [],
              attributes: [.foregroundColor: CodePalette.string],
              text: text, range: range, excluding: [], storage: storage, collect: &strings)
        var comments: [NSRange] = []
        paint(pattern: "(?:^|\\s)#[^\\n]*", options: [],
              attributes: [.foregroundColor: CodePalette.comment],
              text: text, range: range, excluding: [strings], storage: storage, collect: &comments)
        paint(pattern: "(?m)^\\s*(?:-\\s+)?[A-Za-z0-9_.\\-\\/]+(?=\\s*:)", options: [],
              attributes: [.foregroundColor: CodePalette.attribute],
              text: text, range: range, excluding: [strings, comments], storage: storage)
        paint(pattern: "\\b(?:true|false|null|yes|no|on|off)\\b", options: [.caseInsensitive],
              attributes: [.foregroundColor: CodePalette.keyword],
              text: text, range: range, excluding: [strings, comments], storage: storage)
        paint(pattern: "\\b-?\\d+(?:\\.\\d+)?\\b", options: [],
              attributes: [.foregroundColor: CodePalette.number],
              text: text, range: range, excluding: [strings, comments], storage: storage)
    }

    private func applyTOML(storage: NSTextStorage, text: String, range: NSRange) {
        var strings: [NSRange] = []
        paint(pattern: "\"\"\"[\\s\\S]*?\"\"\"|'''[\\s\\S]*?'''|\"(?:\\\\.|[^\"\\\\])*\"|'[^']*'", options: [],
              attributes: [.foregroundColor: CodePalette.string],
              text: text, range: range, excluding: [], storage: storage, collect: &strings)
        var comments: [NSRange] = []
        paint(pattern: "#[^\\n]*", options: [],
              attributes: [.foregroundColor: CodePalette.comment],
              text: text, range: range, excluding: [strings], storage: storage, collect: &comments)
        paint(pattern: "(?m)^\\s*\\[{1,2}[^\\]\\n]+\\]{1,2}", options: [],
              attributes: [.foregroundColor: CodePalette.heading],
              text: text, range: range, excluding: [strings, comments], storage: storage)
        paint(pattern: "(?m)^\\s*[A-Za-z0-9_.\\-]+(?=\\s*=)", options: [],
              attributes: [.foregroundColor: CodePalette.attribute],
              text: text, range: range, excluding: [strings, comments], storage: storage)
        paint(pattern: "\\b(?:true|false)\\b", options: [],
              attributes: [.foregroundColor: CodePalette.keyword],
              text: text, range: range, excluding: [strings, comments], storage: storage)
    }

    private func applyINI(storage: NSTextStorage, text: String, range: NSRange) {
        var strings: [NSRange] = []
        paint(pattern: "\"(?:\\\\.|[^\"\\\\])*\"", options: [],
              attributes: [.foregroundColor: CodePalette.string],
              text: text, range: range, excluding: [], storage: storage, collect: &strings)
        var comments: [NSRange] = []
        paint(pattern: "(?m)^\\s*[;#].*$", options: [],
              attributes: [.foregroundColor: CodePalette.comment],
              text: text, range: range, excluding: [strings], storage: storage, collect: &comments)
        paint(pattern: "(?m)^\\s*\\[[^\\]\\n]+\\]", options: [],
              attributes: [.foregroundColor: CodePalette.heading],
              text: text, range: range, excluding: [strings, comments], storage: storage)
        paint(pattern: "(?m)^\\s*[^=:\\n]+(?=\\s*[=:])", options: [],
              attributes: [.foregroundColor: CodePalette.attribute],
              text: text, range: range, excluding: [strings, comments], storage: storage)
    }

    private func applyDiff(storage: NSTextStorage, text: String, range: NSRange) {
        paint(pattern: "(?m)^\\+.*$", options: [], attributes: [.foregroundColor: CodePalette.inserted],
              text: text, range: range, excluding: [], storage: storage)
        paint(pattern: "(?m)^-.*$", options: [], attributes: [.foregroundColor: CodePalette.deleted],
              text: text, range: range, excluding: [], storage: storage)
        paint(pattern: "(?m)^@@.*$", options: [], attributes: [.foregroundColor: CodePalette.heading],
              text: text, range: range, excluding: [], storage: storage)
        paint(pattern: "(?m)^(?:diff|index|---|\\+\\+\\+).*$", options: [],
              attributes: [.foregroundColor: CodePalette.muted],
              text: text, range: range, excluding: [], storage: storage)
    }

    private func applyLog(storage: NSTextStorage, text: String, range: NSRange) {
        paint(pattern: "(?m)^\\d{4}-\\d{2}-\\d{2}[T ][0-9:.+Z-]+", options: [],
              attributes: [.foregroundColor: CodePalette.muted],
              text: text, range: range, excluding: [], storage: storage)
        paint(pattern: "\\b(?:ERROR|FATAL|CRITICAL|FAIL(?:URE)?|EXCEPTION)\\b", options: [.caseInsensitive],
              attributes: [.foregroundColor: CodePalette.deleted],
              text: text, range: range, excluding: [], storage: storage)
        paint(pattern: "\\b(?:WARN(?:ING)?|DEPRECATED)\\b", options: [.caseInsensitive],
              attributes: [.foregroundColor: CodePalette.number],
              text: text, range: range, excluding: [], storage: storage)
        paint(pattern: "\\b(?:INFO|DEBUG|TRACE|NOTICE)\\b", options: [.caseInsensitive],
              attributes: [.foregroundColor: CodePalette.type],
              text: text, range: range, excluding: [], storage: storage)
    }

    private func applyLaTeX(storage: NSTextStorage, text: String, range: NSRange) {
        var comments: [NSRange] = []
        paint(pattern: "(?<!\\\\)%.*$", options: [],
              attributes: [.foregroundColor: CodePalette.comment],
              text: text, range: range, excluding: [], storage: storage, collect: &comments)
        paint(pattern: "\\\\[A-Za-z@]+\\*?", options: [],
              attributes: [.foregroundColor: CodePalette.keyword],
              text: text, range: range, excluding: [comments], storage: storage)
        paint(pattern: "\\$[^$\\n]+\\$|\\$\\$[\\s\\S]*?\\$\\$", options: [],
              attributes: [.foregroundColor: CodePalette.string],
              text: text, range: range, excluding: [comments], storage: storage)
    }

    private func applyDockerfile(storage: NSTextStorage, text: String, range: NSRange) {
        var comments: [NSRange] = []
        paint(pattern: "(?m)^\\s*#.*$", options: [],
              attributes: [.foregroundColor: CodePalette.comment],
              text: text, range: range, excluding: [], storage: storage, collect: &comments)
        paint(pattern: "(?mi)^\\s*(?:FROM|RUN|CMD|LABEL|MAINTAINER|EXPOSE|ENV|ADD|COPY|ENTRYPOINT|VOLUME|USER|WORKDIR|ARG|ONBUILD|STOPSIGNAL|HEALTHCHECK|SHELL)\\b", options: [],
              attributes: [.foregroundColor: CodePalette.keyword],
              text: text, range: range, excluding: [comments], storage: storage)
        paint(pattern: "\\$\\{?[A-Za-z_][A-Za-z0-9_]*\\}?", options: [],
              attributes: [.foregroundColor: CodePalette.type],
              text: text, range: range, excluding: [comments], storage: storage)
    }

    private func applyMakefile(storage: NSTextStorage, text: String, range: NSRange) {
        var comments: [NSRange] = []
        paint(pattern: "#[^\\n]*", options: [],
              attributes: [.foregroundColor: CodePalette.comment],
              text: text, range: range, excluding: [], storage: storage, collect: &comments)
        paint(pattern: "(?m)^[A-Za-z0-9_.%/-]+(?=\\s*:(?!=))", options: [],
              attributes: [.foregroundColor: CodePalette.heading],
              text: text, range: range, excluding: [comments], storage: storage)
        paint(pattern: "(?m)^[A-Za-z_][A-Za-z0-9_]*(?=\\s*[?:+]?=)", options: [],
              attributes: [.foregroundColor: CodePalette.attribute],
              text: text, range: range, excluding: [comments], storage: storage)
        paint(pattern: "\\$[({][^)}\\n]+[)}]", options: [],
              attributes: [.foregroundColor: CodePalette.type],
              text: text, range: range, excluding: [comments], storage: storage)
    }

    private func applyShell(storage: NSTextStorage, text: String, range: NSRange) {
        applyGeneric(storage: storage, text: text, range: range)
        paint(pattern: "\\$\\{?[A-Za-z_][A-Za-z0-9_]*\\}?", options: [],
              attributes: [.foregroundColor: CodePalette.type],
              text: text, range: range, excluding: [], storage: storage)
    }

    private func applyBatch(storage: NSTextStorage, text: String, range: NSRange) {
        var comments: [NSRange] = []
        paint(pattern: "(?mi)^\\s*(?:rem\\b|::).*$", options: [],
              attributes: [.foregroundColor: CodePalette.comment],
              text: text, range: range, excluding: [], storage: storage, collect: &comments)
        paint(pattern: "(?mi)^\\s*(?:if|else|for|in|do|call|goto|exit|set|echo|cd|mkdir|del|copy|move|start|pause|shift|pushd|popd|goto|not|exist|defined)\\b", options: [],
              attributes: [.foregroundColor: CodePalette.keyword],
              text: text, range: range, excluding: [comments], storage: storage)
        paint(pattern: "%[A-Za-z0-9_]+%", options: [],
              attributes: [.foregroundColor: CodePalette.type],
              text: text, range: range, excluding: [comments], storage: storage)
    }

    private func applyCSV(storage: NSTextStorage, text: String, range: NSRange) {
        // Highlight quoted cells and the first row.
        paint(pattern: "\"(?:[^\"]|\"\")*\"", options: [],
              attributes: [.foregroundColor: CodePalette.string],
              text: text, range: range, excluding: [], storage: storage)
        if let firstLine = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first {
            let length = firstLine.utf16.count
            if length > 0, length <= range.length {
                storage.addAttribute(.foregroundColor, value: CodePalette.heading,
                                     range: NSRange(location: 0, length: length))
            }
        }
    }

    // MARK: Painting helpers

    private func paint(pattern: String, options: NSRegularExpression.Options,
                       attributes: [NSAttributedString.Key: Any],
                       text: String, range: NSRange, excluding: [[NSRange]],
                       storage: NSTextStorage) {
        var ignored: [NSRange] = []
        paint(pattern: pattern, options: options, attributes: attributes, text: text,
              range: range, excluding: excluding, storage: storage, collect: &ignored)
    }

    private func paint(pattern: String, options: NSRegularExpression.Options,
                       attributes: [NSAttributedString.Key: Any],
                       text: String, range: NSRange, excluding: [[NSRange]],
                       storage: NSTextStorage, collect: inout [NSRange]) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
        regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let matchRange = match?.range, matchRange.length > 0 else { return }
            for list in excluding where intersects(matchRange, sorted: list) {
                return
            }
            storage.addAttributes(attributes, range: matchRange)
            collect.append(matchRange)
        }
    }

    private func intersects(_ range: NSRange, sorted: [NSRange]) -> Bool {
        guard !sorted.isEmpty else { return false }
        var low = 0
        var high = sorted.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let candidate = sorted[mid]
            if NSMaxRange(candidate) <= range.location {
                low = mid + 1
            } else if candidate.location >= NSMaxRange(range) {
                high = mid - 1
            } else {
                return true
            }
        }
        return false
    }

    private func merge(_ ranges: [NSRange]) -> [NSRange] {
        guard ranges.count > 1 else { return ranges }
        let sorted = ranges.sorted { $0.location < $1.location }
        var result: [NSRange] = [sorted[0]]
        for range in sorted.dropFirst() {
            if let last = result.last, range.location <= NSMaxRange(last) {
                result[result.count - 1] = NSUnionRange(last, range)
            } else {
                result.append(range)
            }
        }
        return result
    }
}
