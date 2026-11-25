import Foundation

/// A bounded-memory, editable document backed by a piece table.
///
/// The original file is cut into line-aligned pieces (about 1 MB each). A piece
/// is either a raw byte range from the file or in-memory edited text. A viewer
/// renders a small window of pieces; edits split only the pieces they touch.
/// Saving streams raw pieces and encoded edited pieces to a temporary file.
final class PieceTableDocument {
    struct Piece: Sendable {
        let id: UUID
        var source: Source
        var text: String?
        var newlineCount: Int?

        enum Source: Sendable {
            case file(offset: Int64, length: Int)
            case text(String)
        }
    }

    struct Segment: Sendable {
        let pieceID: UUID
        let windowStart: Int
        let windowLength: Int
        let localStart: Int
        let localLength: Int
    }

    struct Window: Sendable {
        let id = UUID()
        let text: String
        let startLine: Int
        let endLine: Int
        let targetLineOffset: Int
        let segments: [Segment]
        let startPieceIndex: Int
        let endPieceIndex: Int
    }

    let url: URL
    let size: Int64
    let encoding: TextEncoding
    let hasBOM: Bool
    let lineEnding: LineEnding
    let contentStart: Int64

    private(set) var pieces: [Piece]
    private let separator: LineSeparator
    private let chunkSize = 256 * 1024

    init(url: URL, size: Int64, encoding: TextEncoding,
         hasBOM: Bool, lineEnding: LineEnding) throws {
        self.url = url
        self.size = size
        self.encoding = encoding
        self.hasBOM = hasBOM
        self.lineEnding = lineEnding
        self.separator = LineSeparator(encoding: encoding, lineEnding: lineEnding)
        let bomLength: Int64
        if hasBOM {
            switch encoding {
            case .utf8: bomLength = 3
            case .utf16LE, .utf16BE: bomLength = 2
            case .utf32LE, .utf32BE: bomLength = 4
            default: bomLength = 0
            }
        } else {
            bomLength = 0
        }
        self.contentStart = min(max(0, bomLength), size)
        self.pieces = []
        try buildPieces()
    }

    // MARK: - Building

    private func buildPieces() throws {
        guard size > contentStart else { return }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var offset = contentStart
        while offset < size {
            try handle.seek(toOffset: UInt64(offset))
            let request = Int(min(Int64(chunkSize + 8), size - offset))
            let raw = try handle.read(upToCount: request) ?? Data()
            if raw.isEmpty { break }
            let bytes = [UInt8](raw)
            let isEOF = offset + Int64(bytes.count) >= size
            let limit = isEOF ? bytes.count : min(chunkSize, bytes.count)
            var index = 0
            var newlines = 0
            var lastSeparatorEnd: Int?
            while index + separator.bytes.count <= limit {
                if separator.matches(bytes, at: index) {
                    newlines += 1
                    lastSeparatorEnd = index + separator.bytes.count
                }
                index += separator.unit
            }
            let cut = isEOF ? bytes.count : (lastSeparatorEnd ?? limit)
            guard cut > 0 else { break }
            pieces.append(Piece(id: UUID(), source: .file(offset: offset, length: cut),
                                text: nil, newlineCount: newlines))
            offset += Int64(cut)
        }
    }

    // MARK: - Piece text and line metadata

    func text(forPieceAt index: Int, cache: Bool = true) throws -> String {
        guard pieces.indices.contains(index) else { return "" }
        if let text = pieces[index].text { return text }
        guard case let .file(offset, length) = pieces[index].source else { return "" }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))
        let data = try handle.read(upToCount: length) ?? Data()
        let outcome = TextDecoder.decodeLenient(data, encoding: encoding, truncated: true)
        let text = normalize(outcome.text)
        if cache {
            pieces[index].text = text
        }
        pieces[index].newlineCount = text.reduce(into: 0) { count, ch in
            if ch == "\n" { count += 1 }
        }
        return text
    }

    func newlineCount(forPieceAt index: Int) throws -> Int {
        guard pieces.indices.contains(index) else { return 0 }
        if let count = pieces[index].newlineCount { return count }
        switch pieces[index].source {
        case .text(let text):
            let count = text.reduce(into: 0) { count, ch in
                if ch == "\n" { count += 1 }
            }
            pieces[index].newlineCount = count
            return count
        case .file(let offset, let length):
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            try handle.seek(toOffset: UInt64(offset))
            let data = try handle.read(upToCount: length) ?? Data()
            let bytes = [UInt8](data)
            var count = 0
            var indexByte = 0
            while indexByte + separator.bytes.count <= bytes.count {
                if separator.matches(bytes, at: indexByte) { count += 1 }
                indexByte += separator.unit
            }
            pieces[index].newlineCount = count
            return count
        }
    }

    var totalLines: Int {
        var newlines = 0
        for index in pieces.indices {
            newlines += (try? newlineCount(forPieceAt: index)) ?? 0
        }
        return newlines + 1
    }

    func startLine(forPieceAt index: Int) -> Int {
        var newlines = 0
        for i in 0..<max(0, min(index, pieces.count)) {
            newlines += (try? newlineCount(forPieceAt: i)) ?? 0
        }
        return newlines + 1
    }

    private func locate(line: Int) throws -> (piece: Int, localLine: Int) {
        guard line >= 1 else { return (0, 1) }
        var before = 0
        for index in pieces.indices {
            let count = try newlineCount(forPieceAt: index)
            let start = before + 1
            let nextStart = before + count + 1
            if line < nextStart || index == pieces.count - 1 {
                return (index, max(1, line - start + 1))
            }
            before += count
        }
        return (max(0, pieces.count - 1), 1)
    }

    // MARK: - Window rendering

    func window(aroundLine targetLine: Int, contextPieces: Int = 1) throws -> Window {
        guard !pieces.isEmpty else {
            return Window(text: "", startLine: 1, endLine: 1, targetLineOffset: 1,
                          segments: [], startPieceIndex: 0, endPieceIndex: 0)
        }
        let location = try locate(line: targetLine)
        let startIndex = max(0, location.piece - contextPieces)
        let endIndex = min(pieces.count - 1, location.piece + contextPieces)
        return try buildWindow(startIndex: startIndex, endIndex: endIndex, targetLine: targetLine)
    }

    func window(startingAtLine targetLine: Int, contextPieces: Int = 4) throws -> Window {
        guard !pieces.isEmpty else {
            return Window(text: "", startLine: 1, endLine: 1, targetLineOffset: 1,
                          segments: [], startPieceIndex: 0, endPieceIndex: 0)
        }
        let location = try locate(line: targetLine)
        let startIndex = max(0, min(location.piece, pieces.count - 1))
        let endIndex = min(pieces.count - 1, startIndex + contextPieces)
        return try buildWindow(startIndex: startIndex, endIndex: endIndex, targetLine: targetLine)
    }

    func window(endingAtLine targetLine: Int, contextPieces: Int = 4) throws -> Window {
        guard !pieces.isEmpty else {
            return Window(text: "", startLine: 1, endLine: 1, targetLineOffset: 1,
                          segments: [], startPieceIndex: 0, endPieceIndex: 0)
        }
        let location = try locate(line: targetLine)
        let endIndex = max(0, min(location.piece, pieces.count - 1))
        let startIndex = max(0, endIndex - contextPieces)
        return try buildWindow(startIndex: startIndex, endIndex: endIndex, targetLine: targetLine)
    }

    /// Extend an existing window forward without changing its anchor. The new
    /// text is a strict prefix-extension, which lets the viewer append to its
    /// NSTextView instead of replacing and re-scrolling the whole buffer.
    func extendedWindow(_ window: Window, forwardPieces: Int) throws -> Window? {
        guard !pieces.isEmpty,
              window.endPieceIndex + 1 < pieces.count else { return nil }
        let newEnd = min(pieces.count - 1, window.endPieceIndex + max(1, forwardPieces))
        guard newEnd > window.endPieceIndex else { return nil }
        var windowText = window.text
        var segments = window.segments
        for index in (window.endPieceIndex + 1)...newEnd {
            let pieceText = try text(forPieceAt: index)
            segments.append(Segment(pieceID: pieces[index].id,
                                    windowStart: windowText.utf16.count,
                                    windowLength: pieceText.utf16.count,
                                    localStart: 0,
                                    localLength: pieceText.utf16.count))
            windowText += pieceText
        }
        let endLine = window.startLine + windowText.reduce(into: 0) { count, ch in
            if ch == "\n" { count += 1 }
        }
        return Window(text: windowText, startLine: window.startLine, endLine: endLine,
                      targetLineOffset: window.targetLineOffset, segments: segments,
                      startPieceIndex: window.startPieceIndex, endPieceIndex: newEnd)
    }

    /// Prepend pieces before an existing window. The old text remains a
    /// suffix, so the viewer can insert the prefix without replacing the buffer.
    func prependedWindow(_ window: Window, backwardPieces: Int) throws -> Window? {
        guard !pieces.isEmpty, window.startPieceIndex > 0 else { return nil }
        let newStart = max(0, window.startPieceIndex - max(1, backwardPieces))
        guard newStart < window.startPieceIndex else { return nil }
        var prefix = ""
        var prefixSegments: [Segment] = []
        for index in newStart..<window.startPieceIndex {
            let pieceText = try text(forPieceAt: index)
            prefixSegments.append(Segment(pieceID: pieces[index].id,
                                          windowStart: prefix.utf16.count,
                                          windowLength: pieceText.utf16.count,
                                          localStart: 0,
                                          localLength: pieceText.utf16.count))
            prefix += pieceText
        }
        let startLine = startLine(forPieceAt: newStart)
        let shiftedSegments = window.segments.map {
            Segment(pieceID: $0.pieceID,
                    windowStart: $0.windowStart + prefix.utf16.count,
                    windowLength: $0.windowLength,
                    localStart: $0.localStart,
                    localLength: $0.localLength)
        }
        let text = prefix + window.text
        let endLine = startLine + text.reduce(into: 0) { count, ch in
            if ch == "\n" { count += 1 }
        }
        let targetAbsolute = window.startLine + window.targetLineOffset - 1
        return Window(text: text, startLine: startLine, endLine: endLine,
                      targetLineOffset: max(1, targetAbsolute - startLine + 1),
                      segments: prefixSegments + shiftedSegments,
                      startPieceIndex: newStart, endPieceIndex: window.endPieceIndex)
    }

    private func buildWindow(startIndex: Int, endIndex: Int, targetLine: Int) throws -> Window {
        let startLine = startLine(forPieceAt: startIndex)
        var segments: [Segment] = []
        var windowText = ""
        for index in startIndex...endIndex {
            let pieceText = try text(forPieceAt: index)
            segments.append(Segment(pieceID: pieces[index].id,
                                    windowStart: windowText.utf16.count,
                                    windowLength: pieceText.utf16.count,
                                    localStart: 0,
                                    localLength: pieceText.utf16.count))
            windowText += pieceText
        }
        let endLine = startLine + windowText.reduce(into: 0) { count, ch in
            if ch == "\n" { count += 1 }
        }
        return Window(text: windowText, startLine: startLine, endLine: endLine,
                      targetLineOffset: max(1, targetLine - startLine + 1),
                      segments: segments, startPieceIndex: startIndex, endPieceIndex: endIndex)
    }

    /// Apply an edit expressed in the rendered window's UTF-16 coordinates.
    @discardableResult
    func applyEdit(in window: Window, range: NSRange, replacement: String) throws -> Bool {
        guard range.location >= 0, range.length >= 0,
              range.location + range.length <= window.text.utf16.count else { return false }
        let start = try windowPosition(in: window, at: range.location, preferNext: true)
        let end = try windowPosition(in: window, at: range.location + range.length, preferNext: false)
        let startIndex = start.piece
        let endIndex = end.piece
        guard startIndex <= endIndex, pieces.indices.contains(startIndex),
              pieces.indices.contains(endIndex) else { return false }
        let startText = try text(forPieceAt: startIndex)
        let endText = try text(forPieceAt: endIndex)
        let startOffset = max(0, min(start.local, startText.utf16.count))
        let endOffset = max(0, min(end.local, endText.utf16.count))
        let prefix = Self.prefix(startText, utf16Length: startOffset)
        let suffix = Self.suffix(endText, fromUTF16: endOffset)

        var replacements: [Piece] = []
        if !prefix.isEmpty {
            replacements.append(Piece(id: UUID(), source: .text(prefix), text: prefix,
                                      newlineCount: prefix.reduce(into: 0) { c, ch in
                                          if ch == "\n" { c += 1 }
                                      }))
        }
        if !replacement.isEmpty {
            replacements.append(Piece(id: UUID(), source: .text(replacement), text: replacement,
                                      newlineCount: replacement.reduce(into: 0) { c, ch in
                                          if ch == "\n" { c += 1 }
                                      }))
        }
        if !suffix.isEmpty {
            replacements.append(Piece(id: UUID(), source: .text(suffix), text: suffix,
                                      newlineCount: suffix.reduce(into: 0) { c, ch in
                                          if ch == "\n" { c += 1 }
                                      }))
        }
        pieces.replaceSubrange(startIndex...endIndex, with: replacements)
        return true
    }

    private func windowPosition(in window: Window, at offset: Int,
                                preferNext: Bool) throws -> (piece: Int, local: Int) {
        guard !window.segments.isEmpty else { return (0, 0) }
        for segment in window.segments {
            let end = segment.windowStart + segment.windowLength
            if offset < end || (preferNext == false && offset == end) {
                let local = min(segment.windowLength, max(0, offset - segment.windowStart))
                guard let index = pieces.firstIndex(where: { $0.id == segment.pieceID }) else {
                    return (0, local)
                }
                return (index, local)
            }
        }
        if let last = window.segments.last,
           let index = pieces.firstIndex(where: { $0.id == last.pieceID }) {
            return (index, last.windowLength)
        }
        return (0, 0)
    }

    // MARK: - Search

    struct SearchMatch: Sendable {
        let line: Int
        let column: Int
        let preview: String
        let length: Int
    }

    func search(query: String, caseSensitive: Bool,
                rangeStartLine: Int = 1, rangeEndLine: Int? = nil,
                limit: Int = 1000) throws -> [SearchMatch] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !pieces.isEmpty else { return [] }
        let lower = max(1, rangeStartLine)
        let upper = max(lower, min(rangeEndLine ?? Int.max, totalLines))
        let startLocation = try locate(line: lower)
        var results: [SearchMatch] = []
        let options: NSString.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        var piece = startLocation.piece
        while piece < pieces.count, results.count < limit {
            let pieceStart = startLine(forPieceAt: piece)
            if pieceStart > upper { break }
            let text = try text(forPieceAt: piece, cache: false)
            let ns = text as NSString
            var searchRange = NSRange(location: 0, length: ns.length)
            while searchRange.length > 0 {
                let found = ns.range(of: trimmed, options: options, range: searchRange)
                if found.location == NSNotFound { break }
                let prefix = ns.substring(to: found.location)
                let lineOffset = prefix.reduce(into: 0) { count, ch in
                    if ch == "\n" { count += 1 }
                }
                let line = pieceStart + lineOffset
                if line > upper { break }
                if line >= lower {
                    let lastNewline = (prefix as NSString).range(of: "\n", options: .backwards)
                    let column = lastNewline.location == NSNotFound
                        ? found.location + 1
                        : found.location - lastNewline.location
                    let previewStart = lastNewline.location == NSNotFound
                        ? 0 : lastNewline.location + 1
                    let lineEnd = ns.range(of: "\n", options: [],
                                           range: NSRange(location: found.location,
                                                          length: ns.length - found.location))
                    let previewEnd = lineEnd.location == NSNotFound ? ns.length : lineEnd.location
                    var preview = ns.substring(with: NSRange(location: previewStart,
                                                             length: max(0, previewEnd - previewStart)))
                    if preview.count > 160 { preview = String(preview.prefix(160)) + "…" }
                    results.append(SearchMatch(line: line, column: column,
                                               preview: preview, length: found.length))
                    if results.count >= limit { break }
                }
                let next = found.location + max(1, found.length)
                if next >= ns.length { break }
                searchRange = NSRange(location: next, length: ns.length - next)
            }
            piece += 1
        }
        return results
    }

    // MARK: - Save

    func save(to destination: URL? = nil) throws {
        let target = destination ?? url
        let directory = target.deletingLastPathComponent()
        let temp = directory.appendingPathComponent(".textlens-\(UUID().uuidString).tmp")
        FileManager.default.createFile(atPath: temp.path, contents: nil)
        let output = try FileHandle(forWritingTo: temp)
        do {
            if hasBOM, let bom = Self.bom(for: encoding) {
                try output.write(contentsOf: bom)
            }
            let input = try FileHandle(forReadingFrom: url)
            defer { try? input.close() }
            for piece in pieces {
                switch piece.source {
                case .file(let offset, let length):
                    try input.seek(toOffset: UInt64(offset))
                    var remaining = length
                    while remaining > 0 {
                        let chunk = try input.read(upToCount: min(1_048_576, remaining)) ?? Data()
                        if chunk.isEmpty { break }
                        try output.write(contentsOf: chunk)
                        remaining -= chunk.count
                    }
                case .text(let text):
                    let normalized = applyLineEnding(text)
                    guard let data = encoding.encode(normalized, includeBOM: false) else {
                        throw FileLoaderError.unreadable("无法用 \(encoding.label) 编码修改内容")
                    }
                    try output.write(contentsOf: data)
                }
            }
            try output.close()
            if target == url {
                let permissions = try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]
                _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
                if let permissions {
                    try? FileManager.default.setAttributes([.posixPermissions: permissions],
                                                           ofItemAtPath: url.path)
                }
            } else {
                if FileManager.default.fileExists(atPath: target.path) {
                    try FileManager.default.removeItem(at: target)
                }
                try FileManager.default.moveItem(at: temp, to: target)
            }
        } catch {
            try? output.close()
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
    }

    // MARK: - Helpers

    private func normalize(_ string: String) -> String {
        guard string.contains("\r") else { return string }
        return string
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private func applyLineEnding(_ string: String) -> String {
        let normalized = normalize(string)
        switch lineEnding {
        case .crlf: return normalized.replacingOccurrences(of: "\n", with: "\r\n")
        case .cr: return normalized.replacingOccurrences(of: "\n", with: "\r")
        default: return normalized
        }
    }

    private static func prefix(_ text: String, utf16Length: Int) -> String {
        guard utf16Length > 0 else { return "" }
        guard utf16Length < text.utf16.count else { return text }
        let index = text.utf16.index(text.utf16.startIndex, offsetBy: utf16Length)
        return String(text[..<index])
    }

    private static func suffix(_ text: String, fromUTF16: Int) -> String {
        guard fromUTF16 > 0 else { return text }
        guard fromUTF16 < text.utf16.count else { return "" }
        let index = text.utf16.index(text.utf16.startIndex, offsetBy: fromUTF16)
        return String(text[index...])
    }

    private static func bom(for encoding: TextEncoding) -> Data? {
        switch encoding {
        case .utf8: return Data([0xEF, 0xBB, 0xBF])
        case .utf16LE: return Data([0xFF, 0xFE])
        case .utf16BE: return Data([0xFE, 0xFF])
        case .utf32LE: return Data([0xFF, 0xFE, 0x00, 0x00])
        case .utf32BE: return Data([0x00, 0x00, 0xFE, 0xFF])
        default: return nil
        }
    }
}
