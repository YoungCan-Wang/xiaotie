import AppKit
import SwiftUI

struct HistoryView: View {
    enum Field: Hashable {
        case search
        case editor
    }

    @ObservedObject var model: PanelModel
    @ObservedObject var store: ClipboardStore
    @FocusState private var focusedField: Field?

    var body: some View {
        let items = model.filtered
        let selected: ClipItem? = items.indices.contains(model.selection) ? items[model.selection] : nil

        ZStack {
            VStack(spacing: 0) {
                searchBar
                if model.scope == .favorites {
                    tagBar
                }
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

            if model.isEditing {
                Color.black.opacity(0.28)
                    .contentShape(Rectangle())
                    .onTapGesture { model.cancelEditor() }
                editorCard
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: PanelLayout.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PanelLayout.cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .onAppear {
            DispatchQueue.main.async { focusedField = .search }
        }
        .onChange(of: model.isEditing) { editing in
            DispatchQueue.main.async { focusedField = editing ? .editor : .search }
        }
    }

    // MARK: 搜索栏

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
            TextField(PanelLayout.searchPlaceholder, text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .focused($focusedField, equals: .search)
            Picker("", selection: $model.scope) {
                Text("全部").tag(PanelModel.Scope.all)
                Text("收藏").tag(PanelModel.Scope.favorites)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 130)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: 收藏页的分类条

    private var tagBar: some View {
        let tags = store.favoriteTags
        let untagged = store.untaggedFavoritesCount
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                tagChip("全部收藏", count: store.favoritesCount, filter: .any)
                if untagged > 0 {
                    tagChip("未分类", count: untagged, filter: .untagged)
                }
                ForEach(tags) { tag in
                    tagChip("#" + tag.name, count: tag.count, filter: .tag(tag.name))
                        .contextMenu {
                            Button("重命名…") { model.beginRenameTag(tag.name) }
                            Button("删除这个标签") { model.deleteTag(tag.name) }
                        }
                }
                if tags.isEmpty {
                    Text("选中一条按 ⌘T 打标签，标签就是分类")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }

    private func tagChip(_ title: String, count: Int, filter: PanelModel.TagFilter) -> some View {
        let active = (model.tagFilter == filter)
        return Button {
            model.tagFilter = filter
        } label: {
            HStack(spacing: 4) {
                Text(title)
                Text("\(count)")
                    .foregroundColor(active ? Color.white.opacity(0.8) : .secondary)
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundColor(active ? .white : .primary)
            .background(Capsule().fill(active ? Color.accentColor : Color.primary.opacity(0.08)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: 列表

    @ViewBuilder
    private func listArea(_ items: [ClipItem]) -> some View {
        if items.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: model.scope == .favorites ? "star" : "doc.on.clipboard")
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
                                .contextMenu { rowMenu(item) }
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

    @ViewBuilder
    private func rowMenu(_ item: ClipItem) -> some View {
        Button("粘贴") { model.onPick?(item, true) }
        Button("仅复制到剪贴板") { model.onPick?(item, false) }
        Divider()
        Button(item.pinned ? "取消收藏" : "收藏") {
            store.toggleFavorite(id: item.id)
            model.clampSelection()
        }
        Button("编辑标签…") { model.beginEditTags(for: item) }
        let tags = store.favoriteTags
        if !tags.isEmpty {
            Menu("添加到分类") {
                ForEach(tags) { tag in
                    Button((item.hasTag(tag.name) ? "✓ " : "") + tag.name) {
                        store.toggleTag(id: item.id, tag: tag.name)
                        model.clampSelection()
                    }
                }
            }
        }
        Divider()
        Button("删除") {
            store.delete(id: item.id)
            model.clampSelection()
        }
    }

    private var emptyText: String {
        if !model.query.trimmingCharacters(in: .whitespaces).isEmpty { return "没有匹配的内容" }
        if model.scope == .favorites {
            switch model.tagFilter {
            case .any:
                return "还没有收藏\n选中一条按 ⌘S 收藏，按 ⌘T 打标签"
            case .untagged:
                return "没有未分类的收藏"
            case .tag:
                return "这个分类下没有内容"
            }
        }
        return "还没有记录\n复制点什么试试"
    }

    // MARK: 标签编辑弹层

    private var editorTitle: String {
        switch model.editorMode {
        case .some(.renameTag(let old)):
            return "重命名标签「\(old)」"
        case .some(.itemTags(let id)):
            let title = store.items.first(where: { $0.id == id })?.title ?? ""
            let short = title.count > 24 ? String(title.prefix(24)) + "…" : title
            return "给「\(short)」打标签"
        case .none:
            return ""
        }
    }

    private var isEditingItemTags: Bool {
        if case .some(.itemTags) = model.editorMode { return true }
        return false
    }

    private var editorCard: some View {
        let tags = store.favoriteTags
        return VStack(alignment: .leading, spacing: 12) {
            Text(editorTitle)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
            TextField(PanelLayout.editorPlaceholder, text: $model.editorText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 14))
                .focused($focusedField, equals: .editor)
            if isEditingItemTags && !tags.isEmpty {
                Text("已有标签，点一下添加：")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(tags) { tag in
                            Button {
                                model.appendTagToEditor(tag.name)
                            } label: {
                                Text("#" + tag.name)
                                    .font(.system(size: 12))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            HStack {
                Text(isEditingItemTags ? "打了标签会自动收藏；清空就是去掉所有标签" : "改成已有的名字会自动合并")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                Button("取消") { model.cancelEditor() }
                Button("保存") { model.commitEditor() }
            }
        }
        .padding(18)
        .frame(width: 440)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.25), radius: 18, y: 6)
    }

    // MARK: 底部提示

    private func footer(count: Int) -> some View {
        HStack(spacing: 10) {
            hint("↑↓", "选择")
            hint("⏎", "粘贴")
            hint("⇧⏎", "仅复制")
            hint("⌘1-9", "快速粘贴")
            hint("⌘S", "收藏")
            hint("⌘T", "标签")
            hint("⌘D", "删除")
            hint("Tab", model.scope == .all ? "看收藏" : "看全部")
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
                HStack(spacing: 6) {
                    if !item.tagList.isEmpty {
                        Text(item.tagList.map { "#" + $0 }.joined(separator: " "))
                            .foregroundColor(isSelected ? .white : .orange)
                            .lineLimit(1)
                    }
                    Text(item.subtitle)
                        .foregroundColor(isSelected ? Color.white.opacity(0.75) : .secondary)
                        .lineLimit(1)
                }
                .font(.system(size: 10.5))
            }
            Spacer(minLength: 6)
            if item.pinned {
                Image(systemName: "star.fill")
                    .font(.system(size: 10))
                    .foregroundColor(isSelected ? .white : .yellow)
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
            metaRow("标签", tagText(item))
        }
        .font(.system(size: 11))
    }

    private func tagText(_ item: ClipItem) -> String {
        if !item.tagList.isEmpty { return item.tagList.map { "#" + $0 }.joined(separator: " ") }
        return item.pinned ? "已收藏，未分类（⌘T 打标签）" : "无（⌘S 收藏，⌘T 打标签）"
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
