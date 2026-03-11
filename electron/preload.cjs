const { contextBridge, ipcRenderer } = require('electron')

contextBridge.exposeInMainWorld('xiaotie', {
  listItems: (filter) => ipcRenderer.invoke('items:list', filter ?? { query: '', groupId: 'all' }),
  listGroups: () => ipcRenderer.invoke('groups:list'),
  createGroup: (name) => ipcRenderer.invoke('groups:create', name),
  renameGroup: (id, name) => ipcRenderer.invoke('groups:rename', id, name),
  deleteGroup: (id) => ipcRenderer.invoke('groups:delete', id),
  toggleItemGroup: (itemId, groupId) => ipcRenderer.invoke('items:toggleGroup', itemId, groupId),
  copyItem: (id) => ipcRenderer.invoke('items:copy', id),
  togglePinned: (id) => ipcRenderer.invoke('items:pin', id),
  deleteItem: (id) => ipcRenderer.invoke('items:delete', id),
  clearAll: () => ipcRenderer.invoke('items:clear'),
  hideWindow: () => ipcRenderer.invoke('window:hide'),
  onUpdated: (handler) => {
    const listener = () => handler()
    ipcRenderer.on('items:updated', listener)
    return () => ipcRenderer.removeListener('items:updated', listener)
  },
})
