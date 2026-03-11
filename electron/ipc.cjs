const { ipcMain, clipboard } = require('electron')
const store = require('./store.cjs')

function registerIpc({ notifyUpdated }) {
  ipcMain.handle('items:list', async (_evt, filter) => {
    return store.listItems(filter)
  })

  ipcMain.handle('groups:list', async () => {
    return store.listGroups()
  })

  ipcMain.handle('groups:create', async (_evt, name) => {
    const res = store.createGroup(name)
    if (res.ok) notifyUpdated?.()
    return res
  })

  ipcMain.handle('groups:rename', async (_evt, id, name) => {
    const res = store.renameGroup(id, name)
    if (res.ok) notifyUpdated?.()
    return res
  })

  ipcMain.handle('groups:delete', async (_evt, id) => {
    const res = store.deleteGroup(id)
    if (res.ok) notifyUpdated?.()
    return res
  })

  ipcMain.handle('items:toggleGroup', async (_evt, itemId, groupId) => {
    const res = store.toggleItemGroup(itemId, groupId)
    if (res.ok) notifyUpdated?.()
    return res
  })

  ipcMain.handle('items:copy', async (_evt, id) => {
    const items = store.listItems('')
    const item = items.find((it) => it.id === id)
    if (!item) return { ok: false }
    if (item.type === 'text') {
      clipboard.writeText(item.text)
      store.markCopied(id)
      notifyUpdated?.()
      return { ok: true }
    }
    return { ok: false }
  })

  ipcMain.handle('items:pin', async (_evt, id) => {
    const res = store.togglePinned(id)
    if (res.changed) notifyUpdated?.()
    return res
  })

  ipcMain.handle('items:delete', async (_evt, id) => {
    const res = store.deleteItem(id)
    if (res.changed) notifyUpdated?.()
    return res
  })

  ipcMain.handle('items:clear', async () => {
    const res = store.clearAll()
    if (res.changed) notifyUpdated?.()
    return res
  })
}

module.exports = { registerIpc }
