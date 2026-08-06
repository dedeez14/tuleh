'use strict'

// Auto-Update — Tahap 3 (Windows/desktop): electron-updater.
//  - Feed: generic provider → https://pos.tatreport.com/unduh (latest.yml + .exe)
//  - Alur: check → downloadUpdate (progress) → quitAndInstall.
//  - autoDownload=false: unduh HANYA saat pengguna menekan "Update Sekarang".
//  - TLS bawaan electron-updater tidak pernah dinonaktifkan (verifikasi sha512
//    dari latest.yml tetap aktif). Kegagalan → renderer fallback ke unduhan browser.

const { app } = require('electron')

let autoUpdater = null
let loaded = false // sudah mencoba require('electron-updater')?
let listenersBound = false
let send = null // (channel, payload) → kirim ke renderer (di-set oleh init)
let downloaded = false

function log(...a) { try { console.log('[updater]', ...a) } catch { /* abaikan */ } }

/** Muat electron-updater secara lazy. null bila belum terpasang (mode dev). */
function get() {
  if (loaded) return autoUpdater
  loaded = true
  try {
    autoUpdater = require('electron-updater').autoUpdater
    autoUpdater.autoDownload = false
    autoUpdater.autoInstallOnAppQuit = true
    autoUpdater.logger = { info: log, warn: log, error: log, debug: () => {} }
  } catch (err) {
    log('electron-updater tak tersedia:', err && err.message)
    autoUpdater = null
  }
  return autoUpdater
}

/** true bila auto-update in-app didukung (build terpasang + modul ada). */
function isSupported() {
  return app.isPackaged && !!get()
}

/** Pasang listener event sekali; relay progress/selesai/error ke renderer. */
function init(sendToRenderer) {
  send = typeof sendToRenderer === 'function' ? sendToRenderer : null
  const u = get()
  if (!u || listenersBound) return
  listenersBound = true
  u.on('download-progress', (p) => {
    if (send) send('update:progress', { percent: Math.round(p.percent || 0), transferred: p.transferred, total: p.total, bytesPerSecond: p.bytesPerSecond })
  })
  u.on('update-downloaded', (info) => {
    downloaded = true
    log('unduhan pembaruan selesai:', info && info.version)
    if (send) send('update:downloaded', { version: (info && info.version) || '' })
  })
  u.on('error', (err) => {
    log('error updater:', err && err.message)
    if (send) send('update:error', { message: (err && err.message) || 'Gagal memperbarui.' })
  })
}

/** Cek ketersediaan update via feed generic. */
async function check() {
  const u = get()
  if (!u) return { ok: false, supported: false, message: 'Auto-update tidak tersedia.' }
  try {
    const r = await u.checkForUpdates()
    const info = r && r.updateInfo ? r.updateInfo : null
    const available = !!(r && r.isUpdateAvailable)
    return { ok: true, supported: true, updateAvailable: available, version: info ? info.version : null }
  } catch (err) {
    return { ok: false, supported: true, message: (err && err.message) || 'Gagal memeriksa pembaruan.' }
  }
}

/** Unduh pembaruan (progress via event). Panggil check dulu agar updateInfo terisi. */
async function download() {
  const u = get()
  if (!isSupported()) return { ok: false, supported: false, message: 'Auto-update hanya di aplikasi terpasang.' }
  try {
    if (downloaded) return { ok: true, alreadyDownloaded: true }
    const r = await u.checkForUpdates()
    if (!r || !r.isUpdateAvailable) return { ok: false, supported: true, message: 'Tidak ada pembaruan yang bisa diunduh.' }
    await u.downloadUpdate()
    return { ok: true }
  } catch (err) {
    return { ok: false, supported: true, message: (err && err.message) || 'Gagal mengunduh pembaruan.' }
  }
}

/** Keluar & pasang pembaruan yang sudah diunduh. */
function install() {
  const u = get()
  if (!u || !downloaded) return { ok: false, message: 'Pembaruan belum siap dipasang.' }
  // isSilent=false (tampilkan installer), isForceRunAfter=true (buka lagi setelah pasang).
  setImmediate(() => { try { u.quitAndInstall(false, true) } catch (err) { log('quitAndInstall gagal:', err && err.message) } })
  return { ok: true }
}

module.exports = { init, check, download, install, isSupported }
