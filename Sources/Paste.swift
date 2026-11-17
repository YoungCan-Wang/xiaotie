import AppKit
import ApplicationServices
import Carbon

/// 把历史条目写回系统剪贴板
enum PasteboardWriter {
    static func write(_ item: ClipItem, store: ClipboardStore) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case .text:
            pb.setString(item.text ?? "", forType: .string)
        case .image:
            guard let url = store.imageURL(for: item), let png = try? Data(contentsOf: url) else { return }
            let pbItem = NSPasteboardItem()
            pbItem.setData(png, forType: .png)
            if let tiff = NSImage(data: png)?.tiffRepresentation {
                pbItem.setData(tiff, forType: .tiff)
            }
            pb.writeObjects([pbItem])
        case .files:
            let urls: [NSPasteboardWriting] = (item.filePaths ?? []).map { URL(fileURLWithPath: $0) as NSURL }
            pb.writeObjects(urls)
        }
    }
}

/// 模拟按下 ⌘V，需要「辅助功能」权限
enum AutoPaste {
    static func isTrusted(prompt: Bool) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func sendCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
