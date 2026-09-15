'use strict'

// Laporan galat/crash/log ke POST /diagnostik (kontrak #1). Pure Node — dipakai
// main/diagnostik.js (desktop) dan teruji tanpa Electron.
//
// Body: { platform, versi, jenis: crash|error|log, pesan (≤2000), stack (≤20000),
//         konteks: object (≤10 KB), terjadi_pada: ISO-8601, client_ref }
// Server menjawab 202; client_ref menyingkirkan duplikat. Saat offline laporan disimpan
// di antrean kecil TERPISAH dari antrean penjualan (galat tidak boleh menahan transaksi).

const crypto = require('node:crypto')
const nodeFs = require('node:fs')
const { samarkan, samarkanObjek } = require('./samarkan')
const { tulisAtomik, bacaDenganPemulihan } = require('./berkas-atomik')
const { adalahGangguan } = require('./klasifikasi-http')

const JENIS_SAH = ['crash', 'error', 'log']
const MAKS_PESAN = 2000
const MAKS_STACK = 20000
const MAKS_KONTEKS_BYTE = 10 * 1024
const MAKS_ANTREAN = 50

function potong(teks, maks) {
  const s = String(teks == null ? '' : teks)
  return s.length > maks ? s.slice(0, maks - 1) + '…' : s
}

/** Konteks disamarkan & dipangkas ke ≤10 KB (buang kunci terbesar dulu). */
function rapikanKonteks(konteks) {
  let k = samarkanObjek(konteks && typeof konteks === 'object' && !Array.isArray(konteks) ? konteks : {})
  const ukuran = (o) => Buffer.byteLength(JSON.stringify(o))
  while (ukuran(k) > MAKS_KONTEKS_BYTE && Object.keys(k).length > 0) {
    const terbesar = Object.keys(k).sort((a, b) => ukuran({ [b]: k[b] }) - ukuran({ [a]: k[a] }))[0]
    k = { ...k, [terbesar]: '[dipangkas: terlalu besar]' }
    if (ukuran(k) > MAKS_KONTEKS_BYTE) { const { [terbesar]: _buang, ...sisa } = k; k = sisa }
  }
  return k
}

/**
 * client_ref: galat yang sama (jenis+pesan+stack+versi) pada hari yang sama = satu laporan
 * (galat berulang dalam perulangan tidak membanjiri server). Laporan log manual = acak.
 */
function refLaporan({ jenis, pesan, stack, versi }, tanggal = new Date()) {
  if (jenis === 'log') return crypto.randomUUID()
  const hari = tanggal.toISOString().slice(0, 10)
  return crypto.createHash('sha256').update([jenis, pesan, stack, versi, hari].join('|')).digest('hex').slice(0, 40)
}

/** Bentuk body laporan yang sah & aman dikirim. */
function bangunLaporan({ platform, versi, jenis, pesan, stack = '', konteks = {}, terjadiPada = new Date(), clientRef = null }) {
  const j = JENIS_SAH.includes(jenis) ? jenis : 'error'
  const p = potong(samarkan(pesan || '(tanpa pesan)'), MAKS_PESAN)
  const st = potong(samarkan(stack || ''), MAKS_STACK)
  const t = terjadiPada instanceof Date && Number.isFinite(terjadiPada.getTime()) ? terjadiPada : new Date()
  return {
    platform,
    versi: String(versi || ''),
    jenis: j,
    pesan: p,
    stack: st,
    konteks: rapikanKonteks(konteks),
    terjadi_pada: t.toISOString(),
    client_ref: clientRef || refLaporan({ jenis: j, pesan: p, stack: st, versi }, t)
  }
}

function antreanSah(d) {
  return !!d && typeof d === 'object' && Array.isArray(d.laporan)
}

/** Antrean laporan diagnostik (terpisah, kecil, dedupe client_ref). */
class AntreanDiagnostik {
  constructor({ berkas = null, fsImpl = nodeFs, maks = MAKS_ANTREAN } = {}) {
    this.berkas = berkas
    this.fsImpl = fsImpl
    this.maks = maks
    this.laporan = []
    this._mengirim = false
    if (berkas) {
      const h = bacaDenganPemulihan(berkas, antreanSah, { fsImpl, nama: 'Antrean laporan diagnostik' })
      if (h.data) this.laporan = h.data.laporan.filter((l) => l && l.client_ref)
    }
  }

  _simpan() {
    if (!this.berkas) return
    try { tulisAtomik(this.berkas, JSON.stringify({ laporan: this.laporan }), { fsImpl: this.fsImpl }) } catch { /* laporan diagnostik boleh hilang; penjualan tidak */ }
  }

  /** Tambah laporan (abaikan duplikat client_ref). Mengembalikan true bila baru. */
  tambah(laporan) {
    if (!laporan || !laporan.client_ref) return false
    if (this.laporan.some((l) => l.client_ref === laporan.client_ref)) return false
    this.laporan.push(laporan)
    if (this.laporan.length > this.maks) this.laporan = this.laporan.slice(this.laporan.length - this.maks)
    this._simpan()
    return true
  }

  get jumlah() { return this.laporan.length }

  /**
   * Kirim semua laporan berurutan. `kirim(body)` → amplop api-client.
   * Gangguan jaringan → berhenti (dicoba lagi nanti); 2xx atau penolakan permanen (4xx) →
   * dibuang dari antrean (laporan rusak tidak dicoba selamanya).
   */
  async kirimSemua(kirim) {
    if (this._mengirim) return 0
    this._mengirim = true
    let terkirim = 0
    try {
      while (this.laporan.length > 0) {
        const l = this.laporan[0]
        let r
        try { r = await kirim(l) } catch (err) { r = { ok: false, status: 0, gangguan: true, message: String(err && err.message) } }
        if (!r.ok && (adalahGangguan(r) || r.status === 426)) break
        this.laporan.shift()
        if (r.ok) terkirim++
        this._simpan()
      }
    } finally {
      this._mengirim = false
    }
    return terkirim
  }
}

module.exports = { bangunLaporan, refLaporan, rapikanKonteks, AntreanDiagnostik, MAKS_PESAN, MAKS_STACK, MAKS_KONTEKS_BYTE, JENIS_SAH }
