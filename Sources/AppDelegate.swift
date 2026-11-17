import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = ClipboardStore.shared
    private lazy var monitor = ClipboardMonitor(store: store)
    private lazy var panel = PanelController(store: store)
    private var statusItem: NSStatusItem!
    private var hotKeyOK = true
    private var promptedAccessibility = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        setupStatusItem()

        panel.model.onPick = { [weak self] item, paste in
            self?.pick(item, paste: paste, fromPanel: true)
        }
        HotKeyCenter.shared.onPress = { [weak self] in
            self?.panel.toggle()
        }
        applyHotKey()
        monitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.saveNow()
    }

    // MARK: 选中一条历史

    private func pick(_ item: ClipItem, paste: Bool, fromPanel: Bool) {
        PasteboardWriter.write(item, store: store)
        monitor.syncChangeCount()
        store.bump(id: item.id)
        if fromPanel { panel.hide() }

        guard paste, AppSettings.shared.autoPaste else { return }
        if AutoPaste.isTrusted(prompt: false) {
            // 等面板/菜单收起、焦点回到原来的应用后再按 ⌘V
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                AutoPaste.sendCommandV()
            }
        } else if !promptedAccessibility {
            promptedAccessibility = true
            _ = AutoPaste.isTrusted(prompt: true)
        }
    }

    // MARK: 快捷键

    private func applyHotKey() {
        let preset = AppSettings.shared.hotKey
        hotKeyOK = HotKeyCenter.shared.register(keyCode: preset.keyCode, modifiers: preset.modifiers)
        if !hotKeyOK {
            NSLog("ClipKeeper: 快捷键 \(preset.title) 注册失败，可能被别的应用占用")
        }
    }

    // MARK: 菜单栏图标

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "ClipKeeper")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "ClipKeeper 剪贴板历史"
            button.appearsDisabled = AppSettings.shared.paused
        }
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let settings = AppSettings.shared

        let recent = Array(store.items.prefix(12))
        if recent.isEmpty {
            menu.addItem(header("还没有记录，复制点什么试试"))
        } else {
            menu.addItem(header("最近复制"))
            for (i, item) in recent.enumerated() {
                menu.addItem(clipMenuItem(for: item, shortcut: i < 9 ? "\(i + 1)" : ""))
            }
        }

        // 收藏，按标签分类
        let favorites = store.items.filter { $0.pinned }
        if !favorites.isEmpty {
            menu.addItem(.separator())
            let favItem = NSMenuItem(title: "收藏（\(favorites.count)）", action: nil, keyEquivalent: "")
            let favMenu = NSMenu()
            for tag in store.favoriteTags {
                let list = favorites.filter { $0.hasTag(tag.name) }
                favMenu.addItem(submenuItem(title: "#\(tag.name)（\(tag.count)）", items: list))
            }
            let untagged = favorites.filter { $0.tagList.isEmpty }
            if !untagged.isEmpty {
                if favMenu.numberOfItems > 0 { favMenu.addItem(.separator()) }
                favMenu.addItem(submenuItem(title: "未分类（\(untagged.count)）", items: untagged))
            }
            favItem.submenu = favMenu
            menu.addItem(favItem)
        }

        menu.addItem(.separator())
        menu.addItem(action("打开剪贴板面板（\(settings.hotKey.title)）", #selector(openPanel)))
        if !hotKeyOK {
            menu.addItem(header("⚠️ \(settings.hotKey.title) 被其他应用占用了，请换一个快捷键"))
        }
        if settings.autoPaste && !AutoPaste.isTrusted(prompt: false) {
            menu.addItem(action("⚠️ 自动粘贴需要「辅助功能」权限，点这里去开启…", #selector(openAccessibilitySettings)))
        }

        menu.addItem(.separator())
        menu.addItem(toggle("暂停记录", on: settings.paused, #selector(togglePaused)))
        menu.addItem(toggle("选中后自动粘贴", on: settings.autoPaste, #selector(toggleAutoPaste)))
        menu.addItem(toggle("开机自动启动", on: SMAppService.mainApp.status == .enabled, #selector(toggleLaunchAtLogin)))

        let hotKeyItem = NSMenuItem(title: "唤出快捷键", action: nil, keyEquivalent: "")
        let hotKeyMenu = NSMenu()
        for (i, preset) in AppSettings.hotKeyPresets.enumerated() {
            let it = NSMenuItem(title: preset.title, action: #selector(chooseHotKey(_:)), keyEquivalent: "")
            it.target = self
            it.tag = i
            it.state = (i == settings.hotKeyIndex) ? .on : .off
            hotKeyMenu.addItem(it)
        }
        hotKeyItem.submenu = hotKeyMenu
        menu.addItem(hotKeyItem)

        let maxItem = NSMenuItem(title: "最多保存", action: nil, keyEquivalent: "")
        let maxMenu = NSMenu()
        for n in AppSettings.maxItemOptions {
            let it = NSMenuItem(title: "\(n) 条", action: #selector(chooseMaxItems(_:)), keyEquivalent: "")
            it.target = self
            it.tag = n
            it.state = (n == settings.maxItems) ? .on : .off
            maxMenu.addItem(it)
        }
        maxItem.submenu = maxMenu
        menu.addItem(maxItem)

        menu.addItem(.separator())
        menu.addItem(action("清空历史（保留收藏）…", #selector(clearHistory)))
        menu.addItem(action("打开数据文件夹", #selector(openDataFolder)))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 ClipKeeper", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }

    private func header(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    private func toggle(_ title: String, on: Bool, _ selector: Selector) -> NSMenuItem {
        let item = action(title, selector)
        item.state = on ? .on : .off
        return item
    }

    private func menuTitle(for item: ClipItem) -> String {
        let limit = 46
        var title = item.title
        if title.count > limit { title = String(title.prefix(limit)) + "…" }
        return item.pinned ? "⭐ " + title : title
    }

    private func clipMenuItem(for item: ClipItem, shortcut: String = "") -> NSMenuItem {
        let mi = NSMenuItem(title: menuTitle(for: item), action: #selector(pickFromMenu(_:)), keyEquivalent: shortcut)
        mi.keyEquivalentModifierMask = []
        mi.target = self
        mi.representedObject = item.id
        mi.image = menuImage(for: item)
        return mi
    }

    private func submenuItem(title: String, items: [ClipItem]) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for item in items.prefix(30) {
            sub.addItem(clipMenuItem(for: item))
        }
        if items.count > 30 {
            let more = NSMenuItem(title: "还有 \(items.count - 30) 条，打开面板查看…", action: #selector(openPanel), keyEquivalent: "")
            more.target = self
            sub.addItem(more)
        }
        parent.submenu = sub
        return parent
    }

    private func menuImage(for item: ClipItem) -> NSImage? {
        let source: NSImage?
        switch item.kind {
        case .text:
            return nil
        case .image:
            if let url = store.imageURL(for: item) {
                source = ImageCache.shared.thumbnail(for: url, maxPixel: 40)
            } else {
                source = nil
            }
        case .files:
            source = NSWorkspace.shared.icon(forFile: item.filePaths?.first ?? "/")
        }
        guard let original = source, let copy = original.copy() as? NSImage else { return nil }
        let h: CGFloat = 16
        let ratio = original.size.height > 0 ? original.size.width / original.size.height : 1
        copy.size = NSSize(width: min(28, max(12, h * ratio)), height: h)
        return copy
    }

    // MARK: 菜单动作

    @objc private func pickFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let item = store.items.first(where: { $0.id == id }) else { return }
        pick(item, paste: true, fromPanel: false)
    }

    @objc private func openPanel() {
        // 等菜单收起再弹面板
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.panel.show()
        }
    }

    @objc private func togglePaused() {
        AppSettings.shared.paused.toggle()
        statusItem.button?.appearsDisabled = AppSettings.shared.paused
    }

    @objc private func toggleAutoPaste() {
        AppSettings.shared.autoPaste.toggle()
        if AppSettings.shared.autoPaste && !AutoPaste.isTrusted(prompt: false) {
            _ = AutoPaste.isTrusted(prompt: true)
        }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            showAlert("设置开机启动失败",
                      "\(error.localizedDescription)\n\n建议先把 ClipKeeper.app 放进「应用程序」文件夹再试。")
        }
    }

    @objc private func chooseHotKey(_ sender: NSMenuItem) {
        AppSettings.shared.hotKeyIndex = sender.tag
        applyHotKey()
        if !hotKeyOK {
            showAlert("快捷键被占用", "\(AppSettings.shared.hotKey.title) 已经被别的应用注册了，换一个试试。")
        }
    }

    @objc private func chooseMaxItems(_ sender: NSMenuItem) {
        AppSettings.shared.maxItems = sender.tag
        store.trim()
    }

    @objc private func clearHistory() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "清空剪贴板历史？"
        alert.informativeText = "收藏的内容（包括标签）会保留，其余记录会被删除，无法恢复。"
        alert.addButton(withTitle: "清空")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            store.clearUnpinned()
        }
    }

    @objc private func openDataFolder() {
        NSWorkspace.shared.open(store.baseURL)
    }

    @objc private func openAccessibilitySettings() {
        _ = AutoPaste.isTrusted(prompt: true)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func showAlert(_ title: String, _ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    // MARK: 隐藏的主菜单（让弹窗里的 ⌘C/⌘V 等能用）

    private func setupMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出 ClipKeeper", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "编辑")
        edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        NSApp.mainMenu = main
    }
}
