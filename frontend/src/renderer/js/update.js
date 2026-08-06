// Auto-Update — layar update (2 mode) + eksekusi pembaruan.
//  - wajib=true            → layar penuh MEMBLOKIR (tanpa tutup/lewati)
//  - update_tersedia=true  → banner bisa ditunda (maks 1×/hari)
//  - gagal jaringan        → FAIL-OPEN (jangan blokir; penegakan keras via 426 API)
// Eksekusi:
//  - Desktop terpasang → electron-updater (unduh dalam app + progress + pasang).
//  - Android / dev / tak didukung → buka URL unduhan di peramban (Tahap 4 akan
//    mengganti Android dgn unduh+install in-app).
// Kontrak /app/versi: { wajib, update_tersedia, versi_terbaru, catatan,
//   unduhan:{ windows:{url,...}, android:{url,...} }, ukuran }

import { api } from './api.js'
import { LOGO_DATA_URI } from './assets/logo.js'

const BANNER_KEY = 'tuleh_update_banner_last' // 1×/hari
const DAY_MS = 24 * 60 * 60 * 1000
const CHECK_THROTTLE_MS = 30 * 60 * 1000 // jangan cek terlalu sering saat foreground

let overlayEl = null
let backGuard = null
let lastCheck = 0
let platform = null
let versiApp = ''

// State eksekusi (dibaca oleh handler klik tombol layar wajib).
let currentInfo = null
let inApp = false // memakai updater in-app (electron-updater / plugin APK)?
let inAppChecked = false // sudah tanya updateSupported?
let phase = 'idle' // idle | downloading | ready | manual
let updaterWired = false

function log(...a) { try { console.log('[update]', ...a) } catch { /* abaikan */ } }
function esc(s) { return String(s == null ? '' : s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c])) }

async function loadInfo() {
  try {
    const r = await api.app.info()
    if (r && r.ok && r.data) { platform = r.data.platform || 'unknown'; versiApp = r.data.version || '' }
  } catch { /* abaikan */ }
}

/**
 * Cek versi ke server. opts.force → tampilkan layar wajib walau bukan `wajib`
 * (dipakai saat 426). opts.message → pesan fallback bila detail tak terambil.
 */
export async function checkForUpdate(opts = {}) {
  if (!api.app || typeof api.app.checkUpdate !== 'function') return
  if (!opts.force && Date.now() - lastCheck < CHECK_THROTTLE_MS) return
  lastCheck = Date.now()
  if (!versiApp) await loadInfo()

  let info = null
  try {
    const r = await api.app.checkUpdate()
    if (r && r.ok) info = r.data || {}
    else log('cek versi gagal (fail-open):', r && r.status, r && r.message)
  } catch { log('cek versi error (fail-open)') }

  if (!info) {
    // Gagal jaringan: fail-open. Kecuali dipaksa 426 → tetap blokir dgn pesan.
    if (opts.force) showUpdate({ message: opts.message }, { block: true })
    return
  }
  log('versi Anda', versiApp, '| hasil:', JSON.stringify(info))
  if (info.wajib || opts.force) showUpdate(info, { block: true })
  else if (info.update_tersedia) maybeBanner(info)
}

/** Dipanggil saat menerima 426 dari server (event update:required). */
export function onServerForcedUpdate(payload) {
  log('426 dari server → layar update wajib')
  checkForUpdate({ force: true, message: payload && payload.message })
}

function unduhanUrl(info) {
  const u = info && info.unduhan
  if (!u) return ''
  return platform === 'android' ? (u.android && u.android.url) || '' : (u.windows && u.windows.url) || ''
}

// ---------- Layar update (blocking untuk wajib, opt-in dari banner) ----------

function showUpdate(info, { block = true } = {}) {
  if (overlayEl) return // sudah tampil
  currentInfo = info
  phase = 'idle'
  overlayEl = document.createElement('div')
  overlayEl.className = 'upd upd--block'
  overlayEl.innerHTML = `
    <div class="upd__card">
      <img class="upd__logo" src="${LOGO_DATA_URI}" alt="Tuléh" />
      <h1 class="upd__title">${block ? 'Update Diperlukan' : 'Pembaruan Tersedia'}</h1>
      <p class="upd__msg">${esc(info.catatan || info.message || 'Versi baru tersedia untuk aplikasi ini.')}</p>
      <div class="upd__ver">
        <span>Versi Anda <b>${esc(versiApp || '-')}</b></span>
        ${info.versi_terbaru ? `<span class="upd__arrow">&rarr;</span><span>Terbaru <b>${esc(info.versi_terbaru)}</b></span>` : ''}
      </div>
      <button type="button" class="upd__btn" id="upd-go">Update Sekarang</button>
      <div class="upd__prog u-hidden" id="upd-prog"><div class="upd__bar" id="upd-bar"></div></div>
      <div class="upd__hint" id="upd-hint"></div>
      ${block ? '' : '<button type="button" class="upd__later" id="upd-later">Nanti saja</button>'}
    </div>`
  document.body.appendChild(overlayEl)
  if (block) swallowBack(true)
  overlayEl.querySelector('#upd-go').addEventListener('click', onUpdateClick)
  const later = overlayEl.querySelector('#upd-later')
  if (later) later.addEventListener('click', closeOverlay)
}

function closeOverlay() {
  if (!overlayEl) return
  swallowBack(false)
  overlayEl.remove()
  overlayEl = null
}

function setProgress(percent) {
  if (!overlayEl) return
  const prog = overlayEl.querySelector('#upd-prog')
  const bar = overlayEl.querySelector('#upd-bar')
  if (prog) prog.classList.remove('u-hidden')
  if (bar) bar.style.width = Math.max(0, Math.min(100, percent)) + '%'
}
function setBtn(text, disabled) {
  const btn = overlayEl && overlayEl.querySelector('#upd-go')
  if (!btn) return
  btn.textContent = text
  btn.disabled = !!disabled
}
function setHint(text) {
  const hint = overlayEl && overlayEl.querySelector('#upd-hint')
  if (hint) hint.textContent = text || ''
}

// Klik tombol utama — routing sesuai fase (unduh → tunggu → pasang / manual).
async function onUpdateClick() {
  if (phase === 'downloading') return
  if (phase === 'ready') { await api.app.installUpdate(); return }
  if (phase === 'manual') { return openManual(currentInfo) }

  // Tentukan jalur: desktop (electron-updater) / Android (plugin APK) → in-app;
  // peramban / dev / tak didukung → unduhan manual.
  if (!inAppChecked) {
    inAppChecked = true
    if (api.app && typeof api.app.updateSupported === 'function') {
      try { const s = await api.app.updateSupported(); inApp = !!(s && s.ok && s.data && s.data.supported) } catch { inApp = false }
    }
  }
  if (!inApp) return openManual(currentInfo)
  return startInAppUpdate()
}

async function startInAppUpdate() {
  wireUpdaterEvents()
  const url = unduhanUrl(currentInfo)
  const filename = 'Tuleh-' + ((currentInfo && currentInfo.versi_terbaru) || 'update') + (platform === 'android' ? '-android.apk' : '.exe')
  phase = 'downloading'
  setBtn('Mengunduh…', true)
  setHint('Mengunduh pembaruan…')
  setProgress(0)
  const r = await api.app.downloadUpdate({ url, filename })
  if (r && r.needPermission) {
    // Android belum diizinkan memasang → user aktifkan izin lalu tekan lagi.
    phase = 'idle'
    setBtn('Coba Lagi', false)
    setHint(r.message || 'Izinkan pemasangan lalu coba lagi.')
    return
  }
  if (r && r.ok && r.alreadyDownloaded) { markReady(); return }
  if (!r || !r.ok) {
    // Gagal unduh in-app → tawarkan unduhan manual (peramban).
    phase = 'manual'
    setBtn('Unduh Manual', false)
    setHint((r && r.message ? r.message + ' ' : '') + 'Coba unduh lewat peramban.')
  }
  // Sukses: tunggu event 'update:downloaded' → markReady().
}

function markReady() {
  phase = 'ready'
  setProgress(100)
  setBtn('Pasang & Mulai Ulang', false)
  setHint('Pembaruan siap dipasang.')
}

function wireUpdaterEvents() {
  if (updaterWired || !api.app || typeof api.app.onUpdateProgress !== 'function') return
  updaterWired = true
  api.app.onUpdateProgress((p) => { if (phase === 'downloading') { setProgress(p.percent || 0); setHint('Mengunduh pembaruan… ' + Math.round(p.percent || 0) + '%') } })
  api.app.onUpdateDownloaded(() => markReady())
  api.app.onUpdateError((e) => {
    phase = 'manual'
    setBtn('Unduh Manual', false)
    setHint((e && e.message ? e.message + ' ' : '') + 'Coba unduh lewat peramban.')
  })
}

async function openManual(info) {
  let url = unduhanUrl(info)
  if (!url) {
    setHint('Mengambil info update…')
    try { const r = await api.app.checkUpdate(); if (r && r.ok && r.data) { currentInfo = r.data; url = unduhanUrl(r.data) } } catch { /* abaikan */ }
  }
  if (!url) { setHint('Info unduhan belum tersedia. Periksa koneksi & coba lagi.'); return }
  log('unduh manual →', url)
  const r = await api.app.openExternal(url)
  if (r && !r.ok) { setHint(r.message || 'Gagal membuka unduhan.'); return }
  // Android: peramban mengunduh APK (DownloadManager: progres + resume + notifikasi).
  // Beri panduan pemasangan agar pengguna tak bingung setelah unduhan selesai.
  if (platform === 'android') {
    setHint('Unduhan dimulai. Setelah selesai, buka berkas untuk memasang — izinkan "Instal aplikasi tak dikenal" bila diminta.')
  } else {
    setHint('Unduhan dibuka di peramban. Jalankan installer setelah selesai mengunduh.')
  }
}

// ---------- Banner opsional (bawah layar, bisa ditutup, maks 1×/hari) ----------

function maybeBanner(info) {
  if (document.querySelector('.upd-banner')) return
  try { if (Date.now() - Number(localStorage.getItem(BANNER_KEY) || 0) < DAY_MS) return } catch { /* abaikan */ }
  const b = document.createElement('div')
  b.className = 'upd-banner'
  b.innerHTML = `
    <span class="upd-banner__txt">Versi ${esc(info.versi_terbaru || 'baru')} tersedia &mdash; perbarui untuk fitur & perbaikan terbaru.</span>
    <button type="button" class="upd-banner__go" id="ub-go">Perbarui</button>
    <button type="button" class="upd-banner__x" id="ub-x" aria-label="Tutup">&times;</button>`
  document.body.appendChild(b)
  try { localStorage.setItem(BANNER_KEY, String(Date.now())) } catch { /* abaikan */ }
  b.querySelector('#ub-x').addEventListener('click', () => b.remove())
  b.querySelector('#ub-go').addEventListener('click', () => { b.remove(); showUpdate(info, { block: false }) })
}

// Telan tombol Back saat layar wajib tampil (Android/WebView) — tak boleh keluar.
function swallowBack(on) {
  if (on && !backGuard) {
    try { history.pushState(null, '', location.href) } catch { /* abaikan */ }
    backGuard = () => { try { history.pushState(null, '', location.href) } catch { /* abaikan */ } }
    window.addEventListener('popstate', backGuard)
  } else if (!on && backGuard) {
    window.removeEventListener('popstate', backGuard); backGuard = null
  }
}
