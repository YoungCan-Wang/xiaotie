import AppKit
import SwiftUI

struct HistoryView: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var store: ClipboardStore
    @FocusState private var searchFocused: Bool

    var body: some View {
        let items = model.filtered
        let selected: ClipItem? = items.indices.contains(model.selection) ? items[model.selection] : nil

        VStack(spacing: 0) {
            searchBar
            Divider()
            HStack(spacing: 0) {
                listArea(items)
                    .frame(width: PanelLayout.listWidth)
                Divider()
                PreviewPane(item: selected, store: store)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            footer(count: items.count)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: PanelLayout.cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .onAppear {
            DispatchQueue.main.async { searchFocused = true }
        }
    }

    // MARK: 搜索栏

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
            TextField("搜索剪贴板历史", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .focused($searchFocused)
            Picker("", selection: $model.scope) {
                Text("全部").tag(PanelModel.Scope.all)
                Text("已固定").tag(PanelModel.Scope.pinned)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 140)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: 列表

    @ViewBuilder
    private func listArea(_ items: [ClipItem]) -> some View {
        if items.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 30))
                    .foregroundColor(.secondary)
                Text(emptyText)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            ClipRow(item: item, index: index, isSelected: index == model.selection, store: store)
                                .id(item.id)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    model.selection = index
                                    model.confirm(paste: true)
                                }
                                .contextMenu {
                                    Button("粘贴") { model.onPick?(item, true) }
                                    Button("仅复制到剪贴板") { model.onPick?(item, false) }
                                    Button(item.pinned ? "取消固定" : "固定") {
                                        store.togglePin(id: item.id)
                                        model.clampSelection()
                                    }
                                    Divider()
                                    Button("删除") {
                                        store.delete(id: item.id)
                                        model.clampSelection()
                                    }
                                }
                        }
                    }
                    .padding(8)
                }
                .onChange(of: model.selection) { newValue in
                    let list = model.filtered
                    guard list.indices.contains(newValue) else { return }
                    proxy.scrollTo(list[newValue].id)
                }
            }
        }
    }

    private var emptyText: String {
        if !model.query.trimmingCharacters(in: .whitespaces).isEmpty { return "没有匹配的内容" }
        if model.scope == .pinned { return "还没有固定的内容\n选中一条按 ⌘P 就能固定" }
        return "还没有记录\n复制点什么试试"
    }

    // MARK: 底部提示

    private func footer(count: Int) -> some View {
        HStack(spacing: 12) {
            hint("↑↓", "选择")
            hint("⏎", "粘贴")
            hint("⇧⏎", "仅复制")
            hint("⌘1-9", "快速粘贴")
            hint("⌘P", "固定")
            hint("⌘D", "删除")
            hint("Tab", "切换")
            Spacer()
            Text("\(count) 条")
                .foregroundColor(.secondary)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10.5, weight: .semibold))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08)))
            Text(label)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - 单行

struct ClipRow: View {
    let item: ClipItem
    let index: Int
    let isSelected: Bool
    let store: ClipboardStore

    var body: some View {
        HStack(spacing: 10) {
            ClipIcon(item: item, store: store, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(item.subtitle)
                    .font(.system(size: 10.5))
                    .foregroundColor(isSelected ? Color.white.opacity(0.75) : .secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if item.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundColor(isSelected ? .white : .orange)
            }
            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(isSelected ? Color.white.opacity(0.8) : .secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .foregroundColor(isSelected ? .white : .primary)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
    }
}

// MARK: - 图标 / 缩略图

struct ClipIcon: View {
    let item: ClipItem
    let store: ClipboardStore
    let size: CGFloat

    var body: some View {
        Group {
            switch item.kind {
            case .image:
                if let url = store.imageURL(for: item),
                   let img = ImageCache.shared.thumbnail(for: url, maxPixel: 96) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    symbol("photo")
                }
            case .files:
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.filePaths?.first ?? "/"))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            case .text:
                symbol(item.isURL ? "link" : "text.alignleft")
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: size * 0.42, weight: .medium))
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.08)))
    }
}

// MARK: - 右侧预览

struct PreviewPane: View {
    let item: ClipItem?
    let store: ClipboardStore

    var body: some View {
        if let item = item {
            VStack(alignment: .leading, spacing: 0) {
                content(item)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Divider()
                meta(item)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
        } else {
            Text("没有选中的内容")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func content(_ item: ClipItem) -> some View {
        switch item.kind {
        case .text:
            ScrollView {
                Text(String((item.text ?? "").prefix(20_000)))
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
        case .image:
            if let url = store.imageURL(for: item),
               let img = ImageCache.shared.thumbnail(for: url, maxPixel: 900) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("图片文件找不到了")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .files:
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(item.filePaths ?? [], id: \.self) { path in
                        HStack(spacing: 8) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                                .resizable()
                                .frame(width: 20, height: 20)
                            Text(path)
                                .font(.system(size: 12))
                                .lineLimit(2)
                                .truncationMode(.middle)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
        }
    }

    private func meta(_ item: ClipItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            metaRow("来源", item.sourceApp ?? "未知")
            metaRow("时间", Formatters.fullFormatter.string(from: item.date))
            metaRow("类型", item.detail)
        }
        .font(.system(size: 11))
    }

    private func metaRow(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(key)
                .foregroundColor(.secondary)
                .frame(width: 30, alignment: .leading)
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
