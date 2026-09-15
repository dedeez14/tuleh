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
const { buatTulisAtauAntre } = require('./offline/tulis')
const diagnostik = require('./diagnostik')
const firewall = require('./firewall')
const { urlHttpsAman, domainServer, hostMilik } = require('./lib/url-aman')
const { tandaiJendelaBayar, lepasJendelaBayar } = require('./lib/izin')

// Validasi masukan & pemetaan kanal → HTTP tinggal di kontrak bersama (dipakai juga Android).
const kontrak = require('../shared/kontrak-kanal')
const { str, num } = kontrak

function fail(message) {
  return { ok: false, status: 0, message, errors: null }
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

// Diisi registerIpcHandlers: pemberitahu layar "Langganan berakhir" (402) untuk simulasi demo.
let kabarLanggananDemo = null

function handle(channel, handler) {
  ipcMain.handle(channel, async (_event, payload) => {
    try {
      if (demo.isActive() && demo.handlers[channel]) {
        // Simulasi kontrak #2 (IPOS_SMOKE_LANGGANAN=blokir): kanal tulis → 402 + layar kunci.
        const blokir = typeof demo.langgananDiblokir === 'function' ? demo.langgananDiblokir(channel) : null
        if (blokir) {
          if (kabarLanggananDemo) kabarLanggananDemo({ pesan: blokir.message, status: blokir.meta.langganan.status, perpanjangUrl: blokir.meta.langganan.perpanjang_url })
          return blokir
        }
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

  const kirimKeRenderer = (kanal, data) => {
    const win = getMainWindow()
    if (win && !win.isDestroyed()) win.webContents.send(kanal, data)
  }

  // ---------- Diagnostik (kontrak #1): laporan galat + log berkas ----------
  diagnostik.init({
    api,
    dir: app.getPath('userData'),
    konteks: () => {
      const gw = gateway.status()
      return { gateway: { running: gw.running, external: gw.external, version: gw.version, versiApp: gw.versiApp } }
    }
  })

  // ---------- Kanal HTTP bersama (src/shared/kontrak-kanal.js) ----------
  const konteksKontrak = () => ({ tokoAktif: api.getActiveTokoId(), versiApp: api.appVersion(), platform: api.PLATFORM })
  function kirimKontrak(kanal, payload) {
    const minta = kontrak.bentuk(kanal, payload, konteksKontrak())
    if (minta.metode === 'UPLOAD') return api.upload(minta.jalur, { file: minta.berkas })
    return api.request(minta.metode, minta.jalur, { query: minta.query, body: minta.body, auth: minta.auth !== false })
  }

  // ---------- Mode offline (salinan baca + antrean kirim) ----------
  // Pengurai mengirim ulang lewat api.post; timeout diberi status -1 agar
  // dibedakan dari "tidak sampai" (0) — lihat offline/pengurai.js.
  offline.init({
    dir: app.getPath('userData'),
    kirim: async (jalur, body, pesan) => {
      // Kirim atas nama toko saat pesan dibuat, bukan toko aktif sekarang.
      const query = pesan && pesan.tokoId ? { toko_id: pesan.tokoId } : undefined
      // pantauKoneksi:false — satu muatan beracun (5xx berulang) tidak menandai seluruh aplikasi offline.
      const r = await withAuthWatch(api.post(jalur, { body, query, pantauKoneksi: false }))
      return r.timeout ? { ...r, status: -1 } : r
    },
    // Daftar transaksi server untuk memulihkan baris "mungkin sudah sampai".
    ambilDaftar: async (tokoId, dari, sampai) => {
      const r = await api.get('/transaksi', {
        query: { dari, sampai, tanggal_dari: dari, tanggal_sampai: sampai, ...(tokoId ? { toko_id: tokoId } : {}) }
      })
      return r.ok && Array.isArray(r.data) ? r.data : null
    },
    // Tanpa token (mis. setelah 401) pengurai tidak mengirim — tidak memukul server tiap detik.
    siapKirim: () => api.hasToken(),
    // Antrean gagal ditulis / berkas rusak → pita status (lewat koneksi._siar) + laporan dukungan.
    onGalatAntrean: (galat) => {
      diagnostik.lapor({
        jenis: 'error',
        pesan: `Antrean offline: ${galat.pesan}`,
        stack: [galat.detail, ...(galat.berkasRusak || [])].filter(Boolean).join('\n'),
        konteks: { layar: 'antrean-offline', jenis_galat: galat.jenis }
      })
    }
  })
  const kirimStatusOffline = () => {
    const win = getMainWindow()
    if (win && !win.isDestroyed()) win.webContents.send('offline:status', offline.status(api.getActiveTokoId()))
  }
  offline.koneksi.langgan(kirimStatusOffline)
  // Kembali online (dari permintaan mana pun) → uraikan antrean + kirim laporan diagnostik tertunda.
  offline.koneksi.langgan(() => {
    if (!offline.koneksi.online) return
    if (offline.antrean.ringkas().menunggu > 0) offline.pengurai.jalankan()
    diagnostik.kirimAntrean()
  })
  // Jalankan sekali saat start bila ada sisa antrean dari sesi sebelumnya.
  setTimeout(() => { if (api.hasToken()) offline.pengurai.jalankan() }, 3000).unref?.()

  /**
   * Permintaan tulis dengan jalur offline (offline/tulis.js): offline / gangguan jaringan
   * (termasuk 5xx/408/429 & galat gateway) → antrekan & kirim ulang otomatis; 402
   * langganan & penolakan 4xx → kembalikan apa adanya (tidak diantrekan).
   */
  const tulisAtauAntre = buatTulisAtauAntre({
    offline,
    kirim: (jalur, body) => withAuthWatch(api.post(jalur, { body })),
    tokoAktif: () => api.getActiveTokoId(),
    setelahAntre: () => kirimStatusOffline()
  })

  handle('offline:status', () => ({ ok: true, data: offline.status(api.getActiveTokoId()) }))
  handle('offline:daftar', () => ({
    ok: true,
    data: offline.antrean.semua().map((p) => ({ ...p, label: offline.labelJenis(p.jenis) }))
  }))
  handle('offline:sinkron', async () => {
    const ping = await api.get('/ping', { auth: false })
    if (!ping.ok) { offline.koneksi.tandaiOffline(); kirimStatusOffline(); return { ok: false, status: 0, message: 'Server belum terjangkau.' } }
    offline.koneksi.tandaiOnline()
    // Manual: lewati jeda global (mis. setelah langganan diperpanjang) lalu kirim yang siap.
    const n = await offline.pengurai.sinkronSekarang()
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
  // Gateway mati / tak menjawab → langsung kembali ke koneksi langsung; pengawas
  // menyalakannya lagi dengan mundur (lib/pengawas-gateway.js).
  gateway.onBerubah((st) => {
    api.setGateway(st.running && st.port ? `http://127.0.0.1:${st.port}` : null)
    console.log('[gateway] status', JSON.stringify(st))
  })
  api.setGatewayGagalHandler(() => gateway.laporGagal())
  gateway.ensureRunning(settings.baseUrl).then((st) => {
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

  // Kontrak #2: HTTP 402 dari endpoint tulis mana pun → layar "Langganan berakhir".
  // Pesan & URL perpanjang dari server; URL divalidasi (https) — kosong = tanpa tombol.
  let perpanjangUrlTerakhir = null
  function kabarkanLanggananTerkunci(info) {
    const url = urlHttpsAman(info && info.perpanjangUrl)
    if (url) perpanjangUrlTerakhir = url
    kirimKeRenderer('langganan:terkunci', {
      pesan: (info && info.pesan) || '',
      status: (info && info.status) || null,
      perpanjang_url: url
    })
    console.log('[langganan] 402 diterima —', (info && info.pesan) || '(tanpa pesan)')
  }
  api.setLanggananHandler(kabarkanLanggananTerkunci)
  kabarLanggananDemo = kabarkanLanggananTerkunci

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
      // Nilai X-Tuleh-Platform / `platform` diagnostik (renderer bersama membedakan desktop vs Android lama).
      platformApi: api.PLATFORM,
      kemampuan: { antreanOffline: true, printerSistem: true, laporanLog: true },
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

  // Auto-Update: cek versi (app:checkUpdate, tanpa auth) didaftarkan lewat kontrak bersama di bawah.

  // Auto-Update Tahap 3 (desktop): unduh & pasang lewat electron-updater.
  // Renderer memakai ini bila didukung; jika tidak, jatuh ke unduhan browser.
  handle('update:supported', () => ({ ok: true, data: { supported: updater.isSupported() } }))
  handle('update:download', () => updater.download())
  handle('update:install', () => { updater.install(); return { ok: true } })

  // Buka URL di browser sistem (halaman pembayaran Midtrans — WAJIB browser penuh,
  // bukan webview: 3-D Secure & deep link e-wallet kerap gagal di webview).
  handle('app:openExternal', async (payload) => {
    // Kompatibel: renderer lama mengirim string, yang baru { url }.
    const mentah = typeof payload === 'string' ? payload : payload && payload.url
    const u = urlHttpsAman(str(mentah, { required: true, max: 2000 }))
    if (!u) return fail('Hanya URL https yang boleh dibuka.')
    await shell.openExternal(u)
    return { ok: true, data: null }
  })

  // Buka akses LAN (firewall) — tombol eksplisit pengguna (boleh meminta lagi walau tadi ditolak).
  handle('firewall:ensure', async () => {
    const r = await firewall.ensure({ paksa: true })
    if (r && r.ok) return { ok: true, data: r }
    return fail('Gagal membuka akses jaringan (izin admin ditolak?). Coba lagi & pilih “Ya” pada dialog Windows.')
  })

  // Buka Papan Antrian (TV/monitor) — URL LAN dibentuk di sini (tepercaya), bukan
  // dari renderer, jadi aman meski http (alamat LAN lokal).
  handle('display:antrian', async () => {
    const ts = tracker.status()
    if (!ts.running || !ts.baseUrl) return fail('Server LAN belum aktif — papan antrian belum bisa dibuka.')
    const url = `${ts.baseUrl}/antrian`
    // Tampilan LAN benar-benar dipakai → baru minta aturan firewall (sekali; tidak diulang
    // bila ditolak di sesi ini). Tidak menunggu dialog UAC agar papan langsung terbuka.
    firewall.ensure().catch(() => {})
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
    const lama = api.getBaseUrl()
    const cek = settingsStore.normalisasiBaseUrl(baseUrl)
    if (!cek.ok) return fail(cek.message)
    const berganti = cek.baseUrl !== lama
    // Antrean berisi penjualan milik server lama — jangan sampai terkirim ke server lain.
    if (berganti && offline.antrean.ringkas().total > 0) {
      return { ok: false, status: 409, code: 'ANTREAN', message: `${offline.antrean.ringkas().total} data offline belum terkirim ke server saat ini. Kirim dulu (Pengaturan → Sinkronisasi) atau batalkan sebelum mengganti server.`, errors: null }
    }
    const result = settingsStore.setBaseUrl(baseUrl)
    if (!result.ok) return fail(result.message)
    api.setBaseUrl(result.baseUrl)
    if (berganti) {
      // Token & salinan offline milik server lama tidak boleh terbawa ke server baru.
      api.setToken(null)
      authStore.clear()
      api.setActiveTokoId(null)
      if (offline.salinan) offline.salinan.hapusSemua()
      perpanjangUrlTerakhir = null
    }
    // Ganti server → gateway di-restart dengan upstream baru (best-effort; status via onBerubah)
    api.setGateway(null)
    gateway.restart(result.baseUrl)
    return { ok: true, data: { baseUrl: result.baseUrl, keluar: berganti } }
  })

  // ---------- Diagnostik: galat renderer & laporan log ke dukungan ----------
  handle('diagnostik:laporGalat', (p) => {
    diagnostik.lapor({
      jenis: p && p.jenis === 'crash' ? 'crash' : 'error',
      pesan: str(p && p.pesan, { max: 4000 }) || 'Galat renderer tanpa pesan',
      stack: str(p && p.stack, { max: 40000 }) || '',
      konteks: { layar: str(p && p.layar, { max: 80 }) || '', sumber: 'renderer' }
    })
    return { ok: true, data: null }
  })
  handle('diagnostik:pratinjauLog', (p) => ({ ok: true, data: diagnostik.pratinjauLog({ catatan: str(p && p.catatan, { max: 2000 }), layar: str(p && p.layar, { max: 80 }) }) }))
  handle('diagnostik:kirimLog', (p) => diagnostik.kirimLog({ id: str(p && p.id, { required: true, max: 80 }) }))

  handle('net:ping', async () => {
    const r = await kirimKontrak('net:ping')
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
      // Antrean yang tertahan karena sesi berakhir dilanjutkan dengan token baru.
      if (offline.antrean.ringkas().menunggu > 0) offline.pengurai.sinkronSekarang()
    }
    return result
  })

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

  // Kanal HTTP generik: SEMUA entri kontrak kecuali yang butuh perilaku khusus desktop
  // (penanda koneksi, antrean offline, riwayat lokal) — ditulis sesudah perulangan ini.
  const KANAL_KHUSUS_DESKTOP = new Set(['net:ping', 'inventory:stokMasuk', 'pengeluaran:create', 'trx:checkout', 'trx:list', 'trx:detail'])
  for (const kanal of Object.keys(kontrak.KANAL)) {
    if (KANAL_KHUSUS_DESKTOP.has(kanal)) continue
    handle(kanal, async (payload) => {
      const r = await withAuthWatch(kirimKontrak(kanal, payload))
      // /config membawa batas tinjau otomatis antrean (juga saat disajikan dari salinan offline).
      if (kanal === 'config:get' && r.ok && r.data) offline.aturKebijakanAntrean(r.data)
      return r
    })
  }

  // Tulis yang boleh diantrekan saat offline (kontrak menandai `antrean`).
  for (const kanal of ['inventory:stokMasuk', 'pengeluaran:create']) {
    const { antrean } = kontrak.KANAL[kanal]
    handle(kanal, (payload) => {
      const minta = kontrak.bentuk(kanal, payload, konteksKontrak())
      return tulisAtauAntre({ jenis: antrean.jenis, jalur: minta.jalur, body: minta.body, deltaStok: antrean.deltaStok ? antrean.deltaStok(payload) : {} })
    })
  }

  // Buka halaman pembayaran Midtrans DI DALAM aplikasi (BrowserWindow modal,
  // Chromium penuh → 3-D Secure & QRIS jalan). Pantau navigasi: saat Midtrans
  // mengarahkan ke URL selesai (mengandung transaction_status atau ke halaman
  // bayar/selesai di domain server), kembalikan hasilnya. result:
  // settlement|capture|pending|deny|cancel|expire|finished|closed.
  handle('langganan:jendelaBayar', ({ url }) => {
    const u = urlHttpsAman(str(url, { required: true, max: 2000 }))
    if (!u) return fail('URL pembayaran tidak valid.')
    // Halaman "selesai" milik server: domain server yang dipakai aplikasi (+ domain URL
    // perpanjang dari server) — bukan domain tertanam.
    const domainSelesai = [domainServer(api.getBaseUrl()), domainServer(perpanjangUrlTerakhir)]
    const parent = getMainWindow()
    return new Promise((resolve) => {
      const win = new BrowserWindow({
        width: 480, height: 760,
        parent: parent && !parent.isDestroyed() ? parent : undefined,
        modal: !!parent, title: 'Pembayaran Langganan', autoHideMenuBar: true,
        webPreferences: { nodeIntegration: false, contextIsolation: true, sandbox: true }
      })
      const idKonten = win.webContents.id
      tandaiJendelaBayar(idKonten) // izin salin (nomor VA) hanya untuk jendela ini
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
          // Halaman selesai milik server (mis. pos.<domain server>/bayar/selesai)
          if (hostMilik(navUrl, domainSelesai) && /bayar|selesai|finish|callback|return/i.test(p.pathname)) return finish('finished')
        } catch { /* abaikan URL non-standar */ }
      }
      win.webContents.on('will-redirect', (_e, navUrl) => inspect(navUrl))
      win.webContents.on('did-navigate', (_e, navUrl) => inspect(navUrl))
      win.webContents.on('did-navigate-in-page', (_e, navUrl) => inspect(navUrl))
      win.on('closed', () => {
        lepasJendelaBayar(idKonten)
        if (!done) { done = true; resolve({ ok: true, data: { result: 'closed' } }) }
      })
      win.loadURL(u).catch(() => finish('error'))
    })
  })

  // Konteks toko aktif (§1.3): simpan id terpilih agar api-client
  // menyisipkannya sebagai ?toko_id di tiap permintaan terautentikasi —
  // menyingkirkan 409 "Pilih toko aktif" pada perusahaan multi-toko.
  // Mode Demo meng-intersep channel ini (demo.js) sehingga tak sampai sini.
  handle('toko:select', ({ id }) => {
    const tokoId = str(id, { required: true })
    api.setActiveTokoId(tokoId)
    return { ok: true, data: { selected: tokoId } }
  })

  // ---------- Transaksi (khusus desktop: antrean offline & riwayat lokal) ----------

  handle('trx:checkout', async (payload) => {
    const { tampilan, kasirNama, pelangganNama } = payload
    const minta = kontrak.bentuk('trx:checkout', payload, konteksKontrak())
    const body = minta.body
    // QRIS otomatis butuh server (tagihan diverifikasi online) → tanpa antrean.
    if (body.qris_tagihan_id) return withAuthWatch(api.post(minta.jalur, { body }))

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
      if (t && t.kelola_stok) deltaStok[String(t.id_produk)] = -(Number((body.items.find((i) => i.id_produk === String(t.id_produk)) || {}).kuantitas) || 0)
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

  handle('trx:list', async (payload) => {
    const r = await withAuthWatch(kirimKontrak('trx:list', payload))
    // Daftar per sesi (detail sesi kasir) hanya berisi transaksi server sesi itu.
    if (payload && payload.sesiId) return r
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
    return withAuthWatch(kirimKontrak('trx:detail', { id: sid }))
  })
}

module.exports = { registerIpcHandlers }
