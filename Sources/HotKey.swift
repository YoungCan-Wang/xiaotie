import Carbon

/// Carbon 事件回调（必须是不捕获上下文的 C 函数）
private func hotKeyEventHandler(_ call: EventHandlerCallRef?,
                                _ event: EventRef?,
                                _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    DispatchQueue.main.async {
        HotKeyCenter.shared.onPress?()
    }
    return OSStatus(noErr)
}

/// 用 Carbon 的 RegisterEventHotKey 注册全局快捷键（不需要辅助功能权限）
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    var onPress: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerInstalled = false

    /// 注册成功返回 true；被别的应用占用会返回 false
    func register(keyCode: UInt32, modifiers: UInt32) -> Bool {
        installHandlerIfNeeded()
        unregister()
        let hotKeyID = EventHotKeyID(signature: OSType(0x434C_4B50), id: 1) // 'CLKP'
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        return status == OSStatus(noErr)
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyEventHandler, 1, &spec, nil, nil)
    }
}
