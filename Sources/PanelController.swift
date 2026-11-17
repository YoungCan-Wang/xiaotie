import AppKit
import SwiftUI

enum PanelLayout {
    static let width: CGFloat = 780
    static let height: CGFloat = 480
    static let listWidth: CGFloat = 400
    static let cornerRadius: CGFloat = 14
}

/// 不抢焦点的浮动面板：弹出时原来的应用仍然是前台，选完直接粘贴到原应用
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// 面板的状态：搜索词、当前选中、全部/已固定
final class PanelModel: ObservableObject {
    enum Scope: Hashable {
        case all
        case pinned
    }

    @Published var query: String = "" {
        didSet { if query != oldValue { selection = 0 } }
    }
    @Published var scope: Scope = .all {
        didSet { if scope != oldValue { selection = 0 } }
    }
    @Published var selection: Int = 0

    let store: ClipboardStore
    /// (条目, 是否自动粘贴)
    var onPick: ((ClipItem, Bool) -> Void)?

    init(store: ClipboardStore) {
        self.store = store
    }

    var filtered: [ClipItem] {
        var list = store.items
        if scope == .pinned { list = list.filter { $0.pinned } }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return list }
        return list.filter {
            $0.searchText.localizedCaseInsensitiveContains(q)
                || ($0.sourceApp ?? "").localizedCaseInsensitiveContains(q)
        }
    }

    var selectedItem: ClipItem? {
        let list = filtered
        return list.indices.contains(selection) ? list[selection] : nil
    }

    func reset() {
        query = ""
        scope = .all
        selection = 0
    }

    func move(_ delta: Int) {
        let count = filtered.count
        guard count > 0 else { selection = 0; return }
        selection = min(max(selection + delta, 0), count - 1)
    }

    func confirm(index: Int? = nil, paste: Bool = true) {
        let list = filtered
        let i = index ?? selection
        guard list.indices.contains(i) else { return }
        onPick?(list[i], paste)
    }

    func togglePinSelected() {
        guard let item = selectedItem else { return }
        store.togglePin(id: item.id)
        clampSelection()
    }

    func deleteSelected() {
        guard let item = selectedItem else { return }
        store.delete(id: item.id)
        clampSelection()
    }

    func clampSelection() {
        let count = filtered.count
        if selection >= count { selection = max(0, count - 1) }
    }
}

final class PanelController: NSObject, NSWindowDelegate {
    let model: PanelModel
    private let store: ClipboardStore
    private let panel: FloatingPanel
    private let hostingView: NSHostingView<AnyView>
    private var keyMonitor: Any?

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
            self?.focusSearchField()
            self?.panel.invalidateShadow()
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        removeKeyMonitor()
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

    private func focusSearchField() {
        guard let field = findTextField(in: panel.contentView) else { return }
        if let editor = panel.firstResponder as? NSTextView, editor.delegate === field { return }
        panel.makeFirstResponder(field)
    }

    private func findTextField(in view: NSView?) -> NSTextField? {
        guard let view = view else { return nil }
        if let tf = view as? NSTextField, tf.isEditable { return tf }
        for sub in view.subviews {
            if let found = findTextField(in: sub) { return found }
        }
        return nil
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
        case 36, 76: // Return / Enter，按住 Shift 只复制不粘贴
            model.confirm(paste: !flags.contains(.shift))
            return true
        case 48: // Tab 切换 全部 / 已固定
            model.scope = (model.scope == .all) ? .pinned : .all
            return true
        default:
            break
        }

        guard flags.contains(.command) else { return false }

        if let n = Int(chars), (1...9).contains(n) {
            model.confirm(index: n - 1, paste: true)
            return true
        }

        switch chars {
        case "p":
            model.togglePinSelected()
            return true
        case "d":
            model.deleteSelected()
            return true
        case "w":
            hide()
            return true
        // 这个应用没有可见的菜单栏，搜索框里的编辑快捷键手动转发
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
            return false
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
