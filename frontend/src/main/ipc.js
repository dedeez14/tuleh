'use strict'

const os = require('node:os')
const { app, ipcMain, shell, BrowserWindow } = require('electron')
const api = require('./api-client')
const authStore = require('./auth-store')
const settingsStore = require('./settings-store')
const demo = require('./demo')
const masaCoba = require('./lib/masa-coba')
const mesin = require('./identitas-mesin')
const gateway = require('./gateway')
const tracker = require('./tracker')
const tunnel = require('./tunnel')
const qr = require('./qr')
const customerWindow = require('./customer-window')
const updater = require('./updater')
const offline = require('./offline')

// ---------- Validasi input dari renderer (jangan percaya begitu saja) ----------

function str(value, { max = 500, required = false } = {}) {
  if (value === undefined || value === null || value === '') {
    if (required) throw new Error('Field wajib diisi.')
    return undefined
  }
  // API MOVERA mendefinisikan id sebagai string terenkripsi, tetapi beberapa
  // deployment mengirim angka mentah — terima dan normalisasi ke string.
  if (typeof value === 'number' && Number.isFinite(value)) value = String(value)
  if (typeof value !== 'string') throw new Error('Tipe data tidak valid.')
  return value.slice(0, max)
}

function num(value, { required = false } = {}) {
  if (value === undefined || value === null || value === '') {
    if (required) throw new Error('Field wajib diisi.')
    return undefined
  }
  const n = Number(value)
  if (!Number.isFinite(n)) throw new Error('Angka tidak valid.')
  return n
}

function intBetween(value, min, max, fallback) {
  const n = Number(value)
  if (!Number.isInteger(n)) return fallback
  return Math.min(max, Math.max(min, n))
}

function fail(message) {
  return { ok: false, status: 0, message, errors: null }
}

// Body PUT /pengaturan/usaha — hanya kunci yang dikirim renderer (partial update).
// Teks kosong pada field boleh-null → dikirim `null` (menghapus nilai di server).
function usahaBody(f) {
  const b = {}
  const teksNull = (v, max) => (v === null || v === undefined || String(v).trim() === '' ? null : String(v).trim().slice(0, max))
  if ('nama' in f) b.nama = str(f.nama, { required: true, max: 150 })
  if ('alamat' in f) b.alamat = teksNull(f.alamat, 500)
  if ('telepon' in f) b.telepon = teksNull(f.telepon, 30)
  if ('email' in f) b.email = teksNull(f.email, 150)
  if ('struk_footer' in f) b.struk_footer = teksNull(f.struk_footer, 300)
  if ('struk_tampil_logo' in f) b.struk_tampil_logo = !!f.struk_tampil_logo
  return b
}

// Body PUT /pengaturan/pembayaran — daftar bank (maks 5) menggantikan seluruh
// daftar; hapus_qr menghapus QR statis.
function pembayaranBody({ bank, hapusQr } = {}) {
  const b = {}
  if (Array.isArray(bank)) {
    b.bank = bank.slice(0, 5).map((r) => ({
      bank: (str(r && r.bank, { max: 40 }) || '').trim(),
      rekening: (str(r && r.rekening, { max: 40 }) || '').trim(),
      atas_nama: (str(r && r.atas_nama, { max: 80 }) || '').trim()
    })).filter((r) => r.bank || r.rekening || r.atas_nama)
  }
  if (hapusQr) b.hapus_qr = true
  return b
}

// Body PUT /pengaturan/pembayaran/midtrans — pasang key {merchant_id, client_key,
// server_key} ATAU saklar {aktif}. Server key TAK PERNAH di-log di sisi app.
function midtransBody(f = {}) {
  const b = {}
  if ('merchant_id' in f) b.merchant_id = str(f.merchant_id, { max: 100 })
  if ('client_key' in f) b.client_key = str(f.client_key, { max: 200 })
  if ('server_key' in f) b.server_key = str(f.server_key, { max: 200 })
  if ('aktif' in f) b.aktif = !!f.aktif
  return b
}

// Handler dibungkus supaya error validasi kembali sebagai envelope, bukan exception IPC.
// Saat Mode Demo aktif, channel yang punya simulasi dialihkan ke demo.js (tanpa jaringan).
// Checkout toko ber-lifecycle → sisipkan URL + QR pelacakan pelanggan ke struk
// (server pelacakan LAN — Blueprint Fase 3 mode lokal).
function enrichTracking(channel, result) {
  // Struk checkout → data; nota bayar-saat-ambil → data.nota
  const target = channel === 'trx:checkout' ? result?.data
    : channel === 'order:simpanNota' ? result?.data?.nota
    : null
  if (!target || !result.ok || !target.token_lacak) return result
  const ts = tracker.status()
  if (!ts.running) return result
  const url = `${ts.baseUrl}/t/${target.token_lacak}`
  target.lacak_url = url
  try {
    target.lacak_qr = qr.svgDataUri(url)
  } catch {
    // QR gagal dibuat — struk tetap sah tanpa QR
  }
  return result
}

function handle(channel, handler) {
  ipcMain.handle(channel, async (_event, payload) => {
    try {
      if (demo.isActive() && demo.handlers[channel]) {
        return enrichTracking(channel, await demo.handlers[channel](payload || {}))
      }
      return enrichTracking(channel, await handler(payload || {}))
    } catch (err) {
      return fail(err && err.message ? err.message : 'Permintaan tidak valid.')
    }
  })
}

function registerIpcHandlers(getMainWindow) {
  // Muat pengaturan + token tersimpan saat start
  const settings = settingsStore.load()
  api.setBaseUrl(settings.baseUrl)

  // ---------- Mode offline (salinan baca + antrean kirim) ----------
  // Pengurai mengirim ulang lewat api.post; timeout diberi status -1 agar
  // dibedakan dari "tidak sampai" (0) — lihat offline/pengurai.js.
  offline.init({
    dir: app.getPath('userData'),
    kirim: async (jalur, body, pesan) => {
      // Kirim atas nama toko saat pesan dibuat, bukan toko aktif sekarang.
      const query = pesan && pesan.tokoId ? { toko_id: pesan.tokoId } : undefined
      const r = await api.post(jalur, { body, query })
      return r.timeout ? { ...r, status: -1 } : r
    },
    // Daftar transaksi server untuk memulihkan baris "mungkin sudah sampai".
    ambilDaftar: async (tokoId, dari, sampai) => {
      const r = await api.get('/transaksi', {
        query: { dari, sampai, tanggal_dari: dari, tanggal_sampai: sampai, ...(tokoId ? { toko_id: tokoId } : {}) }
      })
      return r.ok && Array.isArray(r.data) ? r.data : null
    }
  })
  const kirimStatusOffline = () => {
    const win = getMainWindow()
    if (win && !win.isDestroyed()) win.webContents.send('offline:status', offline.status(api.getActiveTokoId()))
  }
  offline.koneksi.langgan(kirimStatusOffline)
  // Kembali online (dari permintaan mana pun) → uraikan antrean.
  offline.koneksi.langgan(() => {
    if (offline.koneksi.online && offline.antrean.ringkas().menunggu > 0) offline.pengurai.jalankan()
  })
  // Jalankan sekali saat start bila ada sisa antrean dari sesi sebelumnya.
  setTimeout(() => { if (api.hasToken()) offline.pengurai.jalankan() }, 3000).unref?.()

  /**
   * Permintaan tulis dengan jalur offline: bila diketahui offline → antrekan
   * langsung; bila gagal jaringan ATAU timeout setelah kirim → antrekan biasa
   * dan kirim ulang otomatis (server menolak duplikat lewat `client_ref`).
   * Server menolak (4xx) → kembalikan apa adanya.
   */
  async function tulisAtauAntre({ jenis, jalur, body, transaksi = null, deltaStok = {} }) {
    const clientRef = offline.buatClientRef()
    const badan = { ...body, client_ref: clientRef, waktu_klien: new Date().toISOString() }
    if (offline.koneksi.online) {
      const r = await withAuthWatch(api.post(jalur, { body: badan }))
      if (r.ok) return { ...r, clientRef }
      if (r.status !== 0) return r // ditolak server: tampilkan apa adanya
    }
    offline.antrean.antrekan({
      clientRef, jenis, tokoId: api.getActiveTokoId(), path: jalur, body: badan,
      status: offline.STATUS.MENUNGGU
    }, { transaksi, deltaStok })
    kirimStatusOffline()
    return { ok: true, status: 202, data: null, meta: null, message: '', tertunda: true, clientRef }
  }

  handle('offline:status', () => ({ ok: true, data: offline.status(api.getActiveTokoId()) }))
  handle('offline:daftar', () => ({
    ok: true,
    data: offline.antrean.semua().map((p) => ({ ...p, label: offline.labelJenis(p.jenis) }))
  }))
  handle('offline:sinkron', async () => {
    const ping = await api.get('/ping', { auth: false })
    if (!ping.ok) { offline.koneksi.tandaiOffline(); kirimStatusOffline(); return { ok: false, status: 0, message: 'Server belum terjangkau.' } }
    offline.koneksi.tandaiOnline()
    const n = await offline.pengurai.jalankan()
    kirimStatusOffline()
    return { ok: true, data: { terkirim: n, ...offline.status(api.getActiveTokoId()) } }
  })
  handle('offline:kirimUlang', async ({ clientRef }) => {
    await offline.pengurai.kirimUlang(str(clientRef, { required: true }))
    kirimStatusOffline()
    return { ok: true, data: offline.status(api.getActiveTokoId()) }
  })
  handle('offline:batalkan', ({ clientRef }) => {
    offline.antrean.batalkan(str(clientRef, { required: true }))
    kirimStatusOffline()
    return { ok: true, data: offline.status(api.getActiveTokoId()) }
  })
  const savedToken = authStore.restore()
  if (savedToken) api.setToken(savedToken)

  // Nyalakan gateway lokal di latar belakang (best-effort). Sebelum siap,
  // permintaan berjalan langsung ke server — lalu otomatis pindah ke gateway.
  gateway.ensureRunning(settings.baseUrl).then((st) => {
    api.setGateway(st.ok ? `http://127.0.0.1:${st.port}` : null)
    console.log('[gateway]', JSON.stringify(st))
  }).catch((err) => {
    console.error('[gateway] gagal:', err)
  })

  // Beri tahu renderer bila token ditolak server (sesi kedaluwarsa)
  async function withAuthWatch(promise) {
    const result = await promise
    if (!result.ok && result.status === 401) {
      api.setToken(null)
      authStore.clear()
      api.setActiveTokoId(null)
      const win = getMainWindow()
      if (win && !win.isDestroyed()) win.webContents.send('auth:expired')
    }
    return result
  }

  // Auto-Update: HTTP 426 dari endpoint mana pun → sinyal ke renderer untuk
  // membuka layar update wajib (fail-open bila window belum siap).
  api.setUpgradeHandler((message) => {
    const win = getMainWindow()
    if (win && !win.isDestroyed()) win.webContents.send('update:required', { message: message || '' })
    console.log('[update] 426 diterima —', message || '(tanpa pesan)')
  })

  // Auto-Update Tahap 3: relay progres/selesai/error electron-updater ke renderer.
  updater.init((channel, payload) => {
    const win = getMainWindow()
    if (win && !win.isDestroyed()) win.webContents.send(channel, payload)
  })

  // ---------- Aplikasi & pengaturan ----------

  handle('app:info', () => ({
    ok: true,
    data: {
      version: app.getVersion(),
      hostname: os.hostname(),
      platform: process.platform,
      gateway: gateway.status(),
      tracking: tracker.status(),
      // Jalur uji tampilan otomatis (screenshot smoke) — tidak dipakai produksi
      smokeDemo: process.env.IPOS_SMOKE_DEMO === '1',
      smokeTokoIndex: /^\d+$/.test(process.env.IPOS_SMOKE_TOKO || '')
        ? Number(process.env.IPOS_SMOKE_TOKO)
        : null,
      smokeScreen: process.env.IPOS_SMOKE_SCREEN || null,
      smokeTheme: process.env.IPOS_SMOKE_THEME || null,
      smokeOpenBill: process.env.IPOS_SMOKE_OPENBILL === '1',
      smokeFlow: process.env.IPOS_SMOKE_FLOW || null,
      smokeGulir: process.env.IPOS_SMOKE_GULIR || null,
      smokeLogin: process.env.IPOS_SMOKE_LOGIN === '1',
      smokeMasuk: process.env.IPOS_SMOKE_USER ? { user: process.env.IPOS_SMOKE_USER, pass: process.env.IPOS_SMOKE_PASS || '' } : null
    }
  }))

  // Auto-Update: cek versi ke server (tanpa auth). Balasan berisi
  // { wajib, update_tersedia, versi_terbaru, catatan, unduhan:{windows,android}, ukuran }.
  handle('app:checkUpdate', () => api.get('/app/versi', { auth: false, query: { versi: api.appVersion() } }))

  // Auto-Update Tahap 3 (desktop): unduh & pasang lewat electron-updater.
  // Renderer memakai ini bila didukung; jika tidak, jatuh ke unduhan browser.
  handle('update:supported', () => ({ ok: true, data: { supported: updater.isSupported() } }))
  handle('update:download', () => updater.download())
  handle('update:install', () => { updater.install(); return { ok: true } })

  // Buka URL di browser sistem (halaman pembayaran Midtrans — WAJIB browser penuh,
  // bukan webview: 3-D Secure & deep link e-wallet kerap gagal di webview).
  handle('app:openExternal', async ({ url }) => {
    const u = str(url, { required: true, max: 2000 })
    if (!/^https:\/\//i.test(u)) return fail('Hanya URL https yang boleh dibuka.')
    await shell.openExternal(u)
    return { ok: true, data: null }
  })

  // Buka akses LAN (firewall) manual — fallback bila auto-open saat start ditolak.
  handle('firewall:ensure', async () => {
    const r = await require('./firewall').ensure()
    if (r && r.ok) return { ok: true, data: r }
    return fail('Gagal membuka akses jaringan (izin admin ditolak?). Coba lagi & pilih “Ya” pada dialog Windows.')
  })

  // Buka Papan Antrian (TV/monitor) — URL LAN dibentuk di sini (tepercaya), bukan
  // dari renderer, jadi aman meski http (alamat LAN lokal).
  handle('display:antrian', async () => {
    const ts = tracker.status()
    if (!ts.running || !ts.baseUrl) return fail('Server LAN belum aktif — papan antrian belum bisa dibuka.')
    const url = `${ts.baseUrl}/antrian`
    await shell.openExternal(url)
    return { ok: true, data: { url } }
  })

  // Cetak isi #print-root. Bila preferensi "cetak langsung" aktif dan printer
  // dipilih → tanpa dialog (silent) ke printer itu; selain itu dialog OS.
  // `struk: true` = dokumen ini memang struk kasir; hanya itu yang boleh
  // memakai preferensi "cetak langsung". Tanpa penanda (PDF laporan, QR meja)
  // selalu lewat dialog Windows — kalau tidak, ekspor PDF diam-diam keluar di
  // printer thermal tanpa berkas apa pun.
  // `printerSekaliPakai`/`langsungSekaliPakai` = uji cetak: pakai setelan yang
  // sedang dicoba tanpa menyimpannya.
  handle('app:print', ({ paksaDialog, struk, printerSekaliPakai, langsungSekaliPakai } = {}) => {
    const win = getMainWindow()
    if (!win || win.isDestroyed()) return fail('Jendela tidak tersedia.')
    const cetak = settingsStore.getCetak()
    const uji = printerSekaliPakai !== undefined || langsungSekaliPakai !== undefined
    const printer = uji ? str(printerSekaliPakai, { max: 200 }) : cetak.printer
    const maunyaLangsung = uji ? !!langsungSekaliPakai : cetak.langsung
    const langsung = !paksaDialog && (struk === true || uji) && maunyaLangsung && !!printer
    const opsi = { printBackground: true, margins: { marginType: 'printableArea' } }
    if (langsung) { opsi.silent = true; opsi.deviceName = printer }
    return new Promise((resolve) => {
      win.webContents.print(opsi, (success, reason) => {
        if (success) return resolve({ ok: true, data: { langsung } })
        // Printer pilihan tidak ada (dicabut/diganti nama) → beri tahu jelas.
        const pesan = langsung && /device|printer|not found|tidak/i.test(String(reason || ''))
          ? `Printer "${printer}" tidak ditemukan. Pilih ulang di Pengaturan → Printer struk.`
          : (reason || 'Cetak dibatalkan.')
        resolve(fail(pesan))
      })
    })
  })

  handle('app:printers', async () => {
    const win = getMainWindow()
    if (!win || win.isDestroyed()) return fail('Jendela tidak tersedia.')
    try {
      const daftar = await win.webContents.getPrintersAsync()
      return { ok: true, data: daftar.map((p) => ({ nama: p.name, deskripsi: p.description || '', bawaan: !!p.isDefault })) }
    } catch (err) {
      return fail(err && err.message ? err.message : 'Gagal membaca daftar printer.')
    }
  })

  handle('settings:getCetak', () => ({ ok: true, data: settingsStore.getCetak() }))
  handle('settings:setCetak', (patch) => ({ ok: true, data: settingsStore.setCetak(patch || {}) }))

  // Mode Demo: seluruh data disimulasikan lokal, tidak ada permintaan jaringan.
  // Server pelacakan pelanggan (LAN) ikut dinyalakan agar QR struk berfungsi.
  // Masa coba demo 7 hari — tiga lapis (lihat "Kontrak Masa Coba Tuléh"):
  //  1. lokal: waktu server + catatan ber-HMAC, disimpan di 3 tempat;
  //  2. perangkat: /demo/perangkat (server mencatat perangkatId);
  //  3. identitas: OTP → identitas_token, ikut dikirim ke /demo/perangkat.
  // Server yang belum memasang endpoint (404/tak terjangkau) → lapis 1 saja.
  const identitasMesin = () => mesin.identitasHmac()

  async function statusServer({ mulaiBaru }) {
    const body = {
      perangkat_id: mesin.perangkatId(),
      platform: 'windows',
      sidik_jari: mesin.sidikJari(),
      versi_app: api.appVersion(),
      identitas_token: settingsStore.getDemoIdentitasToken() || undefined
    }
    try {
      const r = mulaiBaru
        ? await api.demoPerangkatDaftar(body)
        : await api.demoPerangkatStatus(body.perangkat_id)
      if (r && r.ok && r.data && typeof r.data === 'object') return r.data
      // 404 saat GET = perangkat belum terdaftar → coba daftarkan.
      if (!mulaiBaru && r && r.status === 404) {
        const d = await api.demoPerangkatDaftar(body)
        if (d && d.ok && d.data && typeof d.data === 'object') return d.data
      }
    } catch { /* fail-open ke lapis lokal */ }
    return null
  }

  async function periksaMasaCoba({ mulaiBaru }) {
    const identitas = identitasMesin()
    const waktu = await api.waktuServer()
    const lokal = masaCoba.periksa({
      catatan: masaCoba.pilihCatatan(settingsStore.getDemoTrialSemua(), identitas),
      waktuServer: waktu,
      perangkat: new Date(),
      identitas,
      mulaiBaru
    })
    // Lapis 2/3 hanya bila lapis 1 tidak sedang menunggu koneksi.
    const server = lokal.kode === 'BUTUH_KONEKSI' ? null : await statusServer({ mulaiBaru })
    const hasil = masaCoba.gabungkan(lokal, server, { identitas })
    if (hasil.catatan) settingsStore.setDemoTrial(hasil.catatan)
    return hasil
  }
  const pesanMasaCoba = {
    BUTUH_KONEKSI: 'Mode Demo perlu koneksi internet saat pertama kali dibuka (untuk mencatat waktu mulai masa coba).',
    BUTUH_IDENTITAS: 'Verifikasi nomor WhatsApp atau email dulu untuk memulai masa coba.',
    BERAKHIR: 'Masa coba Mode Demo 7 hari sudah berakhir. Masuk dengan akun berlangganan untuk melanjutkan.',
    DIBLOKIR: 'Mode Demo di perangkat ini tidak tersedia. Hubungi Tuléh atau masuk dengan akun berlangganan.',
    RUSAK: 'Catatan masa coba tidak sah. Masuk dengan akun berlangganan untuk melanjutkan.'
  }

  handle('demo:status', async () => {
    const h = await periksaMasaCoba({ mulaiBaru: false })
    return { ok: true, data: { kode: h.kode, sisaHari: h.sisaHari, berakhirPada: h.berakhirPada || null, belumMulai: !!h.belumMulai } }
  })

  // OTP identitas (lapis 3). Server yang mengirim kode; di sini hanya meneruskan.
  handle('demo:otpKirim', ({ jenis, tujuan } = {}) =>
    api.demoOtpKirim({ perangkat_id: mesin.perangkatId(), jenis: str(jenis, { max: 10, required: true }), tujuan: str(tujuan, { max: 190, required: true }).trim() }))
  handle('demo:otpVerifikasi', async ({ jenis, tujuan, kode } = {}) => {
    const r = await api.demoOtpVerifikasi({
      perangkat_id: mesin.perangkatId(),
      jenis: str(jenis, { max: 10, required: true }),
      tujuan: str(tujuan, { max: 190, required: true }).trim(),
      kode: str(kode, { max: 12, required: true }).trim()
    })
    if (r && r.ok && r.data && typeof r.data.identitas_token === 'string') {
      settingsStore.setDemoIdentitasToken(r.data.identitas_token)
    }
    return r
  })

  handle('demo:start', async () => {
    const h = await periksaMasaCoba({ mulaiBaru: true })
    if (h.kode !== 'AKTIF') {
      return { ok: false, code: `DEMO_${h.kode}`, message: pesanMasaCoba[h.kode] || 'Mode Demo tidak tersedia.', data: { sisaHari: h.sisaHari } }
    }
    const result = demo.start()
    if (result.ok) {
      result.data.masaCoba = { sisaHari: h.sisaHari, berakhirPada: h.berakhirPada || null }
      tracker.start({
        tracking: demo.trackingInfo,
        menu: demo.menuInfo,
        createOrder: demo.createTableOrder,
        queueBoard: demo.queueBoardInfo,
        payment: demo.paymentInfo
      })
      // Jalur uji: ikut nyalakan tunnel publik agar smoke test bisa memverifikasi
      if (process.env.IPOS_SMOKE_TUNNEL === '1') {
        tunnel.start(tracker.status().port).then((r) => {
          if (r.ok) tracker.setPublicUrl(r.url)
        })
      }
    }
    return result
  })

  // Akses internet publik (Cloudflare Quick Tunnel) — saklar di Pengaturan.
  // Disetujui eksplisit oleh pemilik; hanya meneruskan halaman pelanggan
  // read-only + form pesan ber-throttle.
  handle('tunnel:start', async () => {
    const ts = tracker.status()
    if (!ts.running) return fail('Server pelanggan belum aktif — masuk Mode Demo terlebih dahulu.')
    const result = await tunnel.start(ts.port)
    if (!result.ok) return fail(result.reason || 'Gagal menyalakan tunnel.')
    tracker.setPublicUrl(result.url)
    return { ok: true, data: { url: result.url } }
  })

  handle('tunnel:stop', () => {
    tunnel.stop()
    tracker.setPublicUrl(null)
    return { ok: true, data: null }
  })

  // QR generator lokal (untuk QR meja di layar Meja)
  // max 1024: muat payload EMVCo QRIS dinamis Midtrans (data tambahan + CRC) yang
  // bisa >500 char. Android (mobile-bridge qr.make) tak memotong — samakan agar QR
  // tak terpotong & tetap terpindai di desktop.
  handle('qr:make', ({ text }) => ({ ok: true, data: { uri: qr.svgDataUri(str(text, { required: true, max: 1024 })) } }))

  // Display Pelanggan (jendela kedua desktop; di monitor kedua bila ada).
  handle('customer:status', () => ({ ok: true, data: { supported: true, open: customerWindow.isOpen() } }))
  handle('customer:open', () => ({ ok: true, data: customerWindow.open() }))
  handle('customer:close', () => ({ ok: true, data: customerWindow.close() }))
  handle('customer:update', (state) => {
    tracker.setCustomerState(state) // relay ke halaman LAN /display
    return { ok: true, data: customerWindow.update(state) }
  })

  handle('settings:get', () => ({ ok: true, data: settingsStore.load() }))

  handle('settings:setBaseUrl', ({ baseUrl }) => {
    const result = settingsStore.setBaseUrl(baseUrl)
    if (!result.ok) return fail(result.message)
    api.setBaseUrl(result.baseUrl)
    // Ganti server → gateway di-restart dengan upstream baru (best-effort)
    api.setGateway(null)
    gateway.restart(result.baseUrl).then((st) => {
      api.setGateway(st.ok ? `http://127.0.0.1:${st.port}` : null)
    })
    return { ok: true, data: { baseUrl: result.baseUrl } }
  })

  handle('net:ping', async () => {
    const r = await api.get('/ping', { auth: false })
    if (r.ok) offline.koneksi.tandaiOnline(); else offline.koneksi.tandaiOffline()
    return r
  })

  // ---------- Autentikasi ----------

  handle('auth:hasToken', () => ({ ok: true, data: { hasToken: api.hasToken() } }))

  handle('auth:login', async ({ login, password, deviceName }) => {
    const result = await api.post('/auth/login', {
      auth: false,
      body: {
        login: str(login, { required: true, max: 190 }),
        password: str(password, { required: true, max: 190 }),
        device_name: str(deviceName, { max: 100 }) || os.hostname().slice(0, 100)
      }
    })
    if (result.ok && result.data && typeof result.data.token === 'string') {
      api.setToken(result.data.token)
      authStore.persist(result.data.token)
      // Token cukup di main process — jangan bocorkan ke renderer
      delete result.data.token
      delete result.data.token_type
      // Identitas disalin sebagai /auth/me agar masuk otomatis tetap bisa
      // saat internet mati (bentuknya sama dengan jawaban /auth/me).
      if (offline.salinan) offline.salinan.simpan(null, '/auth/me', {}, { data: result.data, meta: null })
    }
    return result
  })

  handle('auth:me', () => withAuthWatch(api.get('/auth/me')))

  handle('auth:logout', async ({ paksa } = {}) => {
    // Antrean berisi = penjualan yang sudah terjadi; jangan hilang diam-diam.
    const sisa = offline.antrean.ringkas().total
    if (sisa > 0 && !paksa) {
      return { ok: false, status: 409, code: 'ANTREAN', message: `${sisa} data belum terkirim ke server. Sambungkan internet dan buka Pengaturan → Sinkronisasi dulu, atau keluar paksa (antrean tetap tersimpan untuk akun yang sama).`, errors: null }
    }
    const result = await api.post('/auth/logout')
    api.setToken(null)
    authStore.clear()
    api.setActiveTokoId(null)
    return result.ok ? result : { ok: true, status: 200, data: null, meta: null, message: '' }
  })

  handle('config:get', () => withAuthWatch(api.get('/config')))

  // ---------- Pengaturan Usaha & Struk (profil perusahaan — O/M) ----------
  // GET semua peran; PUT & upload logo O/M (server menolak kasir 403). Mutasi
  // menyegarkan /config (blok company+struk); renderer refresh config setelah simpan.
  handle('pengaturan:usahaGet', () => withAuthWatch(api.get('/pengaturan/usaha')))
  handle('pengaturan:usahaSimpan', (f) =>
    withAuthWatch(api.request('PUT', '/pengaturan/usaha', { body: usahaBody(f || {}) })))
  handle('pengaturan:uploadLogo', ({ bytes, filename, mime } = {}) =>
    withAuthWatch(api.upload('/pengaturan/usaha/logo', { file: { bytes, filename, mime } })))
  handle('pengaturan:uploadLogoStruk', ({ bytes, filename, mime } = {}) =>
    withAuthWatch(api.upload('/pengaturan/usaha/logo-struk', { file: { bytes, filename, mime } })))

  // ---------- Pengaturan Pembayaran (dua lapis: QR statis+bank & Midtrans) ----------
  handle('pembayaran:get', () => withAuthWatch(api.get('/pengaturan/pembayaran')))
  handle('pembayaran:simpan', ({ bank, hapusQr } = {}) =>
    withAuthWatch(api.request('PUT', '/pengaturan/pembayaran', { body: pembayaranBody({ bank, hapusQr }) })))
  handle('pembayaran:uploadQr', ({ bytes, filename, mime } = {}) =>
    withAuthWatch(api.upload('/pengaturan/pembayaran/qr', { file: { bytes, filename, mime, field: 'qr' } })))
  handle('pembayaran:midtransSimpan', (f) =>
    withAuthWatch(api.request('PUT', '/pengaturan/pembayaran/midtrans', { body: midtransBody(f || {}) })))
  handle('pembayaran:midtransHapus', () =>
    withAuthWatch(api.request('DELETE', '/pengaturan/pembayaran/midtrans', {})))

  // QRIS dinamis (kasir — semua peran). Buat tagihan (jumlah = grand total) + poll status.
  handle('qris:buatTagihan', ({ jumlah, keterangan } = {}) =>
    withAuthWatch(api.post('/qris/tagihan', { body: { jumlah: num(jumlah, { required: true }), keterangan: str(keterangan, { max: 190 }) } })))
  handle('qris:statusTagihan', ({ id } = {}) =>
    withAuthWatch(api.get(`/qris/tagihan/${encodeURIComponent(str(id, { required: true }))}`)))

  // ---------- Langganan & Kontak CS (Sistem Mitra) ----------
  // Endpoint per-tenant; kontrak di docs/Skema-API-Sistem-Mitra-Tuleh.md §6.5.
  // Gateway harus meng-allowlist path ini (lihat Tiket-Server-Backend T-11) —
  // Mode Demo meng-intersep keduanya via demo.js.
  handle('langganan:status', () => withAuthWatch(api.get('/langganan/status')))
  // Buat/ambil tagihan pembayaran (Midtrans Snap). Tanpa body; idempoten di server
  // (dipanggil berulang → tagihan & link sama). Respons: {invoice, pembayaran}.
  handle('langganan:bayar', () => withAuthWatch(api.post('/langganan/bayar', { body: {} })))

  // Buka halaman pembayaran Midtrans DI DALAM aplikasi (BrowserWindow modal,
  // Chromium penuh → 3-D Secure & QRIS jalan). Pantau navigasi: saat Midtrans
  // mengarahkan ke URL selesai (mengandung transaction_status atau ke domain
  // tatreport.com/bayar), kembalikan hasilnya. result:
  // settlement|capture|pending|deny|cancel|expire|finished|closed.
  handle('langganan:jendelaBayar', ({ url }) => {
    const u = str(url, { required: true, max: 2000 })
    if (!/^https:\/\//i.test(u)) return fail('URL pembayaran tidak valid.')
    const parent = getMainWindow()
    return new Promise((resolve) => {
      const win = new BrowserWindow({
        width: 480, height: 760,
        parent: parent && !parent.isDestroyed() ? parent : undefined,
        modal: !!parent, title: 'Pembayaran Langganan', autoHideMenuBar: true,
        webPreferences: { nodeIntegration: false, contextIsolation: true, sandbox: true }
      })
      let done = false
      const finish = (result) => {
        if (done) return
        done = true
        resolve({ ok: true, data: { result } })
        if (!win.isDestroyed()) win.close()
      }
      const inspect = (navUrl) => {
        try {
          const p = new URL(navUrl)
          const ts = p.searchParams.get('transaction_status')
          if (ts) return finish(ts) // sinyal Midtrans langsung
          // Halaman selesai merchant (mis. pos.tatreport.com/bayar/selesai)
          if (/(^|\.)tatreport\.com$/i.test(p.host) && /bayar|selesai|finish|callback|return/i.test(p.pathname)) return finish('finished')
        } catch { /* abaikan URL non-standar */ }
      }
      win.webContents.on('will-redirect', (_e, navUrl) => inspect(navUrl))
      win.webContents.on('did-navigate', (_e, navUrl) => inspect(navUrl))
      win.webContents.on('did-navigate-in-page', (_e, navUrl) => inspect(navUrl))
      win.on('closed', () => { if (!done) { done = true; resolve({ ok: true, data: { result: 'closed' } }) } })
      win.loadURL(u).catch(() => finish('error'))
    })
  })

  handle('cs:kontak', () => withAuthWatch(api.get('/kontak-cs')))

  // ---------- Toko & manifest (POS universal) ----------

  handle('toko:list', () => withAuthWatch(api.get('/tokos')))

  handle('toko:manifest', ({ id }) =>
    withAuthWatch(api.get(`/tokos/${encodeURIComponent(str(id, { required: true }))}/manifest`)))

  // Konteks toko aktif (MOVERA §1.3): simpan id terpilih agar api-client
  // menyisipkannya sebagai ?toko_id di tiap permintaan terautentikasi —
  // menyingkirkan 409 "Pilih toko aktif" pada perusahaan multi-toko.
  // Mode Demo meng-intersep channel ini (demo.js) sehingga tak sampai sini.
  handle('toko:select', ({ id }) => {
    const tokoId = str(id, { required: true })
    api.setActiveTokoId(tokoId)
    return { ok: true, data: { selected: tokoId } }
  })

  // ---------- Stasiun kerja (endpoint server menyusul — Blueprint §13) ----------

  handle('station:list', () => withAuthWatch(api.get('/stations')))

  handle('station:create', ({ type, nama, kapasitas }) =>
    withAuthWatch(api.post('/stations', {
      body: {
        type: str(type, { required: true, max: 40 }),
        nama: str(nama, { required: true, max: 100 }),
        kapasitas: num(kapasitas)
      }
    })))

  handle('station:update', ({ id, nama, status, kapasitas }) =>
    withAuthWatch(api.request('PATCH', `/stations/${encodeURIComponent(str(id, { required: true }))}`, {
      body: {
        nama: str(nama, { max: 100 }),
        status: str(status, { max: 20 }),
        kapasitas: num(kapasitas)
      }
    })))

  handle('station:delete', ({ id }) =>
    withAuthWatch(api.request('DELETE', `/stations/${encodeURIComponent(str(id, { required: true }))}`)))

  // ---------- Pesanan hidup (POS universal — KDS / Papan Proses) ----------

  handle('order:list', ({ stage }) =>
    withAuthWatch(api.get('/orders', { query: { stage: str(stage, { max: 40 }) } })))

  handle('order:transition', ({ id, to }) =>
    withAuthWatch(api.post(`/orders/${encodeURIComponent(str(id, { required: true }))}/transition`, {
      body: { to: str(to, { required: true, max: 40 }) }
    })))

  // Konfirmasi bayar order QR meja. Di server MOVERA dipetakan sebagai
  // transisi keluar dari MENUNGGU_BAYAR (kontrak final menunggu server).
  handle('order:konfirmasiBayar', ({ id, tipePembayaran }) =>
    withAuthWatch(api.post(`/orders/${encodeURIComponent(str(id, { required: true }))}/transition`, {
      body: { to: 'ANTRIAN', tipe_pembayaran: str(tipePembayaran, { max: 20 }) }
    })))

  // Meja: server yang memiliki daftarnya (nomor + kode QR). `semua` menyertakan
  // meja nonaktif untuk layar pengaturan; peta kasir memakai daftar aktif saja.
  handle('table:list', ({ semua } = {}) =>
    withAuthWatch(api.get('/tables', { query: semua ? { semua: 1 } : {} })))

  handle('table:tambah', ({ nomor, kode }) =>
    withAuthWatch(api.post('/tables', {
      body: { nomor: str(nomor, { required: true, max: 30 }), kode: str(kode, { max: 60 }) || undefined }
    })))

  // Ubah nomor. `kode` sengaja TIDAK dikirim bila kosong: QR yang sudah
  // tercetak dan tertempel di meja harus tetap berlaku setelah meja diberi
  // nomor baru.
  handle('table:ubah', ({ id, nomor, kode }) =>
    withAuthWatch(api.put(`/tables/${encodeURIComponent(str(id, { required: true }))}`, {
      body: { nomor: str(nomor, { required: true, max: 30 }), ...(kode ? { kode: str(kode, { max: 60 }) } : {}) }
    })))

  // Nonaktifkan (server soft-delete). Ditolak 409 bila meja masih punya bon
  // terbuka — pesan server ditampilkan apa adanya karena menyebut nomor bonnya.
  handle('table:nonaktifkan', ({ id }) =>
    withAuthWatch(api.hapus(`/tables/${encodeURIComponent(str(id, { required: true }))}`)))

  // Nota bayar-saat-ambil (laundry). Kontrak server final menyusul (Blueprint §13).
  handle('order:simpanNota', ({ items, idPelanggan, catatan }) => {
    if (!Array.isArray(items) || items.length === 0) return fail('Keranjang masih kosong.')
    return withAuthWatch(api.post('/orders', {
      body: {
        bayar: 'NANTI',
        items: items.map((i) => ({
          id_produk: str(i.idProduk, { required: true }),
          harga: num(i.harga, { required: true }),
          kuantitas: num(i.kuantitas, { required: true })
        })),
        id_pelanggan: str(idPelanggan) || null,
        catatan: str(catatan, { max: 500 }) || null
      }
    }))
  })

  handle('order:lunasi', ({ id, tipePembayaran }) =>
    withAuthWatch(api.post(`/orders/${encodeURIComponent(str(id, { required: true }))}/transition`, {
      body: { to: 'SELESAI', tipe_pembayaran: str(tipePembayaran, { max: 20 }) }
    })))

  // ---------- Bon Meja (open bill dine-in). Kontrak server final menyusul (Blueprint §13). ----------

  handle('bill:peta', () => withAuthWatch(api.get('/bills', { query: { status: 'BUKA' } })))

  handle('bill:buka', ({ mejaId, pax }) =>
    withAuthWatch(api.post('/bills', {
      body: { meja_id: str(mejaId, { required: true }), pax: num(pax) ?? 1 }
    })))

  handle('bill:detail', ({ id }) =>
    withAuthWatch(api.get(`/bills/${encodeURIComponent(str(id, { required: true }))}`)))

  handle('bill:tambahRonde', ({ id, items, catatan }) => {
    if (!Array.isArray(items) || items.length === 0) return fail('Belum ada item pesanan.')
    return withAuthWatch(api.post(`/bills/${encodeURIComponent(str(id, { required: true }))}/rounds`, {
      body: {
        items: items.map((i) => ({
          id_produk: str(i.idProduk, { required: true }),
          kuantitas: num(i.kuantitas, { required: true }),
          catatan: str(i.catatan, { max: 120 }) || null
        })),
        catatan: str(catatan, { max: 300 }) || null
      }
    }))
  })

  handle('bill:setPax', ({ id, pax }) =>
    withAuthWatch(api.request('PATCH', `/bills/${encodeURIComponent(str(id, { required: true }))}`, {
      body: { pax: num(pax, { required: true }) }
    })))

  handle('bill:cetak', ({ id }) =>
    withAuthWatch(api.get(`/bills/${encodeURIComponent(str(id, { required: true }))}/prebill`)))

  handle('bill:bayar', ({ id, tipePembayaran, dibayar }) =>
    withAuthWatch(api.post(`/bills/${encodeURIComponent(str(id, { required: true }))}/settle`, {
      body: { tipe_pembayaran: str(tipePembayaran, { max: 20 }), dibayar: num(dibayar) ?? null }
    })))

  handle('bill:gabung', ({ idUtama, idGabung }) =>
    withAuthWatch(api.post(`/bills/${encodeURIComponent(str(idUtama, { required: true }))}/merge`, {
      body: { bill_id: str(idGabung, { required: true }) }
    })))

  handle('bill:batal', ({ id }) =>
    withAuthWatch(api.post(`/bills/${encodeURIComponent(str(id, { required: true }))}/void`, { body: {} })))

  // ---------- Produk & master ----------

  handle('produk:list', ({ q, kategoriId, gudangId, tipe, includeHabis, perPage, page }) =>
    withAuthWatch(api.get('/produk', {
      query: {
        q: str(q, { max: 190 }),
        kategori_id: str(kategoriId),
        gudang_id: str(gudangId),
        // tipe: PRODUK | JASA | SEMUA (layar manajemen & katalog jasa)
        tipe: str(tipe, { max: 10 }),
        include_habis: includeHabis ? 1 : undefined,
        per_page: intBetween(perPage, 1, 100, 50),
        page: intBetween(page, 1, 100000, 1)
      }
    })))

  handle('produk:barcode', ({ barcode, gudangId }) =>
    withAuthWatch(api.get(`/produk/barcode/${encodeURIComponent(str(barcode, { required: true, max: 190 }))}`, {
      query: { gudang_id: str(gudangId) }
    })))

  handle('produk:detail', ({ id, gudangId }) =>
    withAuthWatch(api.get(`/produk/${encodeURIComponent(str(id, { required: true }))}`, {
      query: { gudang_id: str(gudangId) }
    })))

  // Produk CRUD (manajemen — O/M; server menolak KASIR dgn 403)
  handle('produk:create', ({ nama, tipe, hargaBeli, hargaJual, barcode, kelolaStok }) =>
    withAuthWatch(api.post('/produk', {
      body: {
        nama: str(nama, { required: true, max: 190 }),
        tipe: str(tipe, { max: 10 }) || 'PRODUK',
        harga_beli: num(hargaBeli),
        harga_jual: num(hargaJual, { required: true }),
        barcode: str(barcode, { max: 60 }),
        kelola_stok: kelolaStok === undefined ? undefined : !!kelolaStok
      }
    })))

  // PATCH kirim HANYA field yang berubah (renderer mengisi yang berubah saja)
  handle('produk:update', ({ id, nama, hargaBeli, hargaJual, barcode, kelolaStok }) =>
    withAuthWatch(api.request('PATCH', `/produk/${encodeURIComponent(str(id, { required: true }))}`, {
      body: {
        nama: str(nama, { max: 190 }),
        harga_beli: num(hargaBeli),
        harga_jual: num(hargaJual),
        barcode: str(barcode, { max: 60 }),
        kelola_stok: kelolaStok === undefined ? undefined : !!kelolaStok
      }
    })))

  handle('produk:remove', ({ id }) =>
    withAuthWatch(api.request('DELETE', `/produk/${encodeURIComponent(str(id, { required: true }))}`)))

  handle('master:kategori', () => withAuthWatch(api.get('/kategori')))
  handle('master:gudang', () => withAuthWatch(api.get('/gudang')))
  handle('master:satuan', () => withAuthWatch(api.get('/satuan')))

  // ---------- Pelanggan ----------

  handle('pelanggan:list', ({ q }) =>
    withAuthWatch(api.get('/pelanggan', { query: { q: str(q, { max: 190 }) } })))

  handle('pelanggan:create', ({ nama, telepon, alamat }) =>
    withAuthWatch(api.post('/pelanggan', {
      body: {
        nama: str(nama, { required: true, max: 190 }),
        telepon: str(telepon, { max: 30 }),
        alamat: str(alamat, { max: 500 })
      }
    })))

  handle('pelanggan:detail', ({ id }) =>
    withAuthWatch(api.get(`/pelanggan/${encodeURIComponent(str(id, { required: true }))}`)))

  // Quick add customer (nama + no WhatsApp) — semua peran; server normalkan nomor.
  handle('pelanggan:quick', ({ nama, noWhatsapp }) =>
    withAuthWatch(api.post('/pelanggan/quick', {
      body: {
        nama: str(nama, { required: true, max: 190 }),
        no_whatsapp: str(noWhatsapp, { max: 30 })
      }
    })))

  // ---------- Inventory (kelola stok — layar Inventory O/M) ----------

  handle('inventory:stokMasuk', ({ idProduk, jumlah, keterangan }) =>
    tulisAtauAntre({
      jenis: 'STOK_MASUK',
      jalur: '/inventory/stok-masuk',
      body: {
        id_produk: str(idProduk, { required: true }),
        jumlah: num(jumlah, { required: true }),
        keterangan: str(keterangan, { max: 300 })
      },
      deltaStok: { [str(idProduk, { required: true })]: num(jumlah, { required: true }) }
    }))

  handle('inventory:opname', ({ idProduk, jumlah, keterangan }) =>
    withAuthWatch(api.post('/inventory/opname', {
      body: {
        id_produk: str(idProduk, { required: true }),
        jumlah: num(jumlah, { required: true }),
        keterangan: str(keterangan, { max: 300 })
      }
    })))

  handle('inventory:riwayat', ({ page, perPage }) =>
    withAuthWatch(api.get('/inventory/riwayat', {
      query: { page: intBetween(page, 1, 100000, 1), per_page: intBetween(perPage, 1, 100, 25) }
    })))

  // ---------- Pengeluaran (kas keluar — O/M) ----------

  handle('pengeluaran:list', ({ bulan }) =>
    withAuthWatch(api.get('/pengeluaran', { query: { bulan: str(bulan, { max: 7 }) } })))

  handle('pengeluaran:create', ({ keterangan, nominal, tanggal }) =>
    tulisAtauAntre({
      jenis: 'PENGELUARAN',
      jalur: '/pengeluaran',
      body: {
        keterangan: str(keterangan, { required: true, max: 190 }),
        nominal: num(nominal, { required: true }),
        tanggal: str(tanggal, { max: 10 })
      }
    }))

  handle('pengeluaran:remove', ({ id }) =>
    withAuthWatch(api.request('DELETE', `/pengeluaran/${encodeURIComponent(str(id, { required: true }))}`)))

  // ---------- Sesi kasir ----------

  handle('sesi:aktif', () => withAuthWatch(api.get('/sesi/aktif')))

  handle('sesi:list', ({ tanggalDari, tanggalSampai }) =>
    withAuthWatch(api.get('/sesi', {
      query: { tanggal_dari: str(tanggalDari, { max: 10 }), tanggal_sampai: str(tanggalSampai, { max: 10 }) }
    })))

  handle('sesi:buka', ({ gudangId, kasAwal, catatan }) =>
    withAuthWatch(api.post('/sesi/buka', {
      body: {
        gudang_id: str(gudangId, { required: true }),
        kas_awal: num(kasAwal, { required: true }),
        catatan: str(catatan, { max: 500 }),
        // Ikat sesi ke toko aktif (MOVERA §1.3 opsi 2); undefined → dihilangkan JSON
        toko_id: api.getActiveTokoId() || undefined
      }
    })))

  handle('sesi:tutup', ({ id, kasAkhirFisik, catatan }) =>
    withAuthWatch(api.post(`/sesi/${encodeURIComponent(str(id, { required: true }))}/tutup`, {
      body: {
        kas_akhir_fisik: num(kasAkhirFisik, { required: true }),
        catatan: str(catatan, { max: 500 })
      }
    })))

  handle('sesi:rekap', ({ id }) =>
    withAuthWatch(api.get(`/sesi/${encodeURIComponent(str(id, { required: true }))}/rekap`)))

  // ---------- Transaksi ----------

  handle('trx:checkout', async ({ items, tipePembayaran, dibayar, idPelanggan, catatan, qrisTagihanId, tampilan, kasirNama, pelangganNama }) => {
    if (!Array.isArray(items) || items.length === 0) return fail('Keranjang masih kosong.')
    if (items.length > 200) return fail('Terlalu banyak item dalam satu transaksi.')
    const cleanItems = items.map((item) => ({
      id_produk: str(item.idProduk, { required: true }),
      harga: num(item.harga, { required: true }),
      kuantitas: num(item.kuantitas, { required: true }),
      diskon_persen: num(item.diskonPersen) ?? 0,
      pajak_persen: num(item.pajakPersen) ?? 0
    }))
    const body = {
      items: cleanItems,
      tipe_pembayaran: str(tipePembayaran, { required: true, max: 20 }),
      dibayar: num(dibayar, { required: true }),
      id_pelanggan: str(idPelanggan) || null,
      catatan: str(catatan, { max: 500 }) || null,
      // QRIS terverifikasi (Midtrans): id tagihan LUNAS. Hanya dikirim bila ada.
      qris_tagihan_id: str(qrisTagihanId) || undefined
    }
    // QRIS otomatis butuh server (tagihan diverifikasi online) → tanpa antrean.
    if (body.qris_tagihan_id) return withAuthWatch(api.post('/transaksi/checkout', { body }))

    // Struk lokal disusun dulu (nomor L-…) agar bisa dicetak & masuk riwayat
    // walau antre; bila terkirim langsung, struk server yang dipakai.
    const nomor = offline.nomorLokal.berikutnya()
    const struk = offline.buatStrukLokal({
      nomor, body,
      tampilan: Array.isArray(tampilan) ? tampilan : [],
      kasir: str(kasirNama, { max: 100 }) || null,
      pelangganNama: str(pelangganNama, { max: 150 }) || null
    })
    const deltaStok = {}
    for (const t of (Array.isArray(tampilan) ? tampilan : [])) {
      if (t && t.kelola_stok) deltaStok[String(t.id_produk)] = -(Number((cleanItems.find((i) => i.id_produk === String(t.id_produk)) || {}).kuantitas) || 0)
    }
    const r = await tulisAtauAntre({
      jenis: 'CHECKOUT', jalur: '/transaksi/checkout', body, deltaStok,
      transaksi: { tokoId: api.getActiveTokoId(), nomorLokal: nomor, waktuKlien: struk.tanggal, struk }
    })
    if (r.tertunda) {
      struk.catatan_kaki = 'Belum tersinkron — nomor resmi menyusul setelah online.'
      return { ...r, data: struk }
    }
    return r
  })

  handle('trx:list', async ({ status, sesiId, tanggalDari, tanggalSampai }) => {
    const r = await withAuthWatch(api.get('/transaksi', {
      query: {
        status: str(status, { max: 20 }),
        sesi_id: str(sesiId),
        // Dua gaya nama parameter dikirim sekaligus: OpenAPI memakai
        // tanggal_dari/tanggal_sampai, Docs-API.md §6.11 memakai dari/sampai.
        // Server mengabaikan yang tidak dikenalnya.
        tanggal_dari: str(tanggalDari, { max: 10 }),
        tanggal_sampai: str(tanggalSampai, { max: 10 }),
        dari: str(tanggalDari, { max: 10 }),
        sampai: str(tanggalSampai, { max: 10 })
      }
    }))
    // Transaksi lokal yang belum terkirim ditaruh paling atas (id lokal:<ref>).
    const lokal = offline.antrean.transaksiTertunda(api.getActiveTokoId())
      .map((t) => ({ ...t.struk, id: `lokal:${t.clientRef}`, nomor: t.nomorLokal, status: 'BELUM SINKRON' }))
    if (!lokal.length) return r
    if (r.ok && Array.isArray(r.data)) return { ...r, data: [...lokal, ...r.data] }
    if (!r.ok) return { ok: true, status: 200, data: lokal, meta: null, message: '', offline: true }
    return r
  })

  handle('trx:detail', ({ id }) => {
    const sid = str(id, { required: true })
    if (sid.startsWith('lokal:')) {
      const t = offline.antrean.transaksiLokal(sid.slice(6))
      if (!t) return fail('Transaksi lokal tidak ditemukan (mungkin sudah terkirim).')
      return { ok: true, status: 200, data: { ...t.struk, id: sid, nomor: t.nomorLokal, status: 'BELUM SINKRON' }, meta: null, message: '' }
    }
    return withAuthWatch(api.get(`/transaksi/${encodeURIComponent(sid)}`))
  })

  handle('trx:batal', ({ id }) =>
    withAuthWatch(api.post(`/transaksi/${encodeURIComponent(str(id, { required: true }))}/batal`)))

  // ---------- Laporan ----------

  handle('laporan:penjualanHarian', ({ tanggalDari, tanggalSampai }) =>
    withAuthWatch(api.get('/laporan/penjualan-harian', {
      query: { tanggal_dari: str(tanggalDari, { max: 10 }), tanggal_sampai: str(tanggalSampai, { max: 10 }) }
    })))

  handle('laporan:penjualanProduk', ({ tanggalDari, tanggalSampai }) =>
    withAuthWatch(api.get('/laporan/penjualan-produk', {
      query: { tanggal_dari: str(tanggalDari, { max: 10 }), tanggal_sampai: str(tanggalSampai, { max: 10 }) }
    })))

  handle('laporan:stok', ({ gudangId }) =>
    withAuthWatch(api.get('/laporan/stok', { query: { gudang_id: str(gudangId) } })))

  handle('laporan:rekapKasir', ({ tanggalDari, tanggalSampai }) =>
    withAuthWatch(api.get('/laporan/rekap-kasir', {
      query: { tanggal_dari: str(tanggalDari, { max: 10 }), tanggal_sampai: str(tanggalSampai, { max: 10 }) }
    })))

  handle('laporan:keuangan', ({ bulan }) =>
    withAuthWatch(api.get('/laporan/keuangan', { query: { bulan: str(bulan, { max: 7 }) } })))
}

module.exports = { registerIpcHandlers }
