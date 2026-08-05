'use strict'

const os = require('node:os')
const { app, ipcMain, shell, BrowserWindow } = require('electron')
const api = require('./api-client')
const authStore = require('./auth-store')
const settingsStore = require('./settings-store')
const demo = require('./demo')
const gateway = require('./gateway')
const tracker = require('./tracker')
const tunnel = require('./tunnel')
const qr = require('./qr')
const customerWindow = require('./customer-window')

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
      smokeFlow: process.env.IPOS_SMOKE_FLOW || null
    }
  }))

  // Buka URL di browser sistem (halaman pembayaran Midtrans — WAJIB browser penuh,
  // bukan webview: 3-D Secure & deep link e-wallet kerap gagal di webview).
  handle('app:openExternal', async ({ url }) => {
    const u = str(url, { required: true, max: 2000 })
    if (!/^https:\/\//i.test(u)) return fail('Hanya URL https yang boleh dibuka.')
    await shell.openExternal(u)
    return { ok: true, data: null }
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

  handle('app:print', () => {
    const win = getMainWindow()
    if (!win || win.isDestroyed()) return fail('Jendela tidak tersedia.')
    return new Promise((resolve) => {
      win.webContents.print(
        { printBackground: true, margins: { marginType: 'printableArea' } },
        (success, reason) => resolve(success ? { ok: true, data: null } : fail(reason || 'Cetak dibatalkan.'))
      )
    })
  })

  // Mode Demo: seluruh data disimulasikan lokal, tidak ada permintaan jaringan.
  // Server pelacakan pelanggan (LAN) ikut dinyalakan agar QR struk berfungsi.
  handle('demo:start', () => {
    const result = demo.start()
    if (result.ok) {
      tracker.start({
        tracking: demo.trackingInfo,
        menu: demo.menuInfo,
        createOrder: demo.createTableOrder,
        queueBoard: demo.queueBoardInfo
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

  handle('net:ping', () => api.get('/ping', { auth: false }))

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
    }
    return result
  })

  handle('auth:me', () => withAuthWatch(api.get('/auth/me')))

  handle('auth:logout', async () => {
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

  handle('table:list', () => withAuthWatch(api.get('/tables')))

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
    withAuthWatch(api.post('/inventory/stok-masuk', {
      body: {
        id_produk: str(idProduk, { required: true }),
        jumlah: num(jumlah, { required: true }),
        keterangan: str(keterangan, { max: 300 })
      }
    })))

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
    withAuthWatch(api.post('/pengeluaran', {
      body: {
        keterangan: str(keterangan, { required: true, max: 190 }),
        nominal: num(nominal, { required: true }),
        tanggal: str(tanggal, { max: 10 })
      }
    })))

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

  handle('trx:checkout', ({ items, tipePembayaran, dibayar, idPelanggan, catatan, qrisTagihanId }) => {
    if (!Array.isArray(items) || items.length === 0) return fail('Keranjang masih kosong.')
    if (items.length > 200) return fail('Terlalu banyak item dalam satu transaksi.')
    const cleanItems = items.map((item) => ({
      id_produk: str(item.idProduk, { required: true }),
      harga: num(item.harga, { required: true }),
      kuantitas: num(item.kuantitas, { required: true }),
      diskon_persen: num(item.diskonPersen) ?? 0,
      pajak_persen: num(item.pajakPersen) ?? 0
    }))
    return withAuthWatch(api.post('/transaksi/checkout', {
      body: {
        items: cleanItems,
        tipe_pembayaran: str(tipePembayaran, { required: true, max: 20 }),
        dibayar: num(dibayar, { required: true }),
        id_pelanggan: str(idPelanggan) || null,
        catatan: str(catatan, { max: 500 }) || null,
        // QRIS terverifikasi (Midtrans): id tagihan LUNAS. Hanya dikirim bila ada.
        qris_tagihan_id: str(qrisTagihanId) || undefined
      }
    }))
  })

  handle('trx:list', ({ status, sesiId, tanggalDari, tanggalSampai }) =>
    withAuthWatch(api.get('/transaksi', {
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
    })))

  handle('trx:detail', ({ id }) =>
    withAuthWatch(api.get(`/transaksi/${encodeURIComponent(str(id, { required: true }))}`)))

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
