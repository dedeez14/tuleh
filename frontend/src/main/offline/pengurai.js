'use strict'

// Pengurai antrean (padanan Android `pengurai.dart`): kirim pesan MENUNGGU
// satu per satu sesuai urutan (FIFO ketat), mundur eksponensial saat jaringan
// gagal, TINJAU saat server menolak atau timeout SETELAH data terkirim.
//
// `kirim(path, body, pesan)` disuntik (pesan.tokoId = toko saat dibuat): mengembalikan envelope api-client
// { ok, status, data, message, errors } — status 0 = tidak sampai ke server,
// status -1 = timeout (mungkin sudah sampai).

const { STATUS } = require('./antrean')

const JEDA_MUNDUR_MS = [5000, 15000, 45000, 120000, 600000]

function mundur(percobaan) {
  return JEDA_MUNDUR_MS[Math.min(Math.max(percobaan, 1), JEDA_MUNDUR_MS.length) - 1]
}

const PESAN_TIMEOUT_SETELAH_KIRIM =
  'Server tidak menjawab setelah data dikirim. Periksa di Riwayat apakah sudah tercatat sebelum mengirim ulang.'

class Pengurai {
  constructor({ antrean, kirim, koneksi = null, setelahBerubah = null, sekarang = () => Date.now(), jadwal = setTimeout, batalJadwal = clearTimeout }) {
    this.antrean = antrean
    this.kirim = kirim
    this.koneksi = koneksi
    this.setelahBerubah = setelahBerubah
    this.sekarang = sekarang
    this._jadwalFn = jadwal
    this._batalJadwal = batalJadwal
    this._timer = null
    this._berjalan = false
  }

  _ubah() { if (this.setelahBerubah) { try { this.setelahBerubah() } catch { /* abaikan */ } } }

  /** Kirim semua yang siap. Aman dipanggil berulang. Mengembalikan jumlah terkirim. */
  async jalankan() {
    if (this._berjalan) return 0
    this._berjalan = true
    let sukses = 0
    try {
      const kini = this.sekarang()
      const menunggu = this.antrean.semua().filter((p) => p.status === STATUS.MENUNGGU)
      for (const p of menunggu) {
        if (p.cobaLagiSetelah && p.cobaLagiSetelah > kini) break // FIFO ketat
        const hasil = await this._kirim(p)
        if (hasil === 'terkirim') sukses++
        if (hasil === 'berhenti') break
      }
      this._jadwalkanUlang()
    } finally {
      this._berjalan = false
    }
    return sukses
  }

  async _kirim(p) {
    this.antrean.perbarui(p.clientRef, { status: STATUS.MENGIRIM })
    let res
    try {
      res = await this.kirim(p.path, p.body, p)
    } catch (err) {
      res = { ok: false, status: 0, message: err && err.message ? err.message : 'gagal' }
    }
    if (res.ok) {
      this.antrean.selesai(p.clientRef, res.data || null)
      if (this.koneksi) this.koneksi.tandaiOnline()
      this._ubah()
      return 'terkirim'
    }
    if (res.status === -1) {
      // Timeout setelah dikirim: mengulang bisa menggandakan → tinjau manusia.
      this.antrean.perbarui(p.clientRef, { status: STATUS.TINJAU, galat: PESAN_TIMEOUT_SETELAH_KIRIM })
      this._ubah()
      return 'lanjut'
    }
    if (res.status === 0) {
      const percobaan = (p.percobaan || 0) + 1
      this.antrean.perbarui(p.clientRef, {
        status: STATUS.MENUNGGU,
        percobaan,
        cobaLagiSetelah: this.sekarang() + mundur(percobaan),
        galat: 'Tidak dapat terhubung ke server.'
      })
      if (this.koneksi) this.koneksi.tandaiOffline()
      this._ubah()
      return 'berhenti'
    }
    if (res.status === 401) {
      this.antrean.perbarui(p.clientRef, { status: STATUS.MENUNGGU })
      this._ubah()
      return 'berhenti'
    }
    // Ditolak server (409/422/5xx) → tinjau.
    this.antrean.perbarui(p.clientRef, { status: STATUS.TINJAU, galat: pesanServer(res) })
    this._ubah()
    return 'lanjut'
  }

  _jadwalkanUlang() {
    if (this._timer) { this._batalJadwal(this._timer); this._timer = null }
    let terdekat = null
    for (const p of this.antrean.semua()) {
      if (p.status !== STATUS.MENUNGGU) continue
      const t = p.cobaLagiSetelah || this.sekarang()
      if (terdekat === null || t < terdekat) terdekat = t
    }
    if (terdekat === null) return
    const jeda = Math.max(1000, terdekat - this.sekarang())
    this._timer = this._jadwalFn(() => { this._timer = null; this.jalankan() }, jeda)
    if (this._timer && this._timer.unref) this._timer.unref()
  }

  async kirimUlang(clientRef) {
    this.antrean.perbarui(clientRef, { status: STATUS.MENUNGGU, percobaan: 0, cobaLagiSetelah: null })
    this._ubah()
    return this.jalankan()
  }

  hentikan() {
    if (this._timer) { this._batalJadwal(this._timer); this._timer = null }
  }
}

function pesanServer(res) {
  if (res.errors && typeof res.errors === 'object') {
    const k = Object.keys(res.errors)[0]
    const v = k ? res.errors[k] : null
    if (Array.isArray(v) && v.length) return String(v[0])
  }
  if (res.message) return String(res.message)
  return `Ditolak server (HTTP ${res.status}).`
}

module.exports = { Pengurai, mundur, JEDA_MUNDUR_MS, PESAN_TIMEOUT_SETELAH_KIRIM }
