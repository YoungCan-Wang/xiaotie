# ClipKeeper

一个本地运行的 macOS 剪贴板历史工具，原生 Swift（AppKit + SwiftUI）编写，常驻菜单栏。

所有数据只保存在本机 `~/Library/Application Support/ClipKeeper/`（`history.json` 存文字记录，`images/` 存图片），不联网、不上传。

## 功能

- 自动记录复制的文字、图片（截图、网页图片）、在访达里复制的文件
- 重复复制同一内容会自动去重并移到最前
- `⌘⇧V` 唤出浮动面板：搜索（支持中文输入法）、键盘选择、回车直接粘贴到当前应用
- 右侧预览完整文字 / 大图 / 文件路径
- 固定常用条目，固定的不会被清理
- 自动跳过密码管理器（1Password、Bitwarden、钥匙串、系统「密码」等）复制的内容
- 菜单栏快速访问最近 12 条，以及暂停记录、开机启动、快捷键、保存条数等设置

## 安装

需要 macOS 13+，以及 Xcode 或命令行工具（没有的话先运行 `xcode-select --install`）。

```bash
git clone https://github.com/YoungCan-Wang/xiaotie.git
cd xiaotie
bash build.sh install
```

会编译、安装到 `/Applications` 并自动启动。只编译不安装：`bash build.sh`，产物在 `build/ClipKeeper.app`。

## 面板快捷键

| 按键 | 作用 |
| --- | --- |
| 直接打字 | 搜索 |
| `↑` `↓` | 选择 |
| `⏎` | 粘贴到当前应用 |
| `⇧⏎` | 只复制到剪贴板，不粘贴 |
| `⌘1` – `⌘9` | 直接粘贴第 1–9 条 |
| `⌘P` | 固定 / 取消固定 |
| `⌘D` | 删除 |
| `Tab` | 在「全部」和「已固定」之间切换 |
| `Esc` | 关闭 |

鼠标单击某条也会直接粘贴，右键有更多操作。如果 `⌘⇧V` 和某些应用的「粘贴并匹配样式」冲突，可以在菜单栏图标里换成 `⌥⌘V` 等。

## 权限

- **辅助功能**：自动粘贴需要（系统设置 → 隐私与安全性 → 辅助功能）。不给也能用，选中后内容已在剪贴板里，自己按 `⌘V` 即可。
- 每次重新编译后签名会变，自动粘贴可能失效。到辅助功能列表里删掉 ClipKeeper 再重新授权即可。
- 苹果预告以后的 macOS 会在应用读取剪贴板时询问权限，看到「允许 ClipKeeper 从其他应用粘贴」之类的提示时选允许。

## 卸载

菜单栏图标 → 退出 ClipKeeper，然后删除：

```
/Applications/ClipKeeper.app
~/Library/Application Support/ClipKeeper/
```

## 项目结构

```
Sources/
  main.swift              入口
  AppDelegate.swift       菜单栏图标、设置、粘贴流程
  ClipboardMonitor.swift  监听系统剪贴板
  ClipboardStore.swift    历史记录的增删改与持久化
  PanelController.swift   浮动面板、键盘操作
  HistoryView.swift       面板界面（SwiftUI）
  HotKey.swift            全局快捷键（Carbon）
  Paste.swift             写回剪贴板、模拟 ⌘V
  Images.swift            图片保存与缩略图缓存
  Models.swift            数据模型、设置
Resources/Info.plist
Scripts/make_icon.swift   生成应用图标
build.sh                  编译打包脚本
```
