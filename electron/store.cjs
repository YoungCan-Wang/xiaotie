const crypto = require('crypto')
const fs = require('fs')
const path = require('path')
const { app } = require('electron')

const STORE_VERSION = 2
const MAX_ITEMS = 200

const FAVORITES_GROUP_ID = 'favorites'

function nowMs() {
  return Date.now()
}

function newId() {
  if (typeof crypto.randomUUID === 'function') return crypto.randomUUID()
  return crypto.randomBytes(16).toString('hex')
}

function storeFilePath() {
  return path.join(app.getPath('userData'), 'clipboard-history.json')
}

function defaultStore() {
  return {
    version: STORE_VERSION,
    groups: [
      {
        id: FAVORITES_GROUP_ID,
        name: '收藏',
        createdAt: nowMs(),
        protected: true,
      },
    ],
    items: [],
  }
}

function migrateToV2(parsed) {
  const next = defaultStore()
  const items = Array.isArray(parsed?.items) ? parsed.items : []
  next.items = items
    .filter((it) => it && it.type === 'text' && typeof it.text === 'string')
    .map((it) => ({
      id: String(it.id ?? newId()),
      type: 'text',
      text: it.text,
      createdAt: Number(it.createdAt ?? nowMs()),
      lastSeenAt: Number(it.lastSeenAt ?? nowMs()),
      lastCopiedAt: it.lastCopiedAt == null ? null : Number(it.lastCopiedAt),
      pinned: Boolean(it.pinned),
      groupIds: Array.isArray(it.groupIds) ? it.groupIds.map(String) : [],
    }))
  return next
}

function readStore() {
  const filePath = storeFilePath()
  try {
    const raw = fs.readFileSync(filePath, 'utf-8')
    const parsed = JSON.parse(raw)
    if (!parsed || !Array.isArray(parsed.items)) {
      return defaultStore()
    }
    if (parsed.version === STORE_VERSION) {
      const groups = Array.isArray(parsed.groups) ? parsed.groups : []
      if (!groups.some((g) => g && g.id === FAVORITES_GROUP_ID)) {
        parsed.groups = [...groups, ...defaultStore().groups]
      }
      return parsed
    }
    if (parsed.version === 1) {
      const migrated = migrateToV2(parsed)
      writeStore(migrated)
      return migrated
    }
    return defaultStore()
  } catch {
    return defaultStore()
  }
}

function writeStore(data) {
  const filePath = storeFilePath()
  const dir = path.dirname(filePath)
  fs.mkdirSync(dir, { recursive: true })

  const tmpPath = `${filePath}.tmp`
  fs.writeFileSync(tmpPath, JSON.stringify(data, null, 2), 'utf-8')
  fs.renameSync(tmpPath, filePath)
}

function normalizeQuery(q) {
  const s = (q ?? '').toString().trim()
  return s.length ? s.toLowerCase() : ''
}

function listItems(queryOrFilter, groupId) {
  const query =
    typeof queryOrFilter === 'object' && queryOrFilter
      ? queryOrFilter.query
      : queryOrFilter
  const gid =
    typeof queryOrFilter === 'object' && queryOrFilter
      ? queryOrFilter.groupId
      : groupId

  const q = normalizeQuery(query)
  const store = readStore()

  const filtered = store.items.filter((it) => {
    if (!it || it.type !== 'text') return false
    if (gid && gid !== 'all') {
      const groupIds = Array.isArray(it.groupIds) ? it.groupIds : []
      if (!groupIds.includes(gid)) return false
    }
    if (!q) return true
    if (!it || it.type !== 'text') return false
    const text = (it.text ?? '').toString().toLowerCase()
    return text.includes(q)
  })

  return filtered
}

function upsertText(text) {
  const t = (text ?? '').toString()
  if (!t.trim()) return { changed: false }

  const store = readStore()
  const existingIndex = store.items.findIndex((it) => it.type === 'text' && it.text === t)

  const timestamp = nowMs()

  if (existingIndex >= 0) {
    const existing = store.items[existingIndex]
    const updated = {
      ...existing,
      lastSeenAt: timestamp,
      groupIds: Array.isArray(existing.groupIds) ? existing.groupIds : [],
      pinned: Boolean(existing.pinned),
    }
    store.items.splice(existingIndex, 1)
    store.items.unshift(updated)
  } else {
    store.items.unshift({
      id: newId(),
      type: 'text',
      text: t,
      createdAt: timestamp,
      lastSeenAt: timestamp,
      lastCopiedAt: null,
      pinned: false,
      groupIds: [],
    })
  }

  const pinned = store.items.filter((it) => it.pinned)
  const others = store.items.filter((it) => !it.pinned)
  store.items = [...pinned, ...others].slice(0, MAX_ITEMS)

  writeStore(store)
  return { changed: true }
}

function markCopied(id) {
  const store = readStore()
  const idx = store.items.findIndex((it) => it.id === id)
  if (idx < 0) return { changed: false }
  store.items[idx] = { ...store.items[idx], lastCopiedAt: nowMs() }
  writeStore(store)
  return { changed: true, item: store.items[idx] }
}

function togglePinned(id) {
  const store = readStore()
  const idx = store.items.findIndex((it) => it.id === id)
  if (idx < 0) return { changed: false }
  const next = { ...store.items[idx], pinned: !store.items[idx].pinned }
  store.items[idx] = next
  const pinned = store.items.filter((it) => it.pinned)
  const others = store.items.filter((it) => !it.pinned)
  store.items = [...pinned, ...others]
  writeStore(store)
  return { changed: true, item: next }
}

function listGroups() {
  const store = readStore()
  const groups = Array.isArray(store.groups) ? store.groups : []
  return groups
}

function createGroup(name) {
  const n = (name ?? '').toString().trim()
  if (!n) return { ok: false }

  const store = readStore()
  store.groups = Array.isArray(store.groups) ? store.groups : []

  const exists = store.groups.some((g) => g && g.name === n)
  if (exists) return { ok: false, reason: 'exists' }

  const group = { id: newId(), name: n, createdAt: nowMs(), protected: false }
  store.groups.push(group)
  writeStore(store)
  return { ok: true, group }
}

function renameGroup(id, name) {
  const gid = (id ?? '').toString()
  const n = (name ?? '').toString().trim()
  if (!gid || !n) return { ok: false }
  if (gid === FAVORITES_GROUP_ID) return { ok: false, reason: 'protected' }

  const store = readStore()
  const groups = Array.isArray(store.groups) ? store.groups : []
  const idx = groups.findIndex((g) => g && g.id === gid)
  if (idx < 0) return { ok: false }

  const exists = groups.some((g) => g && g.id !== gid && g.name === n)
  if (exists) return { ok: false, reason: 'exists' }

  groups[idx] = { ...groups[idx], name: n }
  store.groups = groups
  writeStore(store)
  return { ok: true, group: groups[idx] }
}

function deleteGroup(id) {
  const gid = (id ?? '').toString()
  if (!gid) return { ok: false }
  if (gid === FAVORITES_GROUP_ID) return { ok: false, reason: 'protected' }

  const store = readStore()
  const groups = Array.isArray(store.groups) ? store.groups : []
  const before = groups.length
  store.groups = groups.filter((g) => g && g.id !== gid)
  if (store.groups.length === before) return { ok: false }

  store.items = (Array.isArray(store.items) ? store.items : []).map((it) => {
    if (!it || it.type !== 'text') return it
    const groupIds = Array.isArray(it.groupIds) ? it.groupIds : []
    if (!groupIds.includes(gid)) return it
    return { ...it, groupIds: groupIds.filter((x) => x !== gid) }
  })

  writeStore(store)
  return { ok: true }
}

function toggleItemGroup(itemId, groupId) {
  const id = (itemId ?? '').toString()
  const gid = (groupId ?? '').toString()
  if (!id || !gid || gid === 'all') return { ok: false }

  const store = readStore()
  const groups = Array.isArray(store.groups) ? store.groups : []
  if (!groups.some((g) => g && g.id === gid)) return { ok: false }

  const idx = store.items.findIndex((it) => it && it.id === id)
  if (idx < 0) return { ok: false }

  const it = store.items[idx]
  const current = Array.isArray(it.groupIds) ? it.groupIds : []
  const next = current.includes(gid) ? current.filter((x) => x !== gid) : [...current, gid]
  store.items[idx] = { ...it, groupIds: next }
  writeStore(store)
  return { ok: true, item: store.items[idx] }
}

function deleteItem(id) {
  const store = readStore()
  const before = store.items.length
  store.items = store.items.filter((it) => it.id !== id)
  if (store.items.length === before) return { changed: false }
  writeStore(store)
  return { changed: true }
}

function clearAll() {
  const store = readStore()
  store.items = store.items.filter((it) => {
    if (!it) return false
    const keepPinned = Boolean(it.pinned)
    const keepGrouped = Array.isArray(it.groupIds) && it.groupIds.length > 0
    return keepPinned || keepGrouped
  })
  writeStore(store)
  return { changed: true }
}

module.exports = {
  listItems,
  listGroups,
  createGroup,
  renameGroup,
  deleteGroup,
  toggleItemGroup,
  upsertText,
  markCopied,
  togglePinned,
  deleteItem,
  clearAll,
}
