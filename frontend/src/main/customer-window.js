'use strict'

// Jendela kedua "Display Pelanggan" (desktop) — dibuka di monitor kedua bila ada,
// memuat renderer yang sama (index.html?display=customer) & menerima state
// keranjang/bayar dari window kasir lewat IPC 'customer:state'.

const path = require('node:path')
const { BrowserWindow, screen } = require('electron')

let win = null
let lastState = null
let external = false

function pickDisplay() {
  try {
    const displays = screen.getAllDisplays()
    const primary = screen.getPrimaryDisplay()
    const ext = displays.find((d) => d.id !== primary.id)
    return { display: ext || primary, isExternal: !!ext }
  } catch {
    return { display: null, isExternal: false }
  }
}

function open() {
  if (win && !win.isDestroyed()) {
    win.show(); win.focus()
    return { opened: true, external }
  }
  const { display, isExternal } = pickDisplay()
  external = isExternal
  const b = display ? display.bounds : { x: 140, y: 140, width: 1024, height: 640 }
  win = new BrowserWindow({
    x: b.x + (isExternal ? 0 : 40),
    y: b.y + (isExternal ? 0 : 40),
    width: isExternal ? b.width : Math.min(1024, b.width - 80),
    height: isExternal ? b.height : Math.min(640, b.height - 80),
    fullscreen: isExternal, // penuh di monitor kedua; berjendela bila hanya 1 monitor
    backgroundColor: '#06201c',
    title: 'Display Pelanggan — Tuléh',
    autoHideMenuBar: true,
    webPreferences: {
      preload: path.join(__dirname, '..', 'preload', 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      webSecurity: true,
      devTools: false
    }
  })
  win.loadFile(path.join(__dirname, '..', 'renderer', 'index.html'), { query: { display: 'customer' } })
  win.webContents.setWindowOpenHandler(() => ({ action: 'deny' }))
  win.webContents.on('will-navigate', (e) => e.preventDefault())
  // Kirim state terakhir begitu siap (agar tak kosong saat baru dibuka).
  win.webContents.on('did-finish-load', () => {
    if (lastState && win && !win.isDestroyed()) win.webContents.send('customer:state', lastState)
  })
  win.on('closed', () => { win = null })
  return { opened: true, external }
}

function close() {
  if (win && !win.isDestroyed()) win.close()
  win = null
  return { closed: true }
}

function update(state) {
  lastState = state || null
  if (win && !win.isDestroyed()) win.webContents.send('customer:state', lastState)
  return { ok: true }
}

function isOpen() { return !!(win && !win.isDestroyed()) }

module.exports = { open, close, update, isOpen }
