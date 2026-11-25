import Foundation
import AppKit
import SwiftUI

// MARK: - Document model

enum FileLoadState: Equatable {
    case idle
    case loading
    case ready
    case failed
}

struct TextStats: Equatable, Sendable {
    var characters: Int = 0
    var lines: Int = 1
    var words: Int = 0

    static func compute(_ text: String, includeWords: Bool = true) -> TextStats {
        guard !text.isEmpty else { return TextStats(characters: 0, lines: 1, words: 0) }
        var words = 0
        if includeWords {
            text.enumerateSubstrings(in: text.startIndex..<text.endIndex,
                                     options: [.byWords, .substringNotRequired]) { _, _, _, _ in
                words += 1
            }
        }
        return TextStats(
            characters: text.count,
            lines: text.reduce(into: 1) { count, character in
                if character == "\n" { count += 1 }
            },
            words: words
        )
    }
}

@MainActor
final class TextFile: ObservableObject, Identifiable {
    let id = UUID()

    @Published var url: URL?
    @Published var displayName: String
    @Published var text: String = ""
    @Published var probe: ProbeResult?
    @Published var loadState: FileLoadState = .ready
    @Published var errorMessage: String?
    @Published var isDirty = false
    @Published var isSaving = false
    @Published var contentVersion = UUID()
    @Published var isEditable = true
    @Published var readOnlyReason: String?
    @Published var encoding: TextEncoding = .utf8
    @Published var hasBOM = false
    @Published var lineEnding: LineEnding = .lf
    @Published var cursorLine = 1
    @Published var cursorColumn = 1
    @Published var selectionLength = 0
    @Published var stats = TextStats()
    @Published var lastModified: Date?
    @Published var createdAt: Date?
    @Published var permissions: String?
    @Published var fileSize: Int64 = 0
    @Published var lastSavedAt: Date?
    @Published var isTruncated = false
    @Published var isLargeFile = false
    @Published var decodeHadErrors = false
    @Published var largeSession: LargeFileSession?
    @Published var ropeSession: RopeEditorSession?
    @Published var externalChange = false
    @Published var isMissingOnDisk = false

    private(set) var rawData: Data?
    private var lastKnownModification: Date?
    private var statsTask: Task<Void, Never>?

    // View state is kept per document so switching tabs feels natural.
    var savedSelection = NSRange(location: 0, length: 0)
    var savedScroll = NSPoint.zero
    var hasSavedViewState = false
    var syntaxOverride: SyntaxLanguage?

    init(untitledNumber: Int = 1) {
        self.url = nil
        self.displayName = untitledNumber > 1 ? "未命名 \(untitledNumber)" : "未命名"
        self.loadState = .ready
        self.isEditable = true
        self.lineEnding = .lf
        self.stats = TextStats()
    }

    init(url: URL) {
        self.url = url.standardizedFileURL
        self.displayName = url.lastPathComponent
        self.loadState = .loading
    }

    var format: FileFormat { probe?.format ?? .plainText }
    var isTextFile: Bool { probe?.isText ?? true }
    var isPagedMode: Bool { largeSession != nil || ropeSession != nil }
    var isRopeMode: Bool { ropeSession != nil }
    var syntax: SyntaxLanguage { syntaxOverride ?? format.syntax }
    var extensionLabel: String {
        guard let ext = url?.pathExtension, !ext.isEmpty else { return "无扩展名" }
        return ".\(ext.lowercased())"
    }
    var path: String { url?.path ?? "尚未保存到磁盘" }
    var canSave: Bool { isEditable || ropeSession != nil }
    var isUntitled: Bool { url == nil }

    func load() async {
        guard let url else { return }
        loadState = .loading
        errorMessage = nil
        do {
            let loaded = try await Task.detached(priority: .userInitiated) {
                try FileLoader.load(url: url)
            }.value
            apply(loaded)
            if loaded.isTruncated, loaded.probe.isText {
                if let document = try? PieceTableDocument(
                    url: url, size: loaded.fileSize,
                    encoding: loaded.probe.encoding,
                    hasBOM: loaded.probe.hasBOM,
                    lineEnding: loaded.probe.lineEnding
                ) {
                    let session = RopeEditorSession(document: document)
                    wireRopeSession(session)
                    ropeSession = session
                    session.loadInitial()
                } else {
                    let session = LargeFileSession(
                        url: url,
                        size: loaded.fileSize,
                        encoding: loaded.probe.encoding,
                        hasBOM: loaded.probe.hasBOM,
                        lineEnding: loaded.probe.lineEnding
                    )
                    largeSession = session
                    await session.loadFirstPageIfNeeded()
                }
            }
        } catch {
            loadState = .failed
            errorMessage = error.localizedDescription
        }
    }

    private func apply(_ loaded: LoadedFile) {
        let normalized = Self.normalizeNewlines(loaded.text)
        largeSession?.cancelAll()
        largeSession = nil
        ropeSession = nil
        probe = loaded.probe
        text = normalized
        rawData = loaded.rawData
        fileSize = loaded.fileSize
        lastModified = loaded.modified
        createdAt = loaded.created
        permissions = loaded.permissions
        lastKnownModification = loaded.modified
        encoding = loaded.probe.encoding
        hasBOM = loaded.probe.hasBOM
        lineEnding = loaded.probe.lineEnding
        isTruncated = loaded.isTruncated
        isLargeFile = loaded.fileSize >= TextDecoder.largeFileThreshold
            || normalized.utf16.count > Int(TextDecoder.largeFileThreshold)
        decodeHadErrors = loaded.decodeHadErrors
        isEditable = loaded.probe.isText && !loaded.isReadOnly && !loaded.decodeHadErrors
        readOnlyReason = loaded.readOnlyReason
            ?? (loaded.decodeHadErrors ? "文件包含无法解码的字节，已以只读方式打开。" : nil)
        loadState = .ready
        isDirty = false
        externalChange = false
        isMissingOnDisk = false
        contentVersion = UUID()
        cursorLine = 1
        cursorColumn = 1
        selectionLength = 0
        savedSelection = NSRange(location: 0, length: 0)
        savedScroll = .zero
        stats = TextStats.compute(normalized, includeWords: !isLargeFile)
        statsTask?.cancel()
        syntaxOverride = nil
    }

    func updateText(_ newText: String) {
        guard newText != text else { return }
        text = newText
        if !isDirty { isDirty = true }
        scheduleStats()
    }

    func updateCursor(line: Int, column: Int, selectionLength: Int) {
        if cursorLine != line { cursorLine = line }
        if cursorColumn != column { cursorColumn = column }
        if self.selectionLength != selectionLength { self.selectionLength = selectionLength }
    }

    private func scheduleStats() {
        statsTask?.cancel()
        let snapshot = text
        let includeWords = snapshot.utf16.count < Int(TextDecoder.largeFileThreshold)
        statsTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            let result = await Task.detached(priority: .utility) {
                TextStats.compute(snapshot, includeWords: includeWords)
            }.value
            guard !Task.isCancelled else { return }
            self?.stats = result
        }
    }

    // MARK: Saving

    @discardableResult
    func save(to destination: URL? = nil) -> Bool {
        guard isEditable else { return false }
        guard let target = (destination ?? url)?.standardizedFileURL else {
            errorMessage = "这个文档还没有保存位置。"
            return false
        }
        let effectiveEnding = lineEnding == .mixed ? .lf : lineEnding
        let output = effectiveEnding.apply(to: text)
        guard let data = encoding.encode(output, includeBOM: hasBOM) else {
            errorMessage = "文本中包含无法用 \(encoding.label) 表示的字符。请改用 UTF-8 保存。"
            return false
        }

        let oldAttributes = try? FileManager.default.attributesOfItem(atPath: target.path)
        do {
            do {
                try data.write(to: target, options: .atomic)
            } catch {
                try data.write(to: target)
            }
        } catch {
            errorMessage = "写入失败：\(error.localizedDescription)"
            return false
        }

        if let permissions = oldAttributes?[.posixPermissions] {
            try? FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: target.path)
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: target.path)
        url = target
        displayName = target.lastPathComponent
        fileSize = Int64(data.count)
        lastModified = attributes?[.modificationDate] as? Date
        lastKnownModification = lastModified
        permissions = (attributes?[.posixPermissions] as? NSNumber).map { String(format: "%03o", $0.intValue) }
        rawData = data
        isDirty = false
        isSaving = false
        errorMessage = nil
        externalChange = false
        isMissingOnDisk = false
        lastSavedAt = Date()
        if lineEnding == .mixed {
            lineEnding = .lf
            probe?.lineEnding = .lf
        }

        var refreshed = FileDetector.probe(
            sample: Data(data.prefix(TextDecoder.sampleLimit)),
            fileURL: target,
            fileSize: Int64(data.count),
            truncated: data.count > TextDecoder.sampleLimit
        )
        refreshed.isText = true
        refreshed.encoding = encoding
        refreshed.hasBOM = hasBOM
        refreshed.lineEnding = lineEnding
        refreshed.text = String(text.prefix(4096))
        refreshed.textConfidence = 1
        refreshed.encodingConfidence = 1
        probe = refreshed
        return true
    }

    func saveAs(to target: URL) -> Bool {
        save(to: target)
    }

    /// Decode the bytes on disk again using a different encoding.
    @discardableResult
    func reinterpret(as newEncoding: TextEncoding) -> Bool {
        guard newEncoding != encoding else { return true }
        guard let rawData else {
            encoding = newEncoding
            hasBOM = false
            return true
        }
        let outcome = TextDecoder.decodeLenient(rawData, encoding: newEncoding,
                                                truncated: isTruncated)
        let normalized = Self.normalizeNewlines(outcome.text)
        encoding = newEncoding
        text = normalized
        hasBOM = newEncoding.bom.map { rawData.starts(with: $0) } ?? false
        decodeHadErrors = outcome.hadErrors
        isEditable = probe?.isText == true && !isTruncated && !outcome.hadErrors
        if outcome.hadErrors {
            readOnlyReason = outcome.warning
            errorMessage = nil
        } else if !isTruncated {
            readOnlyReason = nil
            errorMessage = nil
        }
        contentVersion = UUID()
        isDirty = false
        stats = TextStats.compute(normalized, includeWords: !isLargeFile)
        cursorLine = 1
        cursorColumn = 1
        selectionLength = 0
        savedSelection = NSRange(location: 0, length: 0)
        savedScroll = .zero
        if var probe {
            probe.encoding = newEncoding
            probe.hasBOM = hasBOM
            probe.text = String(normalized.prefix(4096))
            probe.lineEnding = LineEnding.detect(in: normalized)
            if let warning = outcome.warning, !probe.warnings.contains(warning) {
                probe.warnings.append(warning)
            }
            self.probe = probe
        }
        return true
    }

    private func wireRopeSession(_ session: RopeEditorSession) {
        session.onDirtyChanged = { [weak self] dirty in
            self?.isDirty = dirty
        }
        session.onFileSaved = { [weak self] in
            self?.refreshLargeMetadata()
        }
    }

    private func refreshLargeMetadata() {
        guard let url else { return }
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        if let size = attributes?[.size] as? NSNumber {
            fileSize = size.int64Value
        }
        if let modified = attributes?[.modificationDate] as? Date {
            lastModified = modified
            lastKnownModification = modified
        }
        if let permissions = attributes?[.posixPermissions] as? NSNumber {
            self.permissions = String(format: "%o", permissions.intValue)
        }
        lastSavedAt = Date()
        isDirty = false
        externalChange = false
        isMissingOnDisk = false
    }

    /// Reopen the paged reader with another encoding. Large files are not
    /// decoded into a single String, so the session itself must be replaced.
    func reinterpretLargeFile(as newEncoding: TextEncoding) async -> Bool {
        guard let url else { return false }
        let bom = newEncoding.bom.map { rawData?.starts(with: $0) ?? false } ?? false
        if let document = try? PieceTableDocument(
            url: url, size: fileSize, encoding: newEncoding,
            hasBOM: bom, lineEnding: lineEnding
        ) {
            let session = RopeEditorSession(document: document)
            wireRopeSession(session)
            ropeSession = session
            largeSession?.cancelAll()
            largeSession = nil
            encoding = newEncoding
            hasBOM = bom
            decodeHadErrors = false
            if var probe {
                probe.encoding = newEncoding
                probe.hasBOM = bom
                self.probe = probe
            }
            session.loadInitial()
            return session.window != nil
        }
        let session = LargeFileSession(
            url: url,
            size: fileSize,
            encoding: newEncoding,
            hasBOM: bom,
            lineEnding: lineEnding
        )
        ropeSession = nil
        largeSession = session
        encoding = newEncoding
        hasBOM = bom
        decodeHadErrors = false
        if var probe {
            probe.encoding = newEncoding
            probe.hasBOM = bom
            self.probe = probe
        }
        await session.loadFirstPageIfNeeded()
        return session.page != nil
    }

    func setLineEnding(_ newEnding: LineEnding) {
        guard newEnding != lineEnding else { return }
        lineEnding = newEnding
        if !isDirty { isDirty = true }
    }

    func reloadFromDisk() async {
        await load()
    }

    func checkForExternalChange(quiet: Bool = false) {
        guard let url else { return }
        guard let snapshot = FileLoader.snapshot(of: url) else {
            isMissingOnDisk = true
            externalChange = true
            return
        }
        isMissingOnDisk = false
        guard let lastKnownModification else { return }
        if abs(snapshot.modified?.timeIntervalSince(lastKnownModification) ?? 0) > 0.5 {
            externalChange = true
            if !quiet, isDirty {
                // The UI presents the conflict banner; no alert from the model.
            }
        }
    }

    func acknowledgeExternalChange() {
        if let url, let snapshot = FileLoader.snapshot(of: url) {
            lastKnownModification = snapshot.modified
            lastModified = snapshot.modified
        }
        externalChange = false
    }

    func discardUnsavedChanges() {
        isDirty = false
    }

    func cancelLargeFileWork() {
        largeSession?.cancelAll()
    }

    private static func normalizeNewlines(_ value: String) -> String {
        guard value.contains("\r") else { return value }
        return value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}

// MARK: - Persistent recents

struct RecentFile: Codable, Identifiable, Equatable {
    var path: String
    var name: String
    var formatName: String
    var formatID: String
    var tint: FormatTint
    var lastOpened: Date

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }
    var exists: Bool { FileManager.default.fileExists(atPath: path) }
}

// MARK: - UI support models

struct ToastMessage: Identifiable {
    let id = UUID()
    let text: String
    var symbol: String = "checkmark.circle.fill"
}

struct AppAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    var symbol: String = "exclamationmark.triangle.fill"
}

struct HexPayload: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let data: Data
}

enum ActiveSheet: Identifiable {
    case hex(HexPayload)
    case goToLine

    var id: String {
        switch self {
        case .hex(let payload): return "hex-\(payload.id.uuidString)"
        case .goToLine: return "go-to-line"
        }
    }
}

// MARK: - Application store

@MainActor
final class AppStore: ObservableObject {
    static let shared = AppStore()

    @Published var tabs: [TextFile] = []
    @Published var activeID: UUID?
    @Published var recents: [RecentFile] = []
    @Published var showInspector: Bool {
        didSet { defaults.set(showInspector, forKey: Keys.inspector) }
    }
    @Published var wrapLines: Bool {
        didSet { defaults.set(wrapLines, forKey: Keys.wrap) }
    }
    @Published var showInvisibles: Bool {
        didSet { defaults.set(showInvisibles, forKey: Keys.invisibles) }
    }
    @Published var fontSize: Double {
        didSet { defaults.set(fontSize, forKey: Keys.fontSize) }
    }
    @Published var alert: AppAlert?
    @Published var toast: ToastMessage?
    @Published var activeSheet: ActiveSheet?
    @Published var isDropTargeted = false

    private let defaults = UserDefaults.standard
    private var toastTask: Task<Void, Never>?
    private var untitledCounter = 1
    private var isPresentingUnsavedPrompt = false

    private enum Keys {
        static let recents = "TextLens.recents.v1"
        static let inspector = "TextLens.showInspector"
        static let wrap = "TextLens.wrapLines"
        static let invisibles = "TextLens.showInvisibles"
        static let fontSize = "TextLens.fontSize"
    }

    private init() {
        let d = UserDefaults.standard
        if d.object(forKey: Keys.inspector) == nil {
            showInspector = true
        } else {
            showInspector = d.bool(forKey: Keys.inspector)
        }
        if d.object(forKey: Keys.wrap) == nil {
            wrapLines = true
        } else {
            wrapLines = d.bool(forKey: Keys.wrap)
        }
        showInvisibles = d.bool(forKey: Keys.invisibles)
        let size = d.double(forKey: Keys.fontSize)
        fontSize = size > 8 ? min(28, max(10, size)) : 13.5
        loadRecents()
    }

    var activeDocument: TextFile? {
        guard let activeID else { return nil }
        return tabs.first { $0.id == activeID }
    }

    var hasUnsavedChanges: Bool { tabs.contains(where: \.isDirty) }

    var windowSubtitle: String {
        guard let doc = activeDocument else { return "打开任意文件，先识类型，再读内容" }
        if doc.isUntitled { return "尚未保存" }
        return doc.path
    }

    // MARK: Opening

    func openPanel() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "打开任意文件"
        panel.message = "文本、源代码、配置、无扩展名或未知后缀的文件都可以打开"
        panel.prompt = "打开"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = true
        if panel.runModal() == .OK {
            open(urls: panel.urls)
        }
    }

    func open(urls: [URL]) {
        for rawURL in urls {
            let url = rawURL.standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else {
                showAlert(title: "无法打开", message: "“\(url.lastPathComponent)”不是一个普通文件。")
                continue
            }
            if let existing = tabs.first(where: { $0.url?.standardizedFileURL.path == url.path }) {
                activeID = existing.id
                continue
            }
            if let current = activeDocument, current.url == nil, !current.isDirty, current.text.isEmpty,
               current.loadState == .ready {
                tabs.removeAll { $0.id == current.id }
            }
            let doc = TextFile(url: url)
            tabs.append(doc)
            activeID = doc.id
            Task { [weak self] in
                await doc.load()
                guard let self else { return }
                if doc.loadState == .ready {
                    self.remember(doc)
                } else {
                    self.flash("\(doc.displayName) 打开失败", symbol: "exclamationmark.triangle.fill")
                }
            }
        }
    }

    func newDocument() {
        if let active = activeDocument, active.isUntitled, !active.isDirty, active.text.isEmpty {
            return
        }
        untitledCounter += 1
        let doc = TextFile(untitledNumber: untitledCounter)
        tabs.append(doc)
        activeID = doc.id
    }

    func activate(_ doc: TextFile) {
        activeID = doc.id
    }

    func closeTab(_ doc: TextFile) {
        guard let index = tabs.firstIndex(where: { $0.id == doc.id }) else { return }
        doc.cancelLargeFileWork()
        if doc.isDirty {
            let choice = askToSave([doc], action: "关闭")
            guard choice else { return }
        }
        tabs.remove(at: index)
        if activeID == doc.id {
            if tabs.isEmpty {
                activeID = nil
            } else {
                activeID = tabs[min(index, tabs.count - 1)].id
            }
        }
    }

    func closeActiveTab() {
        guard let doc = activeDocument else { return }
        closeTab(doc)
    }

    func selectNextTab() {
        guard !tabs.isEmpty, let activeID,
              let index = tabs.firstIndex(where: { $0.id == activeID }) else { return }
        self.activeID = tabs[(index + 1) % tabs.count].id
    }

    func selectPreviousTab() {
        guard !tabs.isEmpty, let activeID,
              let index = tabs.firstIndex(where: { $0.id == activeID }) else { return }
        self.activeID = tabs[(index - 1 + tabs.count) % tabs.count].id
    }

    // MARK: Saving

    func saveActive() {
        guard let doc = activeDocument else { return }
        save(doc)
    }

    func save(_ doc: TextFile) {
        if let rope = doc.ropeSession {
            rope.save()
            return
        }
        guard doc.isEditable else {
            showAlert(title: "无法保存", message: doc.readOnlyReason ?? "这个文件是只读预览。")
            return
        }
        if doc.isUntitled {
            saveAs(doc)
            return
        }
        doc.checkForExternalChange(quiet: true)
        if doc.externalChange {
            let alert = NSAlert()
            alert.messageText = "磁盘上的文件已经变化"
            alert.informativeText = doc.isMissingOnDisk
                ? "文件已经被删除，仍要保存并重新创建它吗？"
                : "“\(doc.displayName)”在 TextLens 之外被修改过。覆盖磁盘上的版本吗？"
            alert.addButton(withTitle: "覆盖保存")
            alert.addButton(withTitle: "取消")
            if alert.runModal() != .alertFirstButtonReturn { return }
        }
        if doc.save() {
            remember(doc)
            flash("已保存 \(doc.displayName)")
        } else {
            showAlert(title: "保存失败", message: doc.errorMessage ?? "未知错误")
        }
    }

    func saveAs(_ doc: TextFile) {
        guard doc.isEditable else { return }
        let panel = NSSavePanel()
        panel.title = "另存为"
        panel.prompt = "保存"
        panel.canCreateDirectories = true
        panel.allowsOtherFileTypes = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = doc.isUntitled ? "未命名.txt" : doc.displayName
        panel.message = "将使用 \(doc.encoding.label) 编码、\(doc.lineEnding.longLabel) 换行保存"
        guard panel.runModal() == .OK, let target = panel.url else { return }
        if doc.save(to: target) {
            remember(doc)
            flash("已保存 \(doc.displayName)")
        } else {
            showAlert(title: "保存失败", message: doc.errorMessage ?? "未知错误")
        }
    }

    func saveAsActive() {
        guard let doc = activeDocument else { return }
        saveAs(doc)
    }

    @discardableResult
    func saveWithPanel(_ doc: TextFile) -> Bool {
        let panel = NSSavePanel()
        panel.title = "保存文件"
        panel.prompt = "保存"
        panel.canCreateDirectories = true
        panel.allowsOtherFileTypes = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = doc.isUntitled ? "未命名.txt" : doc.displayName
        guard panel.runModal() == .OK, let target = panel.url else { return false }
        if doc.save(to: target) {
            remember(doc)
            return true
        }
        showAlert(title: "保存失败", message: doc.errorMessage ?? "未知错误")
        return false
    }

    func revertActive() {
        guard let doc = activeDocument, doc.url != nil else { return }
        let alert = NSAlert()
        alert.messageText = "重新从磁盘载入？"
        alert.informativeText = doc.isDirty
            ? "未保存的更改会丢失。"
            : "将重新读取文件并重新检测类型与编码。"
        alert.addButton(withTitle: "重新载入")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { await doc.reloadFromDisk() }
        flash("已重新载入", symbol: "arrow.clockwise.circle.fill")
    }

    // MARK: Encoding

    func chooseEncoding(_ newEncoding: TextEncoding, for doc: TextFile) {
        guard newEncoding != doc.encoding else { return }
        if doc.isRopeMode, doc.isDirty {
            showAlert(title: "请先保存", message: "连续窗口中有未保存的修改，保存后再切换编码。")
            return
        }
        if doc.isPagedMode {
            Task {
                if await doc.reinterpretLargeFile(as: newEncoding) {
                    flash("已按 \(newEncoding.label) 重新读取分页", symbol: "textformat.abc")
                } else {
                    showAlert(title: "解码失败", message: "无法按 \(newEncoding.label) 读取这个文件。")
                }
            }
            return
        }
        if doc.isDirty {
            let alert = NSAlert()
            alert.messageText = "重新解码会丢弃未保存的更改"
            alert.informativeText = "要用 \(newEncoding.label) 重新解释磁盘上的原始字节吗？"
            alert.addButton(withTitle: "重新解码")
            alert.addButton(withTitle: "取消")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        if doc.reinterpret(as: newEncoding) {
            flash("已按 \(newEncoding.label) 解码", symbol: "textformat.abc")
        } else {
            showAlert(title: "解码失败", message: doc.errorMessage ?? "无法使用这个编码读取文件。")
        }
    }

    func setLineEnding(_ ending: LineEnding, for doc: TextFile) {
        doc.setLineEnding(ending)
    }

    // MARK: Finder / clipboard / external

    func revealInFinder(_ doc: TextFile? = nil) {
        guard let url = (doc ?? activeDocument)?.url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openWithDefaultApp(_ doc: TextFile? = nil) {
        guard let url = (doc ?? activeDocument)?.url else { return }
        NSWorkspace.shared.open(url)
    }

    func copyPath(_ doc: TextFile? = nil) {
        guard let path = (doc ?? activeDocument)?.url?.path else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(path, forType: .string)
        flash("路径已复制", symbol: "doc.on.doc.fill")
    }

    func showHex(_ doc: TextFile? = nil) {
        guard let doc = doc ?? activeDocument else { return }
        let data: Data
        if let raw = doc.rawData {
            data = Data(raw.prefix(16_384))
        } else if let sample = doc.probe?.byteSample {
            data = sample
        } else {
            data = Data()
        }
        presentSheet(.hex(HexPayload(
            title: doc.displayName,
            subtitle: doc.probe?.isText == true
                ? "前 16 KB 字节（共 \(FileFormatting.bytes(doc.fileSize))）"
                : "前 1 KB 字节（共 \(FileFormatting.bytes(doc.fileSize))）",
            data: data
        )))
    }

    func showGoToLine() {
        if activeDocument?.isPagedMode == true {
            NotificationCenter.default.post(name: EditorNotifications.goToLine, object: nil)
        } else {
            presentSheet(.goToLine)
        }
    }

    /// Present from a deferred runloop turn. SwiftUI drops presentation requests
    /// made while an AppKit menu is still tracking the click.
    func presentSheet(_ sheet: ActiveSheet) {
        DispatchQueue.main.async { [weak self] in
            self?.activeSheet = sheet
        }
    }

    // MARK: Recents

    private func loadRecents() {
        guard let data = defaults.data(forKey: Keys.recents) else { return }
        recents = (try? JSONDecoder().decode([RecentFile].self, from: data)) ?? []
    }

    private func persistRecents() {
        if let data = try? JSONEncoder().encode(Array(recents.prefix(15))) {
            defaults.set(data, forKey: Keys.recents)
        }
    }

    func remember(_ doc: TextFile) {
        guard let url = doc.url else { return }
        let item = RecentFile(
            path: url.path,
            name: url.lastPathComponent,
            formatName: doc.format.name,
            formatID: doc.format.id,
            tint: doc.format.tint,
            lastOpened: Date()
        )
        recents.removeAll { $0.path == item.path }
        recents.insert(item, at: 0)
        if recents.count > 15 { recents.removeLast(recents.count - 15) }
        persistRecents()
    }

    func openRecent(_ item: RecentFile) {
        guard item.exists else {
            showAlert(title: "文件不存在", message: "“\(item.name)”已经被移动或删除。")
            recents.removeAll { $0.path == item.path }
            persistRecents()
            return
        }
        open(urls: [item.url])
    }

    func removeRecent(_ item: RecentFile) {
        recents.removeAll { $0.path == item.path }
        persistRecents()
    }

    func clearRecents() {
        recents.removeAll()
        persistRecents()
    }

    // MARK: View settings

    func toggleInspector() { showInspector.toggle() }
    func toggleWrap() { wrapLines.toggle() }
    func toggleInvisibles() { showInvisibles.toggle() }

    func zoomIn() { fontSize = min(28, fontSize + 1) }
    func zoomOut() { fontSize = max(10, fontSize - 1) }
    func resetZoom() { fontSize = 13.5 }

    // MARK: Find / go to line

    func showFind() {
        NotificationCenter.default.post(name: EditorNotifications.find, object: nil,
                                        userInfo: ["action": 1])
    }

    func findNext() {
        NotificationCenter.default.post(name: EditorNotifications.find, object: nil,
                                        userInfo: ["action": 2])
    }

    func findPrevious() {
        NotificationCenter.default.post(name: EditorNotifications.find, object: nil,
                                        userInfo: ["action": 3])
    }

    func requestGoToLine(_ line: Int) {
        guard line > 0 else { return }
        NotificationCenter.default.post(name: EditorNotifications.goToLine, object: nil,
                                        userInfo: ["line": line])
    }

    // MARK: Alerts and toast

    func showAlert(title: String, message: String, symbol: String = "exclamationmark.triangle.fill") {
        alert = AppAlert(title: title, message: message, symbol: symbol)
    }

    func flash(_ text: String, symbol: String = "checkmark.circle.fill") {
        toastTask?.cancel()
        toast = ToastMessage(text: text, symbol: symbol)
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    // MARK: App lifecycle

    func checkExternalChanges() {
        for doc in tabs where doc.url != nil {
            doc.checkForExternalChange(quiet: true)
        }
    }

    /// Returns true when it is safe to close the window / quit the app.
    func confirmDiscardUnsaved() -> Bool {
        let dirty = tabs.filter(\.isDirty)
        guard !dirty.isEmpty else { return true }
        // NSAlert's modal loop can re-enter the app's close/terminate handling.
        // Never stack two identical save prompts on top of each other.
        guard !isPresentingUnsavedPrompt else { return false }
        isPresentingUnsavedPrompt = true
        defer { isPresentingUnsavedPrompt = false }
        return askToSave(dirty, action: "退出")
    }

    private func askToSave(_ documents: [TextFile], action: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = documents.count == 1
            ? "要保存对“\(documents[0].displayName)”的更改吗？"
            : "有 \(documents.count) 个文件尚未保存"
        alert.informativeText = documents.count == 1
            ? "如果不保存，更改将丢失。"
            : documents.map { "· \($0.displayName)" }.joined(separator: "\n")
        alert.addButton(withTitle: documents.count == 1 ? "保存" : "保存全部")
        alert.addButton(withTitle: "不保存")
        alert.addButton(withTitle: "取消")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            for doc in documents {
                if doc.isUntitled {
                    if !saveWithPanel(doc) { return false }
                } else if doc.save() {
                    remember(doc)
                } else {
                    showAlert(title: "保存失败", message: doc.errorMessage ?? "未知错误")
                    return false
                }
            }
            return true
        } else if response == .alertSecondButtonReturn {
            for doc in documents { doc.discardUnsavedChanges() }
            return true
        }
        return false
    }
}

// MARK: - Editor notification names

enum EditorNotifications {
    static let find = Notification.Name("TextLens.find")
    static let goToLine = Notification.Name("TextLens.goToLine")
}
