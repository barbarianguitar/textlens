import Foundation
import AppKit
import SwiftUI

// MARK: - Page model

struct LargeFilePage: Identifiable, Sendable {
    let id = UUID()
    let startOffset: Int64
    let endOffset: Int64
    let startLine: Int
    let endLine: Int
    let nextLine: Int
    let text: String
    let isEOF: Bool
    let cutMidLine: Bool
}

struct LargeFileSearchResult: Identifiable, Sendable {
    let id = UUID()
    let line: Int
    let column: Int
    let preview: String
    let pageOffset: Int64
    let pageStartLine: Int
    let matchLength: Int
}

struct LargeFileLineAnchor: Sendable {
    let line: Int
    let offset: Int64
}

struct LargeFileLineIndex: Sendable {
    let totalLines: Int
    let anchors: [LargeFileLineAnchor]
    let separator: LineSeparator
    let anchorInterval = 1024

    func offset(forLine target: Int, reader: LargeFileReader) throws -> Int64? {
        guard target >= 1, target <= totalLines else { return nil }
        if target == 1 { return 0 }
        guard let anchor = anchors.last(where: { $0.line <= target }) else { return nil }
        let handle = try FileHandle(forReadingFrom: reader.url)
        defer { try? handle.close() }

        var line = anchor.line
        var offset = anchor.offset
        var lineStart = anchor.offset
        let chunkSize = 1_048_576
        while offset < reader.size {
            try Task.checkCancellation()
            try handle.seek(toOffset: UInt64(offset))
            let remaining = reader.size - offset
            let raw = try handle.read(upToCount: Int(min(Int64(chunkSize + 8), remaining))) ?? Data()
            if raw.isEmpty { break }
            let bytes = [UInt8](raw)
            let limit = min(chunkSize, bytes.count)
            var index = 0
            while index + separator.bytes.count <= bytes.count {
                if index < limit, separator.matches(bytes, at: index) {
                    line += 1
                    lineStart = offset + Int64(index + separator.bytes.count)
                    if line == target { return lineStart }
                }
                index += separator.unit
            }
            offset += Int64(limit)
            if raw.count < limit { break }
        }
        return nil
    }
}

// MARK: - Separators

struct LineSeparator: Sendable {
    let bytes: [UInt8]
    let unit: Int

    init(encoding: TextEncoding, lineEnding: LineEnding) {
        let lf: [UInt8]
        let cr: [UInt8]
        let unit: Int
        switch encoding {
        case .utf16LE:
            lf = [0x0A, 0x00]; cr = [0x0D, 0x00]; unit = 2
        case .utf16BE:
            lf = [0x00, 0x0A]; cr = [0x00, 0x0D]; unit = 2
        case .utf32LE:
            lf = [0x0A, 0x00, 0x00, 0x00]; cr = [0x0D, 0x00, 0x00, 0x00]; unit = 4
        case .utf32BE:
            lf = [0x00, 0x00, 0x00, 0x0A]; cr = [0x00, 0x00, 0x00, 0x0D]; unit = 4
        default:
            lf = [0x0A]; cr = [0x0D]; unit = 1
        }
        self.bytes = lineEnding == .cr ? cr : lf
        self.unit = unit
    }

    func matches(_ bytes: [UInt8], at index: Int) -> Bool {
        guard index >= 0, index + self.bytes.count <= bytes.count else { return false }
        for offset in 0..<self.bytes.count where bytes[index + offset] != self.bytes[offset] {
            return false
        }
        return true
    }

    func firstEnd(in bytes: [UInt8], limit: Int) -> Int? {
        let upper = min(limit, bytes.count)
        guard upper >= self.bytes.count else { return nil }
        var index = 0
        while index + self.bytes.count <= upper {
            if matches(bytes, at: index) { return index + self.bytes.count }
            index += unit
        }
        return nil
    }

    func lastEnd(in bytes: [UInt8], limit: Int) -> Int? {
        let upper = min(limit, bytes.count)
        guard upper >= self.bytes.count else { return nil }
        var index = 0
        var result: Int?
        while index + self.bytes.count <= upper {
            if matches(bytes, at: index) {
                result = index + self.bytes.count
            }
            index += unit
        }
        return result
    }
}

// MARK: - Reader

struct LargeFileReader: Sendable {
    let url: URL
    let size: Int64
    let encoding: TextEncoding
    let hasBOM: Bool
    let lineEnding: LineEnding
    static let pageByteLimit = 2_000_000

    var separator: LineSeparator {
        LineSeparator(encoding: encoding, lineEnding: lineEnding)
    }

    func readPage(offset: Int64, startLine: Int,
                  maxEndOffset: Int64? = nil) throws -> LargeFilePage {
        guard offset >= 0 else { throw FileLoaderError.unreadable("无效的读取位置") }
        let effectiveEnd = min(size, maxEndOffset ?? size)
        guard offset < effectiveEnd else {
            return LargeFilePage(startOffset: effectiveEnd, endOffset: effectiveEnd,
                                 startLine: startLine, endLine: startLine, nextLine: startLine,
                                 text: "", isEOF: true, cutMidLine: false)
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))
        let request = Int(min(Int64(Self.pageByteLimit + 8), effectiveEnd - offset))
        let raw = try handle.read(upToCount: request) ?? Data()
        guard !raw.isEmpty else {
            return LargeFilePage(startOffset: offset, endOffset: offset, startLine: startLine,
                                 endLine: startLine, nextLine: startLine, text: "",
                                 isEOF: true, cutMidLine: false)
        }

        let bytes = [UInt8](raw)
        let eof = offset + Int64(raw.count) >= effectiveEnd
        let scanLimit = min(Self.pageByteLimit, bytes.count)
        var cut = eof ? bytes.count : scanLimit
        if !eof, let separatorEnd = separator.lastEnd(in: bytes, limit: scanLimit) {
            cut = separatorEnd
        }
        cut = max(1, min(cut, bytes.count))

        let pageData = Data(bytes[0..<cut])
        let outcome = TextDecoder.decodeLenient(pageData, encoding: encoding, truncated: true)
        var text = normalizeNewlines(outcome.text)
        let endsWithNewline = text.hasSuffix("\n")
        let newlineCount = text.reduce(into: 0) { count, character in
            if character == "\n" { count += 1 }
        }
        let cutMidLine = !eof && !endsWithNewline
        let lines = text.isEmpty ? 0 : newlineCount + (endsWithNewline ? 0 : 1)
        let endLine = startLine + max(0, lines - 1)
        let nextLine = cutMidLine ? max(startLine, endLine) : startLine + lines

        if !eof, endsWithNewline, !text.isEmpty {
            text.removeLast()
        }

        return LargeFilePage(
            startOffset: offset,
            endOffset: offset + Int64(cut),
            startLine: startLine,
            endLine: endLine,
            nextLine: nextLine,
            text: text,
            isEOF: eof,
            cutMidLine: cutMidLine
        )
    }

    /// Read a context page that ends exactly at `offset` (the start of the
    /// current page). The first partial line is dropped, and absolute line
    /// numbers are derived from the current page's first line.
    func readPageBefore(offset: Int64, startLine: Int) throws -> LargeFilePage? {
        guard offset > 0, startLine > 1 else { return nil }
        let window = Int64(Self.pageByteLimit)
        let start = max(0, offset - window)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(start))
        let request = Int(offset - start)
        guard request > 0 else { return nil }
        let raw = try handle.read(upToCount: request) ?? Data()
        guard !raw.isEmpty else { return nil }
        let bytes = [UInt8](raw)
        var cutStart = 0
        if start > 0 {
            guard let firstEnd = separator.firstEnd(in: bytes, limit: bytes.count) else { return nil }
            cutStart = firstEnd
        }
        guard cutStart < bytes.count else { return nil }
        let contextData = Data(bytes[cutStart..<bytes.count])
        let outcome = TextDecoder.decodeLenient(contextData, encoding: encoding, truncated: true)
        var text = normalizeNewlines(outcome.text)
        let endsWithNewline = text.hasSuffix("\n")
        let newlineCount = text.reduce(into: 0) { count, character in
            if character == "\n" { count += 1 }
        }
        let lines = newlineCount + (endsWithNewline ? 0 : 1)
        guard lines > 0 else { return nil }
        if endsWithNewline, !text.isEmpty { text.removeLast() }
        let previousStartLine = startLine - lines
        guard previousStartLine >= 1 else { return nil }
        return LargeFilePage(
            startOffset: start + Int64(cutStart),
            endOffset: offset,
            startLine: previousStartLine,
            endLine: startLine - 1,
            nextLine: startLine,
            text: text,
            isEOF: false,
            cutMidLine: false
        )
    }

    func buildIndex() throws -> LargeFileLineIndex {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let separator = self.separator
        let chunkSize = 4 * 1024 * 1024
        var offset: Int64 = 0
        var line = 1
        var anchors = [LargeFileLineAnchor(line: 1, offset: 0)]

        while offset < size {
            try Task.checkCancellation()
            try handle.seek(toOffset: UInt64(offset))
            let raw = try handle.read(upToCount: Int(min(Int64(chunkSize + 8), size - offset))) ?? Data()
            if raw.isEmpty { break }
            let bytes = [UInt8](raw)
            let processed = min(chunkSize, bytes.count)
            var index = 0
            while index + separator.bytes.count <= bytes.count {
                if index < processed, separator.matches(bytes, at: index) {
                    line += 1
                    let lineStart = offset + Int64(index + separator.bytes.count)
                    if (line - 1) % 1024 == 0 {
                        anchors.append(LargeFileLineAnchor(line: line, offset: lineStart))
                    }
                }
                index += separator.unit
            }
            offset += Int64(processed)
            if bytes.count < processed + 1 { break }
        }
        return LargeFileLineIndex(totalLines: line, anchors: anchors, separator: separator)
    }

    private func normalizeNewlines(_ string: String) -> String {
        guard string.contains("\r") else { return string }
        return string
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}

enum LargeFileSearchScope: String, CaseIterable, Identifiable {
    case wholeFile
    case currentWindow
    case customLines

    var id: String { rawValue }

    var label: String {
        switch self {
        case .wholeFile: return "整个文件"
        case .currentWindow: return "当前窗口"
        case .customLines: return "指定行范围"
        }
    }

    var shortLabel: String {
        switch self {
        case .wholeFile: return "全文"
        case .currentWindow: return "窗口"
        case .customLines: return "行范围"
        }
    }
}

// MARK: - Session

@MainActor
final class LargeFileSession: ObservableObject {
    let reader: LargeFileReader
    let fileName: String

    @Published private(set) var page: LargeFilePage?
    @Published private(set) var isLoadingPage = false
    @Published private(set) var pageError: String?
    @Published private(set) var isSearching = false
    @Published private(set) var searchProgress = 0.0
    @Published private(set) var searchResults: [LargeFileSearchResult] = []
    @Published private(set) var searchLimitReached = false
    @Published private(set) var isIndexing = false
    @Published private(set) var indexProgress = 0.0
    @Published private(set) var totalLines: Int?
    @Published private(set) var indexError: String?
    @Published private(set) var activeSearchScopeLabel = "整个文件"
    @Published private(set) var scrollToBottomOnPageChange = false
    @Published var highlight: LargeFileSearchResult?

    private var cachedPrevious: LargeFilePage?
    private var cachedNext: LargeFilePage?
    private var index: LargeFileLineIndex?
    private var indexTask: Task<LargeFileLineIndex, Error>?
    private var searchTask: Task<Void, Never>?
    private var loadGeneration = UUID()
    private let maxSearchResults = 1000

    init(url: URL, size: Int64, encoding: TextEncoding, hasBOM: Bool,
         lineEnding: LineEnding) {
        self.fileName = url.lastPathComponent
        self.reader = LargeFileReader(url: url, size: size, encoding: encoding,
                                      hasBOM: hasBOM, lineEnding: lineEnding)
    }

    deinit {
        indexTask?.cancel()
        searchTask?.cancel()
    }

    var canGoBack: Bool { page.map { $0.startOffset > 0 } ?? false }
    var canGoForward: Bool { page.map { !$0.isEOF } ?? false }
    var encodingLabel: String { reader.encoding.label }

    func loadFirstPageIfNeeded() async {
        guard page == nil, !isLoadingPage else { return }
        scrollToBottomOnPageChange = false
        await loadPage(at: 0, startLine: 1, highlight: nil)
    }

    func nextPage() {
        guard let page, !page.isEOF else { return }
        scrollToBottomOnPageChange = false
        if let cachedNext, cachedNext.startOffset == page.endOffset {
            show(cachedNext, highlight: nil)
            return
        }
        Task {
            await loadPage(at: page.endOffset, startLine: page.nextLine, highlight: nil)
        }
    }

    func previousPage() {
        guard let page, page.startOffset > 0 else { return }
        scrollToBottomOnPageChange = true
        if let cachedPrevious {
            show(cachedPrevious, highlight: nil)
            return
        }
        Task {
            do {
                let reader = self.reader
                let previous = try await Task.detached(priority: .userInitiated) {
                    try reader.readPageBefore(offset: page.startOffset, startLine: page.startLine)
                }.value
                guard let previous else { return }
                show(previous, highlight: nil)
            } catch {
                pageError = error.localizedDescription
            }
        }
    }

    func jump(to result: LargeFileSearchResult) {
        scrollToBottomOnPageChange = false
        if let page, page.startOffset == result.pageOffset {
            highlight = result
            return
        }
        Task {
            await loadPage(at: result.pageOffset, startLine: result.pageStartLine,
                           highlight: result)
        }
    }

    func jump(toLine line: Int) {
        guard line > 0 else { return }
        Task {
            await ensureIndex()
            guard let index else { return }
            do {
                let reader = self.reader
                let offset = try await Task.detached(priority: .userInitiated) {
                    try index.offset(forLine: line, reader: reader)
                }.value
                guard let offset else { return }
                let result = LargeFileSearchResult(line: line, column: 1, preview: "",
                                                   pageOffset: offset, pageStartLine: line,
                                                   matchLength: 0)
                scrollToBottomOnPageChange = false
                await loadPage(at: offset, startLine: line, highlight: result)
            } catch {
                pageError = error.localizedDescription
            }
        }
    }

    func ensureIndex() async {
        if index != nil { return }
        if let task = indexTask {
            _ = try? await task.value
            return
        }
        isIndexing = true
        indexProgress = 0
        indexError = nil
        let reader = self.reader
        let task = Task.detached(priority: .utility) {
            try reader.buildIndex()
        }
        indexTask = task
        do {
            let built = try await task.value
            index = built
            totalLines = built.totalLines
            indexProgress = 1
        } catch is CancellationError {
            indexError = "行索引已取消"
        } catch {
            indexError = "建立行索引失败：\(error.localizedDescription)"
        }
        isIndexing = false
    }

    // MARK: Paging

    private func loadPage(at offset: Int64, startLine: Int,
                          highlight: LargeFileSearchResult?) async {
        scrollToBottomOnPageChange = false
        let generation = UUID()
        loadGeneration = generation
        isLoadingPage = true
        pageError = nil
        do {
            let reader = self.reader
            let loaded = try await Task.detached(priority: .userInitiated) {
                try reader.readPage(offset: offset, startLine: startLine)
            }.value
            guard generation == loadGeneration else { return }
            show(loaded, highlight: highlight)
            isLoadingPage = false
        } catch {
            guard generation == loadGeneration else { return }
            isLoadingPage = false
            pageError = error.localizedDescription
        }
    }

    private func show(_ loaded: LargeFilePage, highlight: LargeFileSearchResult?) {
        page = loaded
        self.highlight = highlight
        cachedPrevious = nil
        cachedNext = nil
        prefetchContext(around: loaded)
    }

    /// Keep one page of context on each side. This makes Page Up/Down instant
    /// and gives the scroll-edge auto-advance a cached next page.
    private func prefetchContext(around page: LargeFilePage) {
        let reader = self.reader
        Task { [weak self] in
            async let nextTask: LargeFilePage? = {
                guard !page.isEOF else { return nil }
                return try? await Task.detached(priority: .utility) {
                    try reader.readPage(offset: page.endOffset, startLine: page.nextLine)
                }.value
            }()
            async let previousTask: LargeFilePage? = {
                guard page.startOffset > 0 else { return nil }
                return try? await Task.detached(priority: .utility) {
                    try reader.readPageBefore(offset: page.startOffset,
                                              startLine: page.startLine)
                }.value
            }()
            let next = await nextTask
            guard let self, self.page?.id == page.id else { return }
            self.cachedNext = next
            let previous = await previousTask
            guard self.page?.id == page.id else { return }
            self.cachedPrevious = previous
        }
    }

    // MARK: Search

    func search(query: String, caseSensitive: Bool,
                scope: LargeFileSearchScope = .wholeFile,
                customStartLine: Int? = nil,
                customEndLine: Int? = nil) {
        searchTask?.cancel()
        searchResults = []
        searchLimitReached = false
        searchProgress = 0
        activeSearchScopeLabel = scope.label
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            isSearching = false
            return
        }
        isSearching = true
        let reader = self.reader
        let limit = maxSearchResults

        searchTask = Task { [weak self] in
            guard let self else { return }
            do {
                var rangeStart: Int64 = 0
                var rangeEnd: Int64 = reader.size
                var rangeLine = 1
                switch scope {
                case .wholeFile:
                    activeSearchScopeLabel = "整个文件"
                case .currentWindow:
                    if let page = self.page {
                        rangeStart = page.startOffset
                        rangeLine = page.startLine
                        rangeEnd = page.endOffset
                        if let previous = self.cachedPrevious {
                            rangeStart = previous.startOffset
                            rangeLine = previous.startLine
                        }
                        if let next = self.cachedNext {
                            rangeEnd = next.endOffset
                        }
                    }
                    activeSearchScopeLabel = "当前窗口"
                case .customLines:
                    let startLine = max(1, customStartLine ?? 1)
                    let endLine = max(startLine, customEndLine ?? (customStartLine ?? 1))
                    activeSearchScopeLabel = "第 \(startLine)–\(endLine) 行"
                    await ensureIndex()
                    try Task.checkCancellation()
                    guard let index else {
                        isSearching = false
                        return
                    }
                    guard let startOffset = try await Task.detached(priority: .userInitiated, operation: {
                        try index.offset(forLine: startLine, reader: reader)
                    }).value else {
                        isSearching = false
                        return
                    }
                    let endOffset: Int64
                    if let nextOffset = try await Task.detached(priority: .userInitiated, operation: {
                        try index.offset(forLine: endLine + 1, reader: reader)
                    }).value {
                        endOffset = nextOffset
                    } else {
                        endOffset = reader.size
                    }
                    rangeStart = startOffset
                    rangeEnd = max(startOffset, endOffset)
                    rangeLine = startLine
                }

                let rangeLength = max(1, rangeEnd - rangeStart)
                var offset = rangeStart
                var startLine = rangeLine
                while offset < rangeEnd {
                    try Task.checkCancellation()
                    let chunk = try await Task.detached(priority: .userInitiated) {
                        let page = try reader.readPage(offset: offset, startLine: startLine,
                                                       maxEndOffset: rangeEnd)
                        let matches = Self.findMatches(in: page, query: trimmed,
                                                       caseSensitive: caseSensitive,
                                                       limit: limit)
                        return (page, matches)
                    }.value
                    if !chunk.1.isEmpty {
                        searchResults.append(contentsOf: chunk.1)
                    }
                    if searchResults.count >= limit {
                        searchLimitReached = true
                        break
                    }
                    if chunk.0.endOffset <= offset { break }
                    offset = chunk.0.endOffset
                    startLine = chunk.0.nextLine
                    searchProgress = Double(offset - rangeStart) / Double(rangeLength)
                }
                searchProgress = 1
            } catch is CancellationError {
                // Cancelled by the user or by a new search.
            } catch {
                pageError = "搜索失败：\(error.localizedDescription)"
            }
            self.isSearching = false
        }
    }

    func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
    }

    func cancelAll() {
        cancelSearch()
        indexTask?.cancel()
        indexTask = nil
        isIndexing = false
    }

    func clearSearch() {
        cancelSearch()
        searchResults = []
        searchLimitReached = false
        searchProgress = 0
        activeSearchScopeLabel = "整个文件"
        highlight = nil
    }

    nonisolated private static func findMatches(in page: LargeFilePage, query: String,
                                                caseSensitive: Bool,
                                                limit: Int) -> [LargeFileSearchResult] {
        guard !page.text.isEmpty, !query.isEmpty else { return [] }
        let text = page.text as NSString
        let lineStarts = Self.lineStarts(in: text)
        var results: [LargeFileSearchResult] = []
        var searchRange = NSRange(location: 0, length: text.length)
        let options: NSString.CompareOptions = caseSensitive ? [] : [.caseInsensitive]

        while searchRange.length > 0 {
            let found = text.range(of: query, options: options, range: searchRange)
            if found.location == NSNotFound { break }
            if found.length == 0 { break }
            let lineIndex = Self.lineIndex(for: found.location, starts: lineStarts)
            let lineStart = lineStarts[lineIndex]
            let lineEnd = lineIndex + 1 < lineStarts.count
                ? lineStarts[lineIndex + 1] - 1
                : text.length
            let lineText = text.substring(with: NSRange(location: lineStart,
                                                        length: max(0, lineEnd - lineStart)))
            results.append(LargeFileSearchResult(
                line: page.startLine + lineIndex,
                column: found.location - lineStart + 1,
                preview: String(lineText.prefix(220)),
                pageOffset: page.startOffset,
                pageStartLine: page.startLine,
                matchLength: found.length
            ))
            if results.count >= limit { break }
            let next = NSMaxRange(found)
            guard next > searchRange.location else { break }
            searchRange = NSRange(location: next, length: text.length - next)
        }
        return results
    }

    nonisolated private static func lineStarts(in text: NSString) -> [Int] {
        var starts = [0]
        var index = 0
        while index < text.length {
            let range = text.range(of: "\n", options: [],
                                   range: NSRange(location: index, length: text.length - index))
            if range.location == NSNotFound { break }
            starts.append(range.location + 1)
            index = range.location + 1
        }
        return starts
    }

    nonisolated private static func lineIndex(for location: Int, starts: [Int]) -> Int {
        var low = 0
        var high = starts.count - 1
        while low <= high {
            let mid = (low + high) / 2
            if starts[mid] <= location { low = mid + 1 } else { high = mid - 1 }
        }
        return max(0, high)
    }
}
