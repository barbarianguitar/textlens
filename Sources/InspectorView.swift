import SwiftUI
import AppKit

struct InspectorView: View {
    @ObservedObject var document: TextFile
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    typeHero
                    if document.probe?.mismatch == true {
                        mismatchCard
                    }
                    evidenceSection
                    fileSection
                    if document.isTextFile {
                        textSection
                    }
                    bytesSection
                }
                .padding(14)
                .padding(.bottom, 12)
            }
        }
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("文件识别")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                store.revertActive()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(document.url == nil)
            .help("重新读取并检测（会丢弃未保存更改）")

            Button {
                store.toggleInspector()
            } label: {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("隐藏检查器（⌥⌘I）")
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
    }

    private var typeHero: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(document.format.tint.color.opacity(0.14))
                        .frame(width: 46, height: 46)
                    Image(systemName: document.format.symbol)
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(document.format.tint.color)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(document.format.name)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Text(document.format.category.label)
                        Text("·")
                        Text(document.isTextFile
                             ? (document.isEditable
                                ? "可编辑文本"
                                : (document.isRopeMode ? "窗口编辑" : (document.isPagedMode ? "只读分页" : "只读文本")))
                             : "二进制预览")
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            if let probe = document.probe {
                let confidence = document.isTextFile ? probe.textConfidence : probe.textConfidence
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(document.isTextFile ? "文本判定" : "非文本判定")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int((confidence * 100).rounded()))%")
                            .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                            .foregroundStyle(confidenceColor(confidence))
                    }
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.07))
                            Capsule()
                                .fill(confidenceColor(confidence))
                                .frame(width: max(3, geometry.size.width * confidence))
                        }
                    }
                    .frame(height: 4)
                }
            }
        }
    }

    private var mismatchCard: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text("扩展名与实际内容不一致")
                    .font(.system(size: 10.5, weight: .semibold))
                Text("已以文件内容为准。\(document.probe?.warnings.first ?? "")")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.09)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.orange.opacity(0.18)))
    }

    private var evidenceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("判定依据")
            VStack(alignment: .leading, spacing: 0) {
                if let evidence = document.probe?.evidence, !evidence.isEmpty {
                    ForEach(Array(evidence.prefix(9).enumerated()), id: \.offset) { index, item in
                        EvidenceRow(evidence: item)
                        if index < min(evidence.count, 9) - 1 {
                            Divider().padding(.leading, 24)
                        }
                    }
                } else {
                    Text("尚未获得检测信息")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 5)
                }
            }
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.026)))
        }
    }

    private var fileSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("文件")
            VStack(spacing: 0) {
                InfoRow("格式", document.format.name)
                InfoRow("分类", document.format.category.label)
                InfoRow("MIME", document.probe?.mime ?? "—", selectable: true)
                InfoRow("UTI", document.probe?.uti ?? "—", selectable: true)
                InfoRow("扩展名", document.url?.pathExtension.isEmpty == false
                        ? ".\(document.url!.pathExtension.lowercased())" : "无")
                InfoRow("大小", FileFormatting.bytes(document.fileSize))
                InfoRow("修改", FileFormatting.date(document.lastModified))
                InfoRow("创建", FileFormatting.date(document.createdAt))
                if let permissions = document.permissions, !permissions.isEmpty {
                    InfoRow("权限", permissions)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("路径")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                            .frame(width: 58, alignment: .leading)
                        Spacer()
                        Button {
                            store.copyPath(document)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 9.5))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tertiary)
                        .disabled(document.url == nil)
                    }
                    Text(document.path)
                        .font(.system(size: 9.5).monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(3)
                }
                .padding(.vertical, 4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.026)))
        }
    }

    private var textSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("文本")
            VStack(spacing: 0) {
                HStack {
                    Text("编码")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .frame(width: 58, alignment: .leading)
                    Spacer()
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
                            Text(document.encoding.label)
                                .font(.system(size: 10, weight: .medium))
                            if document.hasBOM {
                                Text("BOM")
                                    .font(.system(size: 8.5, weight: .medium))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(Color.blue.opacity(0.12)))
                                    .foregroundStyle(.blue)
                            }
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 7))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                .padding(.vertical, 5)

                InfoRow("换行", lineEndingDescription)
                InfoRow("语法", document.syntax.label)
                if document.isRopeMode {
                    InfoRow("模式", "连续窗口 · Piece Table")
                } else if document.isPagedMode {
                    InfoRow("模式", "只读分页 · 2 MB/页")
                } else {
                    InfoRow("字符", "\(document.stats.characters)")
                    InfoRow("行 / 词", "\(document.stats.lines) / \(document.stats.words)")
                    if document.isTruncated {
                        InfoRow("模式", "只读预览")
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.026)))

            Text("切换编码会按新编码重新解释磁盘上的原始字节，可用于修复乱码；保存时会使用当前编码。")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(1.5)
        }
    }

    private var bytesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("字节签名")
            VStack(alignment: .leading, spacing: 7) {
                if let signatures = document.probe?.signatures, !signatures.isEmpty {
                    ForEach(signatures.prefix(5), id: \.label) { signature in
                        HStack(alignment: .top, spacing: 7) {
                            Image(systemName: signature.textual ? "text.alignleft" : "doc")
                                .font(.system(size: 9.5))
                                .foregroundStyle(.secondary)
                                .frame(width: 13)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(signature.label)
                                    .font(.system(size: 9.5, weight: .medium))
                                Text("偏移 \(signature.offset) · \(signature.hex)")
                                    .font(.system(size: 8.5, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        }
                    }
                } else {
                    Text("没有匹配到已知文件头。对于文本文件而言这很正常。")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    store.showHex(document)
                } label: {
                    Label("查看十六进制", systemImage: "number")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .padding(.top, 1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.026)))
        }
    }

    private var lineEndingDescription: String {
        switch document.lineEnding {
        case .lf: return "LF · Unix"
        case .crlf: return "CRLF · Windows"
        case .cr: return "CR · 经典 Mac"
        case .mixed: return "混合 · 保存为 LF"
        case .none: return "无换行"
        }
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

    private func confidenceColor(_ value: Double) -> Color {
        if value >= 0.85 { return .green }
        if value >= 0.6 { return .orange }
        return .red
    }
}

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)
    }
}

struct InfoRow: View {
    let key: String
    let value: String
    var selectable = false

    init(_ key: String, _ value: String, selectable: Bool = false) {
        self.key = key
        self.value = value
        self.selectable = selectable
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(key)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
            Spacer(minLength: 4)
            Group {
                if selectable {
                    Text(value).textSelection(.enabled)
                } else {
                    Text(value)
                }
            }
            .font(.system(size: 9.5))
            .foregroundStyle(.primary)
            .lineLimit(2)
            .multilineTextAlignment(.trailing)
            .help(value)
        }
        .padding(.vertical, 4)
    }
}

struct EvidenceRow: View {
    let evidence: DetectionEvidence

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 9.5))
                .foregroundStyle(tint)
                .frame(width: 13)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(evidence.title)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = evidence.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 8.5))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private var icon: String {
        switch evidence.kind {
        case .positive: return "checkmark.circle.fill"
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch evidence.kind {
        case .positive: return .green
        case .info: return .secondary
        case .warning: return .orange
        }
    }
}
