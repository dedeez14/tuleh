'use strict'

// Diagnostik desktop: log berkas berotasi + laporan galat/crash/log ke server (kontrak #1).
//   - mulaiLog()       dipanggil paling awal di main.js (console.* ikut ke main.log)
//   - init({ api })    setelah api-client siap (antrean laporan di userData/offline)
//   - lapor()          galat proses utama/renderer → diantrekan & dikirim (offline-aman)
//   - pratinjauLog()   Pengaturan → "Kirim laporan ke dukungan": tampilkan PERSIS body
//   - kirimLog()       yang akan dikirim, lalu kirim setelah pengguna setuju.

const os = require('node:os')
const path = require('node:path')
const crypto = require('node:crypto')
const { app } = require('electron')
const { buatPencatat, pasangKonsol } = require('./lib/pencatat')
const { bangunLaporan, AntreanDiagnostik, MAKS_STACK } = require('./lib/diagnostik')
const { adalahGangguan } = require('./lib/klasifikasi-http')

const LOG_DIPANTAU = ['main', 'renderer', 'gateway']

let pencatat = null
let antrean = null
let api = null
let konteksTambahan = () => ({})
const pratinjau = new Map() // id → body laporan log yang sudah ditunjukkan ke pengguna

function folderLog() {
  try {
    app.setAppLogsPath()
    return app.getPath('logs')
  } catch {
    return path.join(app.getPath('userData'), 'logs')
  }
}

/** Log berkas + salin console proses utama. Aman dipanggil sebelum app ready. */
function mulaiLog() {
  if (pencatat) return pencatat
  pencatat = buatPencatat({ dir: folderLog() })
  pasangKonsol(pencatat, 'main')
  return pencatat
}

function log(nama, level, ...args) {
  if (pencatat) pencatat.tulis(nama, level, ...args)
}

function konteksDasar(tambahan = {}) {
  let locale = ''
  try { locale = app.getLocale() } catch { /* abaikan */ }
  return {
    os: `${os.type()} ${os.release()}`,
    perangkat: `${os.arch()} · Electron ${process.versions.electron || '-'}`,
    locale,
    ...konteksTambahan(),
    ...tambahan
  }
}

/**
 * @param {object} o
 * @param {object} o.api            api-client (PLATFORM, appVersion, request, hasToken, koneksi via offline)
 * @param {string} o.dir            folder userData
 * @param {() => object} [o.konteks] konteks tambahan tiap laporan (mis. status gateway)
 */
function init({ api: klien, dir, konteks = () => ({}) }) {
  api = klien
  konteksTambahan = konteks
  antrean = new AntreanDiagnostik({ berkas: path.join(dir, 'offline', 'diagnostik.json') })
  return { antrean }
}

// Bearer opsional: token kedaluwarsa tidak boleh menggagalkan laporan → ulang tanpa auth.
async function kirimSatu(body) {
  let r = await api.request('POST', '/diagnostik', { body, auth: api.hasToken() })
  if (!r.ok && r.status === 401) r = await api.request('POST', '/diagnostik', { body, auth: false })
  return r
}

/** Kirim antrean laporan (dipanggil saat kembali online & setelah menambah laporan). */
async function kirimAntrean() {
  if (!antrean || !api) return 0
  try { return await antrean.kirimSemua(kirimSatu) } catch { return 0 }
}

/** Laporkan galat (crash/error). Tidak pernah melempar. */
async function lapor({ jenis = 'error', pesan, stack = '', konteks = {}, terjadiPada = new Date() }) {
  try {
    log('main', jenis === 'crash' ? 'error' : 'warn', `[diagnostik:${jenis}]`, pesan, stack)
    if (!antrean || !api) return false
    const body = bangunLaporan({
      platform: api.PLATFORM, versi: api.appVersion(), jenis, pesan, stack,
      konteks: konteksDasar(konteks), terjadiPada
    })
    if (antrean.tambah(body)) kirimAntrean()
    return true
  } catch {
    return false
  }
}

/** Body laporan log yang AKAN dikirim (sudah disamarkan) — ditunjukkan dulu ke pengguna. */
function pratinjauLog({ catatan = '', layar = '' } = {}) {
  const ekor = pencatat ? pencatat.ekor(LOG_DIPANTAU, MAKS_STACK - 100) : ''
  const body = bangunLaporan({
    platform: api ? api.PLATFORM : 'desktop',
    versi: api ? api.appVersion() : '',
    jenis: 'log',
    pesan: catatan && String(catatan).trim() ? String(catatan).trim() : 'Laporan log dari pengguna (Pengaturan → Kirim laporan ke dukungan).',
    stack: ekor || '(log kosong)',
    konteks: konteksDasar(layar ? { layar: String(layar).slice(0, 80) } : {})
  })
  const id = crypto.randomUUID()
  pratinjau.clear() // hanya pratinjau terakhir yang sah dikirim
  pratinjau.set(id, body)
  return { id, body }
}

/** Kirim laporan log yang sudah dipratinjau. Offline → diantrekan. */
async function kirimLog({ id }) {
  const body = pratinjau.get(id)
  if (!body) return { ok: false, status: 0, message: 'Pratinjau laporan kedaluwarsa. Buka ulang lalu kirim.', errors: null }
  pratinjau.delete(id)
  if (!api) return { ok: false, status: 0, message: 'Aplikasi belum siap.', errors: null }
  const r = await kirimSatu(body)
  if (r.ok) return { ok: true, status: r.status, data: { id: r.data && r.data.id, terkirim: true }, meta: null, message: '' }
  if (adalahGangguan(r)) {
    antrean.tambah(body)
    return { ok: true, status: 202, data: { terkirim: false, tertunda: true }, meta: null, message: 'Server belum terjangkau — laporan dikirim otomatis saat online.' }
  }
  return r
}

module.exports = { mulaiLog, log, init, lapor, kirimAntrean, pratinjauLog, kirimLog, LOG_DIPANTAU }
