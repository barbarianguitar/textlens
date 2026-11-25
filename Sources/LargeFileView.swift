import SwiftUI
import AppKit

struct LargeFilePagedPane: View {
    @ObservedObject var session: LargeFileSession
    @EnvironmentObject private var store: AppStore
    @State private var query = ""
    @State private var caseSensitive = false
    @State private var showJump = false
    @State private var searchScope: LargeFileSearchScope = .wholeFile
    @State private var showCustomRange = false
    @State private var customStartLine = ""
    @State private var customEndLine = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            navigationBar
            Divider()
            pageContent
            if session.isSearching || !session.searchResults.isEmpty || session.searchLimitReached {
                Divider()
                searchResultsPanel
            }
            Divider()
            statusBar
        }
        .background(Color(nsColor: EditorTheme.background))
        .onAppear {
            Task { await session.loadFirstPageIfNeeded() }
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorNotifications.find)) { _ in
            searchFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: EditorNotifications.goToLine)) { _ in
            showJump = true
        }
        .sheet(isPresented: $showJump) {
            LargeFileJumpSheet(session: session)
        }
        .sheet(isPresented: $showCustomRange) {
            LargeFileSearchRangeSheet(startLine: customStartLine,
                                      endLine: customEndLine) { start, end in
                customStartLine = String(start)
                customEndLine = String(end)
                searchScope = .customLines
                if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    runSearch()
                }
            }
        }
    }

    private var navigationBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Button {
                    session.previousPage()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                .disabled(!session.canGoBack || session.isLoadingPage)
                .help("上一页")

                Button {
                    session.nextPage()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
                .disabled(!session.canGoForward || session.isLoadingPage)
                .help("下一页")

                if let page = session.page {
                    Text("第 \(page.startLine)–\(page.endLine) 行")
                        .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                    if let total = session.totalLines {
                        Text("/ 共 \(total) 行")
                            .font(.system(size: 10.5).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                if session.isIndexing {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在建立行索引…")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 6)

                Button {
                    showJump = true
                } label: {
                    Label("跳转到行", systemImage: "number")
                        .font(.system(size: 10.5))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("按行号跳转（首次使用会建立行索引）")

                Button {
                    session.clearSearch()
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .opacity(session.searchResults.isEmpty ? 0 : 1)
                .disabled(session.searchResults.isEmpty)
                .help("清除搜索结果")
            }
            .padding(.horizontal, 12)
            .frame(height: 31)

            HStack(spacing: 7) {
                Menu {
                    ForEach(LargeFileSearchScope.allCases) { scope in
                        Button {
                            if scope == .customLines {
                                DispatchQueue.main.async {
                                    showCustomRange = true
                                }
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
                .help("搜索范围")
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                TextField("在文件中查找", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11.5))
                    .focused($searchFocused)
                    .onSubmit { runSearch() }
                    .onKeyPress(.return) {
                        runSearch()
                        return .handled
                    }
                Toggle("Aa", isOn: $caseSensitive)
                    .toggleStyle(.button)
                    .buttonStyle(.borderless)
                    .font(.system(size: 9.5, weight: .medium))
                    .help("区分大小写")
                if session.isSearching {
                    ProgressView(value: session.searchProgress)
                        .frame(width: 60)
                    Button("停止") { session.cancelSearch() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                } else {
                    Button("查找") { runSearch() }
                        .controlSize(.small)
                        .keyboardShortcut(.defaultAction)
                        .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        if let page = session.page {
            LargePageTextView(page: page, highlight: session.highlight, fontSize: store.fontSize,
                              scrollToBottom: session.scrollToBottomOnPageChange,
                              onReachTop: { session.previousPage() },
                              onReachBottom: { session.nextPage() })
                .overlay(alignment: .topTrailing) {
                    if session.isLoadingPage {
                        ProgressView()
                            .controlSize(.small)
                            .padding(10)
                    }
                }
        } else if let error = session.pageError {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 24))
                    .foregroundStyle(.orange)
                Text(error)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                Button("重试") {
                    Task { await session.loadFirstPageIfNeeded() }
                }
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("正在载入第一页…")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var searchResultsPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("\(session.searchResults.count) 个结果")
                    .font(.system(size: 10.5, weight: .semibold))
                Text(session.activeSearchScopeLabel)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                if session.searchLimitReached {
                    Text("仅显示前 \(session.searchResults.count) 条")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.orange)
                }
                Spacer()
                if session.isSearching {
                    Text("\(Int(session.searchProgress * 100))%")
                        .font(.system(size: 9.5).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Button {
                    session.clearSearch()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("关闭搜索结果")
            }
            .padding(.horizontal, 12)
            .frame(height: 28)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(session.searchResults) { result in
                        Button {
                            session.jump(to: result)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 9) {
                                Text("L\(result.line)")
                                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 58, alignment: .trailing)
                                Text(result.preview)
                                    .font(.system(size: 10.5))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(session.highlight?.id == result.id
                                    ? Color.accentColor.opacity(0.12) : Color.clear)
                        Divider().padding(.leading, 76)
                    }
                }
            }
            .frame(height: 172)
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.55))
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            Label("只读分页", systemImage: "lock")
                .foregroundStyle(.secondary)
            if let page = session.page, session.reader.size > 0 {
                Text("位置 \(Int(Double(page.startOffset) / Double(session.reader.size) * 100))%")
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                if page.cutMidLine {
                    Text("超长行跨页")
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 6)
            if let error = session.indexError {
                Text(error)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
            Text(session.encodingLabel)
                .foregroundStyle(.secondary)
            Text(FileFormatting.bytes(session.reader.size))
                .foregroundStyle(.tertiary)
            Text("每页 2 MB")
                .foregroundStyle(.tertiary)
        }
        .font(.system(size: 10))
        .padding(.horizontal, 12)
        .frame(height: 25)
        .background(.bar)
    }

    private func runSearch() {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            session.clearSearch()
            return
        }
        session.search(query: value, caseSensitive: caseSensitive,
                       scope: searchScope,
                       customStartLine: Int(customStartLine),
                       customEndLine: Int(customEndLine))
    }
}

// MARK: - Read-only page text view

struct LargePageTextView: NSViewRepresentable {
    let page: LargeFilePage
    let highlight: LargeFileSearchResult?
    let fontSize: CGFloat
    var scrollToBottom = false
    var onReachTop: (() -> Void)? = nil
    var onReachBottom: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator()
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

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFindBar = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.drawsBackground = true
        textView.backgroundColor = EditorTheme.background
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 18, height: 14)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width,
                                                       height: .greatestFiniteMagnitude)
        textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.usesAdaptiveColorMappingForDarkAppearance = true

        scrollView.documentView = textView
        let ruler = LineNumberRulerView(textView: textView)
        ruler.lineOffset = page.startLine - 1
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        context.coordinator.textView = textView
        context.coordinator.ruler = ruler
        context.coordinator.pageID = page.id
        context.coordinator.onReachTop = onReachTop
        context.coordinator.onReachBottom = onReachBottom
        let coordinator = context.coordinator
        ruler.onScroll = { [weak coordinator] in
            coordinator?.checkScrollBoundary()
        }
        coordinator.apply(page: page, highlight: highlight, scrollView: scrollView,
                          fontSize: fontSize, scrollToBottom: scrollToBottom, force: true)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onReachTop = onReachTop
        context.coordinator.onReachBottom = onReachBottom
        context.coordinator.apply(page: page, highlight: highlight, scrollView: scrollView,
                                  fontSize: fontSize, scrollToBottom: scrollToBottom, force: false)
    }

    @MainActor
    final class Coordinator {
        weak var textView: NSTextView?
        weak var ruler: LineNumberRulerView?
        var pageID: UUID?
        var lastFontSize: CGFloat?
        var onReachTop: (() -> Void)?
        var onReachBottom: (() -> Void)?
        private var didTriggerTop = false
        private var didTriggerBottom = false
        private var hasScrolledAwayFromTop = false

        func checkScrollBoundary() {
            guard let textView, let scrollView = textView.enclosingScrollView else { return }
            let visible = scrollView.contentView.bounds
            let maxY = max(0, textView.frame.height - visible.height)
            guard maxY > 240 else {
                didTriggerBottom = false
                return
            }
            if visible.minY > 30 {
                hasScrolledAwayFromTop = true
            }
            if visible.minY >= maxY - 10 {
                if !didTriggerBottom {
                    didTriggerBottom = true
                    onReachBottom?()
                }
            } else if visible.minY < maxY - 80 {
                didTriggerBottom = false
            }
            if visible.minY <= 2, hasScrolledAwayFromTop, !didTriggerTop {
                didTriggerTop = true
                onReachTop?()
            }
        }

        func apply(page: LargeFilePage, highlight: LargeFileSearchResult?,
                   scrollView: NSScrollView, fontSize: CGFloat,
                   scrollToBottom: Bool, force: Bool) {
            guard let textView else { return }
            let isNewPage = force || pageID != page.id
            if isNewPage {
                pageID = page.id
                didTriggerTop = false
                didTriggerBottom = false
                hasScrolledAwayFromTop = false
                textView.string = page.text
                ruler?.lineOffset = page.startLine - 1
                ruler?.invalidateLineStarts()
                textView.setSelectedRange(NSRange(location: 0, length: 0))
                DispatchQueue.main.async {
                    let x = scrollView.contentView.bounds.origin.x
                    let y: CGFloat
                    if scrollToBottom {
                        y = max(0, textView.frame.height - scrollView.contentView.bounds.height)
                        self.didTriggerBottom = true
                        self.hasScrolledAwayFromTop = true
                    } else {
                        y = 0
                    }
                    scrollView.contentView.scroll(to: NSPoint(x: x, y: y))
                    scrollView.reflectScrolledClipView(scrollView.contentView)
                }
            }
            if lastFontSize != fontSize {
                lastFontSize = fontSize
                textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            }
            if let highlight {
                highlightMatch(highlight, in: textView)
            }
        }

        private func highlightMatch(_ result: LargeFileSearchResult, in textView: NSTextView) {
            let localLine = result.line - result.pageStartLine
            guard localLine >= 0, !textView.string.isEmpty else { return }
            let ns = textView.string as NSString
            var starts = [0]
            var index = 0
            while index < ns.length {
                let found = ns.range(of: "\n", options: [],
                                     range: NSRange(location: index, length: ns.length - index))
                if found.location == NSNotFound { break }
                starts.append(found.location + 1)
                index = found.location + 1
            }
            guard localLine < starts.count else { return }
            let lineStart = starts[localLine]
            let lineEnd = localLine + 1 < starts.count ? starts[localLine + 1] - 1 : ns.length
            let location = min(lineStart + max(0, result.column - 1), lineEnd)
            let length = result.matchLength > 0
                ? min(result.matchLength, max(0, lineEnd - location)) : 0
            let range = NSRange(location: location, length: length)
            textView.setSelectedRange(range)
            textView.scrollRangeToVisible(range)
            if length > 0 {
                textView.showFindIndicator(for: range)
            }
        }
    }
}

// MARK: - Search range sheet

struct LargeFileSearchRangeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var startText: String
    @State private var endText: String
    let onApply: (Int, Int) -> Void

    init(startLine: String, endLine: String, onApply: @escaping (Int, Int) -> Void) {
        _startText = State(initialValue: startLine)
        _endText = State(initialValue: endLine)
        self.onApply = onApply
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("搜索行范围")
                .font(.system(size: 14, weight: .semibold))
            Text("行号从 1 开始；首次使用会建立行索引。")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                TextField("起始行", text: $startText)
                    .textFieldStyle(.roundedBorder)
                Text("到")
                    .foregroundStyle(.secondary)
                TextField("结束行", text: $endText)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("使用此范围") { apply() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 330)
        .presentationBackground(Color(nsColor: .windowBackgroundColor))
    }

    private var isValid: Bool {
        guard let start = Int(startText), let end = Int(endText) else { return false }
        return start >= 1 && end >= start
    }

    private func apply() {
        guard let start = Int(startText), let end = Int(endText) else { return }
        dismiss()
        onApply(start, end)
    }
}

// MARK: - Jump sheet

struct LargeFileJumpSheet: View {
    @ObservedObject var session: LargeFileSession
    @Environment(\.dismiss) private var dismiss
    @State private var lineText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("跳转到行")
                .font(.system(size: 14, weight: .semibold))
            Text("首次使用会建立稀疏行索引，之后跳转很快。")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            TextField("行号", text: $lineText)
                .textFieldStyle(.roundedBorder)
                .onSubmit(go)
            if session.isIndexing {
                ProgressView()
                    .controlSize(.small)
                Text("正在建立行索引…")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            if let error = session.indexError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("跳转", action: go)
                    .keyboardShortcut(.defaultAction)
                    .disabled(Int(lineText) == nil)
            }
        }
        .padding(20)
        .frame(width: 320)
        .presentationBackground(Color(nsColor: .windowBackgroundColor))
    }

    private func go() {
        guard let line = Int(lineText), line > 0 else { return }
        dismiss()
        session.jump(toLine: line)
    }
}
