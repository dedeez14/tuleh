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
  constructor({ antrean, kirim, koneksi = null, setelahBerubah = null, pemulih = null, sekarang = () => Date.now(), jadwal = setTimeout, batalJadwal = clearTimeout }) {
    this.antrean = antrean
    this.kirim = kirim
    this.koneksi = koneksi
    // Pemulih baris TINJAU "mungkin sudah sampai" (lihat pemulih.js); null = tanpa.
    this.pemulih = pemulih
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
      let gagalJaringan = false
      for (const p of this.antrean.semua().filter((x) => x.status === STATUS.MENUNGGU)) {
        if (p.cobaLagiSetelah && p.cobaLagiSetelah > kini) break // FIFO ketat
        const hasil = await this._kirim(p)
        if (hasil === 'terkirim') sukses++
        if (hasil === 'berhenti') { gagalJaringan = true; break }
      }
      // Baris "mungkin sudah sampai": pastikan ke server, lalu yang ternyata
      // belum tercatat dikirim ulang di putaran ini juga.
      if (!gagalJaringan && this.pemulih) {
        let dipulihkan = 0
        try { dipulihkan = await this.pemulih.jalankan() } catch { dipulihkan = 0 }
        if (dipulihkan > 0) {
          this._ubah()
          for (const p of this.antrean.semua().filter((x) => x.status === STATUS.MENUNGGU)) {
            if (p.cobaLagiSetelah && p.cobaLagiSetelah > this.sekarang()) break
            const hasil = await this._kirim(p)
            if (hasil === 'terkirim') sukses++
            if (hasil === 'berhenti') break
          }
        }
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
      // meta.idempoten = jawaban lama diulang; baris ini sudah tercatat pada
      // percobaan sebelumnya, bukan transaksi baru.
      const data = res.data || null
      if (data && res.meta && res.meta.idempoten === true) data._idempoten = true
      this.antrean.selesai(p.clientRef, data)
      if (this.koneksi) this.koneksi.tandaiOnline()
      this._ubah()
      return 'terkirim'
    }
    // status -1 (timeout setelah kirim) & 0 (belum tersambung) sama-sama
    // dicoba ulang: sejak server MOVERA mengenal `client_ref` (9 Sep 2026),
    // kiriman ulang dengan ref yang sama tidak membuat baris kedua — ia
    // membalas 200 dengan data yang sama. Dulu -1 dilempar ke TINJAU karena
    // mengulang berisiko menggandakan penjualan.
    if (res.status === 0 || res.status === -1) {
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
