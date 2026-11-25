import Foundation
import Combine

/// Continuous sliding-window session for large files.
///
/// The document is a piece table; only a handful of adjacent pieces are
/// rendered at once. Scrolling to a boundary reloads a window around the
/// currently visible top line, preserving the anchor so the text does not jump.
@MainActor
final class RopeEditorSession: ObservableObject {
    let document: PieceTableDocument
    let fileName: String
    var onDirtyChanged: ((Bool) -> Void)?
    var onFileSaved: (() -> Void)?

    @Published private(set) var window: PieceTableDocument.Window?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var isDirty = false
    @Published private(set) var isSaving = false
    @Published private(set) var saveError: String?
    @Published var scrollTargetLine: Int?
    @Published var visibleTopLine = 1
    @Published private(set) var currentLine = 1
    @Published private(set) var totalLines = 1
    @Published private(set) var searchResults: [PieceTableDocument.SearchMatch] = []
    @Published private(set) var isSearching = false
    @Published private(set) var activeSearchScopeLabel = "整个文件"
    @Published private(set) var searchLimitReached = false
    @Published private(set) var highlightLine: Int?

    private var lastBoundaryTop = -1
    private let contextPieces = 1

    init(document: PieceTableDocument) {
        self.document = document
        self.fileName = document.url.lastPathComponent
        self.totalLines = max(1, document.totalLines)
    }

    var encodingLabel: String { document.encoding.label }
    var canGoBack: Bool { (window?.startLine ?? 1) > 1 }
    var canGoForward: Bool { (window?.endLine ?? 1) < totalLines }

    func loadInitial() {
        guard window == nil else { return }
        loadWindow(around: 1, scrollTo: 1)
    }

    func loadWindow(around line: Int, scrollTo target: Int? = nil) {
        let clamped = max(1, min(line, totalLines))
        isLoading = true
        errorMessage = nil
        do {
            let loaded = try document.window(aroundLine: clamped,
                                            contextPieces: contextPieces)
            window = loaded
            currentLine = clamped
            visibleTopLine = loaded.startLine
            scrollTargetLine = target ?? clamped
            totalLines = max(1, document.totalLines)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Shift the sliding window in the requested direction, keeping the
    /// visible top line as the scroll anchor.
    func ensureContext(around visibleLine: Int, forward: Bool, force: Bool = false) {
        let top = max(1, min(visibleLine, totalLines))
        if !force, top == lastBoundaryTop { return }
        lastBoundaryTop = top
        isLoading = true
        errorMessage = nil
        do {
            let loaded = forward
                ? try document.window(startingAtLine: top, contextPieces: 2)
                : try document.window(aroundLine: top, contextPieces: 1)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.window = loaded
                self.currentLine = top
                self.visibleTopLine = top
                self.scrollTargetLine = top
                self.totalLines = max(1, self.document.totalLines)
                self.objectWillChange.send()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Append the next pieces ahead of the viewport. No scroll target is set:
    /// the visible text and reading position remain exactly where they were.
    func prefetchForward(visibleLine: Int) {
        guard let window else { return }
        let textSize = window.text.utf16.count
        if textSize >= 24_000_000 {
            recenter(around: visibleLine)
            return
        }
        do {
            guard let extended = try document.extendedWindow(window, forwardPieces: 2) else {
                return
            }
            self.window = extended
            currentLine = visibleLine
            totalLines = max(1, document.totalLines)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func prefetchBackward(visibleLine: Int) {
        guard let window else { return }
        let textSize = window.text.utf16.count
        if textSize >= 24_000_000 {
            recenter(around: visibleLine)
            return
        }
        do {
            guard let prepended = try document.prependedWindow(window, backwardPieces: 2) else {
                return
            }
            self.window = prepended
            currentLine = visibleLine
            self.scrollTargetLine = visibleLine
            totalLines = max(1, document.totalLines)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func recenter(around visibleLine: Int) {
        loadWindow(around: max(1, min(visibleLine, totalLines)),
                   scrollTo: max(1, min(visibleLine, totalLines)))
    }

    func jump(toLine line: Int) {
        highlightLine = max(1, min(line, totalLines))
        loadWindow(around: max(1, min(line, totalLines)), scrollTo: line)
    }

    func search(query: String, caseSensitive: Bool, scope: LargeFileSearchScope,
                customStartLine: Int? = nil, customEndLine: Int? = nil) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clearSearch()
            return
        }
        var start = 1
        var end = totalLines
        switch scope {
        case .wholeFile:
            activeSearchScopeLabel = "整个文件"
        case .currentWindow:
            start = window?.startLine ?? 1
            end = window?.endLine ?? totalLines
            activeSearchScopeLabel = "当前窗口"
        case .customLines:
            start = max(1, customStartLine ?? 1)
            end = max(start, customEndLine ?? start)
            activeSearchScopeLabel = "第 \(start)–\(end) 行"
        }
        isSearching = true
        searchLimitReached = false
        searchResults = []
        highlightLine = nil
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            do {
                let results = try self.document.search(query: trimmed,
                                                       caseSensitive: caseSensitive,
                                                       rangeStartLine: start,
                                                       rangeEndLine: end,
                                                       limit: 1000)
                self.searchResults = results
                self.searchLimitReached = results.count >= 1000
            } catch {
                self.errorMessage = "搜索失败：\(error.localizedDescription)"
            }
            self.isSearching = false
        }
    }

    func clearSearch() {
        isSearching = false
        searchResults = []
        searchLimitReached = false
        activeSearchScopeLabel = "整个文件"
        highlightLine = nil
    }

    func applyWindowText(_ text: String) {
        guard let window else { return }
        let full = NSRange(location: 0, length: window.text.utf16.count)
        do {
            guard try document.applyEdit(in: window, range: full, replacement: text) else {
                saveError = "无法应用窗口修改"
                return
            }
            isDirty = true
            onDirtyChanged?(true)
            clearSearch()
            saveError = nil
            totalLines = max(1, document.totalLines)
            let anchor = max(1, min(window.startLine, totalLines))
            loadWindow(around: anchor, scrollTo: anchor)
        } catch {
            saveError = error.localizedDescription
        }
    }

    func save() {
        guard isDirty, !isSaving else { return }
        isSaving = true
        saveError = nil
        do {
            try document.save()
            isDirty = false
            onDirtyChanged?(false)
            onFileSaved?()
            let anchor = max(1, min(currentLine, totalLines))
            loadWindow(around: anchor, scrollTo: anchor)
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }

    func clearSaveError() {
        saveError = nil
    }

    func discardChanges() {
        // The piece table cannot cheaply reload from disk yet; recreate the
        // session at the TextFile level for a true revert.
        isDirty = false
    }
}
