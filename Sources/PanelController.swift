import AppKit
import Combine
import SwiftUI

enum PanelLayout {
    static let width: CGFloat = 820
    static let height: CGFloat = 500
    static let listWidth: CGFloat = 420
    static let cornerRadius: CGFloat = 14
    static let searchPlaceholder = "搜索剪贴板历史，#标签 按分类筛选"
    static let editorPlaceholder = "输入标签，用空格或逗号分隔"
}

/// 不抢焦点的浮动面板：弹出时原来的应用仍然是前台，选完直接粘贴到原应用
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// 面板的状态：搜索词、当前选中、全部/收藏、标签筛选、标签编辑
final class PanelModel: ObservableObject {
    enum Scope: Hashable {
        case all
        case favorites
    }

    enum TagFilter: Hashable {
        case any
        case untagged
        case tag(String)
    }

    enum EditorMode: Equatable {
        case itemTags(UUID)
        case renameTag(String)
    }

    @Published var query: String = "" {
        didSet { if query != oldValue { selection = 0 } }
    }
    @Published var scope: Scope = .all {
        didSet {
            if scope != oldValue {
                selection = 0
                tagFilter = .any
            }
        }
    }
    @Published var tagFilter: TagFilter = .any {
        didSet { if tagFilter != oldValue { selection = 0 } }
    }
    @Published var selection: Int = 0
    @Published var editorMode: EditorMode? = nil
    @Published var editorText: String = ""
    /// 正在确认「删除全部」
    @Published var confirmingClear = false

    let store: ClipboardStore
    /// (条目, 是否自动粘贴)
    var onPick: ((ClipItem, Bool) -> Void)?

    init(store: ClipboardStore) {
        self.store = store
    }

    var isEditing: Bool { editorMode != nil }

    // MARK: 过滤

    /// 搜索词里 #开头的是标签，其余是普通关键词（都要匹配）
    private var parsedQuery: (words: [String], tags: [String]) {
        var words: [String] = []
        var tags: [String] = []
        for token in query.split(whereSeparator: { $0.isWhitespace }) {
            if (token.hasPrefix("#") || token.hasPrefix("＃")) && token.count > 1 {
                tags.append(String(token.dropFirst()))
            } else if token != "#" && token != "＃" {
                words.append(String(token))
            }
        }
        return (words, tags)
    }

    var filtered: [ClipItem] {
        var list = store.items
        if scope == .favorites {
            list = list.filter { $0.pinned }
            switch tagFilter {
            case .any:
                break
            case .untagged:
                list = list.filter { $0.tagList.isEmpty }
            case .tag(let name):
                list = list.filter { $0.hasTag(name) }
            }
        }

        let (words, tagQueries) = parsedQuery
        if !tagQueries.isEmpty {
            list = list.filter { item in
                tagQueries.allSatisfy { q in
                    item.tagList.contains { $0.localizedCaseInsensitiveContains(q) }
                }
            }
        }
        if !words.isEmpty {
            list = list.filter { item in
                words.allSatisfy { w in
                    item.searchText.localizedCaseInsensitiveContains(w)
                        || (item.sourceApp ?? "").localizedCaseInsensitiveContains(w)
                        || item.tagList.contains { $0.localizedCaseInsensitiveContains(w) }
                }
            }
        }
        return list
    }

    var selectedItem: ClipItem? {
        let list = filtered
        return list.indices.contains(selection) ? list[selection] : nil
    }

    /// 收藏页顶部可选的分类：全部、未分类、各个标签
    var tagFilters: [TagFilter] {
        var result: [TagFilter] = [.any]
        if store.untaggedFavoritesCount > 0 { result.append(.untagged) }
        result.append(contentsOf: store.favoriteTags.map { TagFilter.tag($0.name) })
        return result
    }

    // MARK: 操作

    func reset() {
        query = ""
        scope = .all
        tagFilter = .any
        selection = 0
        editorMode = nil
        editorText = ""
        confirmingClear = false
    }

    func move(_ delta: Int) {
        let count = filtered.count
        guard count > 0 else { selection = 0; return }
        selection = min(max(selection + delta, 0), count - 1)
    }

    func cycleTagFilter(_ delta: Int) {
        let all = tagFilters
        let current = all.firstIndex(of: tagFilter) ?? 0
        let next = (current + delta + all.count) % all.count
        tagFilter = all[next]
    }

    func confirm(index: Int? = nil, paste: Bool = true) {
        let list = filtered
        let i = index ?? selection
        guard list.indices.contains(i) else { return }
        onPick?(list[i], paste)
    }

    func toggleFavoriteSelected() {
        guard let item = selectedItem else { return }
        store.toggleFavorite(id: item.id)
        clampSelection()
    }

    func deleteSelected() {
        guard let item = selectedItem else { return }
        store.delete(id: item.id)
        clampSelection()
    }

    func deleteTag(_ tag: String) {
        store.deleteTag(tag)
        if case .tag(let current) = tagFilter, current.caseInsensitiveCompare(tag) == .orderedSame {
            tagFilter = .any
        }
        clampSelection()
    }

    // MARK: 删除全部（保留收藏）

    var deletableCount: Int { store.items.filter { !$0.pinned }.count }

    func beginClearAll() {
        guard !isEditing else { return }
        confirmingClear = true
    }

    func confirmClearAll() {
        if deletableCount > 0 { store.clearUnpinned() }
        confirmingClear = false
        selection = 0
    }

    func cancelClearAll() {
        confirmingClear = false
    }

    func clampSelection() {
        let count = filtered.count
        if selection >= count { selection = max(0, count - 1) }
    }

    // MARK: 标签编辑

    func beginEditTags() {
        guard let item = selectedItem else { return }
        beginEditTags(for: item)
    }

    func beginEditTags(for item: ClipItem) {
        editorText = item.tagList.isEmpty ? "" : item.tagList.joined(separator: " ") + " "
        editorMode = .itemTags(item.id)
    }

    func beginRenameTag(_ tag: String) {
        editorText = tag
        editorMode = .renameTag(tag)
    }

    /// 点已有标签时追加到输入框
    func appendTagToEditor(_ tag: String) {
        var list = TagParser.parse(editorText)
        if !list.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
            list.append(tag)
        }
        editorText = list.joined(separator: " ") + " "
    }

    func commitEditor() {
        guard let mode = editorMode else { return }
        switch mode {
        case .itemTags(let id):
            store.setTags(id: id, tags: TagParser.parse(editorText))
        case .renameTag(let old):
            if let newName = store.renameTag(old, to: editorText),
               case .tag(let current) = tagFilter,
               current.caseInsensitiveCompare(old) == .orderedSame {
                tagFilter = .tag(newName)
            }
        }
        editorMode = nil
        editorText = ""
        clampSelection()
    }

    func cancelEditor() {
        editorMode = nil
        editorText = ""
    }
}

final class PanelController: NSObject, NSWindowDelegate {
    let model: PanelModel
    private let store: ClipboardStore
    private let panel: FloatingPanel
    private let hostingView: NSHostingView<AnyView>
    private var keyMonitor: Any?
    private var editorObserver: AnyCancellable?

    init(store: ClipboardStore) {
        self.store = store
        self.model = PanelModel(store: store)
        self.panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: PanelLayout.width, height: PanelLayout.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.hostingView = NSHostingView(rootView: AnyView(EmptyView()))
        super.init()

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .utilityWindow
        panel.delegate = self

        // 毛玻璃背景 + 圆角
        let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: PanelLayout.width, height: PanelLayout.height))
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = PanelController.roundedMask(radius: PanelLayout.cornerRadius)

        hostingView.sizingOptions = []
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: effect.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        panel.contentView = effect

        // 打开/关闭标签编辑框时，把键盘焦点切过去/切回搜索框
        editorObserver = model.$editorMode
            .map { $0 != nil }
            .removeDuplicates()
            .sink { [weak self] editing in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                    self?.focusTextField(editor: editing)
                }
            }
    }

    // MARK: 显示 / 隐藏

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        if panel.isVisible { hide() } else { show() }
    }

    func show() {
        model.reset()
        // 每次弹出都重建视图，保证搜索框是空的并且拿到焦点
        hostingView.rootView = AnyView(HistoryView(model: model, store: store).id(UUID()))
        positionPanel()
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.focusTextField(editor: false)
            self?.panel.invalidateShadow()
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        removeKeyMonitor()
        model.cancelEditor()
        model.cancelClearAll()
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        // 点了别的地方就收起来
        hide()
    }

    private func positionPanel() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        guard let frame = screen?.visibleFrame else {
            panel.center()
            return
        }
        let size = panel.frame.size
        let x = frame.midX - size.width / 2
        let y = frame.midY - size.height / 2 + frame.height * 0.08
        panel.setFrameOrigin(NSPoint(x: x.rounded(), y: y.rounded()))
    }

    /// 把焦点放到搜索框（editor = false）或标签输入框（editor = true）
    private func focusTextField(editor: Bool) {
        guard panel.isVisible else { return }
        var fields: [NSTextField] = []
        collectTextFields(in: panel.contentView, into: &fields)
        guard !fields.isEmpty else { return }
        let placeholder = editor ? PanelLayout.editorPlaceholder : PanelLayout.searchPlaceholder
        let fallback = editor ? fields.last : fields.first
        guard let target = fields.first(where: { $0.placeholderString == placeholder }) ?? fallback else { return }
        if let current = panel.firstResponder as? NSTextView, current.delegate === target { return }
        panel.makeFirstResponder(target)
    }

    private func collectTextFields(in view: NSView?, into result: inout [NSTextField]) {
        guard let view = view else { return }
        if let tf = view as? NSTextField, tf.isEditable { result.append(tf) }
        for sub in view.subviews {
            collectTextFields(in: sub, into: &result)
        }
    }

    // MARK: 键盘

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.panel.isKeyWindow else { return event }
            return self.handleKey(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor {
            NSEvent.removeMonitor(m)
            keyMonitor = nil
        }
    }

    /// 返回 true 表示这个按键已经处理掉了
    private func handleKey(_ event: NSEvent) -> Bool {
        // 输入法正在组字（拼音还没上屏）时，按键全部交给输入法
        if let editor = panel.firstResponder as? NSTextView, editor.hasMarkedText() {
            return false
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let chars = (event.charactersIgnoringModifiers ?? "").lowercased()

        // 「删除全部」确认框：回车删除、Esc 取消，其余按键忽略
        if model.confirmingClear {
            switch event.keyCode {
            case 53:
                model.cancelClearAll()
            case 36, 76:
                model.confirmClearAll()
            default:
                break
            }
            return true
        }

        // 标签编辑框打开时：回车保存、Esc 取消，其余按键交给输入框
        if model.isEditing {
            switch event.keyCode {
            case 53:
                model.cancelEditor()
                return true
            case 36, 76:
                model.commitEditor()
                return true
            case 48:
                return true
            default:
                break
            }
            if flags.contains(.command) {
                return handleEditingShortcut(chars, flags: flags) ?? true
            }
            return false
        }

        switch event.keyCode {
        case 53: // Esc
            hide()
            return true
        case 125: // ↓
            model.move(1)
            return true
        case 126: // ↑
            model.move(-1)
            return true
        case 121: // Page Down
            model.move(8)
            return true
        case 116: // Page Up
            model.move(-8)
            return true
        case 123, 124: // ← → 在收藏页、搜索框为空时切换分类
            if model.scope == .favorites && model.query.isEmpty {
                model.cycleTagFilter(event.keyCode == 123 ? -1 : 1)
                return true
            }
            return false
        case 36, 76: // Return / Enter，按住 Shift 只复制不粘贴
            model.confirm(paste: !flags.contains(.shift))
            return true
        case 48: // Tab 切换 全部 / 收藏
            model.scope = (model.scope == .all) ? .favorites : .all
            return true
        default:
            break
        }

        guard flags.contains(.command) else { return false }

        if event.keyCode == 51 && flags.contains(.shift) { // ⌘⇧⌫ 删除全部（保留收藏）
            model.beginClearAll()
            return true
        }

        if let n = Int(chars), (1...9).contains(n) {
            model.confirm(index: n - 1, paste: true)
            return true
        }

        switch chars {
        case "s":
            model.toggleFavoriteSelected()
            return true
        case "t":
            model.beginEditTags()
            return true
        case "d":
            model.deleteSelected()
            return true
        case "w":
            hide()
            return true
        default:
            return handleEditingShortcut(chars, flags: flags) ?? false
        }
    }

    /// 这个应用没有可见的菜单栏，输入框里的编辑快捷键手动转发；不是编辑快捷键返回 nil
    private func handleEditingShortcut(_ chars: String, flags: NSEvent.ModifierFlags) -> Bool? {
        switch chars {
        case "v":
            return NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
        case "c":
            return NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
        case "x":
            return NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
        case "a":
            return NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
        case "z":
            let sel = flags.contains(.shift) ? Selector(("redo:")) : Selector(("undo:"))
            return NSApp.sendAction(sel, to: nil, from: nil)
        default:
            return nil
        }
    }

    // MARK: 工具

    static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
