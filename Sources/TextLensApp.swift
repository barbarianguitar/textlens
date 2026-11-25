import SwiftUI
import AppKit

@main
enum TextLensLauncher {
    static func main() {
        if CommandLineTool.handle() {
            return
        }
        TextLensApp.main()
    }
}

struct TextLensApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = AppStore.shared

    var body: some Scene {
        Window("文本透镜", id: "main") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 880, minHeight: 560)
                .onAppear {
                    appDelegate.store = store
                    appDelegate.drainPendingFiles()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    store.checkExternalChanges()
                }
        }
        .defaultSize(width: 1180, height: 780)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            TextLensCommands()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: AppStore?
    private var pendingFiles: [URL] = []
    private var didFinishLaunching = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if ProcessInfo.processInfo.arguments.contains("--light") {
            NSApp.appearance = NSAppearance(named: .aqua)
        } else if ProcessInfo.processInfo.arguments.contains("--dark") {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        didFinishLaunching = true
        store = AppStore.shared

        // Support launching from a terminal as `TextLens path/to/file`.
        for argument in CommandLine.arguments.dropFirst() where !argument.hasPrefix("-") {
            let url = URL(fileURLWithPath: argument).standardizedFileURL
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
               !isDirectory.boolValue {
                pendingFiles.append(url)
            }
        }
        drainPendingFiles()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let store {
            store.open(urls: urls)
        } else {
            pendingFiles.append(contentsOf: urls)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func drainPendingFiles() {
        guard didFinishLaunching, !pendingFiles.isEmpty else { return }
        let urls = pendingFiles
        pendingFiles.removeAll()
        store?.open(urls: urls)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Closing the last window already has its own save/discard prompt
        // (WindowLifecycle reopens the window and asks). Don't stack a second one.
        if WindowLifecycle.shared.isPromptingClose {
            return .terminateCancel
        }
        guard let store else { return .terminateNow }
        if store.confirmDiscardUnsaved() {
            WindowLifecycle.shared.markTerminating()
            return .terminateNow
        }
        return .terminateCancel
    }
}

struct TextLensCommands: Commands {
    @ObservedObject private var store = AppStore.shared

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("新建标签页") { store.newDocument() }
                .keyboardShortcut("n", modifiers: .command)
            Button("打开…") { store.openPanel() }
                .keyboardShortcut("o", modifiers: .command)
            Menu("打开最近") {
                if store.recents.isEmpty {
                    Text("没有最近文件")
                } else {
                    ForEach(store.recents.prefix(10)) { item in
                        Button(item.name) { store.openRecent(item) }
                    }
                    Divider()
                    Button("清除最近记录") { store.clearRecents() }
                }
            }
        }

        CommandGroup(replacing: .saveItem) {
            Button("保存") { store.saveActive() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(store.activeDocument?.canSave != true)
            Button("另存为…") { store.saveAsActive() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(store.activeDocument?.isEditable != true)
        }

        CommandGroup(after: .saveItem) {
            Divider()
            Button("关闭标签页") { store.closeActiveTab() }
                .keyboardShortcut("w", modifiers: .command)
                .disabled(store.activeDocument == nil)
            Button("下一个标签页") { store.selectNextTab() }
                .keyboardShortcut(.tab, modifiers: .control)
                .disabled(store.tabs.count < 2)
            Button("上一个标签页") { store.selectPreviousTab() }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
                .disabled(store.tabs.count < 2)
            Divider()
            Button("重新从磁盘载入") { store.revertActive() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(store.activeDocument?.url == nil)
            Button("在 Finder 中显示") { store.revealInFinder() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(store.activeDocument?.url == nil)
            Button("用默认应用打开") { store.openWithDefaultApp() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(store.activeDocument?.url == nil)
            Button("复制文件路径") { store.copyPath() }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(store.activeDocument?.url == nil)
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            Button("查找…") { store.showFind() }
                .keyboardShortcut("f", modifiers: .command)
            Button("查找下一个") { store.findNext() }
                .keyboardShortcut("g", modifiers: .command)
            Button("查找上一个") { store.findPrevious() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            Button("跳转到行…") { store.showGoToLine() }
                .keyboardShortcut("l", modifiers: .command)
                .disabled(store.activeDocument?.isTextFile != true)
        }

        CommandMenu("编码") {
            Button("以 UTF-8 重新解码") { setEncoding(.utf8) }
            Button("以 GB18030 重新解码") { setEncoding(.gb18030) }
            Button("以 Big5 重新解码") { setEncoding(.big5) }
            Button("以 Shift_JIS 重新解码") { setEncoding(.shiftJIS) }
            Button("以 UTF-16 LE 重新解码") { setEncoding(.utf16LE) }
            Button("以 Windows-1252 重新解码") { setEncoding(.windows1252) }
            Divider()
            Menu("更多编码") {
                ForEach(TextEncoding.allCases, id: \.self) { encoding in
                    Button(encoding.label) { setEncoding(encoding) }
                }
            }
            Divider()
            Menu("保存时换行符") {
                Button("LF（Unix / macOS）") { setEnding(.lf) }
                Button("CRLF（Windows）") { setEnding(.crlf) }
                Button("CR（经典 Mac）") { setEnding(.cr) }
            }
            .disabled(store.activeDocument?.isTextFile != true)
        }

        CommandGroup(after: .toolbar) {
            Divider()
            Button(store.showInspector ? "隐藏文件识别" : "显示文件识别") {
                store.toggleInspector()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            Button(store.wrapLines ? "关闭自动换行" : "自动换行") { store.toggleWrap() }
                .keyboardShortcut("w", modifiers: [.command, .option])
            Button(store.showInvisibles ? "隐藏不可见字符" : "显示不可见字符") {
                store.toggleInvisibles()
            }
            .keyboardShortcut("u", modifiers: [.command, .option])
            Divider()
            Button("放大") { store.zoomIn() }
                .keyboardShortcut("+", modifiers: .command)
            Button("缩小") { store.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
            Button("实际大小") { store.resetZoom() }
                .keyboardShortcut("0", modifiers: .command)
            Divider()
            Button("查看十六进制") { store.showHex() }
                .disabled(store.activeDocument == nil)
        }
    }

    private func setEncoding(_ encoding: TextEncoding) {
        guard let doc = store.activeDocument, doc.isTextFile else { return }
        store.chooseEncoding(encoding, for: doc)
    }

    private func setEnding(_ ending: LineEnding) {
        guard let doc = store.activeDocument, doc.isTextFile else { return }
        store.setLineEnding(ending, for: doc)
    }
}
