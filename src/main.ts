type ClipItem = {
  id: string;
  type: "text";
  text: string;
  createdAt: number;
  lastSeenAt: number;
  lastCopiedAt: number | null;
  pinned: boolean;
  groupIds: string[];
};

type ClipGroup = {
  id: string;
  name: string;
  createdAt: number;
  protected?: boolean;
};

function formatTime(ms: number) {
  const d = new Date(ms);
  const hh = d.getHours().toString().padStart(2, "0");
  const mm = d.getMinutes().toString().padStart(2, "0");
  return `${hh}:${mm}`;
}

function escapeHtml(raw: string) {
  return raw
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/\"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

function clampPreview(text: string, max = 240) {
  const t = text.trim();
  if (t.length <= max) return t;
  return `${t.slice(0, max)}…`;
}

const searchEl = document.querySelector<HTMLInputElement>("#search")!;
const listEl = document.querySelector<HTMLDivElement>("#list")!;
const footerEl = document.querySelector<HTMLElement>("#footer")!;
const groupEl = document.querySelector<HTMLSelectElement>("#group")!;
const addBtn = document.querySelector<HTMLButtonElement>("#btn-add")!;
const menuBtn = document.querySelector<HTMLButtonElement>("#btn-menu")!;

let items: ClipItem[] = [];
let selectedId: string | null = null;
let query = "";
let searchTimer: number | null = null;
let groups: ClipGroup[] = [];
let selectedGroupId: string = "all";

const FAVORITES_GROUP_ID = "favorites";

function groupNameMap() {
  const m = new Map<string, string>();
  for (const g of groups) m.set(g.id, g.name);
  return m;
}

function resolveTargetGroupId() {
  return selectedGroupId === "all" ? FAVORITES_GROUP_ID : selectedGroupId;
}

async function loadGroups() {
  groups = await window.xiaotie.listGroups();

  groupEl.innerHTML = "";
  const allOpt = document.createElement("option");
  allOpt.value = "all";
  allOpt.textContent = "全部";
  groupEl.appendChild(allOpt);

  for (const g of groups) {
    const opt = document.createElement("option");
    opt.value = g.id;
    opt.textContent = g.name;
    groupEl.appendChild(opt);
  }

  if (selectedGroupId !== "all" && !groups.some((g) => g.id === selectedGroupId)) {
    selectedGroupId = "all";
  }
  groupEl.value = selectedGroupId;
}

async function refresh() {
  items = await window.xiaotie.listItems({ query, groupId: selectedGroupId });
  if (!selectedId || !items.some((it) => it.id === selectedId)) {
    selectedId = items[0]?.id ?? null;
  }
  render();
}

function render() {
  const groupLabel =
    selectedGroupId === "all"
      ? "全部"
      : groups.find((g) => g.id === selectedGroupId)?.name ?? "";
  footerEl.textContent = `${items.length} 条 · ${groupLabel || "分组"} · Enter 复制 · Esc 关闭`;
  if (!items.length) {
    listEl.innerHTML = `<div class="empty">历史记录为空</div>`;
    return;
  }

  const nameById = groupNameMap();
  const targetGroupId = resolveTargetGroupId();

  listEl.innerHTML = items
    .map((it) => {
      const selected = it.id === selectedId ? "selected" : "";
      const pin = it.pinned ? "★" : "☆";
      const inTargetGroup = (it.groupIds ?? []).includes(targetGroupId);
      const fav = inTargetGroup ? "❤" : "♡";
      const preview = escapeHtml(clampPreview(it.text));

      const groupNames = (it.groupIds ?? [])
        .map((gid) => nameById.get(gid))
        .filter(Boolean)
        .slice(0, 3)
        .join(", ");

      const metaLeft = `${formatTime(it.lastSeenAt)}${
        it.lastCopiedAt ? ` · 已复制 ${formatTime(it.lastCopiedAt)}` : ""
      }`;
      const meta = groupNames ? `${metaLeft} · ${escapeHtml(groupNames)}` : metaLeft;
      return `
        <div class="item ${selected}" data-id="${it.id}">
          <div class="item-top">
            <div class="item-meta">${meta}</div>
            <div class="item-actions">
              <button class="icon-btn" data-action="fav" data-id="${it.id}" type="button">${fav}</button>
              <button class="icon-btn" data-action="pin" data-id="${it.id}" type="button">${pin}</button>
              <button class="icon-btn" data-action="del" data-id="${it.id}" type="button">✕</button>
            </div>
          </div>
          <div class="item-text">${preview}</div>
        </div>
      `;
    })
    .join("");
}

async function copySelected() {
  if (!selectedId) return;
  await window.xiaotie.copyItem(selectedId);
  await window.xiaotie.hideWindow();
}

async function togglePin(id: string) {
  await window.xiaotie.togglePinned(id);
}

async function toggleFavInCurrentGroup(id: string) {
  const targetGroupId = resolveTargetGroupId();
  await window.xiaotie.toggleItemGroup(id, targetGroupId);
}

async function deleteOne(id: string) {
  await window.xiaotie.deleteItem(id);
}

function moveSelection(delta: number) {
  if (!items.length) return;
  const idx = selectedId ? items.findIndex((it) => it.id === selectedId) : -1;
  const nextIndex = Math.min(Math.max((idx < 0 ? 0 : idx) + delta, 0), items.length - 1);
  selectedId = items[nextIndex].id;
  render();
  const node = listEl.querySelector<HTMLElement>(`.item[data-id="${selectedId}"]`);
  node?.scrollIntoView({ block: "nearest" });
}

searchEl.addEventListener("input", () => {
  query = searchEl.value;
  if (searchTimer) window.clearTimeout(searchTimer);
  searchTimer = window.setTimeout(() => refresh(), 120);
});

groupEl.addEventListener("change", () => {
  selectedGroupId = groupEl.value;
  refresh();
});

addBtn.addEventListener("click", async () => {
  const name = window.prompt("新建分组名称：", "")?.trim();
  if (!name) return;
  const res = await window.xiaotie.createGroup(name);
  if (!res?.ok) {
    window.alert("创建失败：名称可能重复或为空");
    return;
  }
  await loadGroups();
  if (res.group?.id) {
    selectedGroupId = res.group.id;
  } else {
    selectedGroupId = "all";
  }
  groupEl.value = selectedGroupId;
  refresh();
});

async function clearAllWithConfirm() {
  const ok = window.confirm("清空将保留：置顶 + 已收藏（任意分组）。确认清空？");
  if (!ok) return;
  await window.xiaotie.clearAll();
}

menuBtn.addEventListener("click", async () => {
  const group = groups.find((g) => g.id === selectedGroupId);

  const title = group && selectedGroupId !== "all" ? `当前分组：${group.name}` : "当前分组：全部";
  const action = window
    .prompt(`${title}\n输入 1 清空（保留置顶+收藏） / 2 重命名分组 / 3 删除分组`, "1")
    ?.trim();
  if (!action) return;

  if (action === "1") {
    await clearAllWithConfirm();
    return;
  }

  if (action === "2") {
    if (!group || selectedGroupId === "all") {
      window.alert("请先在下拉框选择一个具体分组");
      return;
    }
    const nextName = window.prompt("新的分组名称：", group.name)?.trim();
    if (!nextName || nextName === group.name) return;
    const res = await window.xiaotie.renameGroup(group.id, nextName);
    if (!res?.ok) {
      window.alert("重命名失败：可能是系统分组或名称重复");
      return;
    }
    await loadGroups();
    refresh();
    return;
  }

  if (action === "3") {
    if (!group || selectedGroupId === "all") {
      window.alert("请先在下拉框选择一个具体分组");
      return;
    }
    const ok = window.confirm(`确认删除分组「${group.name}」？（分组内内容不会删除，只是取消归类）`);
    if (!ok) return;
    const res = await window.xiaotie.deleteGroup(group.id);
    if (!res?.ok) {
      window.alert("删除失败：系统分组不可删除");
      return;
    }
    selectedGroupId = "all";
    await loadGroups();
    refresh();
  }
});

listEl.addEventListener("click", async (e) => {
  const t = e.target as HTMLElement;
  const action = t.getAttribute("data-action");
  const id = t.getAttribute("data-id");

  if (action && id) {
    e.stopPropagation();
    if (action === "fav") await toggleFavInCurrentGroup(id);
    if (action === "pin") await togglePin(id);
    if (action === "del") await deleteOne(id);
    return;
  }

  const itemNode = (e.target as HTMLElement).closest<HTMLElement>(".item[data-id]");
  const itemId = itemNode?.getAttribute("data-id");
  if (!itemId) return;
  selectedId = itemId;
  render();
  await window.xiaotie.copyItem(itemId);
  await window.xiaotie.hideWindow();
});

window.addEventListener("keydown", async (e) => {
  if (e.key === "ArrowDown") {
    e.preventDefault();
    moveSelection(1);
    return;
  }
  if (e.key === "ArrowUp") {
    e.preventDefault();
    moveSelection(-1);
    return;
  }
  if (e.key === "Enter") {
    e.preventDefault();
    await copySelected();
    return;
  }
  if (e.key === "Escape") {
    e.preventDefault();
    await window.xiaotie.hideWindow();
  }
});

window.addEventListener("focus", () => {
  searchEl.focus();
  searchEl.select();
});

window.xiaotie.onUpdated(() => {
  loadGroups().then(() => refresh());
});

loadGroups().then(() => refresh());
