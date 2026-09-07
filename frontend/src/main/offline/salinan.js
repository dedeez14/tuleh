'use strict'

// Salinan baca (offline fase 1, padanan Android): setiap jawaban GET yang
// berhasil disimpan per toko + jalur + query, lalu disajikan saat server tak
// terjangkau. Disimpan ke satu berkas JSON di userData (tulis ditunda 400 ms)
// dengan batas jumlah entri (yang paling lama dibaca dibuang dulu).

const fs = require('node:fs')
const path = require('node:path')

const MAKS_ENTRI = 600
const JEDA_TULIS_MS = 400

function kunciSalinan(tokoId, endpoint, query) {
  const q = query && typeof query === 'object'
    ? Object.keys(query)
      .filter((k) => query[k] !== undefined && query[k] !== null && query[k] !== '')
      .sort()
      .map((k) => `${k}=${query[k]}`)
      .join('&')
    : ''
  return `${tokoId || '-'}|${endpoint}|${q}`
}

class SalinanBaca {
  constructor({ berkas = null, maksEntri = MAKS_ENTRI, sekarang = () => Date.now() } = {}) {
    this.berkas = berkas
    this.maksEntri = maksEntri
    this.sekarang = sekarang
    this.peta = new Map() // kunci → { data, meta, ditarikPada, dibaca }
    this._timer = null
    this._muat()
  }

  _muat() {
    if (!this.berkas) return
    try {
      const raw = fs.readFileSync(this.berkas, 'utf8')
      const arr = JSON.parse(raw)
      if (Array.isArray(arr)) {
        for (const e of arr) if (e && e.kunci) this.peta.set(e.kunci, e)
      }
    } catch { /* belum ada / rusak → mulai kosong */ }
  }

  _jadwalkanTulis() {
    if (!this.berkas) return
    clearTimeout(this._timer)
    this._timer = setTimeout(() => this.simpanSekarang(), JEDA_TULIS_MS)
    if (this._timer.unref) this._timer.unref()
  }

  simpanSekarang() {
    if (!this.berkas) return
    try {
      fs.mkdirSync(path.dirname(this.berkas), { recursive: true })
      const tmp = `${this.berkas}.tmp`
      fs.writeFileSync(tmp, JSON.stringify([...this.peta.values()]))
      fs.renameSync(tmp, this.berkas)
    } catch { /* gagal simpan: salinan tetap di memori */ }
  }

  simpan(tokoId, endpoint, query, { data, meta }) {
    const kunci = kunciSalinan(tokoId, endpoint, query)
    const kini = this.sekarang()
    this.peta.delete(kunci)
    this.peta.set(kunci, { kunci, data, meta: meta ?? null, ditarikPada: kini, dibaca: kini })
    while (this.peta.size > this.maksEntri) {
      // Map menjaga urutan sisip: yang paling depan = paling lama tak disentuh.
      const tertua = this.peta.keys().next().value
      this.peta.delete(tertua)
    }
    this._jadwalkanTulis()
  }

  ambil(tokoId, endpoint, query) {
    const kunci = kunciSalinan(tokoId, endpoint, query)
    const e = this.peta.get(kunci)
    if (!e) return null
    // Sentuh: pindahkan ke belakang agar tak dibuang duluan.
    this.peta.delete(kunci)
    e.dibaca = this.sekarang()
    this.peta.set(kunci, e)
    return e
  }

  get jumlah() { return this.peta.size }

  hapusSemua() {
    this.peta.clear()
    this._jadwalkanTulis()
  }
}

module.exports = { SalinanBaca, kunciSalinan, MAKS_ENTRI }
