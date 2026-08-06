'use strict'

const fs = require('node:fs')
const path = require('node:path')
const { app, BrowserWindow, Menu, shell } = require('electron')
const { registerIpcHandlers } = require('./ipc')
const gateway = require('./gateway')

const IS_SMOKE = process.env.IPOS_SMOKE === '1'

// Locale Indonesia agar <input type=date> tampil dd/mm/yyyy
app.commandLine.appendSwitch('lang', 'id')

// Renderer berjalan penuh dalam sandbox Chromium
app.enableSandbox()

if (!app.requestSingleInstanceLock()) {
  app.quit()
} else {
  let mainWindow = null

  function createWindow() {
    mainWindow = new BrowserWindow({
      width: 1400,
      height: 880,
      minWidth: 1024,
      minHeight: 680,
      show: false,
      backgroundColor: '#f3faf8',
      title: 'Tuléh',
      autoHideMenuBar: true,
      webPreferences: {
        preload: path.join(__dirname, '..', 'preload', 'preload.js'),
        contextIsolation: true,
        nodeIntegration: false,
        sandbox: true,
        webSecurity: true,
        spellcheck: false,
        devTools: !app.isPackaged
      }
    })

    mainWindow.loadFile(path.join(__dirname, '..', 'renderer', 'index.html'))
    mainWindow.once('ready-to-show', () => mainWindow.show())
    // Tutup Display Pelanggan bila window kasir ditutup (agar app bisa quit).
    mainWindow.on('closed', () => { require('./customer-window').close() })

    // Keamanan: tidak ada navigasi keluar dari aplikasi & tidak ada window baru.
    // Tautan https eksternal dibuka di browser OS.
    mainWindow.webContents.setWindowOpenHandler(({ url }) => {
      if (url.startsWith('https://')) shell.openExternal(url)
      return { action: 'deny' }
    })
    mainWindow.webContents.on('will-navigate', (event) => event.preventDefault())

    if (IS_SMOKE) {
      // Mode uji asap: kumpulkan log renderer, tulis laporan, lalu keluar.
      const smokeLog = []
      mainWindow.webContents.on('console-message', (_event, level, message, line, sourceId) => {
        smokeLog.push(`[${level}] ${message} (${sourceId}:${line})`)
      })
      mainWindow.webContents.on('did-fail-load', (_event, code, desc) => {
        smokeLog.push(`did-fail-load: ${code} ${desc}`)
      })
      mainWindow.webContents.once('did-finish-load', () => {
        // Uji tunnel butuh waktu koneksi edge lebih lama
        const tundaSmokeMs = process.env.IPOS_SMOKE_TUNNEL === '1' ? 30000
          : process.env.IPOS_SMOKE_FLOW ? 3000 : 1500
        setTimeout(async () => {
          if (process.env.IPOS_SMOKE_SHOT) {
            try {
              const image = await mainWindow.webContents.capturePage()
              fs.writeFileSync(process.env.IPOS_SMOKE_SHOT, image.toPNG())
            } catch (err) {
              console.error('Gagal mengambil screenshot smoke:', err)
            }
          }
          if (process.env.IPOS_SMOKE_OUT) {
            try {
              fs.writeFileSync(process.env.IPOS_SMOKE_OUT,
                JSON.stringify({
                  loaded: true,
                  gateway: gateway.status(),
                  tracking: require('./tracker').status(),
                  log: smokeLog
                }, null, 2))
            } catch (err) {
              console.error('Gagal menulis laporan smoke:', err)
            }
          }
          console.log('SMOKE_OK')
          // Uji tunnel: tahan aplikasi tetap hidup agar penguji eksternal
          // sempat mengakses URL publik (tunnel mati bersama aplikasi)
          const tahanMs = process.env.IPOS_SMOKE_TUNNEL === '1' ? 45000 : 0
          setTimeout(() => app.quit(), tahanMs)
        }, tundaSmokeMs)
      })
    }
  }

  app.on('second-instance', () => {
    if (mainWindow) {
      if (mainWindow.isMinimized()) mainWindow.restore()
      mainWindow.focus()
    }
  })

  app.whenReady().then(() => {
    Menu.setApplicationMenu(null)
    registerIpcHandlers(() => mainWindow)
    createWindow()

    // Buka akses LAN (firewall) OTOMATIS — agar TV/HP di jaringan bisa membuka
    // Display Pelanggan (/display) & Papan Antrian (/antrian). UAC muncul sekali
    // saja bila aturan belum ada; setelah disetujui, permanen. Hanya di build
    // terpasang (dev dilewati agar tak mengganggu). Tak memblokir startup.
    if (app.isPackaged) {
      setTimeout(() => { require('./firewall').ensure().catch(() => {}) }, 1500)
    }

    app.on('activate', () => {
      if (BrowserWindow.getAllWindows().length === 0) createWindow()
    })
  })

  app.on('window-all-closed', () => {
    if (process.platform !== 'darwin') app.quit()
  })

  // Matikan gateway yang kita nyalakan (instance eksternal dibiarkan hidup)
  // beserta server pelacakan pelanggan
  app.on('will-quit', () => {
    gateway.stop()
    require('./tracker').stop()
    require('./tunnel').stop()
  })
}
