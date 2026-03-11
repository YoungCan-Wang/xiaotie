# 小贴（Xiaotie）

一个 macOS 剪切板管理工具（MVP），目标体验参考 Paste。

开源不收费，当前以“能用就行”的 MVP 形态快速迭代。

## 本地运行

```bash
cd xiaotie
npm install
npm run dev
```

默认快捷键：`⌘⇧V` 打开/隐藏。

## 打包

```bash
cd xiaotie
npm install
npm run dist
```

产物默认在：`xiaotie/dist/小贴-0.1.0-arm64.dmg`

## 安装（换电脑）

1. 拷贝 `dist/小贴-0.1.0-arm64.dmg` 到新电脑
2. 双击打开 DMG，把「小贴.app」拖进「Applications」
3. 首次打开如果提示“无法验证开发者”，用 Finder 右键「打开」一次即可

如果仍被 Gatekeeper 拦截，可执行：

```bash
sudo xattr -dr com.apple.quarantine "/Applications/小贴.app"
```

## 说明

- 由于 DMG 体积较大（>100MB），需要使用 Git LFS 才能推到 GitHub 仓库。
- 如需“免右键打开”的体验，需要配置 Developer ID 签名 + Notarization。
