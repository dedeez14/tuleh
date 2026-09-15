'use strict'

// Mode offline desktop — simpul yang menyatukan salinan baca, antrean kirim,
// pengurai, nomor lokal, dan status koneksi; dipakai api-client (salinan) dan
// ipc.js (antrean, status ke renderer). Padanan Android fase 1–2.

const path = require('node:path')
const { SalinanBaca } = require('./salinan')
const { Antrean, STATUS, buatClientRef, labelJenis, waktuKlien } = require('./antrean')
const { Pengurai, kebijakanDariConfig, AMBANG_PERINGATAN_PERCOBAAN } = require('./pengurai')
const { Pemulih } = require('./pemulih')
const { NomorLokal, buatStrukLokal } = require('./struk-lokal')

class Koneksi {
  constructor() {
    this.online = true
    this.ditarikPada = null // waktu salinan yang sedang disajikan (ms)
    this._pendengar = new Set()
  }

  langgan(fn) { this._pendengar.add(fn); return () => this._pendengar.delete(fn) }
  _siar() { for (const fn of this._pendengar) { try { fn() } catch { /* abaikan */ } } }

  tandaiOffline(ditarikPada = null) {
    const berubah = this.online || (ditarikPada && ditarikPada !== this.ditarikPada)
    this.online = false
    if (ditarikPada) this.ditarikPada = ditarikPada
    if (berubah) this._siar()
  }

  tandaiOnline() {
    if (!this.online) {
      this.online = true
      this.ditarikPada = null
      this._siar()
    }
  }
}

let salinan = null
let antrean = null
let pengurai = null
let nomorLokal = null
const koneksi = new Koneksi()
// Batas tinjau otomatis dari GET /config (antrean_maks_percobaan_galat_server, antrean_maks_umur_jam);
// diperbarui setiap /config termuat (termasuk dari salinan offline). Belum ada = tanpa tinjau otomatis.
let kebijakanAntrean = { maksPercobaanGalatServer: null, maksUmurJam: null }

/** Terapkan kebijakan antrean dari data /config. */
function aturKebijakanAntrean(config) {
  kebijakanAntrean = kebijakanDariConfig(config)
  return kebijakanAntrean
}

/**
 * Inisialisasi dengan folder userData (dipanggil main/ipc saat start).
 * `onGalatAntrean` menerima galat penyimpanan antrean (tulis gagal / berkas rusak).
 */
function init({ dir, kirim, ambilDaftar = null, onGalatAntrean = null, siapKirim = () => true }) {
  salinan = new SalinanBaca({ berkas: path.join(dir, 'offline', 'salinan.json') })
  antrean = new Antrean({
    berkas: path.join(dir, 'offline', 'antrean.json'),
    onGalat: (galat) => {
      koneksi._siar() // pita status menampilkan peringatan penyimpanan
      if (onGalatAntrean) { try { onGalatAntrean(galat) } catch { /* abaikan */ } }
    }
  })
  nomorLokal = new NomorLokal({ berkas: path.join(dir, 'offline', 'nomor-lokal.json') })
  pengurai = new Pengurai({
    antrean,
    kirim,
    koneksi,
    pemulih: ambilDaftar ? new Pemulih({ antrean, ambilDaftar }) : null,
    kebijakan: () => kebijakanAntrean,
    siapKirim,
    setelahBerubah: () => koneksi._siar()
  })
  return { salinan, antrean, pengurai, nomorLokal, koneksi }
}

/** Ringkasan untuk pita status renderer. */
function status(tokoId = null) {
  const r = antrean ? antrean.ringkas(tokoId) : { menunggu: 0, tinjau: 0, total: 0 }
  // penyimpanan: null = sehat; { jenis: 'simpan'|'muat', pesan } = antrean tak tersimpan / pernah rusak.
  const penyimpanan = antrean ? antrean.masalahPenyimpanan() : null
  // macet: baris yang terus ditolak 5xx (≥ AMBANG_PERINGATAN_PERCOBAAN) dan masih menunggu;
  // tinjauOtomatis: server mengirim batas → baris seperti itu akan pindah ke "perlu ditinjau".
  const macet = antrean ? antrean.macet(tokoId, AMBANG_PERINGATAN_PERCOBAAN) : 0
  const tinjauOtomatis = kebijakanAntrean.maksPercobaanGalatServer !== null || kebijakanAntrean.maksUmurJam !== null
  return { online: koneksi.online, ditarikPada: koneksi.ditarikPada, ...r, penyimpanan, macet, tinjauOtomatis }
}

module.exports = {
  init,
  status,
  aturKebijakanAntrean,
  get kebijakanAntrean() { return kebijakanAntrean },
  koneksi,
  Koneksi,
  STATUS,
  buatClientRef,
  waktuKlien,
  labelJenis,
  buatStrukLokal,
  get salinan() { return salinan },
  get antrean() { return antrean },
  get pengurai() { return pengurai },
  get nomorLokal() { return nomorLokal }
}
