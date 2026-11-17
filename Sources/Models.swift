import AppKit
import Carbon
import CryptoKit

// MARK: - 剪贴板条目

enum ClipKind: String, Codable {
    case text
    case image
    case files
}

struct ClipItem: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var kind: ClipKind
    var text: String? = nil
    var imageFile: String? = nil
    var imageWidth: Int? = nil
    var imageHeight: Int? = nil
    var filePaths: [String]? = nil
    var contentHash: String
    var date: Date = Date()
    var pinned: Bool = false
    var sourceApp: String? = nil
    var sourceBundleID: String? = nil
}

extension ClipItem {
    /// 列表里显示的单行标题
    var title: String {
        switch kind {
        case .text:
            let head = (text ?? "").prefix(300)
            let lines = head.split(whereSeparator: { $0.isNewline })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            return lines.isEmpty ? "（空白文本）" : lines.joined(separator: " ↵ ")
        case .image:
            return "图片 \(imageWidth ?? 0) × \(imageHeight ?? 0)"
        case .files:
            let names = (filePaths ?? []).map { ($0 as NSString).lastPathComponent }
            if names.count > 1 { return "\(names[0]) 等 \(names.count) 个文件" }
            return names.first ?? "文件"
        }
    }

    /// 搜索时匹配的文字
    var searchText: String {
        switch kind {
        case .text: return text ?? ""
        case .image: return "图片 image"
        case .files: return (filePaths ?? []).joined(separator: "\n")
        }
    }

    var isURL: Bool {
        guard kind == .text, let t = text?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return (t.hasPrefix("http://") || t.hasPrefix("https://")) && !t.contains(where: { $0.isWhitespace })
    }

    /// 预览区底部的详细信息
    var detail: String {
        switch kind {
        case .text:
            let t = text ?? ""
            let lineCount = t.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }).count
            return "文本 · \(t.count) 字符 · \(lineCount) 行"
        case .image:
            return "图片 · \(imageWidth ?? 0) × \(imageHeight ?? 0) 像素"
        case .files:
            return "\((filePaths ?? []).count) 个文件"
        }
    }

    /// 列表第二行：来源应用 · 多久之前
    var subtitle: String {
        var parts: [String] = []
        if let app = sourceApp, !app.isEmpty { parts.append(app) }
        parts.append(Formatters.relative(date))
        return parts.joined(separator: " · ")
    }
}

// MARK: - 工具

enum Hashing {
    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func sha256(_ string: String) -> String {
        sha256(Data(string.utf8))
    }
}

enum Formatters {
    static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.unitsStyle = .short
        return f
    }()

    static let fullFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static func relative(_ date: Date) -> String {
        if Date().timeIntervalSince(date) < 60 { return "刚刚" }
        return relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - 设置

struct HotKeyPreset {
    let title: String
    let keyCode: UInt32
    let modifiers: UInt32
}

final class AppSettings {
    static let shared = AppSettings()

    static let hotKeyPresets: [HotKeyPreset] = [
        HotKeyPreset(title: "⌘⇧V", keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | shiftKey)),
        HotKeyPreset(title: "⌥⌘V", keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | optionKey)),
        HotKeyPreset(title: "⌃⌘V", keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | controlKey)),
        HotKeyPreset(title: "⌘⇧C", keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(cmdKey | shiftKey)),
        HotKeyPreset(title: "⌥Space", keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)),
    ]

    static let maxItemOptions = [100, 300, 500, 1000]

    private let defaults = UserDefaults.standard

    private init() {
        defaults.register(defaults: [
            "autoPaste": true,
            "maxItems": 300,
            "hotKeyIndex": 0,
            "paused": false,
        ])
    }

    var autoPaste: Bool {
        get { defaults.bool(forKey: "autoPaste") }
        set { defaults.set(newValue, forKey: "autoPaste") }
    }

    var paused: Bool {
        get { defaults.bool(forKey: "paused") }
        set { defaults.set(newValue, forKey: "paused") }
    }

    var maxItems: Int {
        get { max(10, defaults.integer(forKey: "maxItems")) }
        set { defaults.set(newValue, forKey: "maxItems") }
    }

    var hotKeyIndex: Int {
        get {
            let i = defaults.integer(forKey: "hotKeyIndex")
            return AppSettings.hotKeyPresets.indices.contains(i) ? i : 0
        }
        set { defaults.set(newValue, forKey: "hotKeyIndex") }
    }

    var hotKey: HotKeyPreset { AppSettings.hotKeyPresets[hotKeyIndex] }
}
