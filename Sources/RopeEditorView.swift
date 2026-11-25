import SwiftUI
import AppKit
import ObjectiveC

// MARK: - Search field

enum RopeSearchFieldRegistry {
    static weak var activeField: NSSearchField?
}

struct RopeSearchField: NSViewRepresentable {
    @Binding var text: String
    let focusToken: Int
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = "在文件中查找"
        field.font = .systemFont(ofSize: 11.5)
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.submit)
        field.sendsSearchStringImmediately = true
        RopeSearchFieldRegistry.activeField = field
        objc_setAssociatedObject(field, "textlens.search.coordinator",
                                 context.coordinator, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        context.coordinator.observe(field)
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken
            DispatchQueue.main.async {
                field.window?.makeFirstResponder(field)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: RopeSearchField
        var lastFocusToken = -1
        private var observer: NSObjectProtocol?

        init(_ parent: RopeSearchField) { self.parent = parent }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }

        func observe(_ field: NSSearchField) {
            observer = NotificationCenter.default.addObserver(
                forName: NSControl.textDidChangeNotification, object: field, queue: .main
            ) { [weak self, weak field] _ in
                Task { @MainActor [weak self, weak field] in
                    guard let self, let field else { return }
                    self.parent.text = field.stringValue
                }
            }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            parent.text = field.stringValue
        }

        @objc func submit() {
            parent.onSubmit()
        }
    }
}

// MARK: - Read-only continuous window

struct RopeWindowTextView: NSViewRepresentable {
    static var viewportProvider: (() -> Int?)?

    let window: PieceTableDocument.Window
    let fontSize: CGFloat
    let scrollTargetLine: Int?
    let highlightLine: Int?
    let onVisibleTopLine: (Int) -> Void
    let onReachTop: () -> Void
    let onReachBottom: () -> Void
    let onApproachStart: () -> Void
    let onApproachEnd: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor.textBackgroundColor

        let textView = NSTextView()
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = true
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.textColor = .textColor
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        scrollView.documentView = textView

        let ruler = LineNumberRulerView(textView: textView)
        ruler.numberFont = NSFont.monospacedDigitSystemFont(ofSize: max(9, fontSize - 1.5), weight: .regular)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        context.coordinator.textView = textView
        context.coordinator.ruler = ruler
        RopeWindowTextView.viewportProvider = { [weak coordinator = context.coordinator] in
            coordinator?.currentVisibleTopLine()
        }
        objc_setAssociatedObject(scrollView, "textlens.rope.coordinator",
                                 context.coordinator, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        context.coordinator.startBoundaryTimer()
        context.coordinator.onVisibleTopLine = onVisibleTopLine
        context.coordinator.onReachTop = onReachTop
        context.coordinator.onReachBottom = onReachBottom
        context.coordinator.onApproachStart = onApproachStart
        context.coordinator.onApproachEnd = onApproachEnd
        ruler.onScroll = { [weak coordinator = context.coordinator] in
            coordinator?.scrollChanged()
        }
        context.coordinator.apply(window: window, fontSize: fontSize,
                                  scrollTargetLine: scrollTargetLine,
                                  highlightLine: highlightLine, force: true)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onVisibleTopLine = onVisibleTopLine
        context.coordinator.onReachTop = onReachTop
        context.coordinator.onReachBottom = onReachBottom
        context.coordinator.onApproachStart = onApproachStart
        context.coordinator.onApproachEnd = onApproachEnd
        context.coordinator.apply(window: window, fontSize: fontSize,
                                  scrollTargetLine: scrollTargetLine,
                                  highlightLine: highlightLine, force: false)
    }

    @MainActor
    final class Coordinator {
        weak var textView: NSTextView?
        weak var ruler: LineNumberRulerView?

        deinit {
            boundaryTimer?.invalidate()
        }

        func startBoundaryTimer() {
            boundaryTimer?.invalidate()
            let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.pollBoundary()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            boundaryTimer = timer
        }
        private var windowID: UUID?
        private var lastFontSize: CGFloat?
        private var lastScrollTarget: Int?
        private var lastHighlight: Int?
        private var didTriggerTop = false
        private var didTriggerBottom = false
        private var hasScrolled = false
        private var suppressBoundaryUntil = CFAbsoluteTimeGetCurrent()
        private var lastObservedY: CGFloat = -1
        private var stableSince = Date()
        private var boundaryTimer: Timer?
        var onVisibleTopLine: ((Int) -> Void)?
        var onReachTop: (() -> Void)?
        var onReachBottom: (() -> Void)?
        var onApproachStart: (() -> Void)?
        var onApproachEnd: (() -> Void)?
        private var didRequestPrefetchForward = false
        private var didRequestPrefetchBackward = false

        func apply(window: PieceTableDocument.Window, fontSize: CGFloat,
                   scrollTargetLine: Int?, highlightLine: Int?, force: Bool) {
            guard let textView, let scrollView = textView.enclosingScrollView else { return }
            let isNewWindow = force || windowID != window.id
            if isNewWindow, !force, windowID != nil,
               window.text.utf16.count > textView.string.utf16.count,
               window.text.hasPrefix(textView.string) {
                let suffix = String(window.text.dropFirst(textView.string.count))
                if !suffix.isEmpty {
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: textView.font ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
                        .foregroundColor: textView.textColor ?? NSColor.textColor
                    ]
                    textView.textStorage?.append(NSAttributedString(string: suffix, attributes: attributes))
                    windowID = window.id
                    didRequestPrefetchForward = false
                    didRequestPrefetchBackward = false
                    ruler?.invalidateLineStarts()
                    return
                }
            }
            if isNewWindow, !force, windowID != nil,
               window.text.utf16.count > textView.string.utf16.count,
               window.text.hasSuffix(textView.string),
               let target = scrollTargetLine {
                let prefix = String(window.text.dropLast(textView.string.count))
                if !prefix.isEmpty {
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: textView.font ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
                        .foregroundColor: textView.textColor ?? NSColor.textColor
                    ]
                    textView.textStorage?.insert(NSAttributedString(string: prefix, attributes: attributes), at: 0)
                    windowID = window.id
                    didRequestPrefetchForward = false
                    didRequestPrefetchBackward = false
                    ruler?.lineOffset = window.startLine - 1
                    ruler?.invalidateLineStarts()
                    scroll(toLine: target, window: window, scrollView: scrollView, textView: textView)
                    return
                }
            }
            if isNewWindow {
                windowID = window.id
                didRequestPrefetchForward = false
                didRequestPrefetchBackward = false
                let target = min(max(scrollTargetLine ?? window.startLine,
                                     window.startLine), window.endLine)
                didTriggerTop = target <= window.startLine + 1
                didTriggerBottom = target >= window.endLine - 1
                hasScrolled = false
                suppressBoundaryUntil = CFAbsoluteTimeGetCurrent() + 0.8
                lastObservedY = -1
                stableSince = Date()
                textView.string = window.text
                textView.setSelectedRange(NSRange(location: 0, length: 0))
                ruler?.lineOffset = window.startLine - 1
                ruler?.invalidateLineStarts()
            }
            if isNewWindow || lastFontSize != fontSize {
                lastFontSize = fontSize
                textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
                ruler?.numberFont = .monospacedDigitSystemFont(ofSize: max(9, fontSize - 1.5),
                                                               weight: .regular)
                textView.textContainer?.containerSize =
                    NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
            }
            if let target = scrollTargetLine, isNewWindow || lastScrollTarget != target {
                lastScrollTarget = target
                scroll(toLine: target, window: window, scrollView: scrollView, textView: textView)
            }
            if let line = highlightLine, isNewWindow || lastHighlight != line {
                lastHighlight = line
                select(line: line, window: window, scrollView: scrollView, textView: textView)
            } else if highlightLine == nil {
                lastHighlight = nil
            }
            if isNewWindow, let target = scrollTargetLine {
                // NSTextView may not have laid out the whole replacement yet
                // when the first scroll happens. Do one explicit follow-up
                // scroll/selection after layout, which is the second step the
                // jump needs to land on the requested line.
                let expectedID = window.id
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                    guard let self, self.windowID == expectedID else { return }
                    self.scroll(toLine: target, window: window,
                                scrollView: scrollView, textView: textView)
                    self.select(line: target, window: window,
                                scrollView: scrollView, textView: textView)
                }
            }
        }

        private func select(line: Int, window: PieceTableDocument.Window,
                            scrollView: NSScrollView, textView: NSTextView) {
            guard let ruler, let start = ruler.characterIndex(forLine: line) else { return }
            let next = ruler.characterIndex(forLine: line + 1) ?? textView.string.utf16.count
            let length = max(0, next - start)
            let range = NSRange(location: min(start, textView.string.utf16.count),
                                length: max(0, min(length, textView.string.utf16.count - start)))
            textView.setSelectedRange(range)
            textView.scrollRangeToVisible(range)
        }

        private func scroll(toLine line: Int, window: PieceTableDocument.Window,
                            scrollView: NSScrollView, textView: NSTextView) {
            guard let ruler else { return }
            // Never fall through to the bottom of the newly loaded window. If
            // the anchor is just outside this window, clamp it to the nearest
            // line so the reader stays at the same logical position.
            let clampedLine = min(max(line, window.startLine), window.endLine)
            guard let location = ruler.characterIndex(forLine: clampedLine),
                  location <= textView.string.utf16.count else {
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: 0))
                scrollView.reflectScrolledClipView(scrollView.contentView)
                return
            }
            let length = (textView.string as NSString).length
            let safeLocation = min(location, length)
            suppressBoundaryUntil = max(suppressBoundaryUntil,
                                        CFAbsoluteTimeGetCurrent() + 0.8)
            let range = NSRange(location: safeLocation, length: 0)
            textView.scrollRangeToVisible(range)
            if let layout = textView.layoutManager, let container = textView.textContainer {
                let glyph = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                let rect = layout.boundingRect(forGlyphRange: glyph, in: container)
                let y = max(0, rect.minY)
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
            reportVisibleTop(textView: textView, scrollView: scrollView)
        }

        func scrollChanged() {
            guard let textView, let scrollView = textView.enclosingScrollView else { return }
            let visible = scrollView.contentView.bounds
            let maxY = max(0, textView.frame.height - visible.height)
            guard maxY > 240 else { return }
            if visible.minY > 12 { hasScrolled = true }
            reportVisibleTop(textView: textView, scrollView: scrollView)
            if visible.minY < maxY - 100 { didTriggerBottom = false }
            if visible.minY > 80 { didTriggerTop = false }
            let margin = max(visible.height * 2.0, textView.frame.height * 0.10)
            let distanceBottom = maxY - visible.minY
            if distanceBottom < margin {
                if !didRequestPrefetchForward {
                    didRequestPrefetchForward = true
                    onApproachEnd?()
                }
            } else if distanceBottom > margin * 1.5 {
                didRequestPrefetchForward = false
            }
            let distanceTop = visible.minY
            if distanceTop < margin {
                if !didRequestPrefetchBackward {
                    didRequestPrefetchBackward = true
                    onApproachStart?()
                }
            } else if distanceTop > margin * 1.5 {
                didRequestPrefetchBackward = false
            }
        }

        /// Polling avoids depending on scroll notifications, which can be
        /// coalesced during trackpad momentum. A boundary is loaded only after
        /// the viewport has been still at that boundary for a short time.
        private func pollBoundary() {
            guard let textView, let scrollView = textView.enclosingScrollView else { return }
            let visible = scrollView.contentView.bounds
            let maxY = max(0, textView.frame.height - visible.height)
            guard maxY > 240 else { return }
            if abs(visible.minY - lastObservedY) > 0.5 {
                lastObservedY = visible.minY
                stableSince = Date()
                return
            }
            guard Date().timeIntervalSince(stableSince) >= 0.55,
                  CFAbsoluteTimeGetCurrent() >= suppressBoundaryUntil else { return }
            if visible.minY >= maxY - 12, !didTriggerBottom {
                didTriggerBottom = true
                onReachBottom?()
            } else if visible.minY < maxY - 100 {
                didTriggerBottom = false
            }
            if visible.minY <= 2, hasScrolled, !didTriggerTop {
                didTriggerTop = true
                onReachTop?()
            } else if visible.minY > 80 {
                didTriggerTop = false
            }
        }

        func currentVisibleTopLine() -> Int? {
            guard let textView, let scrollView = textView.enclosingScrollView else { return nil }
            let y = scrollView.contentView.bounds.minY + 1
            let point = NSPoint(x: 2, y: y)
            let index = textView.characterIndexForInsertion(at: point)
            return ruler?.lineNumber(at: index)
        }

        private func reportVisibleTop(textView: NSTextView, scrollView: NSScrollView) {
            let y = scrollView.contentView.bounds.minY + 1
            let point = NSPoint(x: 2, y: y)
            let index = textView.characterIndexForInsertion(at: point)
            let line = ruler?.lineNumber(at: index) ?? 1
            onVisibleTopLine?(line)
        }
    }
}

// MARK: - Editable window sheet

struct RopeEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let initialText: String
    let startLine: Int
    let onApply: (String) -> Void
    @State private var text: String

    init(initialText: String, startLine: Int, onApply: @escaping (String) -> Void) {
        self.initialText = initialText
        self.startLine = startLine
        self.onApply = onApply
        _text = State(initialValue: initialText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("编辑当前窗口")
                    .font(.system(size: 14, weight: .semibold))
                Text("仅修改这个窗口；应用后会更新 Piece Table")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            EditableRopeTextView(text: $text, lineOffset: startLine - 1)
                .frame(minWidth: 760, minHeight: 480)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("应用到文档") {
                    onApply(text)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 900, height: 620)
    }
}

struct EditableRopeTextView: NSViewRepresentable {
    @Binding var text: String
    let lineOffset: Int

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .lineBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor.textBackgroundColor

        let textView = NSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = context.coordinator
        textView.string = text
        scrollView.documentView = textView
        let ruler = LineNumberRulerView(textView: textView)
        ruler.numberFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        ruler.lineOffset = lineOffset
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text, !context.coordinator.isEditing {
            textView.string = text
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: EditableRopeTextView
        weak var textView: NSTextView?
        var isEditing = false

        init(_ parent: EditableRopeTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            isEditing = true
            parent.text = textView.string
            isEditing = false
        }
    }
}

// MARK: - Main pane

struct RopeEditorPane: View {
    @ObservedObject var session: RopeEditorSession
    @EnvironmentObject private var store: AppStore
    @State private var showEdit = false
    @State private var showJump = false
    @State private var jumpText = ""
    @State private var query = ""
    @State private var caseSensitive = false
    @State private var searchScope: LargeFileSearchScope = .wholeFile
    @State private var showCustomRange = false
    @State private var customStartLine = ""
    @State private var customEndLine = ""
    @State private var searchFocusToken = 0

    var body: some View { paneContent }

    private var paneContent: some View {
        VStack(spacing: 0) {
            header
            Divider()
            searchBar
            if session.isSearching || !session.searchResults.isEmpty {
                searchResultsPanel
                Divider()
            }
            if session.isLoading, session.window == nil {
                ProgressView("正在加载窗口…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let window = session.window {
                RopeWindowTextView(window: window,
                                   fontSize: store.fontSize,
                                   scrollTargetLine: session.scrollTargetLine,
                                   highlightLine: session.highlightLine,
                                   onVisibleTopLine: { line in
                                       session.visibleTopLine = line
                                   },
                                   onReachTop: {},
                                   onReachBottom: {},
                                   onApproachStart: {
                                       let top = RopeWindowTextView.viewportProvider?() ?? session.visibleTopLine
                                       session.prefetchBackward(visibleLine: top)
                                   },
                                   onApproachEnd: {
                                       let top = RopeWindowTextView.viewportProvider?() ?? session.visibleTopLine
                                       session.prefetchForward(visibleLine: top)
                                   })
                    .overlay(alignment: .topTrailing) {
                        if session.isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .padding(8)
                        }
                    }
            } else {
                Text(session.errorMessage ?? "无法加载文件")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            statusBar
        }
        .background(Color(nsColor: .textBackgroundColor))
        .sheet(isPresented: $showEdit) {
            if let window = session.window {
                RopeEditSheet(initialText: window.text, startLine: window.startLine) { text in
                    session.applyWindowText(text)
                }
            }
        }
        .sheet(isPresented: $showJump) {
            RopeJumpSheet(totalLines: session.totalLines, text: $jumpText) { line in
                session.jump(toLine: line)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorNotifications.goToLine)) { _ in
            jumpText = ""
            showJump = true
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorNotifications.find)) { _ in
            searchFocusToken &+= 1
        }
        .sheet(isPresented: $showCustomRange) {
            LargeFileSearchRangeSheet(startLine: customStartLine,
                                      endLine: customEndLine) { start, end in
                customStartLine = String(start)
                customEndLine = String(end)
                searchScope = .customLines
                let fieldText = RopeSearchFieldRegistry.activeField?.stringValue ?? query
                if !fieldText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    runSearch()
                }
            }
        }
        .onAppear { session.loadInitial() }
    }

    private var searchBar: some View {
        HStack(spacing: 7) {
            Menu {
                ForEach(LargeFileSearchScope.allCases) { scope in
                    Button {
                        if scope == .customLines {
                            DispatchQueue.main.async { showCustomRange = true }
                        } else {
                            searchScope = scope
                        }
                    } label: {
                        if searchScope == scope {
                            Label(scope.label, systemImage: "checkmark")
                        } else {
                            Text(scope.label)
                        }
                    }
                }
            } label: {
                Label(searchScope.shortLabel, systemImage: "scope")
                    .font(.system(size: 9.5, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
            RopeSearchField(text: $query, focusToken: searchFocusToken,
                            onSubmit: { runSearch() })
                .frame(maxWidth: .infinity)
            Button {
                caseSensitive.toggle()
            } label: {
                Text("Aa")
                    .font(.system(size: 10, weight: caseSensitive ? .bold : .regular))
                    .foregroundStyle(caseSensitive ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)
            .help("区分大小写")
            if session.isSearching {
                ProgressView()
                    .controlSize(.small)
                Button("停止") { session.clearSearch() }
                    .controlSize(.small)
            } else {
                Button("查找") { runSearch() }
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.bar)
    }

    private var searchResultsPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("\(session.searchResults.count) 个结果")
                    .font(.system(size: 10.5, weight: .semibold))
                Text(session.activeSearchScopeLabel)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button {
                    RopeSearchFieldRegistry.activeField?.stringValue = ""
                    query = ""
                    session.clearSearch()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .semibold))
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(session.searchResults.indices, id: \.self) { index in
                        let result = session.searchResults[index]
                        Button {
                            session.jump(toLine: result.line)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("L\(result.line)")
                                    .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 62, alignment: .trailing)
                                Text(result.preview)
                                    .font(.system(size: 10.5).monospaced())
                                    .lineLimit(1)
                                    .foregroundStyle(.primary)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 150)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func runSearch() {
        let value = (RopeSearchFieldRegistry.activeField?.stringValue ?? query)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            session.clearSearch()
            return
        }
        session.search(query: value, caseSensitive: caseSensitive,
                       scope: searchScope,
                       customStartLine: Int(customStartLine),
                       customEndLine: Int(customEndLine))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "rectangle.split.3x1")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if let window = session.window {
                Text("连续窗口  第 \(window.startLine.formatted())–\(window.endLine.formatted()) 行")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
            }
            Spacer()
            Button {
                jumpText = ""
                showJump = true
            } label: {
                Label("跳转", systemImage: "number")
            }
            .buttonStyle(.borderless)
            .help("跳转到行")
            Button {
                showEdit = true
            } label: {
                Label("编辑窗口", systemImage: "square.and.pencil")
            }
            .buttonStyle(.borderless)
            .disabled(session.window == nil || session.isLoading)
            .help("编辑当前窗口")
            if session.isDirty {
                Circle().fill(Color.orange).frame(width: 6, height: 6)
                    .help("有未保存修改")
            }
            Button {
                session.save()
            } label: {
                Label("保存", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderless)
            .disabled(!session.isDirty || session.isSaving)
            .help("流式写回")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
        .alert("保存失败", isPresented: Binding(
            get: { session.saveError != nil },
            set: { if !$0 { session.clearSaveError() } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(session.saveError ?? "")
        }
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            Text("只读查看 · 可编辑窗口")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text("窗口 \(session.window.map { "\($0.startLine.formatted())–\($0.endLine.formatted())" } ?? "—")")
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.tertiary)
            Spacer()
            Text(session.encodingLabel)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text("\(session.totalLines.formatted()) 行")
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.bar)
    }
}

struct RopeJumpSheet: View {
    @Environment(\.dismiss) private var dismiss
    let totalLines: Int
    @Binding var text: String
    let onJump: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("跳转到行")
                .font(.system(size: 13, weight: .semibold))
            Text("共 \(totalLines.formatted()) 行")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            TextField("行号", text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit { jump() }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("跳转") { jump() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(Int(text) == nil)
            }
        }
        .padding(18)
        .frame(width: 280)
    }

    private func jump() {
        guard let line = Int(text), line >= 1 else { return }
        dismiss()
        onJump(min(line, totalLines))
    }
}
