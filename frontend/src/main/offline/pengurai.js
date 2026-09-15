'use strict'

// Pengurai antrean (padanan Android `pengurai.dart`): kirim pesan MENUNGGU yang SIAP
// sesuai urutan dibuat. Tanpa head-of-line blocking: satu baris yang terus ditolak
// server (5xx pada muatan tertentu) mendapat mundur SENDIRI (`cobaLagiSetelah`) dan
// pengurai lanjut ke baris lain yang siap — urutan FIFO hanya di antara baris yang siap.
// Aman karena checkout/pengeluaran/stok masuk idempoten lewat `client_ref`.
//
// `kirim(path, body, pesan)` disuntik (pesan.tokoId = toko saat dibuat): mengembalikan envelope api-client
// { ok, status, data, message, errors, gangguan?, gateway?, timeout? } — status 0 = tidak sampai
// ke server, status -1 = timeout (mungkin sudah sampai). Keputusan per jawaban:
//
//   sukses                          → TERKIRIM
//   JARINGAN (0 / gateway tak terjangkau / 429) → jeda GLOBAL (semua menunggu, urutan utuh);
//                                     dilewati begitu koneksi pulih
//   SERVER (5xx/408 dari server)    → mundur per baris, lanjut; setelah batas dari server
//                                     (GET /config: antrean_maks_percobaan_galat_server,
//                                     antrean_maks_umur_jam) → TINJAU dengan pesan server terakhir.
//                                     Batas tak dikirim server → tetap menunggu + peringatan UI.
//   TIMEOUT (-1)                    → mundur per baris, lanjut (tidak dihitung galat server)
//   402 langganan / 426 update      → jeda global, baris TETAP menunggu (tidak ditinjau)
//   401 sesi berakhir               → berhenti; putaran berikutnya menunggu token (siapKirim)
//   4xx lain                        → TINJAU

const { STATUS, badanWaktuRapi } = require('./antrean')
const { jenisGangguan } = require('../lib/klasifikasi-http')

const JEDA_MUNDUR_MS = [5000, 15000, 45000, 120000, 600000]

// Mekanika UI (bukan kebijakan bisnis): setelah sekian galat server beruntun pada satu baris,
// panel Sinkronisasi menampilkan peringatan menetap walau server tidak mengirim batas tinjau.
const AMBANG_PERINGATAN_PERCOBAAN = 10

// Penyebab tunda baris (disimpan di `sebabTunda`).
const SEBAB = Object.freeze({ JARINGAN: 'JARINGAN', SERVER: 'SERVER', TIMEOUT: 'TIMEOUT', LANGGANAN: 'LANGGANAN', UPDATE: 'UPDATE' })

function mundur(percobaan) {
  return JEDA_MUNDUR_MS[Math.min(Math.max(percobaan, 1), JEDA_MUNDUR_MS.length) - 1]
}

const PESAN_TIMEOUT_SETELAH_KIRIM =
  'Server tidak menjawab setelah data dikirim. Periksa di Riwayat apakah sudah tercatat sebelum mengirim ulang.'

function angkaPositif(v) {
  if (v === null || v === undefined || v === '' || typeof v === 'boolean') return null
  const n = Number(v)
  return Number.isFinite(n) && n > 0 ? n : null
}

/**
 * Kebijakan tinjau otomatis dari data GET /config (field aditif server). Tidak ada / tidak
 * sah → null (tanpa tinjau otomatis; jangan mengarang batas).
 */
function kebijakanDariConfig(config) {
  const c = config && typeof config === 'object' ? config : {}
  const maksPercobaan = angkaPositif(c.antrean_maks_percobaan_galat_server)
  return {
    maksPercobaanGalatServer: maksPercobaan === null ? null : Math.floor(maksPercobaan),
    maksUmurJam: angkaPositif(c.antrean_maks_umur_jam)
  }
}

const milikSendiri = (p) => p.sebabTunda === SEBAB.SERVER || p.sebabTunda === SEBAB.TIMEOUT

/** Baris per-muatan (SERVER/TIMEOUT) memakai mundurnya sendiri; penyebab lain mengikuti jeda global. */
function siapPerBaris(p, kini) {
  if (p.status !== STATUS.MENUNGGU) return false
  return !milikSendiri(p) || !p.cobaLagiSetelah || p.cobaLagiSetelah <= kini
}

class Pengurai {
  /**
   * @param {object} o
   * @param {() => {maksPercobaanGalatServer: number|null, maksUmurJam: number|null}|null} [o.kebijakan]
   * @param {() => boolean} [o.siapKirim]  false = jangan kirim (mis. belum ada token setelah 401)
   */
  constructor({ antrean, kirim, koneksi = null, setelahBerubah = null, pemulih = null, kebijakan = () => null, siapKirim = () => true, sekarang = () => Date.now(), jadwal = setTimeout, batalJadwal = clearTimeout }) {
    this.antrean = antrean
    this.kirim = kirim
    this.koneksi = koneksi
    // Pemulih baris TINJAU "mungkin sudah sampai" (lihat pemulih.js); null = tanpa.
    this.pemulih = pemulih
    this.kebijakan = kebijakan
    this.siapKirim = siapKirim
    this.setelahBerubah = setelahBerubah
    this.sekarang = sekarang
    this._jadwalFn = jadwal
    this._batalJadwal = batalJadwal
    this._timer = null
    this._berjalan = false
    this._janji = null
    this._jeda = null // jeda global { sampai, sebab, percobaan }
  }

  _ubah() { if (this.setelahBerubah) { try { this.setelahBerubah() } catch { /* abaikan */ } } }

  _kebijakan() {
    let k = null
    try { k = this.kebijakan() } catch { k = null }
    return { maksPercobaanGalatServer: (k && k.maksPercobaanGalatServer) || null, maksUmurJam: (k && k.maksUmurJam) || null }
  }

  /** Jeda global masih berlaku? Jeda jaringan gugur begitu koneksi terbukti pulih. */
  _jedaAktif(kini) {
    if (!this._jeda || this._jeda.sampai <= kini) return false
    if (this._jeda.sebab === SEBAB.JARINGAN && this.koneksi && this.koneksi.online === true) return false
    return true
  }

  _pasangJeda(sebab) {
    const percobaan = this._jeda && this._jeda.sebab === sebab ? this._jeda.percobaan + 1 : 1
    const panjang = sebab === SEBAB.UPDATE ? JEDA_MUNDUR_MS[JEDA_MUNDUR_MS.length - 1] : mundur(percobaan)
    this._jeda = { sebab, percobaan, sampai: this.sekarang() + panjang }
    return this._jeda
  }

  /** Status untuk diagnosis/UI. */
  status() {
    return { jeda: this._jeda ? { ...this._jeda } : null }
  }

  async _putaran() {
    let sukses = 0
    const kini = this.sekarang()
    for (const p of this.antrean.semua()) {
      if (this._jedaAktif(this.sekarang())) break
      if (!siapPerBaris(p, kini)) continue
      const hasil = await this._kirim(p)
      if (hasil === 'terkirim') sukses++
      if (hasil === 'berhenti') return { sukses, berhenti: true }
    }
    return { sukses, berhenti: false }
  }

  /**
   * Kirim semua yang siap. Aman dipanggil berulang: selagi satu putaran berjalan, pemanggil
   * lain menunggu putaran itu (mis. "Sinkron sekarang" bersamaan dengan pemicu kembali-online).
   * Mengembalikan jumlah terkirim.
   */
  jalankan() {
    if (this._janji) return this._janji
    this._janji = this._jalankan().finally(() => { this._janji = null })
    return this._janji
  }

  async _jalankan() {
    this._berjalan = true
    let sukses = 0
    try {
      if (!this._jedaAktif(this.sekarang()) && this.siapKirim()) {
        const putaran = await this._putaran()
        sukses += putaran.sukses
        // Baris "mungkin sudah sampai": pastikan ke server, lalu yang ternyata
        // belum tercatat dikirim ulang di putaran ini juga.
        if (!putaran.berhenti && this.pemulih) {
          let dipulihkan = 0
          try { dipulihkan = await this.pemulih.jalankan() } catch { dipulihkan = 0 }
          if (dipulihkan > 0) {
            this._ubah()
            sukses += (await this._putaran()).sukses
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
      res = await this.kirim(p.path, badanWaktuRapi(p.body), p)
    } catch (err) {
      res = { ok: false, status: 0, gangguan: true, message: err && err.message ? err.message : 'gagal' }
    }
    if (res.ok) {
      // meta.idempoten = jawaban lama diulang; baris ini sudah tercatat pada
      // percobaan sebelumnya, bukan transaksi baru.
      const data = res.data || null
      if (data && res.meta && res.meta.idempoten === true) data._idempoten = true
      this.antrean.selesai(p.clientRef, data)
      this._jeda = null
      if (this.koneksi) this.koneksi.tandaiOnline()
      this._ubah()
      return 'terkirim'
    }

    const percobaan = (p.percobaan || 0) + 1
    const gangguan = jenisGangguan(res)

    // Server/gateway tak terjangkau: semua baris akan gagal sama → jeda global, urutan utuh.
    if (gangguan === 'JARINGAN') {
      const jeda = this._pasangJeda(SEBAB.JARINGAN)
      this.antrean.perbarui(p.clientRef, {
        status: STATUS.MENUNGGU, percobaan, cobaLagiSetelah: jeda.sampai, sebabTunda: SEBAB.JARINGAN,
        galat: res.status === 429 ? 'Server membatasi permintaan; dicoba lagi otomatis.' : 'Tidak dapat terhubung ke server.'
      })
      if (this.koneksi) this.koneksi.tandaiOffline()
      this._ubah()
      return 'berhenti'
    }

    // Tidak ada jawaban dalam batas waktu: mundur untuk baris ini saja (server menolak duplikat
    // lewat client_ref bila ternyata sudah tercatat), lanjut ke baris lain.
    if (gangguan === 'TIMEOUT') {
      this.antrean.perbarui(p.clientRef, {
        status: STATUS.MENUNGGU, percobaan, cobaLagiSetelah: this.sekarang() + mundur(percobaan), sebabTunda: SEBAB.TIMEOUT,
        galat: 'Server tidak menjawab tepat waktu; dicoba lagi otomatis.'
      })
      this._ubah()
      return 'lanjut'
    }

    // Server menjawab 5xx/408 untuk muatan INI: mundur per baris, lanjut ke baris lain.
    if (gangguan === 'SERVER') {
      const galatServer = (p.galatServer || 0) + 1
      const pesan = pesanServer(res)
      const k = this._kebijakan()
      const umurJam = (this.sekarang() - (Number(p.dibuat) || this.sekarang())) / 3600000
      const lewatPercobaan = k.maksPercobaanGalatServer !== null && galatServer >= k.maksPercobaanGalatServer
      const lewatUmur = k.maksUmurJam !== null && umurJam >= k.maksUmurJam
      if (lewatPercobaan || lewatUmur) {
        this.antrean.perbarui(p.clientRef, {
          status: STATUS.TINJAU, percobaan, galatServer, cobaLagiSetelah: null, sebabTunda: null,
          galat: `${pesan} (gagal ${galatServer}× di server${lewatUmur && !lewatPercobaan ? `, tertunda lebih dari ${k.maksUmurJam} jam` : ''}; perlu ditinjau)`
        })
      } else {
        this.antrean.perbarui(p.clientRef, {
          status: STATUS.MENUNGGU, percobaan, galatServer, cobaLagiSetelah: this.sekarang() + mundur(galatServer), sebabTunda: SEBAB.SERVER,
          galat: `${pesan} (HTTP ${res.status}; dicoba lagi otomatis)`
        })
      }
      this._ubah()
      return 'lanjut'
    }

    // Langganan diblokir: penjualan tetap sah & tidak dibuang. Semua penulisan akan 402 →
    // jeda global; terkirim otomatis setelah langganan diperpanjang.
    if (res.status === 402) {
      const jeda = this._pasangJeda(SEBAB.LANGGANAN)
      this.antrean.perbarui(p.clientRef, {
        status: STATUS.MENUNGGU, percobaan, cobaLagiSetelah: jeda.sampai, sebabTunda: SEBAB.LANGGANAN,
        galat: res.message ? String(res.message) : pesanServer(res)
      })
      this._ubah()
      return 'berhenti'
    }
    // Aplikasi wajib diperbarui: tunggu pembaruan (jeda panjang, tidak memukul server tiap detik).
    if (res.status === 426) {
      const jeda = this._pasangJeda(SEBAB.UPDATE)
      this.antrean.perbarui(p.clientRef, { status: STATUS.MENUNGGU, cobaLagiSetelah: jeda.sampai, sebabTunda: SEBAB.UPDATE, galat: res.message ? String(res.message) : null })
      this._ubah()
      return 'berhenti'
    }
    // Sesi berakhir: tunggu masuk ulang (siapKirim → token ada lagi).
    if (res.status === 401) {
      this.antrean.perbarui(p.clientRef, { status: STATUS.MENUNGGU })
      this._ubah()
      return 'berhenti'
    }
    // Ditolak server (400/403/404/409/422) → tinjau.
    this.antrean.perbarui(p.clientRef, { status: STATUS.TINJAU, galat: pesanServer(res), sebabTunda: null })
    this._ubah()
    return 'lanjut'
  }

  _jadwalkanUlang() {
    if (this._timer) { this._batalJadwal(this._timer); this._timer = null }
    const kini = this.sekarang()
    const jedaAktif = this._jedaAktif(kini)
    let terdekat = null
    for (const p of this.antrean.semua()) {
      if (p.status !== STATUS.MENUNGGU) continue
      let t = milikSendiri(p) && p.cobaLagiSetelah ? p.cobaLagiSetelah : kini
      if (jedaAktif) t = Math.max(t, this._jeda.sampai)
      if (terdekat === null || t < terdekat) terdekat = t
    }
    if (terdekat === null) return
    // Belum boleh kirim (mis. menunggu masuk ulang) → periksa lagi dengan jeda wajar.
    const minimal = this.siapKirim() ? 1000 : JEDA_MUNDUR_MS[0]
    const jeda = Math.max(minimal, terdekat - kini)
    this._timer = this._jadwalFn(() => { this._timer = null; this.jalankan() }, jeda)
    if (this._timer && this._timer.unref) this._timer.unref()
  }

  /** Kirim ulang manual satu baris (reset hitungan & jeda). */
  async kirimUlang(clientRef) {
    this.antrean.perbarui(clientRef, { status: STATUS.MENUNGGU, percobaan: 0, galatServer: 0, cobaLagiSetelah: null, sebabTunda: null })
    this._jeda = null
    this._ubah()
    return this.jalankan()
  }

  /** Sinkron manual / setelah masuk ulang: abaikan jeda global lalu kirim yang siap. */
  async sinkronSekarang() {
    this._jeda = null
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

module.exports = { Pengurai, mundur, kebijakanDariConfig, JEDA_MUNDUR_MS, AMBANG_PERINGATAN_PERCOBAAN, SEBAB, PESAN_TIMEOUT_SETELAH_KIRIM }
