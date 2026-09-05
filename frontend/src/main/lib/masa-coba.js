'use strict'

// Masa coba Mode Demo — 7 hari sejak pertama kali demo dibuka di perangkat
// ini, dihitung dengan WAKTU SERVER, bukan jam perangkat.
//
// Prinsip:
//  - Mulai masa coba hanya bisa dengan waktu server (header `Date` dari
//    /app/versi). Tanpa koneksi saat pertama kali → demo belum bisa dibuka.
//  - Saat memeriksa, pakai waktu server bila terjangkau. Bila tidak, pakai
//    yang TERBESAR di antara jam perangkat dan waktu server yang terakhir
//    terlihat — memundurkan jam tidak pernah memperpanjang masa coba.
//  - Catatan disimpan dengan tanda HMAC (kunci = konstanta build + identitas
//    mesin). Catatan yang diubah tangan dianggap RUSAK = berakhir.
//  - Menghapus catatan sepenuhnya memang mengulang masa coba; menutup itu
//    butuh pendaftaran perangkat di server MOVERA (di luar repo ini).
//
// Modul ini murni (tanpa I/O) — dipakai main process dan diuji node:test.
// Padanan Android: mobile-flutter/lib/features/demo/domain/masa_coba.dart.

const crypto = require('node:crypto')

const HARI_MS = 24 * 60 * 60 * 1000
const DURASI_HARI = 7
const KUNCI_DASAR = 'tuleh-masa-coba-v1'

function keWaktu(v) {
  if (v instanceof Date) return Number.isFinite(v.getTime()) ? v : null
  if (typeof v === 'number') return Number.isFinite(v) ? new Date(v) : null
  if (typeof v === 'string' && v) {
    const d = new Date(v)
    return Number.isFinite(d.getTime()) ? d : null
  }
  return null
}

/**
 * Waktu "sekarang" yang dipercaya.
 * @param {{waktuServer?: any, serverTerakhir?: any, perangkat: any}} p
 */
function tentukanKini({ waktuServer, serverTerakhir, perangkat }) {
  const s = keWaktu(waktuServer)
  if (s) return { kini: s, sumber: 'server' }
  const p = keWaktu(perangkat) || new Date(0)
  const t = keWaktu(serverTerakhir)
  if (t && t.getTime() > p.getTime()) return { kini: t, sumber: 'server_terakhir' }
  return { kini: p, sumber: 'perangkat' }
}

/** Status masa coba: sisa hari (bulat ke atas, min 0) & sudah berakhir. */
function status(mulai, kini, { durasiHari = DURASI_HARI } = {}) {
  const m = keWaktu(mulai)
  const k = keWaktu(kini)
  if (!m || !k) return { berakhir: true, sisaHari: 0, berakhirPada: null, rusak: true }
  const berakhirPada = new Date(m.getTime() + durasiHari * HARI_MS)
  const sisaMs = berakhirPada.getTime() - k.getTime()
  return {
    berakhir: sisaMs <= 0,
    sisaHari: Math.max(0, Math.ceil(sisaMs / HARI_MS)),
    berakhirPada,
    rusak: false
  }
}

function tanda(mulai, serverTerakhir, identitas) {
  return crypto
    .createHmac('sha256', `${KUNCI_DASAR}|${identitas || ''}`)
    .update(`${mulai}|${serverTerakhir}`)
    .digest('hex')
}

/** Catatan tersimpan: { mulai, serverTerakhir, tanda } — semua ISO string. */
function buatCatatan({ mulai, serverTerakhir, identitas }) {
  const m = keWaktu(mulai).toISOString()
  const t = keWaktu(serverTerakhir || mulai).toISOString()
  return { mulai: m, serverTerakhir: t, tanda: tanda(m, t, identitas) }
}

function catatanSah(catatan, identitas) {
  if (!catatan || typeof catatan !== 'object') return false
  const { mulai, serverTerakhir, tanda: t } = catatan
  if (typeof mulai !== 'string' || typeof serverTerakhir !== 'string' || typeof t !== 'string') return false
  const harap = tanda(mulai, serverTerakhir, identitas)
  return t.length === harap.length && crypto.timingSafeEqual(Buffer.from(t), Buffer.from(harap))
}

/**
 * Periksa masa coba (tanpa I/O): terima catatan tersimpan + waktu, kembalikan
 * keputusan & catatan baru untuk disimpan.
 *
 * Kode: 'BUTUH_KONEKSI' (belum pernah mulai & server tak terjangkau),
 * 'RUSAK' (catatan diubah), 'BERAKHIR', 'AKTIF'.
 */
function periksa({ catatan, waktuServer, perangkat, identitas, mulaiBaru = false }) {
  const server = keWaktu(waktuServer)
  if (!catatan) {
    if (!mulaiBaru) return { kode: 'AKTIF', sisaHari: DURASI_HARI, belumMulai: true, catatan: null }
    if (!server) return { kode: 'BUTUH_KONEKSI', sisaHari: DURASI_HARI, catatan: null }
    const baru = buatCatatan({ mulai: server, serverTerakhir: server, identitas })
    return { kode: 'AKTIF', sisaHari: DURASI_HARI, berakhirPada: status(baru.mulai, server).berakhirPada, catatan: baru }
  }
  if (!catatanSah(catatan, identitas)) return { kode: 'RUSAK', sisaHari: 0, catatan }

  const { kini, sumber } = tentukanKini({ waktuServer: server, serverTerakhir: catatan.serverTerakhir, perangkat })
  const st = status(catatan.mulai, kini)
  // Simpan waktu server terbaru bila ada (menjaga "jam mundur" tetap gagal).
  const simpan = server && server.getTime() > new Date(catatan.serverTerakhir).getTime()
    ? buatCatatan({ mulai: catatan.mulai, serverTerakhir: server, identitas })
    : catatan
  return {
    kode: st.berakhir ? 'BERAKHIR' : 'AKTIF',
    sisaHari: st.sisaHari,
    berakhirPada: st.berakhirPada,
    sumberWaktu: sumber,
    kiniMs: kini.getTime(),
    catatan: simpan
  }
}

/**
 * Gabungkan hasil lapis 1 (lokal) dengan jawaban server (lapis 2/3,
 * `data` dari /demo/perangkat), tanpa I/O.
 *
 * Aturan: server menentukan "sekarang" (waktu_server); `mulai` paling awal
 * menang; siapa pun yang menyatakan berakhir/diblokir menang; server yang
 * minta identitas mengubah kode menjadi BUTUH_IDENTITAS (aplikasi menjalankan
 * OTP lalu memanggil ulang). `server` null/undefined → hasil lokal apa adanya.
 */
function gabungkan(lokal, server, { identitas } = {}) {
  if (!server || typeof server !== 'object') return lokal
  const waktu = keWaktu(server.waktu_server)
  const st = String(server.status || '').toUpperCase()
  if (st === 'DIBLOKIR') return { ...lokal, kode: 'DIBLOKIR', sisaHari: 0, sumberStatus: 'server' }
  if (server.butuh_identitas === true || st === 'BELUM_VERIFIKASI') {
    return { ...lokal, kode: 'BUTUH_IDENTITAS', sumberStatus: 'server' }
  }
  const mulaiServer = keWaktu(server.mulai)
  const mulaiLokal = lokal.catatan ? keWaktu(lokal.catatan.mulai) : null
  let mulai = mulaiServer
  if (mulaiLokal && (!mulai || mulaiLokal.getTime() < mulai.getTime())) mulai = mulaiLokal
  if (!mulai) return lokal // server belum punya mulai dan lokal belum mulai

  const kini = waktu || new Date(lokal.kiniMs || Date.now())
  const hasil = status(mulai, kini)
  const berakhir = st === 'BERAKHIR' || hasil.berakhir || lokal.kode === 'BERAKHIR' || lokal.kode === 'RUSAK'
  // Catatan lokal ikut diperbarui: mulai paling awal + waktu server terbaru.
  const catatan = buatCatatan({
    mulai,
    serverTerakhir: waktu || (lokal.catatan && lokal.catatan.serverTerakhir) || mulai,
    identitas
  })
  return {
    ...lokal,
    kode: berakhir ? 'BERAKHIR' : 'AKTIF',
    sisaHari: berakhir ? 0 : hasil.sisaHari,
    berakhirPada: hasil.berakhirPada,
    sumberStatus: 'server',
    catatan
  }
}

/** Dari beberapa salinan catatan (registry, ProgramData, settings), pilih yang sah dengan `mulai` paling awal. */
function pilihCatatan(salinan, identitas) {
  let terbaik = null
  for (const c of Array.isArray(salinan) ? salinan : []) {
    if (!catatanSah(c, identitas)) continue
    if (!terbaik || new Date(c.mulai).getTime() < new Date(terbaik.mulai).getTime()) terbaik = c
  }
  return terbaik
}

module.exports = { DURASI_HARI, HARI_MS, tentukanKini, status, buatCatatan, catatanSah, periksa, gabungkan, pilihCatatan }
