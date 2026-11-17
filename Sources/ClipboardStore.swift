import AppKit
import Combine

/// 剪贴板历史，存在 ~/Library/Application Support/Xiaotie/
final class ClipboardStore: ObservableObject {
    static let shared = ClipboardStore()

    @Published private(set) var items: [ClipItem] = []

    let baseURL: URL
    let imagesURL: URL
    private let historyURL: URL
    private var pendingSave: DispatchWorkItem?

    private init() {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        baseURL = support.appendingPathComponent("Xiaotie", isDirectory: true)
        imagesURL = baseURL.appendingPathComponent("images", isDirectory: true)
        historyURL = baseURL.appendingPathComponent("history.json")
        ClipboardStore.migrateLegacyData(from: support.appendingPathComponent("ClipKeeper", isDirectory: true),
                                         to: baseURL)
        try? fm.createDirectory(at: imagesURL, withIntermediateDirectories: true)
        load()
    }

    /// 以前叫 ClipKeeper 时的数据搬到新文件夹（只搬一次）
    private static func migrateLegacyData(from old: URL, to new: URL) {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: new.appendingPathComponent("history.json").path),
              fm.fileExists(atPath: old.appendingPathComponent("history.json").path) else { return }
        try? fm.createDirectory(at: new, withIntermediateDirectories: true)
        for name in ["history.json", "images"] {
            let src = old.appendingPathComponent(name)
            let dst = new.appendingPathComponent(name)
            guard fm.fileExists(atPath: src.path) else { continue }
            if fm.fileExists(atPath: dst.path) { try? fm.removeItem(at: dst) }
            do {
                try fm.moveItem(at: src, to: dst)
            } catch {
                NSLog("Xiaotie: 迁移 \(name) 失败 \(error)")
            }
        }
        if let rest = try? fm.contentsOfDirectory(atPath: old.path),
           rest.filter({ $0 != ".DS_Store" }).isEmpty {
            try? fm.removeItem(at: old)
        }
    }

    // MARK: 读写磁盘

    private func load() {
        let fm = FileManager.default
        guard let data = try? Data(contentsOf: historyURL) else { return }
        do {
            items = try JSONDecoder().decode([ClipItem].self, from: data)
        } catch {
            // 文件损坏：备份一份，别直接覆盖
            let backup = baseURL.appendingPathComponent("history.broken-\(Int(Date().timeIntervalSince1970)).json")
            try? fm.moveItem(at: historyURL, to: backup)
            return
        }
        // 清理没人引用的图片文件
        let referenced = Set(items.compactMap { $0.imageFile })
        if let files = try? fm.contentsOfDirectory(atPath: imagesURL.path) {
            for name in files where !referenced.contains(name) {
                try? fm.removeItem(at: imagesURL.appendingPathComponent(name))
            }
        }
    }

    func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        guard let data = try? JSONEncoder().encode(items) else { return }
        do {
            try data.write(to: historyURL, options: .atomic)
            // 只有自己能读
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: historyURL.path)
        } catch {
            NSLog("Xiaotie: 保存失败 \(error)")
        }
    }

    // MARK: 增删改

    func imageURL(for item: ClipItem) -> URL? {
        guard let name = item.imageFile else { return nil }
        return imagesURL.appendingPathComponent(name)
    }

    /// 如果已经有相同内容，就把它挪到最前面并返回 true
    @discardableResult
    func bumpExisting(hash: String, sourceApp: String?, bundleID: String?) -> Bool {
        guard let idx = items.firstIndex(where: { $0.contentHash == hash }) else { return false }
        var item = items.remove(at: idx)
        item.date = Date()
        if let app = sourceApp { item.sourceApp = app }
        if let bid = bundleID { item.sourceBundleID = bid }
        items.insert(item, at: 0)
        scheduleSave()
        return true
    }

    func add(_ item: ClipItem) {
        if bumpExisting(hash: item.contentHash, sourceApp: item.sourceApp, bundleID: item.sourceBundleID) {
            if let name = item.imageFile { removeImage(named: name) }
            return
        }
        items.insert(item, at: 0)
        trim()
        scheduleSave()
    }

    func bump(id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items.remove(at: idx)
        item.date = Date()
        items.insert(item, at: 0)
        scheduleSave()
    }

    // MARK: 收藏与标签

    func toggleFavorite(id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].pinned.toggle()
        trim()
        scheduleSave()
    }

    /// 设置一条的标签；打了标签就自动收藏
    func setTags(id: UUID, tags: [String]) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items[idx]
        item.tags = tags.isEmpty ? nil : tags
        if !tags.isEmpty { item.pinned = true }
        items[idx] = item
        scheduleSave()
    }

    /// 有这个标签就去掉，没有就加上
    func toggleTag(id: UUID, tag: String) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        var list = item.tagList
        if item.hasTag(tag) {
            list.removeAll { $0.caseInsensitiveCompare(tag) == .orderedSame }
        } else {
            list.append(tag)
        }
        setTags(id: id, tags: list)
    }

    /// 所有收藏里用到的标签，按使用次数排序
    var favoriteTags: [TagCount] {
        var counts: [String: Int] = [:]
        var display: [String: String] = [:]
        for item in items where item.pinned {
            for tag in item.tagList {
                let key = tag.lowercased()
                counts[key, default: 0] += 1
                if display[key] == nil { display[key] = tag }
            }
        }
        return counts
            .map { TagCount(name: display[$0.key] ?? $0.key, count: $0.value) }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    var favoritesCount: Int { items.filter { $0.pinned }.count }

    var untaggedFavoritesCount: Int { items.filter { $0.pinned && $0.tagList.isEmpty }.count }

    /// 把所有条目里的 old 标签改名为 new（new 已存在则合并）
    @discardableResult
    func renameTag(_ old: String, to newText: String) -> String? {
        guard let newName = TagParser.parse(newText).first else { return nil }
        var copy = items
        for i in copy.indices where copy[i].hasTag(old) {
            var list: [String] = []
            for tag in copy[i].tagList {
                let replaced = (tag.caseInsensitiveCompare(old) == .orderedSame) ? newName : tag
                if !list.contains(where: { $0.caseInsensitiveCompare(replaced) == .orderedSame }) {
                    list.append(replaced)
                }
            }
            copy[i].tags = list
        }
        items = copy
        scheduleSave()
        return newName
    }

    /// 从所有条目里删掉这个标签（条目本身还在收藏里）
    func deleteTag(_ tag: String) {
        var copy = items
        for i in copy.indices where copy[i].hasTag(tag) {
            let rest = copy[i].tagList.filter { $0.caseInsensitiveCompare(tag) != .orderedSame }
            copy[i].tags = rest.isEmpty ? nil : rest
        }
        items = copy
        scheduleSave()
    }

    func delete(id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: idx)
        cleanup(item)
        scheduleSave()
    }

    /// 清空历史，收藏的保留
    func clearUnpinned() {
        let removed = items.filter { !$0.pinned }
        items.removeAll { !$0.pinned }
        removed.forEach { cleanup($0) }
        scheduleSave()
    }

    /// 未收藏的条目超过上限就删掉最旧的
    func trim() {
        let limit = AppSettings.shared.maxItems
        var unpinned = 0
        var keep: [ClipItem] = []
        var removed: [ClipItem] = []
        for item in items {
            if item.pinned {
                keep.append(item)
                continue
            }
            unpinned += 1
            if unpinned <= limit { keep.append(item) } else { removed.append(item) }
        }
        guard !removed.isEmpty else { return }
        items = keep
        removed.forEach { cleanup($0) }
        scheduleSave()
    }

    private func cleanup(_ item: ClipItem) {
        if let name = item.imageFile { removeImage(named: name) }
    }

    private func removeImage(named name: String) {
        let url = imagesURL.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
        ImageCache.shared.evict(url)
    }
}
