import Foundation

/// A balanced rope over UTF-16 text chunks.
///
/// This is the in-memory building block for the large-file editor. Leaves hold
/// short strings; internal nodes cache UTF-16 length and newline count so line
/// and offset lookups do not need to materialize the whole text.
struct TextRope {
    private final class Node {
        var text: String?
        var left: Node?
        var right: Node?
        var utf16Length: Int
        var newlineCount: Int
        var height: Int
        var priority: UInt64

        init(text: String, priority: UInt64) {
            self.text = text
            self.utf16Length = text.utf16.count
            self.newlineCount = text.reduce(into: 0) { count, ch in
                if ch == "\n" { count += 1 }
            }
            self.height = 1
            self.priority = priority
        }

        init(left: Node?, right: Node?, priority: UInt64) {
            self.text = nil
            self.left = left
            self.right = right
            self.utf16Length = (left?.utf16Length ?? 0) + (right?.utf16Length ?? 0)
            self.newlineCount = (left?.newlineCount ?? 0) + (right?.newlineCount ?? 0)
            self.height = max(left?.height ?? 0, right?.height ?? 0) + 1
            self.priority = max(priority, max(left?.priority ?? 0, right?.priority ?? 0))
        }
    }

   private var root: Node?
    private var seed: UInt64 = 0x9E3779B97F4A7C15

    init(_ text: String = "") {
        if !text.isEmpty { root = Self.build(text) }
    }

    var utf16Length: Int { root?.utf16Length ?? 0 }
    var newlineCount: Int { root?.newlineCount ?? 0 }
    var lineCount: Int { newlineCount + 1 }
    var isEmpty: Bool { utf16Length == 0 }

    func substring(_ range: NSRange) -> String {
        guard range.location >= 0, range.length >= 0,
              range.location + range.length <= utf16Length else { return "" }
        var result = ""
        result.reserveCapacity(range.length)
        collect(root, from: range.location, to: range.location + range.length, into: &result)
        return result
    }

    func substring(from location: Int, length: Int) -> String {
        guard location >= 0, length >= 0, location + length <= utf16Length else { return "" }
        return substring(NSRange(location: location, length: length))
    }

    mutating func replace(_ range: NSRange, with text: String) {
        guard range.location >= 0, range.length >= 0,
              range.location + range.length <= utf16Length else { return }
        let (before, rest) = Self.split(root, at: range.location, seed: &seed)
        let (_, after) = Self.split(rest, at: range.length, seed: &seed)
        let inserted = text.isEmpty ? nil : Self.build(text, seed: &seed)
        root = Self.merge(Self.merge(before, inserted), after)
    }

    mutating func insert(_ text: String, at location: Int) {
        replace(NSRange(location: location, length: 0), with: text)
    }

    mutating func delete(_ range: NSRange) {
        replace(range, with: "")
    }

    /// UTF-16 offset of the start of a 1-based line.
    func lineStart(_ line: Int) -> Int? {
        guard line >= 1, line <= lineCount else { return nil }
        if line == 1 { return 0 }
        var remaining = line - 1
        var offset = 0
        return findOffsetAfterNewlines(root, remaining: &remaining, offset: &offset)
    }

    /// 1-based line/column for a UTF-16 offset.
    func lineAndColumn(at location: Int) -> (line: Int, column: Int) {
        let clamped = max(0, min(location, utf16Length))
        var line = 1
        var lastNewline: Int? = nil
        var scanned = 0
        scan(root, limit: clamped) { character, index in
            scanned = index
            if character == "\n" {
                line += 1
                lastNewline = index
            }
        }
        let column = (lastNewline.map { clamped - ($0 + 1) } ?? clamped) + 1
        _ = scanned
        return (line, column)
    }

    func lineText(_ line: Int) -> String? {
        guard let start = lineStart(line) else { return nil }
        let end: Int
        if let next = lineStart(line + 1) {
            end = next
        } else {
            end = utf16Length
        }
        var text = substring(NSRange(location: start, length: max(0, end - start)))
        if text.hasSuffix("\n") { text.removeLast() }
        return text
    }

    var wholeText: String { substring(NSRange(location: 0, length: utf16Length)) }

    // MARK: - Tree construction / balancing

    private static func build(_ text: String, seed: inout UInt64) -> Node? {
        let units = Array(text.utf16)
        guard !units.isEmpty else { return nil }
        var leaves: [Node] = []
        let chunkSize = 1024
        var index = 0
        while index < units.count {
            var end = min(units.count, index + chunkSize)
            if end < units.count, end > index,
               units[end - 1] >= 0xD800, units[end - 1] <= 0xDBFF,
               units[end] >= 0xDC00, units[end] <= 0xDFFF {
                end -= 1
            }
            let piece = String(decoding: units[index..<end], as: UTF16.self)
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            leaves.append(Node(text: piece, priority: seed))
            index = end
        }
        return buildBalanced(leaves, 0, leaves.count)
    }

    private static func build(_ text: String) -> Node? {
        var localSeed: UInt64 = 0x9E3779B97F4A7C15
        return build(text, seed: &localSeed)
    }

    private static func buildBalanced(_ leaves: [Node], _ low: Int, _ high: Int) -> Node? {
        guard low < high else { return nil }
        if high - low == 1 { return leaves[low] }
        let mid = (low + high) / 2
        let left = buildBalanced(leaves, low, mid)
        let right = buildBalanced(leaves, mid, high)
        return Node(left: left, right: right, priority: 0)
    }

    private static func merge(_ left: Node?, _ right: Node?) -> Node? {
        guard let left else { return right }
        guard let right else { return left }
        // A leaf must never get children; promote the pair to an internal node.
        if left.text != nil || right.text != nil {
            return Node(left: left, right: right,
                        priority: max(left.priority, right.priority))
        }
        if left.priority >= right.priority {
            left.right = merge(left.right, right)
            update(left)
            return left
        } else {
            right.left = merge(left, right.left)
            update(right)
            return right
        }
    }

    private static func split(_ node: Node?, at offset: Int, seed: inout UInt64) -> (Node?, Node?) {
        guard let node else { return (nil, nil) }
        if let text = node.text {
            let units = Array(text.utf16)
            if offset <= 0 { return (nil, node) }
            if offset >= units.count { return (node, nil) }
            let leftText = String(decoding: units[0..<offset], as: UTF16.self)
            let rightText = String(decoding: units[offset..<units.count], as: UTF16.self)
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let leftNode = Node(text: leftText, priority: seed)
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let rightNode = Node(text: rightText, priority: seed)
            return (leftNode, rightNode)
        }
        let leftLength = node.left?.utf16Length ?? 0
        if offset < leftLength {
            let (a, b) = split(node.left, at: offset, seed: &seed)
            node.left = b
            update(node)
            return (a, node)
        } else if offset > leftLength {
            let (a, b) = split(node.right, at: offset - leftLength, seed: &seed)
            node.right = a
            update(node)
            return (node, b)
        } else {
            let left = node.left
            let right = node.right
            return (left, right)
        }
    }

    private static func update(_ node: Node) {
        node.utf16Length = (node.left?.utf16Length ?? 0) + (node.right?.utf16Length ?? 0)
        node.newlineCount = (node.left?.newlineCount ?? 0) + (node.right?.newlineCount ?? 0)
        node.height = max(node.left?.height ?? 0, node.right?.height ?? 0) + 1
    }

    // MARK: - Traversal

    private func collect(_ node: Node?, from start: Int, to end: Int, into result: inout String) {
        guard let node, start < end else { return }
        if let text = node.text {
            let units = Array(text.utf16)
            let localStart = max(0, start)
            let localEnd = min(units.count, end)
            if localStart < localEnd {
                result += String(decoding: units[localStart..<localEnd], as: UTF16.self)
            }
            return
        }
        let leftLength = node.left?.utf16Length ?? 0
        if start < leftLength {
            collect(node.left, from: start, to: min(end, leftLength), into: &result)
        }
        if end > leftLength {
            collect(node.right, from: max(0, start - leftLength), to: end - leftLength, into: &result)
        }
    }

    private func scan(_ node: Node?, limit: Int, _ handler: (Character, Int) -> Void) {
        guard let node, limit > 0 else { return }
        if let text = node.text {
            var offset = 0
            for character in text {
                if offset >= limit { break }
                handler(character, offset)
                offset += String(character).utf16.count
            }
            return
        }
        let leftLength = node.left?.utf16Length ?? 0
        if limit <= leftLength {
            scan(node.left, limit: limit, handler)
        } else {
            scan(node.left, limit: leftLength, handler)
            scan(node.right, limit: limit - leftLength, handler)
        }
    }

    private func findOffsetAfterNewlines(_ node: Node?, remaining: inout Int, offset: inout Int) -> Int? {
        guard let node else { return nil }
        if node.newlineCount < remaining { return nil }
        if let text = node.text {
            var localOffset = 0
            for character in text {
                if character == "\n" {
                    remaining -= 1
                    if remaining == 0 { return offset + localOffset + String(character).utf16.count }
                }
                localOffset += String(character).utf16.count
            }
            offset += localOffset
            return nil
        }
        let leftNewlines = node.left?.newlineCount ?? 0
        if remaining <= leftNewlines {
            return findOffsetAfterNewlines(node.left, remaining: &remaining, offset: &offset)
        }
        remaining -= leftNewlines
        offset += node.left?.utf16Length ?? 0
        return findOffsetAfterNewlines(node.right, remaining: &remaining, offset: &offset)
    }
}
