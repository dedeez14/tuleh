// Titik masuk renderer: boot, login, pemilihan toko, shell (top bar +
// Beranda kartu) dan navigasi. POS universal: kartu Beranda dirender dinamis
// dari MANIFEST toko — bakso melihat Dapur & Antrian, laundry melihat Papan
// Proses, minimarket tetap ringkas. (Blueprint-Universal-POS.md, Fase 1)

import { api, firstError } from './api.js'
import { getState, setState, subscribe, resetAuthState } from './state.js'
import { toast, icons, confirmDialog } from './components/ui.js'
import { applyTheme, getEffectiveTheme, cycleTheme } from './theme.js'
import { hitungNotifikasi, renderPanelNotifikasi } from './notif.js'
import { ringkasLangganan } from './langganan.js'
import { esc, fmtIDR, fmtNumber, toISODate } from './utils/format.js'
import { LOGO_DATA_URI } from './assets/logo.js'
import { renderLogin } from './screens/login.js'
import { PosScreen } from './screens/pos.js'
import { HistoryScreen } from './screens/history.js'
import { SessionsScreen } from './screens/sessions.js'
import { ReportsScreen } from './screens/reports.js'
import { SettingsScreen } from './screens/settings.js'
import { OrdersScreen } from './screens/orders.js'
import { StationsScreen } from './screens/stations.js'
import { ProductsScreen } from './screens/products.js'
import { CustomersScreen } from './screens/customers.js'
import { TablesScreen } from './screens/tables.js'
import { PetaMejaScreen } from './screens/peta-meja.js'
import { KeuanganScreen } from './screens/keuangan.js'
import { PengeluaranScreen } from './screens/pengeluaran.js'
import { StokScreen } from './screens/stok.js'
import { analisisStok } from './lib/stok-store.js'

const SCREENS = [
  PosScreen, HistoryScreen, SessionsScreen, ReportsScreen, SettingsScreen,
  OrdersScreen, StationsScreen, ProductsScreen, CustomersScreen, TablesScreen, PetaMejaScreen,
  KeuanganScreen, PengeluaranScreen, StokScreen
]
const LAST_TOKO_KEY = 'mpos.lastTokoId'

// ---------- Registry modul (id menu manifest → layar / modul mendatang) ----------
// Modul dengan `screen` sudah terbangun; `phase` = kartu "segera hadir" agar
// wajah tiap bidang usaha terlihat sejak Fase 1.

const MODULES = {
  kasir: { screen: 'pos', title: 'Kasir', icon: null, desc: 'Catat penjualan dengan cepat — katalog, barcode, dan pembayaran.' },
  riwayat: { screen: 'history', title: 'Riwayat', icon: null, desc: 'Telusuri transaksi, cetak ulang struk, atau batalkan.' },
  sesi: { screen: 'sessions', title: 'Sesi Kasir', icon: null, desc: 'Buka/tutup shift kasir dan lihat rekap kas X/Z.' },
  laporan: { screen: 'reports', title: 'Laporan', icon: null, desc: 'Penjualan harian, per produk, stok, dan rekap kasir.' },
  pengaturan: { screen: 'settings', title: 'Pengaturan', icon: null, desc: 'Server, akun, dan informasi aplikasi.' },
  dapur: { screen: 'orders', title: 'Dapur (KDS)', iconKey: 'kitchen', desc: 'Layar dapur: klaim pesanan, mulai masak, tandai siap.' },
  antrian: { screen: 'orders', title: 'Antrian', iconKey: 'queue', desc: 'Papan nomor antrian pesanan yang sedang berjalan.' },
  proses: { screen: 'orders', title: 'Papan Proses', iconKey: 'kanban', desc: 'Tahapan pengerjaan: cuci, kering, lipat, siap ambil.' },
  meja: { screen: 'peta-meja', title: 'Meja', iconKey: 'store', desc: 'Buka meja, catat pesanan, dan bayar saat pulang.' },
  stasiun: { screen: 'stations', title: 'Stasiun', iconKey: 'station', desc: 'Atur jumlah & status stasiun kerja di toko ini.' },
  produk: { screen: 'products', title: 'Produk', iconKey: 'box', desc: 'Jelajahi katalog — harga, barcode, dan posisi stok.' },
  inventory: { screen: 'inventory', title: 'Inventory', iconKey: 'box', desc: 'Tambah/kurangi stok, opname, & riwayat perubahan stok.' },
  pelanggan: { screen: 'customers', title: 'Pelanggan', iconKey: 'user', desc: 'Cari, lihat, dan tambahkan pelanggan.' },
  keuangan: { screen: 'keuangan', title: 'Keuangan', iconKey: 'report', desc: 'Omzet, laba, margin, metode bayar, dan tren.' },
  pengeluaran: { screen: 'pengeluaran', title: 'Pengeluaran', iconKey: 'wallet', desc: 'Catat biaya operasional: sewa, gaji, listrik, bahan.' },
  stok: { screen: 'stok', title: 'Stok', iconKey: 'box', desc: 'Pantau stok menipis, atur batas minimum, & saran restok.' }
}

// Fitur ekstra khas app (DI LUAR manifest server) — analisis keuangan UMKM.
// Ditampilkan SETELAH menu manifest, hanya utk peran manajemen. Server tidak
// mengelola menu ini; keputusan pemilik (2 Agu 2026) mempertahankannya sbg
// nilai tambah app. Bukan pelanggaran "menu dari manifest" (itu soal filter peran).
const APP_EXTRA_MODULES = ['keuangan', 'stok']
const MANAGEMENT_ROLES = new Set(['OWNER', 'MANAGER'])
// Route_key yang bukan kartu Beranda (dashboard = Beranda itu sendiri).
const NON_CARD_ROUTES = new Set(['dashboard', 'home'])
// Fallback bila manifest tak menyertakan menus (server lama / tanpa /manifest):
// tampilkan set inti agar app tetap terpakai — bukan filter peran, murni kompatibilitas.
const DEFAULT_MENU_IDS = ['kasir', 'riwayat', 'sesi', 'produk', 'pelanggan', 'laporan', 'pengaturan']

// Peta id modul → token warna aksen (dipakai kartu Beranda; ikut dark via token)
const MODULE_ACCENT = {
  kasir: 'kasir', dapur: 'dapur', antrian: 'antrian', proses: 'proses',
  meja: 'meja', stasiun: 'stasiun', riwayat: 'riwayat', sesi: 'sesi',
  laporan: 'laporan', produk: 'produk', inventory: 'produk', pelanggan: 'pelanggan', pengaturan: 'pengaturan',
  keuangan: 'laporan', pengeluaran: 'meja', stok: 'dapur'
}

const appRoot = document.getElementById('app')
let currentCleanup = null
let unsubscribeShell = null
// Notifikasi dianggap terbaca sesi ini setelah pengguna menekan "tandai terbaca".
let notifDismissed = false

// ---------- Manifest: normalisasi & daftar modul ----------

/** Bentuk server (menus objek, capabilities array string) → bentuk internal.
 *  Menu SUDAH terfilter peran & terurut oleh server (kontrak Bidang-Usaha-Role);
 *  app merender apa adanya — tanpa memfilter ulang. `route_key` menentukan layar. */
function normalizeManifest(raw, toko) {
  if (!raw || typeof raw !== 'object') return null
  const menus = (Array.isArray(raw.menus) ? raw.menus : [])
    .map((m) => (typeof m === 'string' ? { id: m } : m))
    .filter((m) => m && typeof m.id === 'string')
    .map((m) => ({
      id: m.id,
      routeKey: m.route_key || m.id,
      label: m.label || '',
      icon: m.icon || '',
      roles: Array.isArray(m.roles) ? m.roles : null,
      order: Number(m.order) || 0
    }))
  return {
    verticalCode: raw.vertical_code || toko?.bidang_usaha?.code || null,
    verticalName: toko?.bidang_usaha?.nama || '',
    archetype: toko?.bidang_usaha?.archetype || null,
    menus,
    role: raw.role || null,
    premiumFeatures: Array.isArray(raw.premium_features) ? raw.premium_features : [],
    capabilities: Array.isArray(raw.capabilities) ? raw.capabilities : [],
    stationTypes: Array.isArray(raw.station_types) ? raw.station_types : [],
    transactionFlow: Array.isArray(raw.transaction_flow) ? raw.transaction_flow : [],
    lifecycle: raw.lifecycle && Array.isArray(raw.lifecycle.states) ? raw.lifecycle : { states: [], transitions: [] },
    itemConfig: raw.item_config || {},
    paymentModes: Array.isArray(raw.payment_modes) ? raw.payment_modes : []
  }
}

/** Kartu Beranda: menu DARI manifest (sudah terfilter peran & terurut server) +
 *  fitur ekstra app utk peran manajemen. Bila manifest tanpa menus → set default
 *  (kompatibilitas server lama). App tidak memfilter ulang berdasarkan peran. */
function moduleList() {
  const { manifest, posRole } = getState()
  const out = []
  const seen = new Set()

  const push = (key, label, appExtra = false) => {
    if (!key || NON_CARD_ROUTES.has(key) || seen.has(key)) return
    const mod = MODULES[key]
    if (!mod) return // route_key yang app belum kenal → jangan render kartu rusak
    seen.add(key)
    out.push({ id: key, ...mod, title: label || mod.title, appExtra })
  }

  const menus = manifest && Array.isArray(manifest.menus) ? manifest.menus : []
  if (menus.length > 0) {
    for (const menu of [...menus].sort((a, b) => (a.order || 0) - (b.order || 0))) {
      push(menu.routeKey || menu.id, menu.label)
    }
  } else {
    for (const id of DEFAULT_MENU_IDS) push(id, '')
  }

  // Fitur ekstra app (keuangan, stok) — hanya manajemen; bila peran tak diketahui
  // (server lama/manifest kosong) tetap tampil agar tak ada regresi fitur.
  if (!posRole || MANAGEMENT_ROLES.has(posRole)) {
    for (const key of APP_EXTRA_MODULES) push(key, '', true)
  }

  return out
}

// ---------- Pemilihan toko ----------

async function loadTokoAndManifest({ forcePicker = false } = {}) {
  const result = await api.toko.list()
  const list = result.ok && Array.isArray(result.data) ? result.data.filter((t) => t.is_active !== false) : []
  setState({ tokoList: list })

  if (list.length === 0) {
    // Server lama tanpa /tokos atau company tanpa toko → wajah default
    setState({ toko: null, manifest: null })
    return
  }

  let chosen = null
  if (list.length === 1) {
    chosen = list[0]
  } else {
    // Jalur uji tampilan: pilih toko via env (screenshot per wajah)
    const info = await api.app.info()
    const smokeIdx = info.ok && info.data && Number.isInteger(info.data.smokeTokoIndex) ? info.data.smokeTokoIndex : null
    if (smokeIdx !== null && list[smokeIdx]) {
      chosen = list[smokeIdx]
    } else if (!forcePicker) {
      const lastId = localStorage.getItem(LAST_TOKO_KEY)
      chosen = list.find((t) => t.id === lastId) || null
    }
    if (!chosen) chosen = await pickToko(list)
  }

  await applyToko(chosen)
}

/** Terapkan toko terpilih: ingat, beri tahu main process, muat manifest,
 *  lalu segarkan data yang berbeda per toko (kategori & sesi kasir). */
async function applyToko(chosen) {
  localStorage.setItem(LAST_TOKO_KEY, chosen.id)
  await api.toko.select({ id: chosen.id })
  const [manifestResult, kategori, sesi] = await Promise.all([
    api.toko.manifest({ id: chosen.id }),
    api.master.kategori(),
    api.sesi.aktif()
  ])
  const patch = {
    toko: chosen,
    manifest: manifestResult.ok ? normalizeManifest(manifestResult.data, chosen) : null
  }
  if (kategori.ok) patch.kategori = kategori.data || []
  if (sesi.ok) {
    patch.session = sesi.data || null
    patch.sessionId = sesi.data && sesi.data.id ? sesi.data.id : null
  }
  setState(patch)
}

/** Layar pemilih toko (full page) — resolve dengan toko yang dipilih,
 *  atau null bila dibatalkan (hanya saat allowCancel). */
function pickToko(list, { allowCancel = false } = {}) {
  return new Promise((resolve) => {
    appRoot.innerHTML = `
      <div class="picker">
        <div class="picker__inner">
          <div class="picker__head">
            <img class="picker__logo" src="${LOGO_DATA_URI}" alt="" />
            <div>
              <h1 class="picker__title">Pilih Toko</h1>
              <p class="picker__desc">Menu dan alur kerja Tuléh menyesuaikan bidang usaha toko.</p>
            </div>
          </div>
          <div class="picker__grid">
            ${list.map((t, i) => `
              <button type="button" class="picker__card" data-idx="${i}">
                <span class="picker__icon">${icons.store}</span>
                <span class="picker__body">
                  <span class="picker__nama">${esc(t.nama)}</span>
                  <span class="picker__bidang">${esc(t.bidang_usaha?.nama || '')}</span>
                </span>
                <span class="badge badge--mint">${esc(t.bidang_usaha?.kategori || t.bidang_usaha?.archetype || '')}</span>
              </button>`).join('')}
          </div>
          ${allowCancel ? `
            <div class="picker__actions">
              <button type="button" class="btn btn--ghost" id="picker-cancel">Batal</button>
            </div>` : ''}
        </div>
      </div>`
    appRoot.querySelectorAll('.picker__card').forEach((card) => {
      card.addEventListener('click', () => resolve(list[Number(card.dataset.idx)]))
    })
    const cancelBtn = appRoot.querySelector('#picker-cancel')
    if (cancelBtn) cancelBtn.addEventListener('click', () => resolve(null))
  })
}

/** Ganti toko dari top bar (hanya tampil bila toko > 1). */
async function switchToko() {
  const { tokoList, screen } = getState()
  if (tokoList.length < 2) return
  if (typeof currentCleanup === 'function') {
    try { currentCleanup() } catch { /* abaikan */ }
    currentCleanup = null
  }
  const chosen = await pickToko(tokoList, { allowCancel: true })
  if (!chosen) {
    // Batal — kembali ke layar sebelumnya tanpa mengubah apa pun
    renderShell()
    await showScreen(screen || 'home')
    return
  }
  await applyToko(chosen)
  renderShell()
  await showScreen('home')
}

// ---------- Muat data kerja setelah autentikasi ----------

async function loadWorkspace() {
  const [config, sesi, gudang, kategori, langganan, stok] = await Promise.all([
    api.config.get(),
    api.sesi.aktif(),
    api.master.gudang(),
    api.master.kategori(),
    api.langganan.status(),
    api.laporan.stok({})
  ])

  const patch = {}
  if (config.ok && config.data) {
    patch.config = config.data
    patch.paymentMethods = config.data.payment_methods || []
    if (config.data.company) patch.company = config.data.company
    if (config.data.modules) patch.modules = config.data.modules
  }
  if (sesi.ok) {
    patch.session = sesi.data || null
    patch.sessionId = sesi.data && sesi.data.id ? sesi.data.id : null
  }
  if (gudang.ok) {
    patch.gudang = gudang.data || []
    patch.gudangError = null
  } else {
    // Known issue MOVERA (Docs-API.md §10): GET /gudang bisa 500 bila user
    // punya branch_id — simpan pesannya agar layar Sesi bisa menjelaskan.
    patch.gudang = []
    patch.gudangError = gudang.message || 'Gagal memuat daftar gudang.'
  }
  if (kategori.ok) patch.kategori = kategori.data || []
  patch.langganan = langganan.ok ? (langganan.data || null) : null
  if (stok.ok && Array.isArray(stok.data)) {
    patch.stokAlerts = analisisStok(stok.data, getState().toko?.id).alerts
  }
  setState(patch)
}

/** Muat ulang sesi kasir aktif (dipakai layar sesi & kasir setelah buka/tutup). */
export async function refreshActiveSession() {
  const sesi = await api.sesi.aktif()
  if (sesi.ok) {
    setState({
      session: sesi.data || null,
      sessionId: sesi.data && sesi.data.id ? sesi.data.id : null
    })
  }
  return sesi
}

/** Buka WhatsApp CS (mitra perekrut bila aktif, atau CS pusat) via /kontak-cs. */
async function contactCS() {
  const r = await api.cs.kontak()
  if (r.ok && r.data && r.data.wa_link) {
    window.open(r.data.wa_link, '_blank')
  } else {
    toast(firstError(r) || 'Kontak CS belum tersedia.', 'error')
  }
}

/** Buka halaman perpanjang langganan; jika URL tak ada, arahkan ke CS. */
function openPerpanjang() {
  const { langganan } = getState()
  const url = langganan && langganan.perpanjang_url
  if (url) window.open(url, '_blank')
  else contactCS()
}

// ---------- Shell: top bar + area layar ----------

function renderShell() {
  const { user, demo, toko, tokoList } = getState()
  const initials = (user?.name || '?')
    .split(/\s+/)
    .map((w) => w[0])
    .slice(0, 2)
    .join('')
    .toUpperCase()

  const tokoChip = toko
    ? (tokoList.length > 1
      ? `<button type="button" class="topbar__toko" id="tb-toko" title="Klik untuk ganti toko">
           ${icons.store}<span class="u-truncate">${esc(toko.nama)}</span>
           <span class="topbar__toko-more">▾</span>
         </button>`
      : `<span class="topbar__toko topbar__toko--static" title="${esc(toko.bidang_usaha?.nama || '')}">
           ${icons.store}<span class="u-truncate">${esc(toko.nama)}</span>
         </span>`)
    : ''

  appRoot.innerHTML = `
    <div class="shell">
      <header class="topbar">
        <button type="button" class="topbar__brand" id="tb-home" title="Kembali ke Beranda">
          <img class="topbar__logo" src="${LOGO_DATA_URI}" alt="" />
          <span class="topbar__name">Tul<b>éh</b></span>
        </button>
        ${tokoChip}
        <button type="button" class="topbar__back u-hidden" id="tb-back">
          <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="m15 18-6-6 6-6"/></svg>
          <span>Beranda</span>
        </button>
        <span class="topbar__screen" id="tb-screen"></span>
        <div class="topbar__spacer"></div>
        ${demo ? '<span class="topbar__demo" title="Semua data hanya simulasi lokal">DEMO</span>' : ''}
        <div class="topbar__notif" id="tb-notif-wrap">
          <button type="button" class="icon-btn topbar__bell" id="tb-notif" title="Notifikasi" aria-label="Notifikasi" aria-haspopup="true" aria-expanded="false">
            ${icons.bell}
            <span class="topbar__bell-dot" id="tb-notif-dot" aria-hidden="true"></span>
          </button>
        </div>
        <button type="button" class="icon-btn topbar__theme" id="tb-theme" title="Ganti tema (terang/gelap)" aria-label="Ganti tema"></button>
        <button type="button" class="topbar__session" id="tb-session" title="Kelola sesi kasir"></button>
        <span class="topbar__conn" id="tb-conn" title="Status koneksi server">
          <span class="badge__dot"></span>
        </span>
        <div class="topbar__user" title="${esc(user?.email || '')}">
          <span class="topbar__avatar">${esc(initials)}</span>
          <span class="topbar__user-name u-truncate">${esc(user?.name || '')}</span>
        </div>
        <button type="button" class="icon-btn topbar__logout" id="tb-logout" title="Keluar" aria-label="Keluar">
          ${icons.logout}
        </button>
      </header>
      <main class="shell__main" id="screen-root"></main>
    </div>`

  const sessionBtn = appRoot.querySelector('#tb-session')
  const connEl = appRoot.querySelector('#tb-conn')

  function syncSession() {
    const { session } = getState()
    sessionBtn.classList.toggle('is-open', !!session)
    sessionBtn.innerHTML = session
      ? `<span class="badge__dot"></span><span>Sesi</span><span class="mono">${esc(session.nomor || 'BUKA')}</span>`
      : `<span class="badge__dot"></span><span>Sesi belum dibuka</span>`
  }

  function syncConn() {
    const { online } = getState()
    connEl.classList.toggle('is-offline', !online)
    connEl.innerHTML = online
      ? '<span class="badge__dot"></span>'
      : '<span class="badge__dot"></span><span>Terputus</span>'
    connEl.title = online ? 'Terhubung ke server' : 'Tidak terhubung ke server'
  }

  syncSession()
  syncConn()

  // ---- Tombol ganti tema (bulan/matahari) ----
  const themeBtn = appRoot.querySelector('#tb-theme')
  function syncThemeIcon() {
    const dark = getEffectiveTheme() === 'dark'
    themeBtn.innerHTML = dark ? icons.sun : icons.moon
    const label = dark ? 'Beralih ke tema terang' : 'Beralih ke tema gelap'
    themeBtn.title = label
    themeBtn.setAttribute('aria-label', label)
    themeBtn.setAttribute('aria-pressed', dark ? 'true' : 'false')
  }
  syncThemeIcon()
  themeBtn.addEventListener('click', () => {
    cycleTheme()
    syncThemeIcon()
  })

  // ---- Lonceng notifikasi + dropdown ----
  const notifWrap = appRoot.querySelector('#tb-notif-wrap')
  const notifBtn = appRoot.querySelector('#tb-notif')
  const notifDot = appRoot.querySelector('#tb-notif-dot')
  let notifOpen = false

  function syncNotifDot() {
    const ada = !notifDismissed && hitungNotifikasi(getState()).length > 0
    notifDot.classList.toggle('is-on', ada)
  }
  function onDocClickNotif(e) {
    if (!notifWrap.contains(e.target)) closeNotif()
  }
  function onKeydownNotif(e) {
    if (e.key === 'Escape') {
      closeNotif()
      notifBtn.focus()
    }
  }
  function closeNotif() {
    notifOpen = false
    const panel = notifWrap.querySelector('.notif-panel')
    if (panel) panel.remove()
    notifBtn.setAttribute('aria-expanded', 'false')
    document.removeEventListener('click', onDocClickNotif, true)
    document.removeEventListener('keydown', onKeydownNotif, true)
  }
  function openNotif() {
    notifOpen = true
    notifWrap.insertAdjacentHTML('beforeend', renderPanelNotifikasi(hitungNotifikasi(getState())))
    notifBtn.setAttribute('aria-expanded', 'true')
    const mark = notifWrap.querySelector('[data-notif-read]')
    if (mark) mark.addEventListener('click', () => {
      notifDismissed = true
      syncNotifDot()
      closeNotif()
    })
    const csBtn = notifWrap.querySelector('[data-cs-contact]')
    if (csBtn) csBtn.addEventListener('click', () => {
      closeNotif()
      contactCS()
    })
    document.addEventListener('click', onDocClickNotif, true)
    document.addEventListener('keydown', onKeydownNotif, true)
  }
  notifBtn.addEventListener('click', (e) => {
    e.stopPropagation()
    if (notifOpen) closeNotif()
    else openNotif()
  })
  syncNotifDot()

  if (unsubscribeShell) unsubscribeShell()
  unsubscribeShell = subscribe((_state, patch) => {
    if ('session' in patch) syncSession()
    if ('online' in patch) syncConn()
    // Perubahan sesi/produk/orders/langganan dapat mengubah jumlah notifikasi
    if ('session' in patch || 'produk' in patch || 'orders' in patch || 'langganan' in patch || 'stokAlerts' in patch) {
      notifDismissed = false
      syncNotifDot()
    }
  })

  appRoot.querySelector('#tb-home').addEventListener('click', () => showScreen('home'))
  appRoot.querySelector('#tb-back').addEventListener('click', () => showScreen('home'))
  sessionBtn.addEventListener('click', () => showScreen('sessions'))
  appRoot.querySelector('#tb-logout').addEventListener('click', doLogout)
  const tokoBtn = appRoot.querySelector('#tb-toko')
  if (tokoBtn) tokoBtn.addEventListener('click', switchToko)
}

function setTopbarScreen(screen) {
  const back = appRoot.querySelector('#tb-back')
  const label = appRoot.querySelector('#tb-screen')
  if (!back || !label) return
  const isHome = !screen
  back.classList.toggle('u-hidden', isHome)
  label.textContent = screen ? screen.title : ''
}

// ---------- Beranda (dashboard kartu — dinamis dari manifest) ----------

function moduleIcon(mod) {
  if (mod.iconKey && icons[mod.iconKey]) return icons[mod.iconKey]
  if (mod.screen) {
    const screen = SCREENS.find((s) => s.id === mod.screen)
    if (screen) return screen.icon
  }
  return icons.box
}

function homeCardHTML(mod) {
  const isPrimary = mod.id === 'kasir'
  // Token warna aksen per-modul → di-inject sebagai custom property kartu
  const accent = MODULE_ACCENT[mod.id]
  const accentStyle = (accent && !isPrimary)
    ? ` style="--mod: var(--mod-${accent}); --mod-soft: var(--mod-${accent}-soft)"`
    : ''
  return `
    <button type="button" class="home-card${isPrimary ? ' home-card--primary' : ''}"
            data-module="${mod.id}"${accentStyle}>
      <span class="home-card__icon">${moduleIcon(mod)}</span>
      <span class="home-card__body">
        <span class="home-card__title">${esc(mod.title)}${mod.appExtra ? '<span class="home-card__tag">Fitur app</span>' : ''}</span>
        <span class="home-card__desc">${esc(mod.desc)}</span>
      </span>
      <span class="home-card__arrow" aria-hidden="true">
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12h14"/><path d="m13 6 6 6-6 6"/></svg>
      </span>
    </button>`
}

function renderHome(container) {
  const { user, company, session, toko, manifest, langganan } = getState()
  const lang = ringkasLangganan(langganan)
  const hariIni = new Intl.DateTimeFormat('id-ID', {
    weekday: 'long', day: 'numeric', month: 'long', year: 'numeric'
  }).format(new Date())

  const namaTempat = toko ? toko.nama : (company?.nama || '')
  const bidang = manifest?.verticalName || ''

  container.innerHTML = `
    <div class="home">
      <div class="home__inner">
        <div class="home__head">
          <div>
            <div class="home__date">${esc(hariIni)}</div>
            <h1 class="home__greet">Halo, ${esc((user?.name || 'Kasir').split(' ')[0])} 👋</h1>
            <p class="home__sub">${esc(namaTempat)}${bidang ? ` <span class="home__bidang">· ${esc(bidang)}</span>` : ''}</p>
          </div>
          <div class="home__stats">
            <div class="stat-tile home__stat">
              <span class="stat-tile__chip stat-tile__chip--trx">${icons.pos}</span>
              <div class="stat-tile__main">
                <div class="stat-tile__label">Transaksi hari ini</div>
                <div class="stat-tile__value num" id="home-trx">—</div>
              </div>
            </div>
            <div class="stat-tile home__stat">
              <span class="stat-tile__chip stat-tile__chip--omzet">${icons.wallet}</span>
              <div class="stat-tile__main">
                <div class="stat-tile__label">Omzet hari ini</div>
                <div class="stat-tile__value num" id="home-omzet">—</div>
              </div>
            </div>
          </div>
        </div>

        ${session ? '' : `
          <div class="home__notice">
            <span class="home__notice-icon">${icons.alert}</span>
            <span class="u-grow">Sesi kasir belum dibuka — buka sesi terlebih dahulu untuk mulai mencatat transaksi.</span>
            <button type="button" class="btn btn--primary btn--sm" data-module="sesi">Buka Sesi</button>
          </div>`}

        ${lang.perluAksi ? `
          <div class="home__notice home__notice--${lang.level === 'kedaluwarsa' ? 'danger' : 'warn'}">
            <span class="home__notice-icon">${icons.alert}</span>
            <span class="u-grow"><strong>${esc(lang.judul)}.</strong> ${esc(lang.detail)}</span>
            <button type="button" class="btn btn--ghost btn--sm" data-cs-contact>Hubungi CS</button>
            <button type="button" class="btn btn--primary btn--sm" data-langganan-perpanjang>Perpanjang</button>
          </div>` : ''}

        <div class="home__grid">
          ${moduleList().map(homeCardHTML).join('')}
        </div>
      </div>
    </div>`

  container.querySelectorAll('[data-module]').forEach((el) => {
    el.addEventListener('click', () => {
      const mod = MODULES[el.dataset.module]
      if (!mod) return
      showScreen(mod.screen)
    })
  })

  const csBtn = container.querySelector('[data-cs-contact]')
  if (csBtn) csBtn.addEventListener('click', contactCS)
  const perpanjangBtn = container.querySelector('[data-langganan-perpanjang]')
  if (perpanjangBtn) perpanjangBtn.addEventListener('click', openPerpanjang)

  // Statistik ringkas hari ini — best effort, jangan blokir beranda
  let alive = true
  const today = toISODate(new Date())
  api.trx.list({ tanggalDari: today, tanggalSampai: today }).then((result) => {
    if (!alive || !result.ok) return
    const rows = (result.data || []).filter((t) => String(t.status).toUpperCase() !== 'DIBATALKAN')
    const omzet = rows.reduce((sum, t) => sum + (Number(t.grand_total) || 0), 0)
    const trxEl = container.querySelector('#home-trx')
    const omzetEl = container.querySelector('#home-omzet')
    if (trxEl) trxEl.textContent = fmtNumber(rows.length)
    if (omzetEl) omzetEl.textContent = fmtIDR(omzet)
  })

  return () => {
    alive = false
  }
}

// ---------- Navigasi layar ----------

export async function showScreen(id) {
  const isHome = id === 'home'
  const screen = isHome ? null : SCREENS.find((s) => s.id === id)

  if (typeof currentCleanup === 'function') {
    try {
      currentCleanup()
    } catch (err) {
      console.error('Cleanup layar gagal:', err)
    }
    currentCleanup = null
  }

  setState({ screen: id })
  // Layar yang belum dibangun (mis. route_key manifest yang lebih baru dari app)
  // ditampilkan sbg "segera hadir" — jangan diam saja / crash.
  setTopbarScreen(isHome ? null : (screen || { title: 'Segera hadir' }))

  const root = appRoot.querySelector('#screen-root')
  if (!root) return
  root.innerHTML = ''
  try {
    if (isHome) currentCleanup = renderHome(root)
    else if (screen) currentCleanup = (await screen.render(root)) || null
    else currentCleanup = renderComingSoon(root)
  } catch (err) {
    console.error(`Gagal memuat layar ${id}:`, err)
    root.innerHTML = `<div class="screen-page"><p class="u-muted">Terjadi kesalahan saat memuat layar. Kembali ke Beranda lalu coba lagi.</p></div>`
  }
}

/** Placeholder untuk route_key yang belum punya layar di versi app ini. */
function renderComingSoon(root) {
  root.innerHTML = `
    <div class="screen-page">
      <div class="coming-soon">
        <div class="coming-soon__icon">${icons.box}</div>
        <h2 class="coming-soon__title">Segera hadir</h2>
        <p class="u-muted">Menu ini belum tersedia di versi aplikasi ini. Perbarui aplikasi untuk memakainya.</p>
        <button type="button" class="btn btn--ghost" data-goto-home>Kembali ke Beranda</button>
      </div>
    </div>`
  const back = root.querySelector('[data-goto-home]')
  if (back) back.addEventListener('click', () => showScreen('home'))
  return null
}

// ---------- Autentikasi ----------

async function doLogout() {
  const yes = await confirmDialog({
    title: 'Keluar dari Tuléh?',
    message: 'Anda perlu masuk kembali dengan akun dan kata sandi untuk memakai aplikasi ini.',
    confirmText: 'Keluar',
    danger: true
  })
  if (!yes) return
  await api.auth.logout()
  enterLogin()
}

function enterLogin() {
  if (typeof currentCleanup === 'function') {
    try { currentCleanup() } catch { /* abaikan */ }
    currentCleanup = null
  }
  if (unsubscribeShell) {
    unsubscribeShell()
    unsubscribeShell = null
  }
  resetAuthState()
  renderLogin(appRoot, { onSuccess: enterApp })
}

async function enterApp(identity) {
  // identity: { user, pos_role, company, branch, permissions, modules, payment_methods, demo? }
  setState({
    user: identity.user || null,
    posRole: identity.pos_role || null,
    company: identity.company || null,
    branch: identity.branch || null,
    permissions: identity.permissions || [],
    modules: identity.modules || {},
    paymentMethods: identity.payment_methods || [],
    demo: !!identity.demo
  })
  // Toko dulu (menetapkan toko aktif) baru workspace, agar /gudang, /kategori,
  // /langganan otomatis membawa ?toko_id (MOVERA §1.3).
  await loadTokoAndManifest()
  await loadWorkspace()
  renderShell()
  await showScreen('home')
}

// ---------- Pemantau koneksi & pintasan global ----------

const PING_INTERVAL_MS = 45000
setInterval(async () => {
  const result = await api.net.ping()
  const online = !!result.ok
  if (getState().online !== online) setState({ online })
}, PING_INTERVAL_MS)

document.addEventListener('keydown', (e) => {
  if (!e.ctrlKey || e.altKey || e.shiftKey) return
  if (!getState().user) return
  if (e.key === '0') {
    e.preventDefault()
    showScreen('home')
    return
  }
  const index = Number(e.key) - 1
  if (index >= 0 && index < SCREENS.length) {
    e.preventDefault()
    showScreen(SCREENS[index].id)
  }
})

api.auth.onExpired(() => {
  toast('Sesi berakhir — silakan masuk kembali.', 'error')
  enterLogin()
})

// ---------- Boot ----------

async function boot() {
  // Jalur uji tampilan (screenshot smoke): langsung masuk Mode Demo
  const info = await api.app.info()
  if (info.ok && info.data && info.data.smokeTheme) {
    const { setTheme } = await import('./theme.js')
    setTheme(info.data.smokeTheme) // 'light' | 'dark' — uji tampilan tema
  }
  if (info.ok && info.data && info.data.smokeDemo) {
    const demoResult = await api.demo.start()
    if (demoResult.ok && demoResult.data) {
      await enterApp(demoResult.data)
      if (info.data.smokeScreen) await showScreen(info.data.smokeScreen)
      // Uji tampilan: buka bon meja pertama yang terisi (dipicu env smoke)
      if (info.data.smokeOpenBill) {
        await new Promise((r) => setTimeout(r, 250))
        const card = document.querySelector('.meja-card[data-bill]')
        if (card) card.click()
      }
      // Uji alur bon meja langkah-demi-langkah (screenshot bukti) — hanya uji
      if (info.data.smokeFlow) {
        const jeda = (ms) => new Promise((r) => setTimeout(r, ms))
        const kartuTerisi = () => document.querySelector('.meja-card[data-bill]')
        await jeda(300)
        if (info.data.smokeFlow === 'bayar') {
          kartuTerisi()?.click(); await jeda(450)
          document.querySelector('#bill-bayar')?.click(); await jeda(300)
        } else if (info.data.smokeFlow === 'siklus') {
          kartuTerisi()?.click(); await jeda(450)
          document.querySelector('#bill-bayar')?.click(); await jeda(300)
          document.querySelector('#bp-ok')?.click(); await jeda(700)
        } else if (info.data.smokeFlow === 'gabung') {
          document.querySelector('#meja-gabung-mode')?.click(); await jeda(250)
          document.querySelectorAll('.meja-card[data-bill]').forEach((c, i) => { if (i < 2) c.click() })
          await jeda(300)
        } else if (info.data.smokeFlow === 'prabill') {
          kartuTerisi()?.click(); await jeda(450)
          document.querySelector('#bill-cetak')?.click(); await jeda(400)
        }
      }
      return
    }
  }

  const has = await api.auth.hasToken()
  if (has.ok && has.data && has.data.hasToken) {
    const me = await api.auth.me()
    if (me.ok && me.data && me.data.user) {
      setState({
        user: me.data.user,
        posRole: me.data.pos_role || null,
        company: me.data.company || null,
        branch: me.data.branch || null,
        session: me.data.sesi_aktif || null,
        sessionId: me.data.sesi_aktif && me.data.sesi_aktif.id ? me.data.sesi_aktif.id : null
      })
      await loadTokoAndManifest()
      await loadWorkspace()
      renderShell()
      await showScreen('home')
      return
    }
  }
  enterLogin()
}

// Terapkan tema tersimpan sedini mungkin agar tidak ada kedip warna saat boot.
applyTheme()
boot()
