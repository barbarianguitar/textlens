import Foundation
import CoreFoundation
import Darwin
import UniformTypeIdentifiers

// MARK: - Basic vocabulary

enum TextEncoding: String, CaseIterable, Codable, Sendable {
    case utf8
    case utf16LE
    case utf16BE
    case utf32LE
    case utf32BE
    case gb18030
    case big5
    case shiftJIS
    case eucJP
    case eucKR
    case windows1252
    case isoLatin1
    case macRoman

    var label: String {
        switch self {
        case .utf8: return "UTF-8"
        case .utf16LE: return "UTF-16 LE"
        case .utf16BE: return "UTF-16 BE"
        case .utf32LE: return "UTF-32 LE"
        case .utf32BE: return "UTF-32 BE"
        case .gb18030: return "GB 18030 / GBK"
        case .big5: return "Big5"
        case .shiftJIS: return "Shift_JIS"
        case .eucJP: return "EUC-JP"
        case .eucKR: return "EUC-KR"
        case .windows1252: return "Windows-1252"
        case .isoLatin1: return "ISO-8859-1"
        case .macRoman: return "Mac Roman"
        }
    }

    var shortLabel: String {
        switch self {
        case .utf8: return "UTF-8"
        case .utf16LE: return "UTF-16LE"
        case .utf16BE: return "UTF-16BE"
        case .utf32LE: return "UTF-32LE"
        case .utf32BE: return "UTF-32BE"
        case .gb18030: return "GB18030"
        case .big5: return "Big5"
        case .shiftJIS: return "Shift_JIS"
        case .eucJP: return "EUC-JP"
        case .eucKR: return "EUC-KR"
        case .windows1252: return "CP1252"
        case .isoLatin1: return "Latin-1"
        case .macRoman: return "Mac Roman"
        }
    }

    var note: String {
        switch self {
        case .utf8: return "最通用的 Unicode 编码，兼容 ASCII"
        case .utf16LE: return "Windows 常见的 Unicode 编码"
        case .utf16BE: return "Java、部分系统使用的 Unicode 编码"
        case .utf32LE, .utf32BE: return "32 位 Unicode 编码"
        case .gb18030: return "简体中文常见编码，兼容 GBK、GB2312"
        case .big5: return "繁体中文常见编码"
        case .shiftJIS: return "日文常见编码"
        case .eucJP: return "日文 Unix 环境常见编码"
        case .eucKR: return "韩文常见编码"
        case .windows1252: return "西欧语言常见编码"
        case .isoLatin1: return "较老的西欧编码"
        case .macRoman: return "经典 Mac 西文编码"
        }
    }

    var isUnicode: Bool {
        switch self {
        case .utf8, .utf16LE, .utf16BE, .utf32LE, .utf32BE: return true
        default: return false
        }
    }

    var nsEncoding: String.Encoding {
        switch self {
        case .utf8: return .utf8
        case .utf16LE: return .utf16LittleEndian
        case .utf16BE: return .utf16BigEndian
        case .utf32LE: return .utf32LittleEndian
        case .utf32BE: return .utf32BigEndian
        case .gb18030:
            return TextEncoding.cfEncoding(.GB_18030_2000)
        case .big5:
            return TextEncoding.cfEncoding(.big5)
        case .shiftJIS: return .shiftJIS
        case .eucJP: return .japaneseEUC
        case .eucKR:
            return TextEncoding.cfEncoding(.EUC_KR)
        case .windows1252: return .windowsCP1252
        case .isoLatin1: return .isoLatin1
        case .macRoman: return .macOSRoman
        }
    }

    private static func cfEncoding(_ value: CFStringEncodings) -> String.Encoding {
        String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(value.rawValue)))
    }

    var bom: [UInt8]? {
        switch self {
        case .utf8: return [0xEF, 0xBB, 0xBF]
        case .utf16LE: return [0xFF, 0xFE]
        case .utf16BE: return [0xFE, 0xFF]
        case .utf32LE: return [0xFF, 0xFE, 0x00, 0x00]
        case .utf32BE: return [0x00, 0x00, 0xFE, 0xFF]
        default: return nil
        }
    }

    func decode(_ data: Data) -> String? {
        var bytes = [UInt8](data)
        if let bom, bytes.starts(with: bom) {
            bytes.removeFirst(bom.count)
        }
        return String(data: Data(bytes), encoding: nsEncoding)
    }

    func encode(_ string: String, includeBOM: Bool) -> Data? {
        guard var data = string.data(using: nsEncoding, allowLossyConversion: false) else { return nil }
        if includeBOM, let bom {
            // Foundation occasionally adds a BOM on its own for UTF-16/32.
            while data.starts(with: bom) {
                data.removeFirst(bom.count)
            }
            data.insert(contentsOf: bom, at: 0)
        }
        return data
    }
}

enum LineEnding: String, Codable, CaseIterable, Sendable {
    case lf
    case crlf
    case cr
    case mixed
    case none

    var label: String {
        switch self {
        case .lf: return "LF"
        case .crlf: return "CRLF"
        case .cr: return "CR"
        case .mixed: return "混合"
        case .none: return "单行"
        }
    }

    var longLabel: String {
        switch self {
        case .lf: return "LF（Unix / macOS）"
        case .crlf: return "CRLF（Windows）"
        case .cr: return "CR（经典 Mac）"
        case .mixed: return "混合换行（保存时统一）"
        case .none: return "没有换行符"
        }
    }

    func apply(to text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        switch self {
        case .crlf: return normalized.replacingOccurrences(of: "\n", with: "\r\n")
        case .cr: return normalized.replacingOccurrences(of: "\n", with: "\r")
        default: return normalized
        }
    }

    static func detect(in text: String) -> LineEnding {
        var crlf = 0
        var lf = 0
        var cr = 0
        let scalars = Array(text.unicodeScalars)
        var index = 0
        while index < scalars.count {
            let value = scalars[index].value
            if value == 13 {
                if index + 1 < scalars.count, scalars[index + 1].value == 10 {
                    crlf += 1
                    index += 2
                    continue
                }
                cr += 1
            } else if value == 10 {
                lf += 1
            }
            index += 1
        }
        let total = crlf + lf + cr
        guard total > 0 else { return .none }
        let dominant = max(crlf, max(lf, cr))
        if dominant < total {
            // A stray carriage return at the end of a file should not make it "mixed".
            let minority = total - dominant
            if Double(minority) / Double(total) > 0.02 {
                return .mixed
            }
        }
        if crlf == dominant { return .crlf }
        if lf == dominant { return .lf }
        return .cr
    }
}

enum FileCategory: String, Codable, Sendable {
    case text
    case sourceCode
    case config
    case data
    case markup
    case document
    case image
    case archive
    case executable
    case audio
    case video
    case database
    case font
    case binary
    case empty

    var label: String {
        switch self {
        case .text: return "文本"
        case .sourceCode: return "源代码"
        case .config: return "配置文件"
        case .data: return "结构化数据"
        case .markup: return "标记文本"
        case .document: return "文档"
        case .image: return "图像"
        case .archive: return "压缩包"
        case .executable: return "可执行文件"
        case .audio: return "音频"
        case .video: return "视频"
        case .database: return "数据库"
        case .font: return "字体"
        case .binary: return "二进制"
        case .empty: return "空文件"
        }
    }

    var isTextual: Bool {
        switch self {
        case .text, .sourceCode, .config, .data, .markup, .document: return true
        default: return false
        }
    }
}

enum FormatTint: String, Codable, Sendable {
    case gray, blue, indigo, purple, pink, red, orange, yellow, green, teal, cyan, mint, brown
}

enum SyntaxLanguage: String, Codable, CaseIterable, Sendable {
    case plainText
    case swift
    case python
    case javascript
    case typescript
    case json
    case jsonc
    case html
    case xml
    case css
    case markdown
    case yaml
    case toml
    case ini
    case shell
    case sql
    case c
    case cpp
    case objectiveC
    case java
    case kotlin
    case ruby
    case php
    case go
    case rust
    case lua
    case r
    case perl
    case haskell
    case fortran77
    case fortran90
    case dockerfile
    case makefile
    case diff
    case graphql
    case protobuf
    case latex
    case csv
    case log
    case powershell
    case batch
    case plist
    case vue
    case svelte

    var label: String {
        switch self {
        case .plainText: return "纯文本"
        case .swift: return "Swift"
        case .python: return "Python"
        case .javascript: return "JavaScript"
        case .typescript: return "TypeScript"
        case .json: return "JSON"
        case .jsonc: return "JSON with Comments"
        case .html: return "HTML"
        case .xml: return "XML"
        case .css: return "CSS"
        case .markdown: return "Markdown"
        case .yaml: return "YAML"
        case .toml: return "TOML"
        case .ini: return "INI / 配置"
        case .shell: return "Shell"
        case .sql: return "SQL"
        case .c: return "C"
        case .cpp: return "C++"
        case .objectiveC: return "Objective-C"
        case .java: return "Java"
        case .kotlin: return "Kotlin"
        case .ruby: return "Ruby"
        case .php: return "PHP"
        case .go: return "Go"
        case .rust: return "Rust"
        case .lua: return "Lua"
        case .r: return "R"
        case .perl: return "Perl"
        case .haskell: return "Haskell"
        case .fortran77: return "FORTRAN 77"
        case .fortran90: return "FORTRAN 90"
        case .dockerfile: return "Dockerfile"
        case .makefile: return "Makefile"
        case .diff: return "Diff / Patch"
        case .graphql: return "GraphQL"
        case .protobuf: return "Protocol Buffers"
        case .latex: return "LaTeX"
        case .csv: return "CSV / TSV"
        case .log: return "日志"
        case .powershell: return "PowerShell"
        case .batch: return "Batch"
        case .plist: return "Property List"
        case .vue: return "Vue"
        case .svelte: return "Svelte"
        }
    }
}

// MARK: - Format catalog

struct FileFormat: Codable, Equatable, Sendable {
    let id: String
    let name: String
    let category: FileCategory
    let mime: String
    let symbol: String
    let tint: FormatTint
    let syntax: SyntaxLanguage
    let known: Bool

    static let plainText = FileFormat(
        id: "plain", name: "纯文本", category: .text, mime: "text/plain",
        symbol: "doc.plaintext", tint: .gray, syntax: .plainText, known: false
    )
    static let unknownBinary = FileFormat(
        id: "binary", name: "未知二进制", category: .binary, mime: "application/octet-stream",
        symbol: "doc", tint: .gray, syntax: .plainText, known: false
    )
}

enum FileCatalog {
    static let allFormats: [FileFormat] = makeFormats()

    static let byID: [String: FileFormat] = {
        Dictionary(uniqueKeysWithValues: allFormats.map { ($0.id, $0) })
    }()

    static let byExtension: [String: FileFormat] = {
        var result: [String: FileFormat] = [:]
        func add(_ extensions: [String], _ id: String) {
            guard let format = byID[id] else { return }
            for ext in extensions { result[ext] = format }
        }
        add(["txt", "text", "nfo", "me", "readme", "license", "notice", "authors"], "plain")
        add(["md", "markdown", "mdown", "mkdn", "mkd"], "markdown")
        add(["json", "geojson", "webmanifest"], "json")
        add(["jsonc"], "jsonc")
        add(["jsonl", "ndjson"], "jsonl")
        add(["yaml", "yml"], "yaml")
        add(["toml"], "toml")
        add(["ini", "cfg", "conf", "config", "properties", "editorconfig", "service", "socket", "timer"], "ini")
        add(["env"], "env")
        add(["csv"], "csv")
        add(["tsv", "tab"], "tsv")
        add(["xml", "xsd", "xsl", "xslt", "rss", "atom"], "xml")
        add(["svg"], "svg")
        add(["html", "htm", "xhtml", "shtml"], "html")
        add(["css"], "css")
        add(["scss", "sass", "less", "styl"], "scss")
        add(["js", "mjs", "cjs", "jsx"], "javascript")
        add(["ts", "mts", "cts", "tsx"], "typescript")
        add(["swift"], "swift")
        add(["py", "pyw", "pyi", "pyx"], "python")
        add(["c", "h"], "c")
        add(["cpp", "cc", "cxx", "c++", "hpp", "hh", "hxx", "ipp"], "cpp")
        add(["m", "mm"], "objc")
        add(["java"], "java")
        add(["kt", "kts"], "kotlin")
        add(["rb", "rake", "gemspec", "podfile", "gemfile", "rakefile", "brewfile", "vagrantfile"], "ruby")
        add(["php", "phtml"], "php")
        add(["go"], "go")
        add(["rs"], "rust")
        add(["lua"], "lua")
        add(["r", "rmd"], "r")
        add(["pl", "pm", "t"], "perl")
        add(["hs", "lhs"], "haskell")
        add(["f", "for", "ftn", "f77"], "fortran77")
        add(["f90", "f95", "f03", "f08", "f18", "fpp"], "fortran90")
        add(["sh", "bash", "zsh", "fish", "ksh", "command", "tool"], "shell")
        add(["ps1", "psm1", "psd1"], "powershell")
        add(["bat", "cmd"], "batch")
        add(["sql"], "sql")
        add(["graphql", "gql"], "graphql")
        add(["proto"], "protobuf")
        add(["tex", "latex", "sty", "cls", "bib"], "latex")
        add(["diff", "patch"], "diff")
        add(["log"], "log")
        add(["dockerfile", "containerfile"], "dockerfile")
        add(["mk", "mak", "makefile"], "makefile")
        add(["cmake"], "cmake")
        add(["gradle"], "gradle")
        add(["rtf"], "rtf")
        add(["pem", "crt", "cer", "key", "csr", "p8"], "pem")
        add(["plist", "entitlements"], "plist")
        add(["strings", "po", "pot"], "strings")
        add(["lock"], "lockfile")
        add(["vue"], "vue")
        add(["svelte"], "svelte")
        add(["asciidoc", "adoc", "rst"], "documentation")
        add(["texinfo", "texi"], "documentation")
        add(["1", "2", "3", "4", "5", "6", "7", "8", "9"], "manpage")

        // Binary formats (the content detector still has the final word).
        add(["png"], "png")
        add(["jpg", "jpeg", "jpe"], "jpeg")
        add(["gif"], "gif")
        add(["webp"], "webp")
        add(["bmp", "dib"], "bmp")
        add(["tif", "tiff"], "tiff")
        add(["heic", "heif"], "heic")
        add(["ico"], "ico")
        add(["icns"], "icns")
        add(["psd"], "psd")
        add(["pdf"], "pdf")
        add(["zip"], "zip")
        add(["gz", "gzip", "tgz"], "gzip")
        add(["bz2", "tbz2"], "bzip2")
        add(["xz", "txz"], "xz")
        add(["7z"], "sevenzip")
        add(["rar"], "rar")
        add(["tar"], "tar")
        add(["dmg"], "dmg")
        add(["iso"], "iso")
        add(["docx"], "docx")
        add(["xlsx"], "xlsx")
        add(["pptx"], "pptx")
        add(["epub"], "epub")
        add(["mp3"], "mp3")
        add(["m4a", "aac"], "aac")
        add(["wav"], "wav")
        add(["flac"], "flac")
        add(["ogg", "opus"], "ogg")
        add(["mp4", "m4v"], "mp4")
        add(["mov"], "mov")
        add(["mkv"], "mkv")
        add(["avi"], "avi")
        add(["webm"], "webm")
        add(["sqlite", "sqlite3", "db"], "sqlite")
        add(["exe"], "pe")
        add(["dll"], "pe")
        add(["dylib"], "macho")
        add(["so"], "elf")
        add(["o", "a"], "object")
        add(["wasm"], "wasm")
        add(["class"], "class")
        add(["jar"], "jar")
        add(["dex"], "dex")
        add(["apk"], "apk")
        add(["ttf", "otf", "woff", "woff2"], "font")
        return result
    }()

    private static func makeFormats() -> [FileFormat] {
        func f(_ id: String, _ name: String, _ category: FileCategory, _ mime: String,
               _ symbol: String, _ tint: FormatTint, _ syntax: SyntaxLanguage) -> FileFormat {
            FileFormat(id: id, name: name, category: category, mime: mime, symbol: symbol,
                       tint: tint, syntax: syntax, known: true)
        }
        return [
            f("plain", "纯文本", .text, "text/plain", "doc.plaintext", .gray, .plainText),
            f("markdown", "Markdown 文档", .markup, "text/markdown", "text.alignleft", .indigo, .markdown),
            f("json", "JSON 数据", .data, "application/json", "curlybraces", .yellow, .json),
            f("jsonc", "JSON with Comments", .data, "application/json", "curlybraces", .yellow, .jsonc),
            f("jsonl", "JSON Lines", .data, "application/x-ndjson", "list.bullet.rectangle", .yellow, .json),
            f("yaml", "YAML 配置", .config, "application/yaml", "list.bullet.indent", .green, .yaml),
            f("toml", "TOML 配置", .config, "application/toml", "gearshape.2", .orange, .toml),
            f("ini", "INI / 配置文件", .config, "text/plain", "slider.horizontal.3", .gray, .ini),
            f("env", "环境变量文件", .config, "text/plain", "key.horizontal", .gray, .shell),
            f("csv", "CSV 表格", .data, "text/csv", "tablecells", .green, .csv),
            f("tsv", "TSV 表格", .data, "text/tab-separated-values", "tablecells", .green, .csv),
            f("xml", "XML 文档", .markup, "application/xml", "chevron.left.forwardslash.chevron.right", .blue, .xml),
            f("svg", "SVG 矢量图", .markup, "image/svg+xml", "photo", .orange, .xml),
            f("html", "HTML 网页", .markup, "text/html", "globe", .orange, .html),
            f("css", "CSS 样式表", .sourceCode, "text/css", "paintbrush", .blue, .css),
            f("scss", "Sass / Less 样式表", .sourceCode, "text/x-scss", "paintbrush", .pink, .css),
            f("javascript", "JavaScript 源代码", .sourceCode, "text/javascript", "chevron.left.forwardslash.chevron.right", .yellow, .javascript),
            f("typescript", "TypeScript 源代码", .sourceCode, "text/typescript", "chevron.left.forwardslash.chevron.right", .blue, .typescript),
            f("swift", "Swift 源代码", .sourceCode, "text/x-swift", "swift", .orange, .swift),
            f("python", "Python 源代码", .sourceCode, "text/x-python", "chevron.left.forwardslash.chevron.right", .blue, .python),
            f("c", "C 源代码", .sourceCode, "text/x-c", "chevron.left.forwardslash.chevron.right", .indigo, .c),
            f("cpp", "C++ 源代码", .sourceCode, "text/x-c++", "chevron.left.forwardslash.chevron.right", .indigo, .cpp),
            f("objc", "Objective-C 源代码", .sourceCode, "text/x-objc", "chevron.left.forwardslash.chevron.right", .blue, .objectiveC),
            f("java", "Java 源代码", .sourceCode, "text/x-java", "cup.and.saucer", .red, .java),
            f("kotlin", "Kotlin 源代码", .sourceCode, "text/x-kotlin", "chevron.left.forwardslash.chevron.right", .purple, .kotlin),
            f("ruby", "Ruby 源代码", .sourceCode, "text/x-ruby", "diamond", .red, .ruby),
            f("php", "PHP 源代码", .sourceCode, "text/x-php", "chevron.left.forwardslash.chevron.right", .purple, .php),
            f("go", "Go 源代码", .sourceCode, "text/x-go", "chevron.left.forwardslash.chevron.right", .cyan, .go),
            f("rust", "Rust 源代码", .sourceCode, "text/x-rust", "gearshape", .brown, .rust),
            f("lua", "Lua 脚本", .sourceCode, "text/x-lua", "moon", .blue, .lua),
            f("r", "R 脚本", .sourceCode, "text/x-r", "chart.bar", .blue, .r),
            f("perl", "Perl 脚本", .sourceCode, "text/x-perl", "chevron.left.forwardslash.chevron.right", .indigo, .perl),
            f("haskell", "Haskell 源代码", .sourceCode, "text/x-haskell", "function", .purple, .haskell),
            f("fortran77", "FORTRAN 77 源代码", .sourceCode, "text/x-fortran", "function", .purple, .fortran77),
            f("fortran90", "FORTRAN 90 源代码", .sourceCode, "text/x-fortran", "function", .teal, .fortran90),
            f("shell", "Shell 脚本", .sourceCode, "text/x-shellscript", "terminal", .green, .shell),
            f("powershell", "PowerShell 脚本", .sourceCode, "text/x-powershell", "terminal", .blue, .powershell),
            f("batch", "Batch 脚本", .sourceCode, "text/x-bat", "terminal", .gray, .batch),
            f("sql", "SQL 脚本", .sourceCode, "text/x-sql", "cylinder.split.1x2", .teal, .sql),
            f("graphql", "GraphQL 查询", .sourceCode, "application/graphql", "point.3.connected.trianglepath.dotted", .pink, .graphql),
            f("protobuf", "Protocol Buffers", .sourceCode, "text/x-protobuf", "square.stack.3d.up", .cyan, .protobuf),
            f("latex", "LaTeX 文档", .markup, "text/x-tex", "function", .green, .latex),
            f("diff", "Diff / Patch", .text, "text/x-diff", "plus.forwardslash.minus", .green, .diff),
            f("log", "日志文件", .text, "text/plain", "list.bullet.rectangle", .gray, .log),
            f("dockerfile", "Dockerfile", .config, "text/x-dockerfile", "shippingbox", .blue, .dockerfile),
            f("makefile", "Makefile", .config, "text/x-makefile", "hammer", .brown, .makefile),
            f("cmake", "CMake 构建脚本", .config, "text/x-cmake", "hammer", .blue, .makefile),
            f("gradle", "Gradle 构建脚本", .config, "text/x-gradle", "hammer", .green, .kotlin),
            f("rtf", "RTF 富文本", .document, "text/rtf", "doc.richtext", .orange, .plainText),
            f("pem", "证书 / 密钥", .data, "application/x-pem-file", "key", .yellow, .plainText),
            f("plist", "Property List", .data, "application/x-plist", "list.bullet.rectangle.portrait", .teal, .plist),
            f("strings", "本地化字符串", .data, "text/plain", "character.bubble", .purple, .plainText),
            f("lockfile", "依赖锁定文件", .data, "text/plain", "lock", .gray, .plainText),
            f("vue", "Vue 组件", .sourceCode, "text/x-vue", "v.square", .green, .vue),
            f("svelte", "Svelte 组件", .sourceCode, "text/x-svelte", "s.square", .orange, .svelte),
            f("documentation", "文档", .markup, "text/plain", "book", .indigo, .markdown),
            f("manpage", "man 手册", .document, "text/plain", "book.closed", .gray, .plainText),
            f("png", "PNG 图像", .image, "image/png", "photo", .green, .plainText),
            f("jpeg", "JPEG 图像", .image, "image/jpeg", "photo", .orange, .plainText),
            f("gif", "GIF 图像", .image, "image/gif", "photo", .purple, .plainText),
            f("webp", "WebP 图像", .image, "image/webp", "photo", .blue, .plainText),
            f("bmp", "BMP 图像", .image, "image/bmp", "photo", .teal, .plainText),
            f("tiff", "TIFF 图像", .image, "image/tiff", "photo", .brown, .plainText),
            f("heic", "HEIC 图像", .image, "image/heic", "photo", .blue, .plainText),
            f("ico", "ICO 图标", .image, "image/x-icon", "app.badge", .gray, .plainText),
            f("icns", "ICNS 图标", .image, "image/icns", "app.badge", .gray, .plainText),
            f("psd", "Photoshop 文档", .image, "image/vnd.adobe.photoshop", "photo.on.rectangle", .blue, .plainText),
            f("pdf", "PDF 文档", .document, "application/pdf", "doc.richtext", .red, .plainText),
            f("zip", "ZIP 压缩包", .archive, "application/zip", "archivebox", .yellow, .plainText),
            f("gzip", "Gzip 压缩包", .archive, "application/gzip", "archivebox", .brown, .plainText),
            f("bzip2", "Bzip2 压缩包", .archive, "application/x-bzip2", "archivebox", .brown, .plainText),
            f("xz", "XZ 压缩包", .archive, "application/x-xz", "archivebox", .gray, .plainText),
            f("sevenzip", "7-Zip 压缩包", .archive, "application/x-7z-compressed", "archivebox", .purple, .plainText),
            f("rar", "RAR 压缩包", .archive, "application/vnd.rar", "archivebox", .red, .plainText),
            f("tar", "Tar 归档", .archive, "application/x-tar", "archivebox", .brown, .plainText),
            f("dmg", "磁盘映像", .archive, "application/x-apple-diskimage", "externaldrive", .gray, .plainText),
            f("iso", "光盘映像", .archive, "application/x-iso9660-image", "opticaldisc", .gray, .plainText),
            f("docx", "Word 文档", .document, "application/vnd.openxmlformats-officedocument.wordprocessingml.document", "doc.text", .blue, .plainText),
            f("xlsx", "Excel 表格", .document, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "tablecells", .green, .plainText),
            f("pptx", "PowerPoint 演示文稿", .document, "application/vnd.openxmlformats-officedocument.presentationml.presentation", "rectangle.on.rectangle", .orange, .plainText),
            f("epub", "EPUB 电子书", .document, "application/epub+zip", "book", .green, .plainText),
            f("mp3", "MP3 音频", .audio, "audio/mpeg", "waveform", .pink, .plainText),
            f("aac", "AAC / M4A 音频", .audio, "audio/aac", "waveform", .pink, .plainText),
            f("wav", "WAV 音频", .audio, "audio/wav", "waveform", .pink, .plainText),
            f("flac", "FLAC 音频", .audio, "audio/flac", "waveform", .pink, .plainText),
            f("ogg", "OGG 音频", .audio, "audio/ogg", "waveform", .pink, .plainText),
            f("mp4", "MP4 视频", .video, "video/mp4", "film", .purple, .plainText),
            f("mov", "QuickTime 视频", .video, "video/quicktime", "film", .purple, .plainText),
            f("mkv", "Matroska 视频", .video, "video/x-matroska", "film", .purple, .plainText),
            f("avi", "AVI 视频", .video, "video/x-msvideo", "film", .purple, .plainText),
            f("webm", "WebM 视频", .video, "video/webm", "film", .purple, .plainText),
            f("sqlite", "SQLite 数据库", .database, "application/vnd.sqlite3", "cylinder", .teal, .plainText),
            f("pe", "Windows 可执行文件", .executable, "application/vnd.microsoft.portable-executable", "cpu", .blue, .plainText),
            f("macho", "Mach-O 可执行文件", .executable, "application/x-mach-binary", "cpu", .blue, .plainText),
            f("elf", "ELF 可执行文件", .executable, "application/x-elf", "cpu", .blue, .plainText),
            f("object", "目标文件 / 静态库", .executable, "application/octet-stream", "cpu", .gray, .plainText),
            f("wasm", "WebAssembly 模块", .executable, "application/wasm", "cpu", .purple, .plainText),
            f("class", "Java Class 文件", .executable, "application/java-vm", "cup.and.saucer", .red, .plainText),
            f("jar", "Java 归档", .archive, "application/java-archive", "archivebox", .red, .plainText),
            f("dex", "Android DEX", .executable, "application/x-android-dex", "cpu", .green, .plainText),
            f("apk", "Android 应用包", .archive, "application/vnd.android.package-archive", "archivebox", .green, .plainText),
            f("font", "字体文件", .font, "font/ttf", "textformat", .purple, .plainText)
        ]
    }

    static func format(forExtension ext: String) -> FileFormat? {
        let key = ext.lowercased()
        guard !key.isEmpty else { return nil }
        return byExtension[key]
    }

    static func format(forURL url: URL) -> FileFormat? {
        let name = url.lastPathComponent.lowercased()
        let special: [String: String] = [
            "dockerfile": "dockerfile", "containerfile": "dockerfile",
            "makefile": "makefile", "gnumakefile": "makefile",
            "cmakelists.txt": "cmake", "rakefile": "ruby", "gemfile": "ruby",
            "podfile": "ruby", "brewfile": "ruby", "vagrantfile": "ruby",
            "package.json": "json", "tsconfig.json": "json", "composer.json": "json",
            ".gitignore": "gitignore", ".gitattributes": "gitignore", ".gitmodules": "gitignore",
            ".editorconfig": "ini", ".env": "env", ".npmrc": "ini", ".yarnrc": "ini",
            ".zshrc": "shell", ".bashrc": "shell", ".bash_profile": "shell",
            ".profile": "shell", ".vimrc": "ini", "license": "plain", "readme": "plain",
            "notice": "plain", "authors": "plain"
        ]
        if let id = special[name] {
            if id == "gitignore" {
                return FileFormat(id: "gitignore", name: "Git 配置", category: .config,
                                  mime: "text/plain", symbol: "arrow.triangle.branch",
                                  tint: .orange, syntax: .ini, known: true)
            }
            return byID[id]
        }
        if name.hasPrefix("readme.") { return byID["plain"] }
        if name.hasPrefix("license.") { return byID["plain"] }
        let ext = url.pathExtension
        if let format = format(forExtension: ext) { return format }
        if ext.isEmpty, name.hasPrefix(".") {
            return FileFormat(id: "dotfile", name: "配置文件", category: .config,
                              mime: "text/plain", symbol: "gearshape", tint: .gray,
                              syntax: .ini, known: false)
        }
        return nil
    }

    static func format(forID id: String) -> FileFormat? { byID[id] }
}

// MARK: - Evidence and results

struct DetectionEvidence: Codable, Sendable {
    enum Kind: String, Codable, Sendable { case positive, info, warning }
    let kind: Kind
    let title: String
    let detail: String?

    var id: String { "\(kind.rawValue)|\(title)|\(detail ?? "")" }
}

struct MagicSignature: Codable, Equatable, Sendable {
    let label: String
    let formatID: String?
    let offset: Int
    let bytes: [UInt8]
    let textual: Bool
    let strong: Bool

    var hex: String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

struct ProbeResult: Sendable {
    var isText: Bool
    var format: FileFormat
    var encoding: TextEncoding
    var hasBOM: Bool
    var encodingConfidence: Double
    var textConfidence: Double
    var lineEnding: LineEnding
    var signatures: [MagicSignature]
    var evidence: [DetectionEvidence]
    var warnings: [String]
    var text: String?
    var byteSample: Data
    var mime: String
    var uti: String?
    var truncatedSample: Bool
    var mismatch: Bool
}

struct LoadedFile: Sendable {
    let url: URL
    let fileSize: Int64
    let modified: Date?
    let created: Date?
    let permissions: String?
    let probe: ProbeResult
    let text: String
    let rawData: Data?
    let isTruncated: Bool
    let isReadOnly: Bool
    let readOnlyReason: String?
    let decodeHadErrors: Bool
}

/// Result of a best-effort decode. `hadErrors` means some bytes could not be
/// represented by the selected encoding and were substituted.
struct DecodeOutcome: Sendable {
    let text: String
    let hadErrors: Bool
    let warning: String?
}

// MARK: - Encoding analysis

struct TextProbe {
    var isText: Bool
    var encoding: TextEncoding
    var hasBOM: Bool
    var confidence: Double
    var lineEnding: LineEnding
    var text: String?
    var evidence: [DetectionEvidence]
    var warnings: [String]
    var controlRatio: Double
}

enum TextDecoder {
    /// Total detection sample: split across head, middle and tail for large files.
    static let sampleLimit = 1_048_576
    static let maxEditableBytes: Int64 = 32 * 1024 * 1024
    static let previewBytes = 1_000_000
    static let largeFileThreshold: Int64 = 4 * 1024 * 1024

    private static let commonHan = Set("的一是在不了有和人这中大为上个国我以要他时来用们生到作地于出就分对成会可主发年动同工也能下过子说产种面而方后多定行学法所民得经十三之进着等部度家电力里如水化高自二理起小物现实加量都两体制机当使点从业本去把性好应开它合还因由其些然前外天政四日那社义事平形相全表间样与关各重新线内数正心反你明看原又么利比或但质气第向道命此变条只没结解问意建月公无系军很情者最立代想已通并提直题党程展五果料象员革位入常文总次品式活设及管特件长求老头基资边流路级少图山统接知较将组见计别她手角期根论运农指几九区强放决西被干做必战先回则任取据处队南给色光门即保治北造百规热领七海口东导器压志世金增争济阶油思术极交受联什认六共权收证改清己美再采转更单风切打白教速花带安场身车例真务具万每目至达走积示议声报斗完类八离华名确才科张信马节话米整空元况今集温传土许步群广石记需段研界拉林律叫且究观越织装影算低持音众书布复容儿须际商非验连断深难近矿千周委素技备半办青省列习响约支般史感劳便团往酸历市克何除消构府称太准精值号率族维划选标写存候毛亲快效斯院查江型眼王按格养易置派层片始却专状育厂京识适属圆包火住调满县局照参红细引听该铁价严龙飞傳統與這個為國學說時會後裡麼發長還開關點種實體樣動員應該讓給們來對從無聲義車東門見問題語文書畫電話電腦網絡軟體資訊處理設計圖檔案編輯檢視視窗結束儲存開啟新增刪除確定取消選擇設定説明協助")

    private static let mojibakeMarkers = [
        "Ã©", "Ã¨", "Ã ", "â€™", "â€œ", "â€", "Ã¢", "Â ", "å¤§", "ä¸", "æ–‡",
        "çš„", "ï¿½", "锟斤拷", "烫烫烫", "屯屯屯"
    ]

    static func probe(_ data: Data, truncated: Bool) -> TextProbe {
        if data.isEmpty {
            return TextProbe(isText: true, encoding: .utf8, hasBOM: false, confidence: 1,
                             lineEnding: .none, text: "", evidence: [
                                DetectionEvidence(kind: .info, title: "空文件", detail: "没有可读取的内容")
                             ], warnings: [], controlRatio: 0)
        }

        let working = decodeSampleData(data, truncated: truncated)
        let bom = detectBOM(working)
        if let bom, let encoding = bom.encoding {
            if let text = encoding.decode(working) {
                let clean = text.replacingOccurrences(of: "\u{0}", with: "")
                return TextProbe(
                    isText: true, encoding: encoding, hasBOM: true, confidence: 1,
                    lineEnding: LineEnding.detect(in: clean), text: text,
                    evidence: [
                        DetectionEvidence(kind: .positive, title: "检测到 \(encoding.label) BOM",
                                          detail: "文件开头的字节标记直接指明了编码")
                    ], warnings: [], controlRatio: 0
                )
            }
        }

        let bytes = [UInt8](working)
        let nullInfo = analyzeNulls(bytes)
        if nullInfo.total > 0 {
            if let guessed = guessBOMLessUTF16(bytes, nullInfo: nullInfo) {
                return guessed
            }
        }

        if let nearUTF8 = nearlyValidUTF8(working, bytes: bytes) {
            return nearUTF8
        }

        if let text = String(data: working, encoding: .utf8),
           !text.contains("\u{0}") {
            let controls = controlRatio(bytes)
            if controls < 0.02 {
                let evidence = [
                    DetectionEvidence(kind: .positive, title: "内容可按 UTF-8 完整解码",
                                      detail: "抽样 \(formatBytes(working.count))，没有发现非法字节序列"),
                    DetectionEvidence(kind: .info, title: "控制字符比例很低",
                                      detail: String(format: "%.3f%%", controls * 100))
                ]
                return TextProbe(isText: true, encoding: .utf8, hasBOM: false,
                                 confidence: max(0.9, 1 - controls * 10),
                                 lineEnding: LineEnding.detect(in: text), text: text,
                                 evidence: evidence, warnings: [], controlRatio: controls)
            }
        }

        // Try all plausible legacy encodings and score the decoded result.
        var candidates: [(TextEncoding, String, Double)] = []
        var autoEncoding: TextEncoding?
        var autoString: String?
        var converted: NSString?
        let autoRaw = NSString.stringEncoding(for: working, encodingOptions: nil,
                                              convertedString: &converted,
                                              usedLossyConversion: nil)
        if autoRaw != 0 {
            autoEncoding = encodingFromNSStringRawValue(autoRaw)
            autoString = converted as String?
        }

        for encoding in [TextEncoding.gb18030, .big5, .shiftJIS, .eucJP, .eucKR,
                         .windows1252, .isoLatin1, .macRoman, .utf16LE, .utf16BE] {
            guard let text = encoding.decode(working), !text.contains("\u{0}") else { continue }
            var score = scoreText(text, encoding: encoding, bytes: bytes)
            if let autoEncoding, autoEncoding == encoding { score += 5 }
            candidates.append((encoding, text, score))
        }

        candidates.sort { $0.2 > $1.2 }
        if let best = candidates.first {
            let control = controlRatio(bytes)
            var confidence = min(0.99, max(0.25, (best.2 - 35) / 60))
            var warnings: [String] = []
            var evidence: [DetectionEvidence] = []

            if let autoEncoding, autoEncoding == best.0 {
                evidence.append(DetectionEvidence(
                    kind: .info, title: "系统编码探测器也建议 \(best.0.label)",
                    detail: "与本地评分结果一致"
                ))
            }
            if best.0 != .utf8, autoString != nil, autoEncoding != best.0 {
                evidence.append(DetectionEvidence(
                    kind: .info, title: "系统建议的候选为 \(autoEncoding?.label ?? "未知")",
                    detail: "本地评分更倾向于 \(best.0.label)"
                ))
            }

            if best.2 < 53 || control > 0.08 {
                let reason = control > 0.08
                    ? String(format: "抽样中有 %.1f%% 的控制字符", control * 100)
                    : "按常见文本编码解码后仍不像自然语言"
                return TextProbe(
                    isText: false, encoding: .utf8, hasBOM: false,
                    confidence: max(0.55, 1 - control), lineEnding: .none, text: nil,
                    evidence: [DetectionEvidence(kind: .warning, title: "未通过文本判定",
                                                 detail: reason)],
                    warnings: [reason], controlRatio: control
                )
            }

            if control > 0.02 {
                warnings.append(String(format: "抽样中有 %.1f%% 的控制字符，显示内容可能异常", control * 100))
                confidence = min(confidence, 0.7)
            }
            if best.0 != .isoLatin1 && best.0 != .windows1252 {
                evidence.insert(DetectionEvidence(
                    kind: .positive, title: "按 \(best.0.label) 解码成功",
                    detail: "文本质量评分 \(Int(best.2)) / 100"
                ), at: 0)
            } else {
                evidence.insert(DetectionEvidence(
                    kind: .positive, title: "按 \(best.0.label) 解码",
                    detail: "单字节编码总能解码，主要依据控制字符比例判断"
                ), at: 0)
            }
            return TextProbe(
                isText: true, encoding: best.0, hasBOM: false, confidence: confidence,
                lineEnding: LineEnding.detect(in: best.1), text: best.1,
                evidence: evidence, warnings: warnings, controlRatio: control
            )
        }

        return TextProbe(
            isText: false, encoding: .utf8, hasBOM: false, confidence: 0.8,
            lineEnding: .none, text: nil,
            evidence: [DetectionEvidence(kind: .warning, title: "没有可用作文本的解码方式",
                                         detail: "抽样包含大量 NUL 或控制字节")],
            warnings: ["内容不符合常见文本编码"], controlRatio: controlRatio(bytes)
        )
    }

    private struct BOMInfo { let encoding: TextEncoding?; let length: Int }

    private static func detectBOM(_ data: Data) -> BOMInfo? {
        let b = [UInt8](data.prefix(4))
        if b.starts(with: [0x00, 0x00, 0xFE, 0xFF]) { return BOMInfo(encoding: .utf32BE, length: 4) }
        if b.starts(with: [0xFF, 0xFE, 0x00, 0x00]) { return BOMInfo(encoding: .utf32LE, length: 4) }
        if b.starts(with: [0xEF, 0xBB, 0xBF]) { return BOMInfo(encoding: .utf8, length: 3) }
        if b.starts(with: [0xFE, 0xFF]) { return BOMInfo(encoding: .utf16BE, length: 2) }
        if b.starts(with: [0xFF, 0xFE]) { return BOMInfo(encoding: .utf16LE, length: 2) }
        return nil
    }

    private struct NullInfo {
        let total: Int
        let even: Int
        let odd: Int
        let evenNull: Int
        let oddNull: Int
    }

    private static func analyzeNulls(_ bytes: [UInt8]) -> NullInfo {
        var total = 0, even = 0, odd = 0, evenNull = 0, oddNull = 0
        for (index, byte) in bytes.enumerated() where index < 8192 {
            total += 1
            if index % 2 == 0 {
                even += 1
                if byte == 0 { evenNull += 1 }
            } else {
                odd += 1
                if byte == 0 { oddNull += 1 }
            }
        }
        return NullInfo(total: total, even: even, odd: odd, evenNull: evenNull, oddNull: oddNull)
    }

    private static func guessBOMLessUTF16(_ bytes: [UInt8], nullInfo: NullInfo) -> TextProbe? {
        guard nullInfo.total >= 8 else { return nil }
        let evenRatio = Double(nullInfo.evenNull) / Double(max(1, nullInfo.even))
        let oddRatio = Double(nullInfo.oddNull) / Double(max(1, nullInfo.odd))
        let encoding: TextEncoding?
        if oddRatio > 0.35 && evenRatio < 0.06 {
            encoding = .utf16LE
        } else if evenRatio > 0.35 && oddRatio < 0.06 {
            encoding = .utf16BE
        } else {
            encoding = nil
        }
        guard let encoding else { return nil }
        let trimmed = bytes.count % 2 == 0 ? bytes : Array(bytes.dropLast())
        guard let text = encoding.decode(Data(trimmed)), !text.contains("\u{0}") else { return nil }
        let score = scoreText(text, encoding: encoding, bytes: bytes)
        guard score > 55 else { return nil }
        return TextProbe(
            isText: true, encoding: encoding, hasBOM: false,
            confidence: min(0.95, score / 100),
            lineEnding: LineEnding.detect(in: text), text: text,
            evidence: [
                DetectionEvidence(kind: .positive, title: "检测到无 BOM 的 \(encoding.label) 文本",
                                  detail: "字节奇偶位置的 NUL 分布符合 UTF-16 特征")
            ], warnings: [], controlRatio: 0
        )
    }

    private static func scoreText(_ text: String, encoding: TextEncoding, bytes: [UInt8]) -> Double {
        let scalars = Array(text.unicodeScalars)
        guard !scalars.isEmpty else { return 0 }
        let count = Double(scalars.count)
        var controls = 0.0
        var replacement = 0.0
        var privateUse = 0.0
        var han = 0.0
        var common = 0.0
        var high = 0.0
        var printable = 0.0

        for scalar in scalars {
            let v = scalar.value
            if v == 0xFFFD { replacement += 1; continue }
            if v == 0 { controls += 3; continue }
            if v < 0x20 || v == 0x7F {
                if v == 9 || v == 10 || v == 12 || v == 13 { printable += 1 }
                else { controls += 1 }
                continue
            }
            if (0x80...0x9F).contains(v) { controls += 1; continue }
            if (0xE000...0xF8FF).contains(v) { privateUse += 1; continue }
            if (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v) {
                han += 1
                if commonHan.contains(Character(scalar)) { common += 1 }
            }
            if v >= 0x80 { high += 1 }
            printable += 1
        }

        var score = 100.0
        score -= (controls / count) * 900
        score -= (replacement / count) * 1200
        score -= (privateUse / count) * 500
        score -= (1 - printable / count) * 100
        _ = high

        if han > 4 {
            let ratio = common / han
            score += min(8, ratio * 14)
            if ratio < 0.05 { score -= 12 }
        }

        let lower = text.lowercased()
        for marker in mojibakeMarkers where lower.contains(marker) {
            score -= 9
        }
        if text.contains("\u{FFFD}") { score -= 20 }

        switch encoding {
        case .gb18030: score += 3
        case .big5: score += 2
        case .windows1252: score += 1.5
        case .isoLatin1:
            if bytes.contains(where: { (0x80...0x9F).contains($0) }) { score -= 4 }
        case .shiftJIS, .eucJP: score += 1
        default: break
        }
        return min(100, max(0, score))
    }

    /// A handful of bad bytes should not turn an otherwise UTF-8 file into
    /// GB18030/CP1252. Accept UTF-8 when invalid sequences are very rare
    /// compared with the amount of non-ASCII text.
    private static func nearlyValidUTF8(_ data: Data, bytes: [UInt8]) -> TextProbe? {
        guard controlRatio(bytes) < 0.01 else { return nil }
        let text = String(decoding: data, as: UTF8.self)
        let replacements = text.unicodeScalars.reduce(into: 0) { count, scalar in
            if scalar.value == 0xFFFD { count += 1 }
        }
        guard replacements > 0, replacements <= 16 else { return nil }
        let nonASCII = bytes.reduce(into: 0) { count, byte in
            if byte >= 0x80 { count += 1 }
        }
        guard nonASCII > 0, replacements * 12 <= nonASCII else { return nil }
        let warning = "文件中检测到 \(replacements) 处非法 UTF-8 字节，已用替换字符显示。"
        return TextProbe(
            isText: true, encoding: .utf8, hasBOM: false,
            confidence: 0.82,
            lineEnding: LineEnding.detect(in: text), text: text,
            evidence: [
                DetectionEvidence(kind: .warning, title: "UTF-8 中有少量非法字节",
                                  detail: "仍按 UTF-8 打开，异常字节以 U+FFFD 显示"),
                DetectionEvidence(kind: .info, title: "其余内容可按 UTF-8 解码",
                                  detail: "非法序列只占非 ASCII 字节的很小一部分")
            ],
            warnings: [warning], controlRatio: controlRatio(bytes)
        )
    }

    private static func controlRatio(_ bytes: [UInt8]) -> Double {
        guard !bytes.isEmpty else { return 0 }
        var count = 0
        for byte in bytes.prefix(16384) {
            if byte == 0 { return 1 }
            if byte < 0x20 && byte != 9 && byte != 10 && byte != 12 && byte != 13 {
                count += 1
            } else if byte == 0x7F {
                count += 1
            }
        }
        return Double(count) / Double(min(bytes.count, 16384))
    }

    // MARK: - Best-effort decoding

    /// Decode text without treating a handful of bad bytes as a fatal error.
    /// UTF-8/16/32 use native replacement decoding; legacy CJK encodings use
    /// iconv with `//IGNORE` so one damaged byte does not destroy the file.
    static func decodeLenient(_ data: Data, encoding: TextEncoding,
                              truncated: Bool = false) -> DecodeOutcome {
        guard !data.isEmpty else {
            return DecodeOutcome(text: "", hadErrors: false, warning: nil)
        }

        if truncated {
            var candidate = data
            for _ in 0..<8 {
                if let text = encoding.decode(candidate) {
                    return DecodeOutcome(text: text, hadErrors: false, warning: nil)
                }
                guard candidate.count > 1 else { break }
                candidate = candidate.dropLast(1)
            }
        }
        if let text = encoding.decode(data) {
            return DecodeOutcome(text: text, hadErrors: false, warning: nil)
        }

        let body = stripBOM(data, encoding: encoding)
        var text = ""
        switch encoding {
        case .utf8:
            text = String(decoding: body, as: UTF8.self)
        case .utf16LE, .utf16BE:
            let units = utf16Units(body, littleEndian: encoding == .utf16LE)
            text = String(decoding: units, as: UTF16.self)
        case .utf32LE, .utf32BE:
            let units = utf32Units(body, littleEndian: encoding == .utf32LE)
            text = String(decoding: units, as: UTF32.self)
        default:
            if let name = iconvName(encoding), let decoded = iconvDecode(body, from: name) {
                text = decoded
            } else {
                text = String(data: body, encoding: .isoLatin1) ?? ""
            }
        }

        if truncated {
            // A partial multi-byte character at the preview boundary is not
            // interesting; don't show a replacement glyph for it.
            var removable = 0
            while text.hasSuffix("\u{FFFD}"), removable < 4 {
                text.removeLast()
                removable += 1
            }
        }

        let warning = "文件包含无法按 \(encoding.label) 完整解码的字节，异常部分已跳过或以替换字符显示，当前以只读方式显示。"
        return DecodeOutcome(text: text, hadErrors: true, warning: warning)
    }

    private static func stripBOM(_ data: Data, encoding: TextEncoding) -> Data {
        if let bom = encoding.bom, data.starts(with: bom) {
            return Data(data.dropFirst(bom.count))
        }
        return data
    }

    private static func utf16Units(_ data: Data, littleEndian: Bool) -> [UInt16] {
        let bytes = [UInt8](data)
        let count = bytes.count / 2
        return (0..<count).map { index in
            let a = UInt16(bytes[index * 2])
            let b = UInt16(bytes[index * 2 + 1])
            return littleEndian ? (a | (b << 8)) : ((a << 8) | b)
        }
    }

    private static func utf32Units(_ data: Data, littleEndian: Bool) -> [UInt32] {
        let bytes = [UInt8](data)
        let count = bytes.count / 4
        return (0..<count).map { index in
            let b0 = UInt32(bytes[index * 4])
            let b1 = UInt32(bytes[index * 4 + 1])
            let b2 = UInt32(bytes[index * 4 + 2])
            let b3 = UInt32(bytes[index * 4 + 3])
            return littleEndian
                ? (b0 | (b1 << 8) | (b2 << 16) | (b3 << 24))
                : ((b0 << 24) | (b1 << 16) | (b2 << 8) | b3)
        }
    }

    private static func iconvName(_ encoding: TextEncoding) -> String? {
        switch encoding {
        case .gb18030: return "GB18030"
        case .big5: return "BIG5"
        case .shiftJIS: return "SHIFT_JIS"
        case .eucJP: return "EUC-JP"
        case .eucKR: return "EUC-KR"
        case .windows1252: return "CP1252"
        case .isoLatin1: return "ISO-8859-1"
        case .macRoman: return "MACINTOSH"
        default: return nil
        }
    }

    private static func iconvDecode(_ data: Data, from source: String) -> String? {
        let target = "UTF-8//IGNORE"
        let cd = target.withCString { to in
            source.withCString { from in iconv_open(to, from) }
        }
        guard let cd, cd != iconv_t(bitPattern: -1) else { return nil }
        defer { iconv_close(cd) }

        var input = [CChar](data.map { CChar(bitPattern: $0) })
        guard !input.isEmpty else { return "" }
        let outputSize = max(64, input.count * 4 + 32)
        return input.withUnsafeMutableBufferPointer { inBuffer -> String? in
            var inPointer = inBuffer.baseAddress
            var inLeft = inBuffer.count
            var output = [CChar](repeating: 0, count: outputSize)
            return output.withUnsafeMutableBufferPointer { outBuffer -> String? in
                var outPointer = outBuffer.baseAddress
                var outLeft = outBuffer.count
                let result = iconv(cd, &inPointer, &inLeft, &outPointer, &outLeft)
                guard result != -1 || inLeft == 0 else { return nil }
                let written = outBuffer.count - outLeft
                return String(decoding: outBuffer.prefix(written).map { UInt8(bitPattern: $0) },
                              as: UTF8.self)
            }
        }
    }

    private static func decodeSampleData(_ data: Data, truncated: Bool) -> Data {
        guard truncated, data.count > 8 else { return data }
        return data.dropLast(4)
    }

    private static func encodingFromNSStringRawValue(_ raw: UInt) -> TextEncoding? {
        for encoding in TextEncoding.allCases where encoding.nsEncoding.rawValue == raw {
            return encoding
        }
        // Big5 and GB18030 come from CF and are present in allCases.
        return nil
    }

    private static func formatBytes(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }
}

// MARK: - Magic signatures

enum MagicScanner {
    private struct Rule {
        let label: String
        let formatID: String?
        let offset: Int
        let bytes: [UInt8]
        let textual: Bool
        let strong: Bool
    }

    private static let rules: [Rule] = [
        Rule(label: "PNG 图像", formatID: "png", offset: 0, bytes: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A], textual: false, strong: true),
        Rule(label: "JPEG 图像", formatID: "jpeg", offset: 0, bytes: [0xFF, 0xD8, 0xFF], textual: false, strong: true),
        Rule(label: "GIF 图像", formatID: "gif", offset: 0, bytes: [0x47, 0x49, 0x46, 0x38], textual: false, strong: true),
        Rule(label: "PDF 文档", formatID: "pdf", offset: 0, bytes: [0x25, 0x50, 0x44, 0x46], textual: false, strong: true),
        Rule(label: "ZIP 容器", formatID: "zip", offset: 0, bytes: [0x50, 0x4B, 0x03, 0x04], textual: false, strong: true),
        Rule(label: "ZIP 容器（空）", formatID: "zip", offset: 0, bytes: [0x50, 0x4B, 0x05, 0x06], textual: false, strong: true),
        Rule(label: "Gzip 压缩包", formatID: "gzip", offset: 0, bytes: [0x1F, 0x8B], textual: false, strong: true),
        Rule(label: "Bzip2 压缩包", formatID: "bzip2", offset: 0, bytes: [0x42, 0x5A, 0x68], textual: false, strong: true),
        Rule(label: "XZ 压缩包", formatID: "xz", offset: 0, bytes: [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00], textual: false, strong: true),
        Rule(label: "7-Zip 压缩包", formatID: "sevenzip", offset: 0, bytes: [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C], textual: false, strong: true),
        Rule(label: "RAR 压缩包", formatID: "rar", offset: 0, bytes: [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07], textual: false, strong: true),
        Rule(label: "SQLite 3 数据库", formatID: "sqlite", offset: 0, bytes: Array("SQLite format 3\u{0}".utf8), textual: false, strong: true),
        Rule(label: "Mach-O 可执行文件", formatID: "macho", offset: 0, bytes: [0xFE, 0xED, 0xFA, 0xCE], textual: false, strong: true),
        Rule(label: "Mach-O 可执行文件", formatID: "macho", offset: 0, bytes: [0xFE, 0xED, 0xFA, 0xCF], textual: false, strong: true),
        Rule(label: "Mach-O 可执行文件", formatID: "macho", offset: 0, bytes: [0xCE, 0xFA, 0xED, 0xFE], textual: false, strong: true),
        Rule(label: "Mach-O 可执行文件", formatID: "macho", offset: 0, bytes: [0xCF, 0xFA, 0xED, 0xFE], textual: false, strong: true),
        Rule(label: "Mach-O 通用二进制", formatID: "macho", offset: 0, bytes: [0xCA, 0xFE, 0xBA, 0xBE], textual: false, strong: true),
        Rule(label: "ELF 可执行文件", formatID: "elf", offset: 0, bytes: [0x7F, 0x45, 0x4C, 0x46], textual: false, strong: true),
        Rule(label: "PE / Windows 可执行文件", formatID: "pe", offset: 0, bytes: [0x4D, 0x5A], textual: false, strong: false),
        Rule(label: "WASM 模块", formatID: "wasm", offset: 0, bytes: [0x00, 0x61, 0x73, 0x6D], textual: false, strong: true),
        Rule(label: "Java Class 文件", formatID: "class", offset: 0, bytes: [0xCA, 0xFE, 0xBA, 0xBE], textual: false, strong: false),
        Rule(label: "Android DEX", formatID: "dex", offset: 0, bytes: [0x64, 0x65, 0x78, 0x0A], textual: false, strong: true),
        Rule(label: "WebP 图像", formatID: "webp", offset: 0, bytes: Array("RIFF".utf8), textual: false, strong: false),
        Rule(label: "WAV 音频", formatID: "wav", offset: 0, bytes: Array("RIFF".utf8), textual: false, strong: false),
        Rule(label: "MP4 / QuickTime 视频", formatID: "mp4", offset: 4, bytes: Array("ftyp".utf8), textual: false, strong: false),
        Rule(label: "Ogg 媒体", formatID: "ogg", offset: 0, bytes: Array("OggS".utf8), textual: false, strong: true),
        Rule(label: "FLAC 音频", formatID: "flac", offset: 0, bytes: Array("fLaC".utf8), textual: false, strong: true),
        Rule(label: "MP3 音频", formatID: "mp3", offset: 0, bytes: Array("ID3".utf8), textual: false, strong: true),
        Rule(label: "TIFF 图像", formatID: "tiff", offset: 0, bytes: [0x49, 0x49, 0x2A, 0x00], textual: false, strong: true),
        Rule(label: "TIFF 图像", formatID: "tiff", offset: 0, bytes: [0x4D, 0x4D, 0x00, 0x2A], textual: false, strong: true),
        Rule(label: "BMP 图像", formatID: "bmp", offset: 0, bytes: [0x42, 0x4D], textual: false, strong: true),
        Rule(label: "ICO 图标", formatID: "ico", offset: 0, bytes: [0x00, 0x00, 0x01, 0x00], textual: false, strong: true),
        Rule(label: "ICNS 图标", formatID: "icns", offset: 0, bytes: [0x69, 0x63, 0x6E, 0x73], textual: false, strong: true),
        Rule(label: "Photoshop 文档", formatID: "psd", offset: 0, bytes: [0x38, 0x42, 0x50, 0x53], textual: false, strong: true),
        Rule(label: "Tar 归档", formatID: "tar", offset: 257, bytes: Array("ustar".utf8), textual: false, strong: true),
        Rule(label: "二进制 Property List", formatID: "plist", offset: 0, bytes: Array("bplist00".utf8), textual: false, strong: true),
        Rule(label: "PNG 图像", formatID: "png", offset: 0, bytes: [0x89, 0x50, 0x4E, 0x47], textual: false, strong: true),
        Rule(label: "RTF 富文本", formatID: "rtf", offset: 0, bytes: Array("{\\rtf".utf8), textual: true, strong: false),
        Rule(label: "XML 声明", formatID: "xml", offset: 0, bytes: Array("<?xml".utf8), textual: true, strong: false),
        Rule(label: "PEM 证书 / 密钥", formatID: "pem", offset: 0, bytes: Array("-----BEGIN ".utf8), textual: true, strong: false),
        Rule(label: "Shebang 脚本", formatID: nil, offset: 0, bytes: [0x23, 0x21], textual: true, strong: false)
    ]

    static func scan(_ data: Data) -> [MagicSignature] {
        let bytes = [UInt8](data)
        guard !bytes.isEmpty else { return [] }
        var found: [MagicSignature] = []
        for rule in rules {
            guard bytes.count >= rule.offset + rule.bytes.count else { continue }
            let slice = Array(bytes[rule.offset..<(rule.offset + rule.bytes.count)])
            guard slice == rule.bytes else { continue }
            var label = rule.label
            var formatID = rule.formatID
            if rule.bytes == Array("RIFF".utf8), bytes.count >= 12 {
                let kind = String(bytes: bytes[8..<12], encoding: .ascii) ?? ""
                if kind == "WEBP" { label = "WebP 图像"; formatID = "webp" }
                else if kind == "WAVE" { label = "WAV 音频"; formatID = "wav" }
                else { label = "RIFF 容器"; formatID = nil }
            }
            if rule.bytes == Array("ftyp".utf8), bytes.count >= 12 {
                let brand = String(bytes: bytes[8..<12], encoding: .ascii) ?? ""
                if brand.hasPrefix("qt") { label = "QuickTime 视频"; formatID = "mov" }
                else { label = "MP4 视频"; formatID = "mp4" }
            }
            let signature = MagicSignature(label: label, formatID: formatID, offset: rule.offset,
                                           bytes: rule.bytes, textual: rule.textual, strong: rule.strong)
            if !found.contains(where: { $0.label == signature.label && $0.formatID == signature.formatID }) {
                found.append(signature)
            }
        }
        return found
    }
}

// MARK: - Whole-file detection

enum FileDetector {
    static func probe(sample: Data, fileURL: URL, fileSize: Int64, truncated: Bool) -> ProbeResult {
        let textProbe = TextDecoder.probe(sample, truncated: truncated)
        let signatures = MagicScanner.scan(sample)
        let ext = fileURL.pathExtension.lowercased()
        let extFormat = FileCatalog.format(forURL: fileURL)
        let extensionKnown = !ext.isEmpty && FileCatalog.format(forExtension: ext) != nil

        var evidence: [DetectionEvidence] = []
        var warnings: [String] = []
        var mismatch = false

        for signature in signatures.prefix(3) {
            evidence.append(DetectionEvidence(
                kind: .info,
                title: "文件头匹配：\(signature.label)",
                detail: signature.offset == 0
                    ? "起始字节 \(signature.hex)"
                    : "偏移 \(signature.offset) 字节：\(signature.hex)"
            ))
        }

        let strongBinary = signatures.first(where: { $0.strong && !$0.textual })
        let weakBinary = signatures.first(where: { !$0.strong && !$0.textual })
        let textSignature = signatures.first(where: { $0.textual })

        var isText: Bool
        if strongBinary != nil {
            isText = false
        } else if textProbe.isText {
            isText = true
        } else if weakBinary != nil {
            isText = false
        } else {
            isText = false
        }

        // A PDF or archive is never treated as text even if its first bytes happen to decode.
        if let strongBinary, strongBinary.formatID == "pdf" { isText = false }

        // A text-looking file with only a weak signature (for example a text file starting "MZ")
        // stays text; a real executable has control bytes and will already have failed the text probe.
        if isText == false, weakBinary != nil, textProbe.isText, strongBinary == nil {
            isText = true
        }

        var format: FileFormat
        var mime = "application/octet-stream"
        var uti: String?

        if isText {
            let sniffed = sniffText(sample, text: textProbe.text, extFormat: extFormat, ext: ext)
            if let strongBinary { // defensive
                _ = strongBinary
            }
            if let sniffed {
                format = sniffed.format
                if let detail = sniffed.detail {
                    evidence.append(DetectionEvidence(kind: .info, title: sniffed.title, detail: detail))
                }
            } else if let extFormat {
                format = extFormat
            } else {
                format = FileFormat.plainText
            }

            if let extFormat, !extFormat.category.isTextual {
                mismatch = true
                warnings.append("扩展名 .\(ext) 通常表示「\(extFormat.name)」，但文件内容是可解码的文本。")
                format = sniffed?.format ?? FileFormat.plainText
            }

            if ext.isEmpty {
                evidence.append(DetectionEvidence(kind: .info, title: "文件没有扩展名",
                                                  detail: "类型完全依据文件内容判断"))
            } else if !extensionKnown {
                evidence.append(DetectionEvidence(kind: .info, title: "扩展名 .\(ext) 不在已知类型表中",
                                                  detail: "内容能解码为文本，因此仍可打开和编辑"))
            } else if let extFormat, extFormat.id == format.id {
                evidence.append(DetectionEvidence(kind: .info, title: "扩展名与内容一致",
                                                  detail: ".\(ext) → \(format.name)"))
            }

            if textProbe.text != nil {
                evidence.append(contentsOf: textProbe.evidence)
                warnings.append(contentsOf: textProbe.warnings)
            }

            let line = textProbe.lineEnding
            if line != .none {
                evidence.append(DetectionEvidence(
                    kind: .info, title: "换行符：\(line.label)",
                    detail: line.longLabel
                ))
            }
            mime = format.mime
            uti = utiFor(ext: ext, isText: true)
            if let textFormat = textSignature, textFormat.formatID == nil, ext.isEmpty {
                if let shebang = shebangFormat(textProbe.text) {
                    format = shebang.format
                    evidence.append(DetectionEvidence(kind: .info, title: "识别到 Shebang",
                                                      detail: shebang.detail))
                    evidence.append(DetectionEvidence(kind: .info, title: "解释器",
                                                      detail: shebang.interpreter))
                }
            }
        } else {
            if let strong = strongBinary, let id = strong.formatID,
               let magicFormat = FileCatalog.format(forID: id) {
                format = magicFormat
                if ext == "docx" { format = FileCatalog.byID["docx"] ?? magicFormat }
                if ext == "xlsx" { format = FileCatalog.byID["xlsx"] ?? magicFormat }
                if ext == "pptx" { format = FileCatalog.byID["pptx"] ?? magicFormat }
                if ext == "jar" { format = FileCatalog.byID["jar"] ?? magicFormat }
                if ext == "apk" { format = FileCatalog.byID["apk"] ?? magicFormat }
                if ext == "epub" { format = FileCatalog.byID["epub"] ?? magicFormat }
                if ext != "", let extFormat, extFormat.category.isTextual, extFormat.id != format.id {
                    mismatch = true
                    warnings.append("扩展名 .\(ext) 通常表示「\(extFormat.name)」，但文件头是 \(strong.label)。")
                }
            } else if let extFormat {
                format = extFormat
            } else if let strong = strongBinary, let id = strong.formatID,
                      let magicFormat = FileCatalog.format(forID: id) {
                format = magicFormat
            } else {
                format = FileFormat.unknownBinary
            }

            if let weak = weakBinary, format.id == "binary", let id = weak.formatID,
               let f = FileCatalog.format(forID: id) {
                format = f
            }
            mime = format.mime
            uti = utiFor(ext: ext, isText: false)
            if ext.isEmpty {
                evidence.append(DetectionEvidence(kind: .info, title: "文件没有扩展名",
                                                  detail: "类型依据文件头和字节特征判断"))
            } else if !extensionKnown {
                evidence.append(DetectionEvidence(kind: .info, title: "扩展名 .\(ext) 不在已知类型表中",
                                                  detail: "已根据文件头判断为 \(format.name)"))
            }
            if !textProbe.isText {
                evidence.append(contentsOf: textProbe.evidence)
            }
            if format.id == "binary" {
                warnings.append("没有匹配到已知文件头，内容也不是可解码的文本。")
            }
        }

        var textConfidence = textProbe.confidence
        if isText {
            if textProbe.hasBOM { textConfidence = 1 }
            else if format.category == .text, textProbe.encoding == .utf8 { textConfidence = max(textConfidence, 0.95) }
        } else {
            textConfidence = max(textProbe.confidence, 0.8)
            if signatures.contains(where: { $0.strong && !$0.textual }) {
                textConfidence = 1
            }
        }

        if !warnings.isEmpty {
            for warning in warnings {
                if !evidence.contains(where: { $0.title == warning }) {
                    evidence.append(DetectionEvidence(kind: .warning, title: warning, detail: nil))
                }
            }
        }

        let truncatedSample = truncated
        return ProbeResult(
            isText: isText,
            format: format,
            encoding: textProbe.encoding,
            hasBOM: textProbe.hasBOM,
            encodingConfidence: isText ? textProbe.confidence : 0,
            textConfidence: textConfidence,
            lineEnding: isText ? LineEnding.detect(in: textProbe.text ?? "") : .none,
            signatures: signatures,
            evidence: evidence,
            warnings: warnings,
            text: isText ? textProbe.text : nil,
            byteSample: Data(sample.prefix(1024)),
            mime: mime,
            uti: uti,
            truncatedSample: truncatedSample,
            mismatch: mismatch
        )
    }

    private struct SniffResult {
        let format: FileFormat
        let title: String
        let detail: String?
    }

    private static func sniffText(_ data: Data, text: String?, extFormat: FileFormat?, ext: String) -> SniffResult? {
        guard let text else { return nil }
        let trimmed = text.drop(while: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" })
        let prefix = String(trimmed.prefix(8192))
        let lower = prefix.lowercased()
        let genericExt = ext.isEmpty || ["txt", "text", "log", "dat", "data", "tmp", "out", "dump"].contains(ext)
        let extIsStrong = extFormat != nil && !genericExt

        if prefix.hasPrefix("#!") {
            if let shebang = shebangFormat(text) {
                return SniffResult(format: shebang.format, title: "识别到 Shebang 脚本",
                                   detail: shebang.interpreter)
            }
        }
        if lower.contains("<svg") && (lower.hasPrefix("<svg") || lower.hasPrefix("<?xml")) {
            return SniffResult(format: FileCatalog.byID["svg"]!, title: "内容看起来是 SVG",
                               detail: "SVG 本质上是 XML 文本，可以直接编辑")
        }
        if lower.hasPrefix("<?xml") {
            return SniffResult(format: FileCatalog.byID["xml"]!, title: "内容看起来是 XML",
                               detail: "以 XML 声明开头")
        }
        if lower.hasPrefix("<!doctype html") || lower.hasPrefix("<html") {
            return SniffResult(format: FileCatalog.byID["html"]!, title: "内容看起来是 HTML",
                               detail: "以 HTML 文档标记开头")
        }
        if (prefix.hasPrefix("{") || prefix.hasPrefix("[")) && !extIsStrong {
            if (try? JSONSerialization.jsonObject(with: Data(prefix.utf8))) != nil {
                return SniffResult(format: FileCatalog.byID["json"]!, title: "内容看起来是 JSON",
                                   detail: "开头是合法 JSON 结构")
            }
        }
        if prefix.hasPrefix("-----BEGIN ") {
            return SniffResult(format: FileCatalog.byID["pem"]!, title: "内容看起来是 PEM 证书 / 密钥",
                               detail: "以 PEM 边界标记开头")
        }
        if lower.hasPrefix("{\\rtf") {
            return SniffResult(format: FileCatalog.byID["rtf"]!, title: "内容看起来是 RTF",
                               detail: "以 RTF 控制字开头")
        }
        if !extIsStrong {
            let firstLine = prefix.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
            let commaCount = firstLine.filter { $0 == "," }.count
            if commaCount >= 2, prefix.contains("\n") {
                return SniffResult(format: FileCatalog.byID["csv"]!, title: "内容看起来是 CSV",
                                   detail: "首行包含多个逗号分隔字段")
            }
        }
        if ["sql"].contains(ext) { return nil }
        return nil
    }

    private static func shebangFormat(_ text: String?) -> (format: FileFormat, interpreter: String, detail: String)? {
        guard let text, text.hasPrefix("#!") else { return nil }
        let firstLine = text.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? text
        let lower = firstLine.lowercased()
        let mapping: [(String, String, SyntaxLanguage)] = [
            ("python", "python", .python),
            ("swift", "swift", .swift),
            ("node", "node", .javascript),
            ("deno", "deno", .typescript),
            ("bash", "bash", .shell),
            ("zsh", "zsh", .shell),
            ("sh", "sh", .shell),
            ("ruby", "ruby", .ruby),
            ("perl", "perl", .perl),
            ("php", "php", .php),
            ("lua", "lua", .lua),
            ("osascript", "osascript", .plainText)
        ]
        for (needle, name, syntax) in mapping where lower.contains(needle) {
            let format = FileFormat(id: "script-\(name)", name: "\(name) 脚本", category: .sourceCode,
                                    mime: "text/x-script", symbol: "terminal", tint: .green,
                                    syntax: syntax, known: true)
            return (format, firstLine, "解释器：\(firstLine)")
        }
        return nil
    }

    private static func utiFor(ext: String, isText: Bool) -> String? {
        if !ext.isEmpty, let type = UTType(filenameExtension: ext),
           !type.identifier.hasPrefix("dyn.") {
            return type.identifier
        }
        return isText ? "public.plain-text" : "public.data"
    }
}

// MARK: - Loader

enum FileLoaderError: LocalizedError {
    case notAFile
    case unreadable(String)
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .notAFile: return "这不是一个普通文件"
        case .unreadable(let message): return "无法读取文件：\(message)"
        case .tooLarge: return "文件太大，无法载入"
        }
    }
}

enum FileLoader {
    static func snapshot(of url: URL) -> (size: Int64, modified: Date?)? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        return (size, attrs[.modificationDate] as? Date)
    }

    static func load(url: URL) throws -> LoadedFile {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw FileLoaderError.notAFile
        }
        let attrs: [FileAttributeKey: Any]
        do {
            attrs = try fm.attributesOfItem(atPath: url.path)
        } catch {
            throw FileLoaderError.unreadable(error.localizedDescription)
        }
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let modified = attrs[.modificationDate] as? Date
        let created = attrs[.creationDate] as? Date
        let permissions = (attrs[.posixPermissions] as? NSNumber).map { String(format: "%03o", $0.intValue) }

        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw FileLoaderError.unreadable(error.localizedDescription)
        }
        defer { try? handle.close() }

        let sample = readSample(handle: handle, size: size)
        let truncatedSample = size > Int64(sample.count)
        var probe = FileDetector.probe(sample: sample, fileURL: url, fileSize: size,
                                       truncated: truncatedSample)
        if truncatedSample {
            probe.evidence.insert(DetectionEvidence(
                kind: .info,
                title: "大文件采用多段抽样",
                detail: "同时读取文件头、中部和结尾，避免编码特征只出现在后段时漏检"
            ), at: 0)
        }

        var text = ""
        var rawData: Data?
        var isTruncated = false
        var readOnly = false
        var readOnlyReason: String?
        var decodeHadErrors = false

        if probe.isText && size > 0 {
            if size <= TextDecoder.maxEditableBytes {
                let data: Data
                do {
                    data = try Data(contentsOf: url, options: [.mappedIfSafe])
                } catch {
                    throw FileLoaderError.unreadable(error.localizedDescription)
                }

                if data.count <= TextDecoder.sampleLimit {
                    // For small files the complete bytes are the best sample.
                    let fullProbe = FileDetector.probe(sample: data, fileURL: url,
                                                       fileSize: size, truncated: false)
                    if fullProbe.isText { probe = fullProbe }
                }

                let outcome = TextDecoder.decodeLenient(data, encoding: probe.encoding)
                text = outcome.text
                rawData = data
                if outcome.hadErrors {
                    decodeHadErrors = true
                    readOnly = true
                    readOnlyReason = outcome.warning
                    if let warning = outcome.warning {
                        probe.warnings.append(warning)
                        probe.evidence.append(DetectionEvidence(
                            kind: .warning,
                            title: "解码存在无法识别的字节",
                            detail: warning
                        ))
                    }
                }
                if probe.text == nil { probe.text = text }
            } else {
                let previewLength = Int(min(Int64(TextDecoder.previewBytes), size))
                try? handle.seek(toOffset: 0)
                let data = (try? handle.read(upToCount: previewLength)) ?? sample
                let outcome = TextDecoder.decodeLenient(data, encoding: probe.encoding,
                                                        truncated: true)
                text = outcome.text
                rawData = data
                isTruncated = true
                readOnly = true
                readOnlyReason = "文件大于 \(FileFormatting.bytes(TextDecoder.maxEditableBytes))，当前以连续窗口模式打开。"
                probe.warnings.append(readOnlyReason!)
                probe.evidence.append(DetectionEvidence(
                    kind: .warning,
                    title: "大文件连续窗口模式",
                    detail: "按窗口浏览、搜索和编辑，不会把整份文件加载进内存"
                ))
                if outcome.hadErrors {
                    decodeHadErrors = true
                    probe.warnings.append("预览范围内有无法解码的字节，已跳过。")
                }
                if probe.text == nil { probe.text = text }
            }

            if !text.isEmpty {
                let detectedLine = LineEnding.detect(in: text)
                if detectedLine != .none {
                    probe.lineEnding = detectedLine
                }
            }
        } else if size == 0 {
            readOnly = false
        } else {
            readOnly = true
            readOnlyReason = "这是二进制文件，不在文本编辑器中直接修改。"
        }

        return LoadedFile(
            url: url,
            fileSize: size,
            modified: modified,
            created: created,
            permissions: permissions,
            probe: probe,
            text: text,
            rawData: rawData,
            isTruncated: isTruncated,
            isReadOnly: readOnly,
            readOnlyReason: readOnlyReason,
            decodeHadErrors: decodeHadErrors
        )
    }

    /// For large files, read head + middle + tail instead of only the first
    /// 256 KB. Offsets are 4-byte aligned so UTF-16/32 samples stay aligned.
    private static func readSample(handle: FileHandle, size: Int64) -> Data {
        guard size > 0 else { return Data() }
        let limit = Int64(TextDecoder.sampleLimit)
        if size <= limit {
            try? handle.seek(toOffset: 0)
            return (try? handle.read(upToCount: Int(size))) ?? Data()
        }

        let segment = max(Int64(64 * 1024), (limit / 3) & ~3)
        var pieces: [Data] = []
        pieces.append(readWindow(handle, offset: 0, length: Int(segment)))

        if size >= segment * 3 {
            let middleOffset = ((size / 2) - segment / 2) & ~3
            let tailOffset = (size - segment) & ~3
            pieces.append(readWindow(handle, offset: middleOffset, length: Int(segment)))
            pieces.append(readWindow(handle, offset: tailOffset, length: Int(segment)))
        } else {
            let tailOffset = (size - segment) & ~3
            pieces.append(readWindow(handle, offset: tailOffset, length: Int(segment)))
        }

        var result = Data()
        for (index, piece) in pieces.enumerated() {
            if index < pieces.count - 1, piece.count > 4 {
                result.append(contentsOf: piece.dropLast(4))
            } else {
                result.append(piece)
            }
        }
        return result
    }

    private static func readWindow(_ handle: FileHandle, offset: Int64, length: Int) -> Data {
        guard offset >= 0, length > 0 else { return Data() }
        try? handle.seek(toOffset: UInt64(offset))
        return (try? handle.read(upToCount: length)) ?? Data()
    }
}

// MARK: - Formatting helpers

enum FileFormatting {
    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    static func date(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    static func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    static func hexDump(_ data: Data, maxBytes: Int = 512) -> String {
        let bytes = [UInt8](data.prefix(maxBytes))
        guard !bytes.isEmpty else { return "（空文件）" }
        var lines: [String] = []
        var offset = 0
        while offset < bytes.count {
            let end = min(offset + 16, bytes.count)
            let slice = bytes[offset..<end]
            let hex = slice.map { String(format: "%02X", $0) }.joined(separator: " ")
            let padded = hex.padding(toLength: 47, withPad: " ", startingAt: 0)
            let ascii = slice.map { byte -> String in
                (32...126).contains(byte) ? String(UnicodeScalar(byte)) : "."
            }.joined()
            lines.append(String(format: "%08X  %@  %@", offset, padded, ascii))
            offset = end
        }
        return lines.joined(separator: "\n")
    }
}
