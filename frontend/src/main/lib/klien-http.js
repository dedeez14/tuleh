'use strict'

// Klien HTTP POS API (inti api-client.js tanpa ketergantungan Electron agar bisa diuji
// dengan fetch palsu). api-client.js merakitnya dengan net.fetch & versi aplikasi.
//
// Semua jawaban dinormalisasi ke amplop:
//   sukses → { ok: true,  status, data, meta, message }
//   gagal  → { ok: false, status, message, errors, meta, gangguan?, gateway?, timeout? }
// `gangguan: true` = server tak terjangkau / galat sementara (lihat klasifikasi-http.js):
// pemanggil tulis mengantrekan, GET disajikan dari salinan offline bila ada.

const { JENIS, klasifikasi, penandaGateway, infoLangganan } = require('./klasifikasi-http')

const API_PREFIX = '/api/pos/v1'
const TIMEOUT_MS = 15000
const WAKTU_SERVER_TIMEOUT_MS = 6000
const MAX_BODY_BYTES = 5 * 1024 * 1024

// Jalur GET yang TIDAK disalin untuk offline (status pembayaran, masa coba, versi,
// langganan, PIN persetujuan): jawaban lama justru menyesatkan — kartu PIN akan menawarkan
// "Ganti PIN" untuk PIN yang sudah dicabut, dan daftar pemberi persetujuan memajang orang yang
// haknya sudah ditarik. (App-Lock ada di /pengaturan/keamanan, awalan berbeda.)
const TANPA_SALINAN = ['/qris', '/demo', '/ping', '/app/versi', '/langganan', '/diagnostik', '/keamanan']
function bolehDisalin(endpoint) {
  return !TANPA_SALINAN.some((p) => endpoint.startsWith(p))
}

const PESAN_STATUS = {
  0: 'Tidak dapat terhubung ke server. Periksa koneksi internet Anda.',
  401: 'Sesi Anda telah berakhir. Silakan masuk kembali.',
  402: 'Langganan berakhir. Perpanjang langganan untuk melanjutkan.',
  403: 'Anda tidak memiliki akses untuk aksi ini.',
  404: 'Data tidak ditemukan.',
  408: 'Server tidak merespons tepat waktu. Coba lagi sebentar.',
  409: 'Aksi bentrok dengan kondisi saat ini.',
  413: 'Data yang dikirim terlalu besar.',
  422: 'Data yang dikirim tidak valid.',
  426: 'Aplikasi Anda perlu diperbarui ke versi terbaru.',
  429: 'Terlalu banyak permintaan. Coba lagi sebentar.',
  500: 'Terjadi kesalahan pada server.',
  502: 'Server tidak dapat dihubungi. Periksa koneksi internet.',
  503: 'Server sedang tidak tersedia. Coba lagi sebentar.',
  504: 'Server tidak merespons tepat waktu. Coba lagi sebentar.'
}

function statusMessage(status) {
  return PESAN_STATUS[status] || `Terjadi kesalahan (HTTP ${status}).`
}

/** Koneksi ke gateway lokal ditolak (proses gateway mati) — permintaan belum terkirim. */
function sambunganDitolak(err) {
  if (!err) return false
  const kode = (err.cause && err.cause.code) || err.code || ''
  return kode === 'ECONNREFUSED' || /ERR_CONNECTION_REFUSED|ECONNREFUSED/i.test(String(err.message || ''))
}

async function readJsonSafe(response) {
  let text = ''
  try { text = await response.text() } catch { return null }
  if (text.length > MAX_BODY_BYTES) return null
  try {
    return text ? JSON.parse(text) : null
  } catch {
    return null
  }
}

/**
 * @param {object} o
 * @param {(url: string, init: object) => Promise<Response>} o.fetch
 * @param {() => string} o.versiApp
 * @param {string} o.platform            nilai X-Tuleh-Platform (mis. 'desktop')
 * @param {object} o.offline             { salinan: SalinanBaca|null, koneksi: Koneksi }
 * @param {() => boolean} [o.pura2Offline]  jalur uji (IPOS_SMOKE_OFFLINE)
 */
function buatKlienHttp({ fetch, versiApp, platform, offline, pura2Offline = () => false, timeoutMs = TIMEOUT_MS }) {
  let baseUrl = null
  let gatewayUrl = null // bila di-set, transport lewat gateway lokal (mpos-backend)
  let token = null
  let activeTokoId = null
  let upgradeHandler = null
  let langgananHandler = null
  let gatewayGagalHandler = null

  const salinan = () => (offline && offline.salinan) || null
  const koneksi = () => (offline && offline.koneksi) || null

  function panggil(handler, arg) {
    if (handler) { try { handler(arg) } catch { /* abaikan */ } }
  }

  function kunciSalinanUntuk(endpoint, query) {
    // Identitas (/auth/me) berlaku lintas toko → kunci tanpa toko/query, agar masuk
    // otomatis saat offline tetap bekerja walau toko aktif berganti.
    return endpoint === '/auth/me' ? [null, endpoint, {}] : [activeTokoId, endpoint, query]
  }

  function buildUrl(endpoint, query, { langsung = false } = {}) {
    const asal = (!langsung && gatewayUrl) || baseUrl
    const url = new URL(asal + API_PREFIX + endpoint)
    if (query && typeof query === 'object') {
      for (const [key, value] of Object.entries(query)) {
        if (value === undefined || value === null || value === '') continue
        url.searchParams.set(key, String(value))
      }
    }
    return url.toString()
  }

  function headerDasar() {
    const h = { Accept: 'application/json', 'X-Tuleh-Version': versiApp() }
    if (platform) h['X-Tuleh-Platform'] = platform
    return h
  }

  function denganToko(query, auth) {
    if (auth && activeTokoId && !(query && Object.prototype.hasOwnProperty.call(query, 'toko_id'))) {
      return { ...(query || {}), toko_id: activeTokoId }
    }
    return query
  }

  /** fetch dengan batas waktu; gateway mati (koneksi ditolak) → lapor & ulang sekali langsung. */
  async function kirimFetch(endpoint, query, init, batasMs) {
    const jalan = async (langsung) => {
      const controller = new AbortController()
      const timer = setTimeout(() => controller.abort(), batasMs)
      try {
        return await fetch(buildUrl(endpoint, query, { langsung }), { ...init, signal: controller.signal })
      } finally {
        clearTimeout(timer)
      }
    }
    const lewatGateway = !!gatewayUrl
    try {
      return await jalan(false)
    } catch (err) {
      if (lewatGateway && sambunganDitolak(err)) {
        // Proses gateway sudah tidak ada: permintaan belum sampai ke mana pun → aman
        // diulang langsung ke server. Pengawas gateway mencoba menyalakannya lagi.
        gatewayUrl = null
        panggil(gatewayGagalHandler, err)
        return jalan(true)
      }
      throw err
    }
  }

  function amplopGangguan({ status, message, errors = null, meta = null, gateway = null, timeout = false }) {
    const r = { ok: false, status, message, errors, meta, gangguan: true }
    if (gateway) r.gateway = gateway
    if (timeout) r.timeout = true
    return r
  }

  /** Gangguan jaringan untuk GET terautentikasi → salinan terakhir bila ada. */
  function sajikanSalinanAtau(method, endpoint, query, auth, gagal) {
    if (auth && koneksi()) {
      const s = method === 'GET' && salinan() && bolehDisalin(endpoint)
        ? salinan().ambil(...kunciSalinanUntuk(endpoint, query))
        : null
      if (s) {
        koneksi().tandaiOffline(s.ditarikPada)
        return { ok: true, status: 200, data: s.data, meta: s.meta, message: '', offline: true, ditarikPada: s.ditarikPada }
      }
      koneksi().tandaiOffline()
    }
    return gagal
  }

  /** Jawaban HTTP diterima → amplop sesuai klasifikasi + efek samping (offline/426/402). */
  async function olahJawaban(method, endpoint, query, auth, response, { simpanSalinan }) {
    const payload = await readJsonSafe(response)
    const jenis = klasifikasi(response.status, response.headers, payload)
    const gw = penandaGateway(response.headers)
    const message = (payload && typeof payload.message === 'string' && payload.message) || statusMessage(response.status)
    const errors = (payload && payload.errors) || null
    const meta = payload && payload.meta !== undefined ? payload.meta : null

    if (jenis === JENIS.GANGGUAN) {
      return sajikanSalinanAtau(method, endpoint, query, auth,
        amplopGangguan({ status: response.status, message, errors, meta, gateway: gw }))
    }
    // Server menjawab (bukan galat buatan gateway) → online.
    if (auth && !gw && koneksi()) koneksi().tandaiOnline()

    if (jenis !== JENIS.SUKSES || !payload) {
      if (jenis === JENIS.UPDATE) panggil(upgradeHandler, message)
      if (jenis === JENIS.LANGGANAN) {
        const info = infoLangganan(payload)
        panggil(langgananHandler, { ...info, pesan: info.pesan || message })
      }
      // `data` ikut pada amplop GAGAL: sebagian penolakan membawa angka yang dibutuhkan layar
      // (mis. data.terkunci_detik pada 429 kunci PIN → hitung mundur di dialog persetujuan).
      const r = { ok: false, status: response.status, data: payload && payload.data !== undefined ? payload.data : null, message, errors, meta }
      if (gw) r.gateway = gw
      return r
    }

    const hasil = {
      ok: true,
      status: response.status,
      data: payload.data !== undefined ? payload.data : null,
      meta: payload.meta !== undefined ? payload.meta : null,
      message: payload.message || ''
    }
    if (simpanSalinan && method === 'GET' && auth && salinan() && bolehDisalin(endpoint)) {
      salinan().simpan(...kunciSalinanUntuk(endpoint, query), hasil)
    }
    return hasil
  }

  /**
   * `pantauKoneksi: false` = permintaan latar (pengurai antrean) yang TIDAK mengubah penanda
   * online/offline aplikasi dan tanpa salinan: satu muatan yang terus ditolak 5xx tidak boleh
   * membuat seluruh aplikasi tampak offline. Pengurai sendiri menandai offline untuk gangguan jaringan.
   */
  async function request(method, endpoint, { query, body, auth = true, pantauKoneksi = true } = {}) {
    query = denganToko(query, auth)
    const efek = auth && pantauKoneksi // koneksi & salinan offline
    const headers = headerDasar()
    if (body !== undefined) headers['Content-Type'] = 'application/json'
    if (auth && token) headers.Authorization = `Bearer ${token}`

    let response
    try {
      if (pura2Offline()) throw new TypeError('smoke offline')
      response = await kirimFetch(endpoint, query, {
        method,
        headers,
        body: body !== undefined ? JSON.stringify(body) : undefined
      }, timeoutMs)
    } catch (err) {
      const timedOut = !!err && err.name === 'AbortError'
      return sajikanSalinanAtau(method, endpoint, query, efek, amplopGangguan({
        status: 0,
        message: timedOut ? 'Server tidak merespons (timeout).' : statusMessage(0),
        timeout: timedOut
      }))
    }
    return olahJawaban(method, endpoint, query, efek, response, { simpanSalinan: true })
  }

  /**
   * Unggah file multipart (field bawaan `logo`). `file` = { bytes, filename, mime, field }.
   * Content-Type TIDAK di-set manual — fetch mengisi boundary multipart otomatis.
   */
  async function upload(endpoint, { query, file, auth = true } = {}) {
    query = denganToko(query, auth)
    if (!file || !file.bytes) return { ok: false, status: 0, message: 'File tidak ada.', errors: null, meta: null }
    const bytes = file.bytes instanceof ArrayBuffer ? new Uint8Array(file.bytes) : file.bytes
    const headers = headerDasar()
    if (auth && token) headers.Authorization = `Bearer ${token}`

    let response
    try {
      // FormData dibuat per percobaan: badan stream tidak bisa dipakai dua kali.
      const form = new FormData()
      form.append(file.field || 'logo', new Blob([bytes], { type: file.mime || 'application/octet-stream' }), file.filename || 'upload.png')
      response = await kirimFetch(endpoint, query, { method: 'POST', headers, body: form }, timeoutMs * 2)
    } catch (err) {
      const timedOut = !!err && err.name === 'AbortError'
      if (auth && koneksi()) koneksi().tandaiOffline()
      return amplopGangguan({ status: 0, message: timedOut ? 'Server tidak merespons (timeout).' : statusMessage(0), timeout: timedOut })
    }
    return olahJawaban('POST', endpoint, query, auth, response, { simpanSalinan: false })
  }

  /**
   * Waktu server (header `Date` dari endpoint publik /app/versi). Dipakai masa coba
   * Mode Demo agar jam perangkat tidak menentukan. SELALU langsung ke server — tidak
   * lewat gateway lokal — supaya cap waktu benar-benar dari server. null bila tak terjangkau.
   */
  async function waktuServer() {
    const controller = new AbortController()
    const timer = setTimeout(() => controller.abort(), WAKTU_SERVER_TIMEOUT_MS)
    try {
      const response = await fetch(buildUrl('/app/versi', { versi: versiApp(), platform }, { langsung: true }), {
        method: 'GET',
        headers: headerDasar(),
        signal: controller.signal
      })
      const date = response.headers && typeof response.headers.get === 'function' ? response.headers.get('date') : null
      const d = date ? new Date(date) : null
      return d && Number.isFinite(d.getTime()) ? d : null
    } catch {
      return null
    } finally {
      clearTimeout(timer)
    }
  }

  return {
    request,
    get: (endpoint, options) => request('GET', endpoint, options),
    post: (endpoint, options) => request('POST', endpoint, options),
    put: (endpoint, options) => request('PUT', endpoint, options),
    hapus: (endpoint, options) => request('DELETE', endpoint, options),
    upload,
    waktuServer,
    buildUrl,
    setBaseUrl(url) { baseUrl = url },
    getBaseUrl() { return baseUrl },
    /** Alirkan permintaan lewat gateway lokal (null = koneksi langsung). */
    setGateway(url) { gatewayUrl = url || null },
    getGateway() { return gatewayUrl },
    setToken(value) { token = typeof value === 'string' && value.length > 0 ? value : null },
    hasToken() { return token !== null },
    /** Toko aktif — disisipkan sebagai ?toko_id pada tiap permintaan terautentikasi. */
    setActiveTokoId(id) { activeTokoId = typeof id === 'string' && id.length > 0 ? id : null },
    getActiveTokoId() { return activeTokoId },
    /** HTTP 426 dari endpoint mana pun → layar update wajib. */
    setUpgradeHandler(fn) { upgradeHandler = typeof fn === 'function' ? fn : null },
    /** HTTP 402 dari endpoint mana pun → layar "Langganan berakhir" ({ pesan, status, perpanjangUrl }). */
    setLanggananHandler(fn) { langgananHandler = typeof fn === 'function' ? fn : null },
    /** Koneksi ke gateway lokal ditolak → pengawas gateway mengembalikan ke koneksi langsung. */
    setGatewayGagalHandler(fn) { gatewayGagalHandler = typeof fn === 'function' ? fn : null }
  }
}

module.exports = { buatKlienHttp, statusMessage, bolehDisalin, sambunganDitolak, API_PREFIX }
