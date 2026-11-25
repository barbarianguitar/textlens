import SwiftUI
import AppKit

struct WelcomeView: View {
    @EnvironmentObject private var store: AppStore
    @State private var appeared = false

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        ZStack {
            background
            ScrollView {
                VStack(spacing: 0) {
                    hero
                        .padding(.top, 38)
                    actionButtons
                        .padding(.top, 22)
                    dropCard
                        .padding(.top, 26)
                    recentSection
                        .padding(.top, 30)
                    featureCards
                        .padding(.top, 22)
                    footerHints
                        .padding(.top, 26)
                }
                .frame(maxWidth: 780)
                .padding(.horizontal, 36)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity)
                .offset(y: appeared ? 0 : 8)
                .opacity(appeared ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.35)) { appeared = true }
        }
    }

    private var background: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(
                colors: [
                    Color.indigo.opacity(0.14),
                    Color(nsColor: .windowBackgroundColor).opacity(0.2),
                    Color.teal.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color.indigo.opacity(0.12))
                .frame(width: 480, height: 480)
                .blur(radius: 100)
                .offset(x: -330, y: -260)
            Circle()
                .fill(Color.teal.opacity(0.10))
                .frame(width: 420, height: 420)
                .blur(radius: 110)
                .offset(x: 360, y: 300)
        }
        .ignoresSafeArea()
    }

    private var hero: some View {
        VStack(spacing: 10) {
            appIcon
                .padding(.bottom, 4)
            Text("TEXTLENS")
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .tracking(2.4)
                .foregroundStyle(.tertiary)
            Text("文本透镜")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text("先看懂文件，再打开它。")
                .font(.system(size: 16.5, weight: .medium))
                .foregroundStyle(.secondary)
            Text("不迷信扩展名。判断内容是不是文本，识别真实格式与编码，然后直接查看、编辑和保存。")
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 500)
                .padding(.top, 2)
        }
    }

    private var appIcon: some View {
        Group {
            if let image = NSApp.applicationIconImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: "doc.text.magnifyingglass")
                    .resizable()
                    .scaledToFit()
                    .padding(18)
                    .foregroundStyle(.white)
                    .background(
                        LinearGradient(colors: [.indigo, .blue], startPoint: .topLeading,
                                       endPoint: .bottomTrailing)
                    )
            }
        }
        .frame(width: 86, height: 86)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button {
                store.openPanel()
            } label: {
                Label("打开文件…", systemImage: "folder.fill")
                    .font(.system(size: 12.5, weight: .semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Color.accentColor))
                    .foregroundStyle(.white)
                    .shadow(color: Color.accentColor.opacity(0.28), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("o", modifiers: .command)

            Button {
                store.newDocument()
            } label: {
                Label("新建文本", systemImage: "square.and.pencil")
                    .font(.system(size: 12.5, weight: .medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Color.primary.opacity(0.055)))
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.10), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: .command)
        }
    }

    private var dropCard: some View {
        HStack(spacing: 13) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.11))
                    .frame(width: 40, height: 40)
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("把文件拖到这里")
                    .font(.system(size: 12, weight: .semibold))
                Text("任意后缀、无后缀、配置文件或二进制文件都可以")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("⌘O")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.05)))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(
                    store.isDropTargeted ? Color.accentColor : Color.primary.opacity(0.12),
                    style: StrokeStyle(lineWidth: store.isDropTargeted ? 2 : 1, dash: [6, 5])
                )
        )
        .animation(.easeOut(duration: 0.15), value: store.isDropTargeted)
    }

    @ViewBuilder
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("最近打开")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !store.recents.isEmpty {
                    Button("清除") { store.clearRecents() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
            }
            if store.recents.isEmpty {
                emptyRecentHint
            } else {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(store.recents.prefix(8)) { item in
                        RecentFileCard(item: item)
                    }
                }
            }
        }
    }

    private var emptyRecentHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .foregroundStyle(.tertiary)
            Text("打开过的文件会出现在这里，方便下次一步直达。")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.025)))
    }

    private var featureCards: some View {
        HStack(spacing: 10) {
            FeatureCard(symbol: "wand.and.stars", tint: .indigo,
                        title: "不只看后缀",
                        detail: "同时检查文件头、字节分布与可解码性，识别真实格式。")
            FeatureCard(symbol: "textformat.abc", tint: .teal,
                        title: "读懂编码",
                        detail: "UTF-8、GB18030、Big5、Shift_JIS、UTF-16 等自动判定。")
            FeatureCard(symbol: "lock.open", tint: .orange,
                        title: "精确保存",
                        detail: "保留原编码、BOM 与换行风格，可作为普通文本直接改。")
        }
    }

    private var footerHints: some View {
        HStack(spacing: 16) {
            hint("⌘S", "保存")
            hint("⌘F", "查找")
            hint("⌘L", "跳转到行")
            hint("⌥⌘I", "文件识别")
        }
        .padding(.top, 4)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.055)))
            Text(label)
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
        }
    }
}

struct FeatureCard: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.primary.opacity(0.028))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

struct RecentFileCard: View {
    @EnvironmentObject private var store: AppStore
    let item: RecentFile
    @State private var hovering = false

    var body: some View {
        Button {
            store.openRecent(item)
        } label: {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(item.tint.color.opacity(0.13))
                        .frame(width: 30, height: 30)
                    Image(systemName: FileCatalog.format(forID: item.formatID)?.symbol ?? "doc")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(item.tint.color)
                }
                VStack(alignment: .leading, spacing: 1.5) {
                    Text(item.name)
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(item.formatName)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(relative(item.lastOpened))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(hovering ? Color.primary.opacity(0.055) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(item.exists ? 1 : 0.5)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("打开") { store.openRecent(item) }
            Button("在 Finder 中显示") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
            Button("从列表中移除") { store.removeRecent(item) }
        }
        .help(item.path)
    }

    private func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
