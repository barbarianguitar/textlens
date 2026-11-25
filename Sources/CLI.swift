import Foundation

enum CommandLineTool {
    static func handle() -> Bool {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.contains("--selftest") {
            runSelfTest()
            return true
        }
        if let index = args.firstIndex(of: "--detect"), index + 1 < args.count {
            let path = args[index + 1]
            runDetect(path: path)
            return true
        }
        if args.contains("--help") || args.contains("-h") {
            print("""
            TextLens 文本透镜

            用法：
              TextLens                     启动图形界面
              TextLens <文件>              启动并打开文件
              TextLens --detect <文件>     在终端输出文件识别结果（JSON）
              TextLens --selftest          运行检测内核自测
            """)
            return true
        }
        if let first = args.first, !first.hasPrefix("-"), FileManager.default.fileExists(atPath: first) {
            // The GUI launches later; AppDelegate picks this up as a pending file.
            return false
        }
        return false
    }

    private struct Report: Codable {
        let path: String
        let size: Int64
        let isText: Bool
        let format: String
        let formatID: String
        let category: String
        let mime: String
        let uti: String?
        let encoding: String
        let encodingConfidence: Double
        let hasBOM: Bool
        let lineEnding: String
        let textConfidence: Double
        let language: String
        let warnings: [String]
        let evidence: [String]
        let signatures: [String]
        let preview: String
    }

    private static func runDetect(path: String) {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        do {
            let loaded = try FileLoader.load(url: url)
            let report = Report(
                path: url.path,
                size: loaded.fileSize,
                isText: loaded.probe.isText,
                format: loaded.probe.format.name,
                formatID: loaded.probe.format.id,
                category: loaded.probe.format.category.label,
                mime: loaded.probe.mime,
                uti: loaded.probe.uti,
                encoding: loaded.probe.encoding.label,
                encodingConfidence: (loaded.probe.encodingConfidence * 1000).rounded() / 1000,
                hasBOM: loaded.probe.hasBOM,
                lineEnding: loaded.probe.lineEnding.label,
                textConfidence: (loaded.probe.textConfidence * 1000).rounded() / 1000,
                language: loaded.probe.format.syntax.label,
                warnings: loaded.probe.warnings,
                evidence: loaded.probe.evidence.map { $0.title + ($0.detail.map { " — " + $0 } ?? "") },
                signatures: loaded.probe.signatures.map { $0.label },
                preview: String(loaded.text.prefix(600))
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(report)
            print(String(decoding: data, as: UTF8.self))
        } catch {
            FileHandle.standardError.write(Data("错误：\(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    // MARK: - Self test

    private static var failures = 0
    private static var passes = 0

    private static func check(_ name: String, _ condition: @autoclosure () -> Bool, _ detail: String = "") {
        if condition() {
            passes += 1
            print("  ✓ \(name)")
        } else {
            failures += 1
            print("  ✗ \(name)\(detail.isEmpty ? "" : " — \(detail)")")
        }
    }

    private static func runSelfTest() {
        print("TextLens 识别内核自测")
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("textlens-selftest-\(UUID().uuidString)")
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        func write(_ name: String, _ data: Data) -> URL {
            let url = root.appendingPathComponent(name)
            try? data.write(to: url)
            return url
        }

        if let data = "这是一个测试文件，包含中文和标点。\n第二行。\n".data(using: .utf8) {
            let url = write("sample.weird", data)
            if let loaded = try? FileLoader.load(url: url) {
                check("未知扩展名识别为文本", loaded.probe.isText)
                check("未知扩展名编码为 UTF-8", loaded.probe.encoding == .utf8)
                check("未知扩展名没有被误判为二进制", loaded.probe.format.category.isTextual)
                check("未知扩展名可编辑", !loaded.isReadOnly && loaded.rawData != nil)
            } else { check("未知扩展名加载", false) }
        }

        let json = "{\n  \"name\": \"TextLens\",\n  \"text\": true\n}\n"
        if let loaded = try? FileLoader.load(url: write("no-extension", Data(json.utf8))) {
            check("无扩展名 JSON 按内容识别", loaded.probe.format.id == "json", loaded.probe.format.id)
            check("JSON 是文本", loaded.probe.isText)
        }

        let chinese = "这是一个测试文件，包含中文和标点。\n第二行。\n"
        if let gb = TextEncoding.gb18030.encode(chinese, includeBOM: false) {
            if let loaded = try? FileLoader.load(url: write("gbk-sample.gbk", gb)) {
                check("GB18030 编码识别", loaded.probe.encoding == .gb18030, loaded.probe.encoding.label)
                check("GB18030 内容正确", loaded.text.contains("测试文件"), loaded.text)
            }
        }

        let traditional = "這是一個測試檔案，包含中文與標點。\n第二行。\n"
        if let big5 = TextEncoding.big5.encode(traditional, includeBOM: false) {
            if let loaded = try? FileLoader.load(url: write("big5-sample.big5", big5)) {
                check("Big5 编码识别", loaded.probe.encoding == .big5, loaded.probe.encoding.label)
                check("Big5 内容正确", loaded.text.contains("測試檔案"), loaded.text)
            }
        }

        let utf16Text = "UTF-16 测试文本\r\n第二行"
        if let utf16 = TextEncoding.utf16LE.encode(utf16Text, includeBOM: true) {
            if let loaded = try? FileLoader.load(url: write("utf16.txt", utf16)) {
                check("UTF-16LE BOM 编码识别", loaded.probe.encoding == .utf16LE, loaded.probe.encoding.label)
                check("UTF-16 BOM 被记录", loaded.probe.hasBOM)
                check("UTF-16 内容正确", loaded.text.contains("测试文本"))
            }
        }

        var png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D])
        png.append(contentsOf: [0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01])
        if let loaded = try? FileLoader.load(url: write("image.bin", png)) {
            check("PNG 文件头识别", !loaded.probe.isText)
            check("PNG 格式识别", loaded.probe.format.id == "png", loaded.probe.format.id)
            check("PNG 只读", loaded.isReadOnly)
        }

        if let loaded = try? FileLoader.load(url: write("windows.ini", Data("a=1\r\nb=2\r\n".utf8))) {
            check("CRLF 识别", loaded.probe.lineEnding == .crlf, loaded.probe.lineEnding.label)
        }

        var random = Data(count: 4096)
        random.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            arc4random_buf(base, buffer.count)
        }
        if let loaded = try? FileLoader.load(url: write("random.dat", random)) {
            check("随机二进制识别", !loaded.probe.isText)
        }

        if let loaded = try? FileLoader.load(url: write("fake.png", Data("这其实是一个文本文件。\n".utf8))) {
            check("错误扩展名的文本仍按文本打开", loaded.probe.isText)
            check("扩展名冲突给出提示", loaded.probe.mismatch)
        }

        if let loaded = try? FileLoader.load(url: write("tool", Data("#!/usr/bin/env python3\nprint('hi')\n".utf8))) {
            check("Shebang 脚本识别", loaded.probe.format.id == "script-python", loaded.probe.format.id)
        }

        if let loaded = try? FileLoader.load(url: write("empty.zzz", Data())) {
            check("空文件识别为文本", loaded.probe.isText && loaded.text.isEmpty)
        }

        let fixedForm = """
        C     FORTRAN 77 FIXED-FORM COMMENT
              PROGRAM HELLO
              INTEGER I
              DO 10 I = 1, 3
              PRINT *, 'HELLO', I
         10   CONTINUE
              END
        """
        if let loaded = try? FileLoader.load(url: write("hello.f77", Data(fixedForm.utf8))) {
            check("FORTRAN 77 扩展名识别", loaded.probe.format.id == "fortran77",
                  loaded.probe.format.id)
            check("FORTRAN 77 语法标签", loaded.probe.format.syntax == .fortran77,
                  loaded.probe.format.syntax.label)
        }

        let freeForm = """
        program hello
          implicit none
          integer :: i
          do i = 1, 3
            print *, "HELLO", i
          end do
        end program hello
        """
        if let loaded = try? FileLoader.load(url: write("hello.f90", Data(freeForm.utf8))) {
            check("FORTRAN 90 扩展名识别", loaded.probe.format.id == "fortran90",
                  loaded.probe.format.id)
            check("FORTRAN 90 语法标签", loaded.probe.format.syntax == .fortran90,
                  loaded.probe.format.syntax.label)
        }

        if let loaded = try? FileLoader.load(url: write("looks-like-json.md",
                                                         Data("{\n  not: json\n}\n".utf8))) {
            check("Markdown 扩展名不被 JSON 内容抢走", loaded.probe.format.id == "markdown",
                  loaded.probe.format.id)
        }

        if let loaded = try? FileLoader.load(url: write("drawing.svg",
                                                         Data("<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>\n".utf8))) {
            check("SVG 单独识别", loaded.probe.format.id == "svg", loaded.probe.format.id)
        }

        if let plistData = try? PropertyListSerialization.data(
            fromPropertyList: ["name": "TextLens"], format: .binary, options: 0) {
            if let loaded = try? FileLoader.load(url: write("sample.plist", plistData)) {
                check("二进制 plist 不误报扩展名冲突", !loaded.probe.isText && loaded.probe.warnings.isEmpty,
                      loaded.probe.warnings.joined(separator: ";"))
                check("二进制 plist 格式识别", loaded.probe.format.id == "plist", loaded.probe.format.id)
            }
        }

        var mixed = Data("a\r\nb\nc\r".utf8)
        if let loaded = try? FileLoader.load(url: write("mixed.txt", mixed)) {
            check("混合换行识别", loaded.probe.lineEnding == .mixed, loaded.probe.lineEnding.label)
        }
        mixed.removeAll(keepingCapacity: false)

        // Large but editable text (over the old 8 MB limit).
        let largeText = "HEAD-MARKER\n" + String(repeating: "0123456789abcdef\n", count: 560_000)
        if let largeData = largeText.data(using: .utf8) {
            if let loaded = try? FileLoader.load(url: write("large.log", largeData)) {
                check("约 9 MB 文本可编辑", !loaded.isReadOnly && !loaded.isTruncated)
                check("大文件内容从开头完整载入", loaded.text.hasPrefix("HEAD-MARKER"),
                      String(loaded.text.prefix(24)))
                check("大文件没有丢尾部", loaded.text.hasSuffix("0123456789abcdef\n"))
            }
        }

        // Encoding feature appears only after the old 256 KB head sample.
        var lateGBK = Data(String(repeating: "ASCII prefix line\n", count: 100_000).utf8)
        if let chinese = TextEncoding.gb18030.encode(
            "这是藏在文件尾部的中文编码测试，用来验证多段抽样。\n", includeBOM: false) {
            lateGBK.append(chinese)
            if let loaded = try? FileLoader.load(url: write("late-gbk.log", lateGBK)) {
                check("大文件多段抽样识别尾部 GB18030", loaded.probe.encoding == .gb18030,
                      loaded.probe.encoding.label)
                check("尾部中文内容正确", loaded.text.contains("藏在文件尾部"), loaded.text.suffix(80).description)
                check("多段抽样后仍可编辑", !loaded.isReadOnly)
            }
        }

        // A few malformed UTF-8 bytes should not make the whole file fail.
        var corruptUTF8 = Data(String(repeating: "正常 UTF-8 文本 line\n", count: 60_000).utf8)
        corruptUTF8.append(0xFF)
        corruptUTF8.append(Data("结尾仍然可以读取。\n".utf8))
        if let loaded = try? FileLoader.load(url: write("corrupt-utf8.log", corruptUTF8)) {
            check("少量坏字节不会导致打开失败", loaded.probe.isText)
            check("坏字节被替换并标记", loaded.decodeHadErrors && loaded.isReadOnly)
            check("坏字节周围文本仍可读取", loaded.text.contains("结尾仍然可以读取"), loaded.text.suffix(80).description)
        }

        // Rope core: balanced text, line lookup, edits.
        do {
            var rope = TextRope("alpha\nbeta\ngamma\n")
            check("Rope 行数", rope.lineCount == 4, "\(rope.lineCount)")
            check("Rope 行首定位", rope.lineStart(2) == 6 && rope.lineStart(3) == 11)
            check("Rope 行列定位", rope.lineAndColumn(at: 12) == (3, 2),
                  "\(rope.lineAndColumn(at: 12))")
            rope.replace(NSRange(location: 6, length: 4), with: "BETA!")
            check("Rope 中间替换", rope.wholeText == "alpha\nBETA!\ngamma\n", rope.wholeText)
            rope.insert("X", at: 0)
            rope.delete(NSRange(location: 11, length: 1))
            check("Rope 插入删除", rope.wholeText == "Xalpha\nBETA\ngamma\n", rope.wholeText)
            var reference = "Xalpha\nBETA\ngamma\n"
            var random = SystemRandomNumberGenerator()
            var ok = true
            for _ in 0..<300 {
                let location = Int.random(in: 0...reference.utf16.count, using: &random)
                let maxLength = reference.utf16.count - location
                let length = Int.random(in: 0...min(5, maxLength), using: &random)
                let insert = String((0..<Int.random(in: 0...3, using: &random)).map { _ in
                    ["a", "b", "\n", "中"][Int.random(in: 0...3, using: &random)]
                })
                let ns = NSRange(location: location, length: length)
                let start = reference.utf16.index(reference.utf16.startIndex, offsetBy: location)
                let end = reference.utf16.index(start, offsetBy: length)
                reference.replaceSubrange(start..<end, with: insert)
                rope.replace(ns, with: insert)
                if rope.wholeText != reference { ok = false; break }
            }
            check("Rope 随机编辑一致性", ok)
        }

        // Piece table: bounded window editing and streaming save.
        do {
            let original = "alpha\nbeta\ngamma\ndelta\n"
            let sourceURL = write("piece-small.txt", Data(original.utf8))
            let document = try PieceTableDocument(url: sourceURL,
                                                  size: Int64(original.utf8.count),
                                                  encoding: .utf8, hasBOM: false,
                                                  lineEnding: .lf)
            let window = try document.window(aroundLine: 2, contextPieces: 1)
            check("PieceTable 窗口行号", window.startLine == 1 && window.targetLineOffset == 2,
                  "\(window.startLine)/\(window.targetLineOffset)")
            if let range = window.text.range(of: "beta") {
                let ns = NSRange(range, in: window.text)
                let edited = try document.applyEdit(in: window, range: ns, replacement: "BETA!")
                check("PieceTable 窗口编辑", edited)
            }
            let matches = (try? document.search(query: "beta", caseSensitive: false)) ?? []
            check("PieceTable 搜索行号", matches.first?.line == 2, matches.first.map { "\($0.line)" } ?? "nil")
            let narrowed = (try? document.search(query: "gamma", caseSensitive: true,
                                                  rangeStartLine: 1, rangeEndLine: 2)) ?? []
            check("PieceTable 限定行搜索", narrowed.isEmpty)
            let outputURL = sourceURL.deletingLastPathComponent().appendingPathComponent("piece-small-out.txt")
            try? document.save(to: outputURL)
            let saved = (try? String(contentsOf: outputURL, encoding: .utf8)) ?? ""
            check("PieceTable 流式保存", saved == "alpha\nBETA!\ngamma\ndelta\n", saved)

            // Edit a range spanning two file pieces.
            let repeated = String(repeating: "0123456789\n", count: 220_000)
            let bigURL = write("piece-big.txt", Data(repeated.utf8))
            let big = try PieceTableDocument(url: bigURL, size: Int64(repeated.utf8.count),
                                             encoding: .utf8, hasBOM: false, lineEnding: .lf)
            let bigWindow = try big.window(aroundLine: 80_000, contextPieces: 1)
            if bigWindow.segments.count >= 2 {
                let first = bigWindow.segments[0]
                let second = bigWindow.segments[1]
                let start = first.windowStart + max(0, first.windowLength - 6)
                let end = second.windowStart + 6
                let ns = NSRange(location: start, length: end - start)
                let crossed = try big.applyEdit(in: bigWindow, range: ns,
                                                replacement: "CROSS-PIECE")
                check("PieceTable 跨片段编辑", crossed,
                      "\(bigWindow.segments.count) pieces")
            }
            let bigOut = bigURL.deletingLastPathComponent().appendingPathComponent("piece-big-out.txt")
            try? big.save(to: bigOut)
            let bigSaved = (try? String(contentsOf: bigOut, encoding: .utf8)) ?? ""
            check("PieceTable 跨片段保存", bigSaved.contains("CROSS-PIECE"))

            let inPlaceURL = write("piece-inplace.txt", Data("one\ntwo\nthree\n".utf8))
            let inPlace = try PieceTableDocument(url: inPlaceURL, size: 14,
                                                 encoding: .utf8, hasBOM: false,
                                                 lineEnding: .lf)
            let inPlaceWindow = try inPlace.window(aroundLine: 2)
            if let range = inPlaceWindow.text.range(of: "two") {
                let ns = NSRange(range, in: inPlaceWindow.text)
                _ = try inPlace.applyEdit(in: inPlaceWindow, range: ns, replacement: "TWO")
            }
            try inPlace.save()
            let inPlaceText = (try? String(contentsOf: inPlaceURL, encoding: .utf8)) ?? ""
            check("PieceTable 原位保存", inPlaceText == "one\nTWO\nthree\n", inPlaceText)
        } catch {
            check("PieceTable 测试异常", false, error.localizedDescription)
        }

        // Paged reader + sparse line index (the >32 MB read-only path).
        let pagedText = (0..<80_000).map { "line-\($0) payload 0123456789\n" }.joined()
        if let pagedData = pagedText.data(using: .utf8) {
            let pagedURL = write("paged-reader.txt", pagedData)
            let reader = LargeFileReader(url: pagedURL, size: Int64(pagedData.count),
                                         encoding: .utf8, hasBOM: false, lineEnding: .lf)
            if let first = try? reader.readPage(offset: 0, startLine: 1) {
                check("分页读取第一页", !first.isEOF && first.text.hasPrefix("line-0"))
                check("第一页行号范围", first.startLine == 1 && first.endLine > 1)
                if let second = try? reader.readPage(offset: first.endOffset, startLine: first.nextLine) {
                    check("下一页行号衔接", second.startLine == first.endLine + 1,
                          "\(first.endLine) → \(second.startLine)")
                    if let previous = try? reader.readPageBefore(offset: second.startOffset,
                                                                 startLine: second.startLine) {
                        check("上一页上下文读取", previous.endOffset == second.startOffset
                              && previous.endLine == second.startLine - 1)
                    }
                    if let limited = try? reader.readPage(offset: first.endOffset,
                                                          startLine: first.nextLine,
                                                          maxEndOffset: first.endOffset + 1000) {
                        check("限定范围分页读取", limited.endOffset <= first.endOffset + 1000)
                    }
                }
            }
            if let index = try? reader.buildIndex() {
                check("行索引总数", index.totalLines == 80_001, "\(index.totalLines)")
                if let offset = try? index.offset(forLine: 40_000, reader: reader) {
                    let page = try? reader.readPage(offset: offset, startLine: 40_000)
                    check("按行索引跳页", page?.text.hasPrefix("line-39999") == true,
                          String((page?.text ?? "").prefix(30)))
                }
            }
        }

        print("\n结果：\(passes) 通过，\(failures) 失败")
        exit(failures == 0 ? 0 : 1)
    }
}
