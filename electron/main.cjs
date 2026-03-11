const path = require('path')
const {
  app,
  BrowserWindow,
  Tray,
  Menu,
  nativeImage,
  globalShortcut,
  clipboard,
  screen,
  ipcMain,
} = require('electron')

const { registerIpc } = require('./ipc.cjs')
const store = require('./store.cjs')

let tray = null
let win = null
let pollTimer = null
let lastText = ''

const PANEL_MARGIN = 18

if (process.env.VITE_DEV_SERVER_URL || process.env.XIAOTIE_NO_SANDBOX === '1') {
  app.commandLine.appendSwitch('no-sandbox')
  app.commandLine.appendSwitch('disable-gpu-sandbox')
}

if (process.env.XIAOTIE_USERDATA_DIR) {
  app.setPath('userData', path.resolve(process.cwd(), process.env.XIAOTIE_USERDATA_DIR))
}

function resolveAssetPath(rel) {
  return path.join(__dirname, rel)
}

function getDevServerUrl() {
  return process.env.VITE_DEV_SERVER_URL || ''
}

function isDev() {
  return Boolean(getDevServerUrl())
}

function createWindow() {
  win = new BrowserWindow({
    width: 1020,
    height: 420,
    show: false,
    resizable: false,
    fullscreenable: false,
    maximizable: false,
    minimizable: false,
    transparent: process.platform === 'darwin',
    vibrancy: process.platform === 'darwin' ? 'under-window' : undefined,
    visualEffectState: process.platform === 'darwin' ? 'active' : undefined,
    backgroundColor: process.platform === 'darwin' ? '#00000000' : '#f7f7f9',
    titleBarStyle: process.platform === 'darwin' ? 'hiddenInset' : undefined,
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      preload: resolveAssetPath('preload.cjs'),
    },
  })

  win.setAlwaysOnTop(true, 'floating')
  win.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true })
  win.setSkipTaskbar(true)

  const url = getDevServerUrl()
  if (url) {
    win.loadURL(url)
    if (process.env.XIAOTIE_DEVTOOLS === '1') {
      win.webContents.openDevTools({ mode: 'detach' })
    }
  } else {
    win.loadFile(path.join(app.getAppPath(), 'dist', 'index.html'))
  }

  win.on('blur', () => win.hide())

  return win
}

function toggleWindow() {
  if (!win) return
  if (win.isVisible()) {
    win.hide()
    return
  }

  const cursor = screen.getCursorScreenPoint()
  const display = screen.getDisplayNearestPoint(cursor)
  const bounds = display.workArea
  const [w, h] = win.getSize()

  const x = bounds.x + Math.round((bounds.width - w) / 2)
  const y = bounds.y + bounds.height - h - PANEL_MARGIN

  win.setPosition(x, y, false)
  win.show()
  win.focus()
}

function ensureTray() {
  if (tray) return tray

  const iconPath = path.join(app.getAppPath(), 'src-tauri', 'icons', '32x32.png')
  const icon = nativeImage.createFromPath(iconPath)
  tray = new Tray(icon.isEmpty() ? nativeImage.createEmpty() : icon)
  tray.setToolTip('小贴')
  tray.on('click', () => toggleWindow())

  const menu = Menu.buildFromTemplate([
    { label: '打开小贴', click: () => toggleWindow() },
    { type: 'separator' },
    { label: '退出', click: () => app.quit() },
  ])
  tray.setContextMenu(menu)
  return tray
}

function notifyUpdated() {
  if (!win) return
  win.webContents.send('items:updated')
}

function startClipboardPolling() {
  if (pollTimer) return

  pollTimer = setInterval(() => {
    const text = clipboard.readText()
    if (!text || !text.trim()) return
    if (text === lastText) return

    lastText = text
    const res = store.upsertText(text)
    if (res.changed) notifyUpdated()
  }, 400)
}

function registerShortcuts() {
  globalShortcut.register('CommandOrControl+Shift+V', () => {
    toggleWindow()
  })
}

app.setName('小贴')
if (process.platform === 'darwin') {
  app.dock.hide()
}

app.whenReady().then(() => {
  createWindow()
  ensureTray()
  registerShortcuts()
  startClipboardPolling()

  ipcMain.handle('window:hide', async () => {
    win?.hide()
    return true
  })

  registerIpc({ notifyUpdated })
})

app.on('activate', () => {
  if (!win) createWindow()
  toggleWindow()
})

app.on('window-all-closed', (e) => {
  e.preventDefault()
})

app.on('before-quit', () => {
  if (pollTimer) clearInterval(pollTimer)
  globalShortcut.unregisterAll()
})
