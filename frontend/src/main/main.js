'use strict'

const fs = require('node:fs')
const path = require('node:path')
const { app, BrowserWindow, Menu, shell, session } = require('electron')
// Log berkas SEDINI mungkin: galat saat memuat modul lain pun tercatat.
const diagnostik = require('./diagnostik')
diagnostik.mulaiLog()
const { registerIpcHandlers } = require('./ipc')
const gateway = require('./gateway')
const { urlHttpsAman } = require('./lib/url-aman')
const { izinkan } = require('./lib/izin')

// Galat proses utama yang lolos → log + laporan dukungan (antre bila offline).
// Aplikasi tetap berjalan: kasir di tengah transaksi tidak boleh tertutup mendadak.
process.on('uncaughtException', (err) => {
  console.error('[crash] uncaughtException:', err)
  diagnostik.lapor({ jenis: 'crash', pesan: (err && err.message) || String(err), stack: (err && err.stack) || '', konteks: { sumber: 'main' } })
})
process.on('unhandledRejection', (alasan) => {
  console.error('[galat] unhandledRejection:', alasan)
  diagnostik.lapor({ jenis: 'error', pesan: (alasan && alasan.message) || String(alasan), stack: (alasan && alasan.stack) || '', konteks: { sumber: 'main' } })
})

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

    // Log renderer → logs/renderer.log (Electron ≥35: properti di objek event; lama: argumen posisi).
    mainWindow.webContents.on('console-message', (event, level, message, line, sourceId) => {
      const e = event && typeof event === 'object' ? event : {}
      const lv = e.level !== undefined ? e.level : level
      const teks = e.message !== undefined ? e.message : message
      const tingkat = ['info', 'info', 'warn', 'error'][Number(lv)] || String(lv)
      diagnostik.log('renderer', tingkat, `${teks} (${e.sourceId || sourceId || ''}:${e.lineNumber || line || ''})`)
    })
    mainWindow.webContents.on('render-process-gone', (_event, details) => {
      diagnostik.lapor({
        jenis: 'crash',
        pesan: `Renderer berhenti: ${details && details.reason} (kode ${details && details.exitCode})`,
        konteks: { sumber: 'renderer', layar: 'jendela-kasir' }
      })
    })
    // Tutup Display Pelanggan bila window kasir ditutup (agar app bisa quit).
    mainWindow.on('closed', () => { require('./customer-window').close() })

    // Keamanan: tidak ada navigasi keluar dari aplikasi & tidak ada window baru.
    // Tautan https eksternal dibuka di browser OS.
    mainWindow.webContents.setWindowOpenHandler(({ url }) => {
      const aman = urlHttpsAman(url)
      if (aman) shell.openExternal(aman)
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
        // Uji tunnel butuh waktu koneksi edge lebih lama. IPOS_SMOKE_DELAY (ms)
        // menimpa semua: screenshot layar butuh > durasi splash (2800 ms),
        // jika tidak yang tertangkap hanya splash "Memuat…".
        const delayEnv = Number(process.env.IPOS_SMOKE_DELAY)
        const tundaSmokeMs = Number.isFinite(delayEnv) && delayEnv > 0 ? delayEnv
          : process.env.IPOS_SMOKE_TUNNEL === '1' ? 30000
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

  // Windows: notifikasi sistem (pemantau pesanan meja) butuh AppUserModelID yang
  // sama dengan appId electron-builder agar toast memakai nama & ikon Tuléh.
  if (process.platform === 'win32') app.setAppUserModelId('com.movera.mpos')
  app.whenReady().then(() => {
    Menu.setApplicationMenu(null)

    // Izin Chromium: tolak semua kecuali yang dipakai (lib/izin.js).
    const asalPeminta = (wc, details) => (details && (details.requestingUrl || details.embeddingOrigin)) || (wc && !wc.isDestroyed() ? wc.getURL() : '')
    session.defaultSession.setPermissionRequestHandler((wc, permission, callback, details) => {
      const boleh = izinkan(permission, { asalUrl: asalPeminta(wc, details), webContentsId: wc ? wc.id : null })
      if (!boleh) console.warn('[izin] ditolak:', permission, asalPeminta(wc, details))
      callback(boleh)
    })
    session.defaultSession.setPermissionCheckHandler((wc, permission, requestingOrigin, details) => {
      return izinkan(permission, { asalUrl: (details && details.requestingUrl) || requestingOrigin || (wc && !wc.isDestroyed() ? wc.getURL() : ''), webContentsId: wc ? wc.id : null })
    })

    registerIpcHandlers(() => mainWindow)
    createWindow()

    // Akses LAN (firewall) TIDAK lagi diminta saat start: firewall.js meminta hanya
    // saat pengguna memakai tampilan LAN (Papan Antrian / tombol "Buka akses jaringan").

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
