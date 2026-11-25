import SwiftUI
import AppKit
import Quartz
import UniformTypeIdentifiers

// MARK: - Colors

extension FormatTint {
    var color: Color {
        switch self {
        case .gray: return Color(red: 0.55, green: 0.56, blue: 0.60)
        case .blue: return .blue
        case .indigo: return .indigo
        case .purple: return .purple
        case .pink: return .pink
        case .red: return .red
        case .orange: return .orange
        case .yellow: return Color(red: 0.82, green: 0.62, blue: 0.05)
        case .green: return .green
        case .teal: return .teal
        case .cyan: return .cyan
        case .mint: return .mint
        case .brown: return .brown
        }
    }
}

// MARK: - Root

struct ContentView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if store.tabs.isEmpty {
                    WelcomeView()
                } else {
                    WorkspaceView()
                }
            }
            if let toast = store.toast {
                ToastView(message: toast)
                    .padding(.bottom, 48)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .frame(minWidth: 880, minHeight: 560)
        .background(
            WindowAccessor { window in
                WindowLifecycle.shared.attach(to: window)
                window.minSize = NSSize(width: 880, height: 560)
                window.titlebarSeparatorStyle = .line
                window.tabbingMode = .disallowed
            }
        )
        .navigationTitle(store.activeDocument?.displayName ?? "文本透镜")
        .navigationSubtitle(store.windowSubtitle)
        .toolbar { toolbarContent }
        .onDrop(of: [UTType.fileURL], isTargeted: $store.isDropTargeted) { providers in
            handleDrop(providers)
            return true
        }
        .overlay {
            if store.isDropTargeted {
                DropOverlay()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.16), value: store.isDropTargeted)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: store.toast?.id)
        .alert(item: $store.alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message),
                  dismissButton: .default(Text("好")))
        }
        .sheet(item: $store.activeSheet) { sheet in
            switch sheet {
            case .hex(let payload):
                HexViewSheet(payload: payload)
            case .goToLine:
                GoToLineSheet()
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                store.newDocument()
            } label: {
                Label("新建", systemImage: "square.and.pencil")
            }
            .help("新建标签页（⌘N）")

            Button {
                store.openPanel()
            } label: {
                Label("打开", systemImage: "folder")
            }
            .help("打开任意文件（⌘O）")

            Menu {
                if store.recents.isEmpty {
                    Text("没有最近打开的文件")
                } else {
                    ForEach(store.recents.prefix(10)) { item in
                        Button {
                            store.openRecent(item)
                        } label: {
                            Text(item.name)
                        }
                    }
                }
            } label: {
                Label("最近", systemImage: "clock.arrow.circlepath")
            }
            .help("最近打开")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                store.saveActive()
            } label: {
                Label("保存", systemImage: "square.and.arrow.down")
            }
            .disabled(store.activeDocument?.canSave != true)
            .help("保存（⌘S）")

            Button {
                store.toggleInspector()
            } label: {
                Label("文件识别", systemImage: "sidebar.right")
            }
            .help("显示或隐藏文件识别检查器（⌥⌘I）")

            Menu {
                Button("重新从磁盘载入") { store.revertActive() }
                    .disabled(store.activeDocument?.url == nil)
                Button("在 Finder 中显示") { store.revealInFinder() }
                    .disabled(store.activeDocument?.url == nil)
                Button("用默认应用打开") { store.openWithDefaultApp() }
                    .disabled(store.activeDocument?.url == nil)
                Button("复制文件路径") { store.copyPath() }
                    .disabled(store.activeDocument?.url == nil)
                Divider()
                Button("查看十六进制") { store.showHex() }
                    .disabled(store.activeDocument == nil)
                Button("跳转到行…") { store.showGoToLine() }
                    .disabled(store.activeDocument?.isTextFile != true)
            } label: {
                Label("更多", systemImage: "ellipsis.circle")
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { continue }
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let value = item as? URL {
                    url = value
                } else if let string = item as? String {
                    url = URL(fileURLWithPath: string)
                }
                guard let url else { return }
                DispatchQueue.main.async {
                    AppStore.shared.open(urls: [url])
                }
            }
        }
    }
}

// MARK: - Workspace

struct WorkspaceView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            TabBarView()
            Divider()
            if let doc = store.activeDocument {
                HStack(spacing: 0) {
                    DocumentPane(document: doc)
                    if store.showInspector {
                        Divider()
                        InspectorView(document: doc)
                            .frame(width: 326)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
            } else {
                WelcomeView()
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(.easeInOut(duration: 0.2), value: store.showInspector)
    }
}

// MARK: - Tab bar

struct TabBarView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ScrollViewReader { proxy in
            HStack(spacing: 4) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(store.tabs) { doc in
                            TabItemView(doc: doc, isActive: store.activeID == doc.id)
                                .id(doc.id)
                        }
                    }
                    .padding(.horizontal, 8)
                }
                Button {
                    store.newDocument()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("新建标签页（⌘N）")
                .padding(.trailing, 8)
            }
            .frame(height: 38)
            .background(.bar)
            .onChange(of: store.activeID) { _, id in
                guard let id else { return }
                withAnimation(.easeInOut(duration: 0.18)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }
}

struct TabItemView: View {
    @ObservedObject var doc: TextFile
    @EnvironmentObject private var store: AppStore
    var isActive: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(doc.format.tint.color)
                .frame(width: 7, height: 7)
            Text(doc.displayName)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 185, alignment: .leading)
            if doc.isDirty {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
                    .help("未保存")
            }
            Button {
                store.closeTab(doc)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8.5, weight: .bold))
                    .frame(width: 16, height: 16)
                    .background(
                        Circle().fill(hovering || isActive ? Color.primary.opacity(0.08) : .clear)
                    )
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(hovering || isActive ? 1 : 0)
            .help("关闭标签页")
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isActive ? Color(nsColor: .textBackgroundColor) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(isActive ? Color.primary.opacity(0.09) : .clear, lineWidth: 1)
        )
        .overlay(alignment: .top) {
            if isActive {
                Capsule()
                    .fill(doc.format.tint.color)
                    .frame(width: 20, height: 2)
                    .offset(y: -0.5)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { store.activate(doc) }
        .onHover { hovering = $0 }
        .help(doc.path)
        .contextMenu {
            Button("关闭") { store.closeTab(doc) }
            Divider()
            Button("在 Finder 中显示") { store.revealInFinder(doc) }
                .disabled(doc.url == nil)
            Button("复制路径") { store.copyPath(doc) }
                .disabled(doc.url == nil)
        }
    }
}

// MARK: - Document pane

struct DocumentPane: View {
    @ObservedObject var document: TextFile
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            DocumentHeader(document: document)
            Divider()
            if let session = document.ropeSession {
                RopeEditorPane(session: session)
                    .id(ObjectIdentifier(session))
                if document.externalChange {
                    ExternalChangeBar(document: document)
                }
            } else if let session = document.largeSession {
                LargeFilePagedPane(session: session)
                if document.externalChange {
                    ExternalChangeBar(document: document)
                }
            } else {
                content
                if document.externalChange {
                    ExternalChangeBar(document: document)
                }
                if document.isTextFile && document.isEditable && document.isLargeFile {
                    LargeFileBar()
                }
                if document.isTextFile && !document.isEditable {
                    ReadOnlyBar(document: document)
                }
                Divider()
                StatusBar(document: document)
            }
        }
        .background(Color(nsColor: EditorTheme.background))
    }

    @ViewBuilder
    private var content: some View {
        switch document.loadState {
        case .loading:
            LoadingPane(document: document)
        case .failed:
            ErrorPane(document: document)
        case .idle:
            Color.clear
        case .ready:
            if document.isTextFile {
                CodeEditorView(
                    document: document,
                    wrapLines: store.wrapLines,
                    showInvisibles: store.showInvisibles,
                    fontSize: store.fontSize,
                    isEditable: document.isEditable
                )
            } else if let url = document.url {
                QuickLookPane(url: url, document: document)
                    .id(url)
            } else {
                ErrorPane(document: document)
            }
        }
    }
}

struct DocumentHeader: View {
    @ObservedObject var document: TextFile
    @EnvironmentObject private var store: AppStore

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(document.format.tint.color.opacity(0.14))
                    .frame(width: 29, height: 29)
                Image(systemName: document.format.symbol)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(document.format.tint.color)
            }

            VStack(alignment: .leading, spacing: 1.5) {
                HStack(spacing: 6) {
                    Text(document.isUntitled ? "纯文本" : document.format.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                    TypePill(text: document.isTextFile ? "文本" : "二进制",
                             tint: document.isTextFile ? .green : .secondary)
                    if !document.urlPathExtension.isEmpty {
                        TypePill(text: document.urlPathExtension, tint: .secondary)
                    }
                    if document.probe?.mismatch == true {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                            .help("扩展名与实际内容不一致，以内容判定为准")
                    }
                    if document.isLargeFile {
                        TypePill(text: "大文件", tint: .blue)
                    }
                }
                Text(document.path)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 12)

            HStack(spacing: 10) {
                if document.isDirty {
                    HStack(spacing: 4) {
                        Circle().fill(Color.orange).frame(width: 5, height: 5)
                        Text("未保存")
                    }
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.orange)
                } else if document.lastSavedAt != nil {
                    Text("已保存")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                } else if document.isRopeMode {
                    Text("可编辑窗口")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                } else if !document.isEditable {
                    Text("只读")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Text(FileFormatting.bytes(document.fileSize))
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }
}

private extension TextFile {
    var urlPathExtension: String {
        guard let ext = url?.pathExtension.lowercased(), !ext.isEmpty else { return "" }
        return ".\(ext)"
    }
}

struct TypePill: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 5.5)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.11)))
            .foregroundStyle(tint == .secondary ? Color.secondary : tint)
    }
}

// MARK: - Status bar

struct StatusBar: View {
    @ObservedObject var document: TextFile
    @EnvironmentObject private var store: AppStore

    var body: some View {
        HStack(spacing: 12) {
            if document.isTextFile {
                Text("Ln \(document.cursorLine), Col \(document.cursorColumn)")
                    .monospacedDigit()
                if document.selectionLength > 0 {
                    Text("\(document.selectionLength) 选中")
                        .foregroundStyle(.secondary)
                }
                Text(document.stats.words > 0
                     ? "\(document.stats.lines) 行 · \(document.stats.characters) 字符 · \(document.stats.words) 词"
                     : "\(document.stats.lines) 行 · \(document.stats.characters) 字符")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 6)

                Text(document.syntax.label)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)

                encodingMenu
                lineEndingMenu

                if !document.isEditable {
                    Label("只读", systemImage: "lock")
                        .foregroundStyle(.secondary)
                }
            } else {
                Label("只读二进制预览", systemImage: "lock")
                    .foregroundStyle(.secondary)
                Text(FileFormatting.bytes(document.fileSize))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 6)
                Label("二进制", systemImage: "shippingbox")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 10.5))
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(.bar)
    }

    private var encodingMenu: some View {
        Menu {
            Section("Unicode") {
                ForEach([TextEncoding.utf8, .utf16LE, .utf16BE, .utf32LE, .utf32BE], id: \.self) { encoding in
                    encodingButton(encoding)
                }
            }
            Section("中文") {
                ForEach([TextEncoding.gb18030, .big5], id: \.self) { encoding in
                    encodingButton(encoding)
                }
            }
            Section("日文 / 韩文") {
                ForEach([TextEncoding.shiftJIS, .eucJP, .eucKR], id: \.self) { encoding in
                    encodingButton(encoding)
                }
            }
            Section("西欧") {
                ForEach([TextEncoding.windows1252, .isoLatin1, .macRoman], id: \.self) { encoding in
                    encodingButton(encoding)
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(document.encoding.shortLabel)
                if document.hasBOM { Text("BOM").foregroundStyle(.tertiary) }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("选择编码；切换后会按新编码重新解释磁盘字节")
    }

    private func encodingButton(_ encoding: TextEncoding) -> some View {
        Button {
            store.chooseEncoding(encoding, for: document)
        } label: {
            if encoding == document.encoding {
                Label(encoding.label, systemImage: "checkmark")
            } else {
                Text(encoding.label)
            }
        }
    }

    private var lineEndingMenu: some View {
        Menu {
            ForEach([LineEnding.lf, .crlf, .cr], id: \.self) { ending in
                Button {
                    store.setLineEnding(ending, for: document)
                } label: {
                    if ending == document.lineEnding {
                        Label(ending.longLabel, systemImage: "checkmark")
                    } else {
                        Text(ending.longLabel)
                    }
                }
            }
            if document.lineEnding == .mixed || document.lineEnding == .none {
                Divider()
                Text(document.lineEnding.longLabel)
            }
        } label: {
            HStack(spacing: 3) {
                Text(document.lineEnding.label)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("保存时使用的换行符")
    }
}

// MARK: - Bars

struct LargeFileBar: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.horizontal.circle")
                .foregroundStyle(.blue)
            Text("大文件模式")
                .font(.system(size: 11, weight: .semibold))
            Text("已关闭语法高亮与词数统计，编辑和保存仍会保留原编码。")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(Color.blue.opacity(0.07))
        .overlay(alignment: .top) { Divider() }
    }
}

struct ExternalChangeBar: View {
    @ObservedObject var document: TextFile
    @EnvironmentObject private var store: AppStore

    var body: some View {
        NoticeBar(
            symbol: "arrow.triangle.2.circlepath",
            tint: .orange,
            title: document.isMissingOnDisk ? "磁盘上的文件已被删除" : "磁盘上的文件已在外部修改",
            detail: document.isDirty ? "保存会覆盖外部版本" : "重新载入以查看最新内容",
            primaryTitle: "重新载入",
            primaryAction: { store.revertActive() },
            secondaryTitle: "忽略",
            secondaryAction: { document.acknowledgeExternalChange() }
        )
    }
}

struct ReadOnlyBar: View {
    @ObservedObject var document: TextFile
    @EnvironmentObject private var store: AppStore

    var body: some View {
        NoticeBar(
            symbol: document.decodeHadErrors ? "exclamationmark.triangle.fill" : "lock.fill",
            tint: document.isTruncated ? .blue : (document.decodeHadErrors ? .orange : .secondary),
            title: document.isTruncated
                ? "只读预览"
                : (document.decodeHadErrors ? "解码不完整" : "二进制文件"),
            detail: document.readOnlyReason ?? "这个文件不能在文本编辑器中直接保存。",
            primaryTitle: "用默认应用打开",
            primaryAction: { store.openWithDefaultApp(document) },
            secondaryTitle: nil,
            secondaryAction: nil
        )
    }
}

struct NoticeBar: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String
    let primaryTitle: String
    let primaryAction: () -> Void
    let secondaryTitle: String?
    let secondaryAction: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
            Text(detail)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button(primaryTitle, action: primaryAction)
                .controlSize(.small)
            if let secondaryTitle, let secondaryAction {
                Button(secondaryTitle, action: secondaryAction)
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(tint.opacity(0.09))
        .overlay(alignment: .top) { Divider() }
    }
}

// MARK: - Panes

struct LoadingPane: View {
    @ObservedObject var document: TextFile

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.small)
            Text("正在读取并识别 \(document.displayName)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(document.path)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 460)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: EditorTheme.background))
    }
}

struct ErrorPane: View {
    @ObservedObject var document: TextFile
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.orange)
            Text("无法打开这个文件")
                .font(.system(size: 14, weight: .semibold))
            Text(document.errorMessage ?? "未知错误")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            HStack(spacing: 10) {
                Button("重试") {
                    Task { await document.load() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Button("关闭标签页") {
                    store.closeTab(document)
                }
                .controlSize(.small)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: EditorTheme.background))
    }
}

struct QuickLookPane: View {
    let url: URL
    @ObservedObject var document: TextFile
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ZStack(alignment: .bottom) {
            QuickLookView(url: url)
                .background(Color(nsColor: .windowBackgroundColor))
            HStack(spacing: 10) {
                Image(systemName: document.format.symbol)
                    .foregroundStyle(document.format.tint.color)
                Text(document.format.name)
                    .font(.system(size: 11, weight: .medium))
                Text(document.probe?.mime ?? "")
                    .font(.system(size: 10).monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button("查看十六进制") { store.showHex(document) }
                    .controlSize(.small)
                Button("用默认应用打开") { store.openWithDefaultApp(document) }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial)
            .overlay(alignment: .top) { Divider() }
        }
    }
}

struct QuickLookView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        view.autostarts = true
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        view.previewItem = url as NSURL
        view.refreshPreviewItem()
    }
}

// MARK: - Toast

struct ToastView: View {
    let message: ToastMessage

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: message.symbol)
                .foregroundStyle(.green)
            Text(message.text)
                .font(.system(size: 11.5, weight: .medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }
}

// MARK: - Drop overlay

struct DropOverlay: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).opacity(0.75)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .padding(22)
            VStack(spacing: 12) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(Color.accentColor)
                Text("松开即可打开")
                    .font(.system(size: 18, weight: .semibold))
                Text("可以是文本、源代码、配置、无扩展名，或任何未知格式")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Window accessor and close guard

struct WindowAccessor: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window, !context.coordinator.configured {
                context.coordinator.configured = true
                configure(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard !context.coordinator.configured else { return }
        DispatchQueue.main.async {
            if let window = nsView.window {
                context.coordinator.configured = true
                configure(window)
            }
        }
    }

    final class Coordinator {
        var configured = false
    }
}

@MainActor
final class WindowLifecycle: NSObject {
    static let shared = WindowLifecycle()
    private var windows: [ObjectIdentifier: NSWindow] = [:]
    private var observers: [NSObjectProtocol] = []
    private var confirmedClose: Set<ObjectIdentifier> = []
    private var isTerminating = false
    private(set) var isPromptingClose = false

    func attach(to window: NSWindow) {
        let id = ObjectIdentifier(window)
        guard windows[id] == nil else { return }
        windows[id] = window
        window.isReleasedWhenClosed = false
        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self, weak window] _ in
            guard let window else { return }
            Task { @MainActor in
                self?.windowWillClose(window)
            }
        }
        observers.append(observer)
    }

    func markTerminating() {
        isTerminating = true
    }

    private func windowWillClose(_ window: NSWindow) {
        let id = ObjectIdentifier(window)
        if confirmedClose.remove(id) != nil { return }
        guard !isTerminating else { return }
        guard AppStore.shared.hasUnsavedChanges else { return }

        // The red close button has already ordered the window out at this point.
        // Bring it back immediately, then ask. Cancel keeps the window open; save
        // or discard closes it again for real.
        isPromptingClose = true
        DispatchQueue.main.async {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            let shouldClose = AppStore.shared.confirmDiscardUnsaved()
            self.isPromptingClose = false
            if shouldClose {
                self.confirmedClose.insert(id)
                window.close()
            }
        }
    }
}


struct SheetWindowStyler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.isOpaque = true
            window.backgroundColor = .windowBackgroundColor
            window.hasShadow = true
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Sheets

struct HexViewSheet: View {
    let payload: HexPayload
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            VStack(spacing: 0) {
                sheetHeader
                Divider()
                hexContent
            }
        }
        .frame(width: 780, height: 520)
        .presentationBackground(Color(nsColor: .windowBackgroundColor))
        .background(SheetWindowStyler())
    }

    private var sheetHeader: some View {
        HStack(spacing: 10) {
                Image(systemName: "number")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(payload.title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(payload.subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        FileFormatting.hexDump(payload.data, maxBytes: payload.data.count),
                        forType: .string
                    )
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
                .controlSize(.small)
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.cancelAction)
        }
        .padding(14)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var hexContent: some View {
        GeometryReader { geometry in
            ScrollView([.vertical, .horizontal]) {
                Text(FileFormatting.hexDump(payload.data, maxBytes: payload.data.count))
                    .font(.system(size: 11.5, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(14)
                    .frame(minWidth: geometry.size.width, minHeight: geometry.size.height,
                           alignment: .topLeading)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

struct GoToLineSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var value = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("跳转到行")
                .font(.system(size: 14, weight: .semibold))
            Text("输入行号，按回车跳转。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("行号", text: $value)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .onSubmit(go)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("跳转", action: go)
                    .keyboardShortcut(.defaultAction)
                    .disabled(Int(value) == nil)
            }
        }
        .padding(20)
        .frame(width: 300)
        .presentationBackground(Color(nsColor: .windowBackgroundColor))
        .background(SheetWindowStyler())
    }

    private func go() {
        guard let line = Int(value), line > 0 else { return }
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            store.requestGoToLine(line)
        }
    }
}
