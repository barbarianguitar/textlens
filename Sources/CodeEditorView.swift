import AppKit
import SwiftUI

// MARK: - Text view

final class CodeTextView: NSTextView {
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard selectedRange().length == 0,
              let layoutManager,
              let container = textContainer,
              string.utf16.count > 0 else { return }
        let location = min(selectedRange().location, max(0, string.utf16.count - 1))
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: location)
        var lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        lineRect.origin.y += textContainerInset.height
        lineRect.origin.x = 0
        lineRect.size.width = bounds.width
        EditorTheme.currentLine.setFill()
        lineRect.fill()
        _ = container
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        backgroundColor = EditorTheme.background
        insertionPointColor = .controlAccentColor
        needsDisplay = true
    }
}

// MARK: - Gutter

final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?
    private var lineStarts: [Int] = [0]
    private var lineStartsDirty = true
    private var observers: [NSObjectProtocol] = []
    var numberFont = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
    /// Absolute line number of the first line in this text view.
    var lineOffset: Int = 0
    var onScroll: (() -> Void)?

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 54
        observe()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    override var requiredThickness: CGFloat { 54 }

    private func observe() {
        guard let textView else { return }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSText.didChangeNotification, object: textView, queue: .main
        ) { [weak self] _ in
            self?.lineStartsDirty = true
            self?.needsDisplay = true
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSTextView.didChangeSelectionNotification, object: textView, queue: .main
        ) { [weak self] _ in
            self?.needsDisplay = true
        })
        if let clipView = scrollView?.contentView {
            clipView.postsBoundsChangedNotifications = true
            observers.append(NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: clipView, queue: .main
            ) { [weak self] _ in
                self?.needsDisplay = true
                self?.onScroll?()
            })
        }
    }

    func invalidateLineStarts() {
        lineStartsDirty = true
        needsDisplay = true
    }

    /// Absolute line number containing a UTF-16 character index.
    func lineNumber(at characterIndex: Int) -> Int {
        refreshLineStartsIfNeeded()
        guard !lineStarts.isEmpty else { return lineOffset + 1 }
        var low = 0
        var high = lineStarts.count - 1
        while low <= high {
            let mid = (low + high) / 2
            if lineStarts[mid] <= characterIndex {
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return lineOffset + max(0, high) + 1
    }

    /// UTF-16 location of an absolute line's first character.
    func characterIndex(forLine line: Int) -> Int? {
        refreshLineStartsIfNeeded()
        let local = line - lineOffset - 1
        guard local >= 0, local < lineStarts.count else { return nil }
        return lineStarts[local]
    }

    private func refreshLineStartsIfNeeded() {
        guard lineStartsDirty, let textView else { return }
        let ns = textView.string as NSString
        var starts: [Int] = [0]
        var searchStart = 0
        while searchStart < ns.length {
            let found = ns.range(of: "\n", options: [],
                                 range: NSRange(location: searchStart, length: ns.length - searchStart))
            if found.location == NSNotFound { break }
            starts.append(found.location + 1)
            searchStart = found.location + 1
        }
        lineStarts = starts
        lineStartsDirty = false
    }

    func lineColumn(forCharacter characterIndex: Int) -> (line: Int, column: Int) {
        refreshLineStartsIfNeeded()
        let length = textView?.string.utf16.count ?? 0
        let location = min(max(0, characterIndex), length)
        var low = 0
        var high = lineStarts.count - 1
        while low <= high {
            let mid = (low + high) / 2
            if lineStarts[mid] <= location {
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        let line = max(1, high + 1)
        let start = lineStarts[min(line - 1, lineStarts.count - 1)]
        return (line + lineOffset, max(1, location - start + 1))
    }

    func range(forLine line: Int) -> NSRange? {
        refreshLineStartsIfNeeded()
        let localLine = line - lineOffset
        guard localLine >= 1, localLine <= lineStarts.count, let textView else { return nil }
        let ns = textView.string as NSString
        let start = lineStarts[localLine - 1]
        let end = localLine < lineStarts.count ? lineStarts[localLine] - 1 : ns.length
        return NSRange(location: start, length: max(0, end - start))
    }

    private func lineNumber(forCharacter characterIndex: Int) -> Int {
        var low = 0
        var high = lineStarts.count - 1
        while low <= high {
            let mid = (low + high) / 2
            if lineStarts[mid] <= characterIndex {
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return max(1, high + 1)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        EditorTheme.gutterBackground.setFill()
        bounds.fill()
        EditorTheme.separator.setFill()
        NSRect(x: bounds.maxX - 1, y: 0, width: 1, height: bounds.height).fill()

        guard let textView, let layoutManager = textView.layoutManager, let container = textView.textContainer else { return }
        refreshLineStartsIfNeeded()
        layoutManager.ensureLayout(for: container)

        let visibleRect = textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: container)
        let selectedLocation = textView.selectedRange().location
        let currentLine = lineNumber(forCharacter: selectedLocation)

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: numberFont,
            .paragraphStyle: paragraph
        ]

        var glyphIndex = glyphRange.location
        var lastDrawnLine = -1
        while glyphIndex < NSMaxRange(glyphRange) {
            var fragmentRange = NSRange()
            let fragmentRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex,
                                                             effectiveRange: &fragmentRange)
            let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
            let line = lineNumber(forCharacter: characterIndex)
            if line != lastDrawnLine, characterIndex == lineStarts[line - 1] {
                let isCurrent = line == currentLine
                var attributes = baseAttributes
                attributes[.foregroundColor] = isCurrent
                    ? EditorTheme.gutterCurrentText
                    : EditorTheme.gutterText
                let string = NSAttributedString(string: "\(line + lineOffset)", attributes: attributes)
                let size = string.size()
                let y = fragmentRect.minY + textView.textContainerInset.height - visibleRect.minY
                    + max(0, (fragmentRect.height - size.height) / 2)
                let x = max(4, bounds.width - size.width - 6)
                string.draw(at: NSPoint(x: x, y: y))
                lastDrawnLine = line
            }
            glyphIndex = NSMaxRange(fragmentRange)
        }

        if textView.string.isEmpty {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: numberFont,
                .foregroundColor: EditorTheme.gutterCurrentText,
                .paragraphStyle: paragraph
            ]
            let string = NSAttributedString(string: "\(1 + lineOffset)", attributes: attributes)
            let size = string.size()
            let x = max(4, bounds.width - size.width - 6)
            string.draw(at: NSPoint(x: x, y: textView.textContainerInset.height))
        }
    }
}

// MARK: - SwiftUI wrapper

struct CodeEditorView: NSViewRepresentable {
    @ObservedObject var document: TextFile
    var wrapLines: Bool
    var showInvisibles: Bool
    var fontSize: CGFloat
    var isEditable: Bool = true

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = EditorTheme.background
        scrollView.scrollerStyle = .overlay

        let textView = CodeTextView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.usesFontPanel = false
        textView.isFieldEditor = false
        textView.drawsBackground = true
        textView.backgroundColor = EditorTheme.background
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor
        textView.textContainerInset = NSSize(width: 18, height: 14)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width,
                                                       height: .greatestFiniteMagnitude)
        textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.usesAdaptiveColorMappingForDarkAppearance = true

        scrollView.documentView = textView
        textView.delegate = context.coordinator

        let ruler = LineNumberRulerView(textView: textView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        context.coordinator.ruler = ruler
        context.coordinator.install(document: document, force: true)
        context.coordinator.syncSettings(wrapLines: wrapLines, showInvisibles: showInvisibles,
                                         fontSize: fontSize, isEditable: isEditable, force: true)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.install(document: document, force: false)
        context.coordinator.syncSettings(wrapLines: wrapLines, showInvisibles: showInvisibles,
                                         fontSize: fontSize, isEditable: isEditable, force: false)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditorView
        weak var textView: CodeTextView?
        weak var scrollView: NSScrollView?
        weak var ruler: LineNumberRulerView?

        private var currentDocID: UUID?
        private var currentVersion: UUID?
        private var currentDocument: TextFile?
        private var isProgrammatic = false
        private var highlightWork: DispatchWorkItem?
        private var lastWrap: Bool?
        private var lastInvisibles: Bool?
        private var lastFontSize: CGFloat?
        private var lastEditable: Bool?
        private var findObservers: [NSObjectProtocol] = []
        private let highlighter = SyntaxHighlighter(language: .plainText, fontSize: 13.5)

        init(parent: CodeEditorView) {
            self.parent = parent
            super.init()
            findObservers.append(NotificationCenter.default.addObserver(
                forName: EditorNotifications.find, object: nil, queue: .main
            ) { [weak self] notification in
                guard let action = notification.userInfo?["action"] as? Int else { return }
                Task { @MainActor [weak self] in self?.performFind(action: action) }
            })
            findObservers.append(NotificationCenter.default.addObserver(
                forName: EditorNotifications.goToLine, object: nil, queue: .main
            ) { [weak self] notification in
                guard let line = notification.userInfo?["line"] as? Int else { return }
                Task { @MainActor [weak self] in self?.goTo(line: line) }
            })
        }

        deinit {
            for observer in findObservers {
                NotificationCenter.default.removeObserver(observer)
            }
            highlightWork?.cancel()
        }

        func install(document: TextFile, force: Bool) {
            let isSameDocument = currentDocID == document.id
            if isSameDocument, !force, currentVersion == document.contentVersion {
                return
            }
            guard let textView else { return }

            if let old = currentDocument, old.id != document.id {
                old.savedSelection = textView.selectedRange()
                old.savedScroll = scrollView?.contentView.bounds.origin ?? .zero
                old.hasSavedViewState = true
            }

            if isSameDocument, !force, currentVersion != document.contentVersion {
                // Reloaded or decoded differently. The model has already cleared undo.
            }

            currentDocument = document
            currentDocID = document.id
            currentVersion = document.contentVersion

            isProgrammatic = true
            textView.string = document.text
            textView.font = NSFont.monospacedSystemFont(ofSize: parent.fontSize, weight: .regular)
            textView.textColor = .labelColor
            highlighter.language = document.syntax
            highlighter.fontSize = parent.fontSize
            highlighter.apply(to: textView)
            ruler?.invalidateLineStarts()
            let length = textView.string.utf16.count
            let selection = document.savedSelection
            let safeLocation = min(max(0, selection.location), length)
            let safeLength = min(max(0, selection.length), length - safeLocation)
            textView.setSelectedRange(NSRange(location: safeLocation, length: safeLength))
            isProgrammatic = false

            if let scrollView {
                if document.hasSavedViewState {
                    scrollView.contentView.scroll(to: document.savedScroll)
                    scrollView.reflectScrolledClipView(scrollView.contentView)
                } else {
                    // Large documents can otherwise be left at an arbitrary layout
                    // offset after the first layout pass. A freshly opened file
                    // should always start at the beginning.
                    DispatchQueue.main.async {
                        let x = scrollView.contentView.bounds.origin.x
                        scrollView.contentView.scroll(to: NSPoint(x: x, y: 0))
                        scrollView.reflectScrolledClipView(scrollView.contentView)
                        textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
                    }
                }
            }
            updateCursor()
            DispatchQueue.main.async { [weak self] in
                guard let self, let textView = self.textView, textView.window != nil else { return }
                textView.window?.makeFirstResponder(textView)
            }
        }

        func syncSettings(wrapLines: Bool, showInvisibles: Bool, fontSize: CGFloat,
                           isEditable: Bool, force: Bool) {
            guard let textView, let scrollView else { return }
            if force || lastEditable != isEditable {
                lastEditable = isEditable
                textView.isEditable = isEditable
                textView.isSelectable = true
            }
            if force || lastWrap != wrapLines {
                lastWrap = wrapLines
                scrollView.hasHorizontalScroller = !wrapLines
                textView.isHorizontallyResizable = !wrapLines
                textView.textContainer?.widthTracksTextView = wrapLines
                if wrapLines {
                    textView.autoresizingMask = [.width]
                    textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width,
                                                                   height: .greatestFiniteMagnitude)
                } else {
                    textView.autoresizingMask = [.height]
                    textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                                   height: .greatestFiniteMagnitude)
                }
                ruler?.needsDisplay = true
            }
            if force || lastInvisibles != showInvisibles {
                lastInvisibles = showInvisibles
                textView.layoutManager?.showsInvisibleCharacters = showInvisibles
                textView.layoutManager?.showsControlCharacters = showInvisibles
            }
            if force || lastFontSize != fontSize {
                lastFontSize = fontSize
                let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
                textView.font = font
                highlighter.fontSize = fontSize
                scheduleHighlight(delay: 0.02)
            }
        }

        // MARK: NSTextViewDelegate

        func textDidChange(_ notification: Notification) {
            guard !isProgrammatic, let textView else { return }
            currentDocument?.updateText(textView.string)
            ruler?.invalidateLineStarts()
            updateCursor()
            scheduleHighlight()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isProgrammatic else { return }
            if let textView {
                currentDocument?.savedSelection = textView.selectedRange()
                textView.needsDisplay = true
            }
            updateCursor()
            ruler?.needsDisplay = true
        }

        // MARK: Highlighting

        private func scheduleHighlight(delay: TimeInterval = 0.12) {
            highlightWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.applyHighlight()
            }
            highlightWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }

        private func applyHighlight() {
            guard let textView, !textView.hasMarkedText() else { return }
            highlighter.language = currentDocument?.syntax ?? .plainText
            highlighter.fontSize = lastFontSize ?? parent.fontSize
            highlighter.apply(to: textView)
            ruler?.invalidateLineStarts()
        }

        private func updateCursor() {
            guard let textView, let ruler else { return }
            let selection = textView.selectedRange()
            let position = ruler.lineColumn(forCharacter: selection.location)
            currentDocument?.updateCursor(line: position.line, column: position.column,
                                         selectionLength: selection.length)
        }

        // MARK: Find / go to line

        private func performFind(action: Int) {
            guard let textView else { return }
            let item = NSMenuItem()
            item.tag = action
            textView.performFindPanelAction(item)
        }

        private func goTo(line: Int) {
            guard let textView, let ruler, let range = ruler.range(forLine: line) else { return }
            textView.window?.makeFirstResponder(textView)
            textView.setSelectedRange(range)
            textView.scrollRangeToVisible(range)
            textView.showFindIndicator(for: range)
        }
    }
}
