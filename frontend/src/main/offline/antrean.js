'use strict'

// Antrean kirim (offline fase 2, padanan Android `core/offline/antrean.dart`):
// permintaan tulis yang gagal karena jaringan disimpan berurutan dan dikirim
// satu per satu saat server terjangkau. Satu berkas JSON di userData berisi
// pesan antrean, transaksi lokal (struk untuk riwayat/cetak ulang), dan delta
// stok yang belum terkirim.

const nodeFs = require('node:fs')
const crypto = require('node:crypto')
const { tulisAtomik, bacaDenganPemulihan } = require('../lib/berkas-atomik')

const STATUS = Object.freeze({ MENUNGGU: 'MENUNGGU', MENGIRIM: 'MENGIRIM', TERKIRIM: 'TERKIRIM', TINJAU: 'TINJAU' })

const LABEL = Object.freeze({
  CHECKOUT: 'Transaksi',
  PENGELUARAN: 'Pengeluaran',
  STOK_MASUK: 'Stok masuk',
  SESI_BUKA: 'Buka sesi'
})

function labelJenis(jenis) { return LABEL[jenis] || jenis }

function buatClientRef() {
  return crypto.randomUUID()
}

/**
 * `waktu_klien` untuk badan permintaan: ISO-8601 **waktu lokal kasir**, detik
 * penuh, tanpa akhiran zona.
 *
 * Bukan `toISOString()`: itu menghasilkan "…T07:25:40.635Z" (UTC + Z), dan
 * server menyimpannya apa adanya ke kolom MySQL `datetime` → error 1292
 * "Incorrect datetime value" sehingga transaksi ditolak. Waktu lokal juga yang
 * dimaksud kolom itu: kapan kasir menekan Bayar menurut jam tokonya.
 */
function waktuKlien(waktu = new Date()) {
  const dua = (n) => String(n).padStart(2, '0')
  return `${waktu.getFullYear()}-${dua(waktu.getMonth() + 1)}-${dua(waktu.getDate())}`
    + `T${dua(waktu.getHours())}:${dua(waktu.getMinutes())}:${dua(waktu.getSeconds())}`
}

/** Bentuk berkas antrean yang sah (objek dengan `pesan` berupa array). */
function bentukAntreanSah(d) {
  return !!d && typeof d === 'object' && !Array.isArray(d) && Array.isArray(d.pesan)
}

class Antrean {
  /**
   * @param {object} o
   * @param {string|null} o.berkas      null = hanya memori (tes)
   * @param {(galat: {jenis: 'simpan'|'muat', pesan: string, detail?: string, berkasRusak?: string[]}) => void} [o.onGalat]
   *        dipanggil saat berkas gagal ditulis / rusak saat dimuat — ipc.js meneruskan ke
   *        status UI dan laporan diagnostik. Penjualan TIDAK boleh hilang diam-diam.
   */
  constructor({ berkas = null, sekarang = () => Date.now(), fsImpl = nodeFs, onGalat = null } = {}) {
    this.berkas = berkas
    this.sekarang = sekarang
    this.fsImpl = fsImpl
    this.onGalat = onGalat
    this.pesan = []        // urut naik
    this.transaksi = {}    // clientRef → { tokoId, nomorLokal, struk, waktuKlien, ... }
    this.delta = []        // { clientRef, idProduk, delta }
    this._urut = 0
    this.galatSimpan = null    // { pesan, detail, pada } — penulisan terakhir gagal (data hanya di memori)
    this.peringatanMuat = null // { pesan, berkasRusak, pada } — berkas rusak saat aplikasi dibuka
    this._muat()
  }

  _lapor(galat) {
    if (this.onGalat) { try { this.onGalat(galat) } catch { /* abaikan */ } }
  }

  _muat() {
    if (!this.berkas) return
    const hasil = bacaDenganPemulihan(this.berkas, bentukAntreanSah, {
      fsImpl: this.fsImpl,
      sekarang: () => new Date(this.sekarang()),
      nama: 'Berkas antrean offline'
    })
    if (hasil.data) {
      const d = hasil.data
      this.pesan = d.pesan
      this.transaksi = d.transaksi && typeof d.transaksi === 'object' ? d.transaksi : {}
      this.delta = Array.isArray(d.delta) ? d.delta : []
      this._urut = this.pesan.reduce((m, p) => Math.max(m, p.urut || 0), 0)
      // Proses mati saat MENGIRIM → kembalikan ke MENUNGGU agar dicoba lagi.
      for (const p of this.pesan) if (p.status === STATUS.MENGIRIM) p.status = STATUS.MENUNGGU
    }
    if (hasil.peringatan) {
      this.peringatanMuat = { pesan: hasil.peringatan, berkasRusak: hasil.berkasRusak, pada: this.sekarang() }
      this._lapor({ jenis: 'muat', pesan: hasil.peringatan, berkasRusak: hasil.berkasRusak })
    }
  }

  /**
   * Tulis antrean ke disk (atomik + generasi .bak). Mengembalikan true bila tersimpan.
   * Gagal → `galatSimpan` diisi & dilaporkan; data tetap di memori dan penulisan
   * berikutnya mencoba lagi.
   */
  simpan() {
    if (!this.berkas) return true
    try {
      tulisAtomik(this.berkas, JSON.stringify({ pesan: this.pesan, transaksi: this.transaksi, delta: this.delta }), { fsImpl: this.fsImpl })
      if (this.galatSimpan) this.galatSimpan = null
      return true
    } catch (err) {
      const pertama = !this.galatSimpan
      this.galatSimpan = {
        pesan: 'Antrean offline gagal disimpan ke komputer ini. Jangan tutup aplikasi sampai data terkirim atau masalah disk diatasi.',
        detail: err && err.message ? String(err.message) : String(err),
        pada: this.sekarang()
      }
      if (pertama) this._lapor({ jenis: 'simpan', pesan: this.galatSimpan.pesan, detail: this.galatSimpan.detail })
      return false
    }
  }

  /** Tandai peringatan muat sudah dilihat pengguna. */
  abaikanPeringatanMuat() { this.peringatanMuat = null }

  /** Antrekan pesan (+ transaksi lokal & delta stok) dalam satu penulisan. */
  antrekan({ clientRef, jenis, tokoId = null, path: jalur, body, status = STATUS.MENUNGGU, galat = null }, { transaksi = null, deltaStok = {} } = {}) {
    const p = {
      urut: ++this._urut,
      clientRef,
      jenis,
      tokoId,
      path: jalur,
      body,
      dibuat: this.sekarang(),
      status,
      percobaan: 0,
      cobaLagiSetelah: null,
      galat,
      hasil: null
    }
    this.pesan.push(p)
    if (transaksi) this.transaksi[clientRef] = { ...transaksi, clientRef }
    for (const [idProduk, d] of Object.entries(deltaStok)) {
      if (Number(d)) this.delta.push({ clientRef, idProduk, delta: Number(d) })
    }
    this.simpan()
    return p
  }

  semua() { return this.pesan.slice().sort((a, b) => a.urut - b.urut) }
  aktif() { return this.semua().filter((p) => p.status !== STATUS.TERKIRIM) }
  cari(clientRef) { return this.pesan.find((p) => p.clientRef === clientRef) || null }

  perbarui(clientRef, patch) {
    const p = this.cari(clientRef)
    if (!p) return null
    Object.assign(p, patch)
    this.simpan()
    return p
  }

  /** Terkirim: simpan hasil, buang transaksi lokal & delta stoknya. */
  selesai(clientRef, hasil) {
    const p = this.cari(clientRef)
    if (!p) return
    p.status = STATUS.TERKIRIM
    p.hasil = hasil || null
    p.cobaLagiSetelah = null
    p.galat = null
    delete this.transaksi[clientRef]
    this.delta = this.delta.filter((d) => d.clientRef !== clientRef)
    // Riwayat terkirim dipangkas agar berkas tak membengkak.
    const terkirim = this.pesan.filter((x) => x.status === STATUS.TERKIRIM)
    if (terkirim.length > 100) {
      const buang = new Set(terkirim.slice(0, terkirim.length - 100).map((x) => x.clientRef))
      this.pesan = this.pesan.filter((x) => !buang.has(x.clientRef))
    }
    this.simpan()
  }

  /** Batalkan (pengguna): buang pesan, transaksi lokal, delta stok. */
  batalkan(clientRef) {
    this.pesan = this.pesan.filter((p) => p.clientRef !== clientRef)
    delete this.transaksi[clientRef]
    this.delta = this.delta.filter((d) => d.clientRef !== clientRef)
    this.simpan()
  }

  ringkas(tokoId = null) {
    const cocok = (p) => tokoId == null || p.tokoId == null || p.tokoId === tokoId
    let menunggu = 0; let tinjau = 0
    for (const p of this.pesan) {
      if (!cocok(p)) continue
      if (p.status === STATUS.MENUNGGU || p.status === STATUS.MENGIRIM) menunggu++
      else if (p.status === STATUS.TINJAU) tinjau++
    }
    return { menunggu, tinjau, total: menunggu + tinjau }
  }

  /**
   * Jumlah baris yang masih menunggu setelah ≥ `ambang` galat server beruntun (muatan
   * yang terus ditolak 5xx) — panel Sinkronisasi menampilkan peringatan menetap.
   */
  macet(tokoId = null, ambang = Infinity) {
    const cocok = (p) => tokoId == null || p.tokoId == null || p.tokoId === tokoId
    return this.pesan.filter((p) => cocok(p) && (p.status === STATUS.MENUNGGU || p.status === STATUS.MENGIRIM) && (p.galatServer || 0) >= ambang).length
  }

  /** Masalah penyimpanan untuk pita status UI (null = sehat). */
  masalahPenyimpanan() {
    if (this.galatSimpan) return { jenis: 'simpan', pesan: this.galatSimpan.pesan, pada: this.galatSimpan.pada }
    if (this.peringatanMuat) return { jenis: 'muat', pesan: this.peringatanMuat.pesan, pada: this.peringatanMuat.pada, berkasRusak: this.peringatanMuat.berkasRusak }
    return null
  }

  transaksiTertunda(tokoId = null) {
    return Object.values(this.transaksi)
      .filter((t) => tokoId == null || t.tokoId == null || t.tokoId === tokoId)
      .sort((a, b) => String(b.waktuKlien).localeCompare(String(a.waktuKlien)))
  }

  transaksiLokal(clientRef) { return this.transaksi[clientRef] || null }

  deltaStokTertunda(tokoId = null) {
    const out = {}
    for (const d of this.delta) {
      const t = this.transaksi[d.clientRef]
      if (tokoId != null && t && t.tokoId && t.tokoId !== tokoId) continue
      out[d.idProduk] = (out[d.idProduk] || 0) + d.delta
    }
    return out
  }
}

/**
 * Rapikan `waktu_klien` pada badan yang sudah tersimpan di antrean sebelum
 * dikirim. Baris yang diantrekan versi lama membawa "…Z" (UTC) yang ditolak
 * MySQL; tanpa ini transaksi lama akan terus gagal walau aplikasi sudah baru.
 */
function badanWaktuRapi(body) {
  const nilai = body && body.waktu_klien
  if (typeof nilai !== 'string' || !nilai) return body
  const t = new Date(nilai)
  if (Number.isNaN(t.getTime())) return body
  const rapi = waktuKlien(t)
  return rapi === nilai ? body : { ...body, waktu_klien: rapi }
}

module.exports = { Antrean, STATUS, labelJenis, buatClientRef, waktuKlien, badanWaktuRapi, bentukAntreanSah }
