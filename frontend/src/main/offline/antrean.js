'use strict'

// Antrean kirim (offline fase 2 + Fase 4 batch v2, padanan Android `core/offline/antrean.dart`):
// permintaan tulis yang gagal karena jaringan disimpan berurutan dan dikirim saat server
// terjangkau. Satu berkas JSON di userData berisi identitas perangkat (id + nomor urut perangkat
// yang tak pernah mundur), pesan antrean, transaksi lokal (struk untuk riwayat/cetak ulang), dan
// delta stok yang belum terkirim.
//
// Berkas v2: { versi: 2, perangkat: { id, seqTerakhir, syncBatchVersi }, pesan[], transaksi{}, delta[] }.
// Berkas lama (tanpa `perangkat`) tetap sah: id dibuat baru dan deviceSeq baris lama = urut.

const nodeFs = require('node:fs')
const crypto = require('node:crypto')
const { tulisAtomik, bacaDenganPemulihan } = require('../lib/berkas-atomik')

const STATUS = Object.freeze({ MENUNGGU: 'MENUNGGU', MENGIRIM: 'MENGIRIM', TERKIRIM: 'TERKIRIM', TINJAU: 'TINJAU' })

const LABEL = Object.freeze({
  CHECKOUT: 'Transaksi',
  PENGELUARAN: 'Pengeluaran',
  STOK_MASUK: 'Stok masuk',
  SESI_BUKA: 'Buka sesi',
  REFUND: 'Refund',
  BATAL: 'Pembatalan',
  BILL_BAYAR: 'Bayar bon',
  ORDER_TRANSISI: 'Pesanan'
})

// Riwayat TERKIRIM yang disimpan (panel "Terkirim terakhir"). Baris yang masih dirujuk turunan aktif
// (refund/pembatalan atas transaksi lokal) tidak ikut dipangkas: pengurai per baris butuh id servernya.
const MAKS_TERKIRIM = 100

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

/**
 * `waktu_klien` BER-ZONA untuk operasi batch v2: "2026-09-24T10:15:02+08:00". Server mengonversi offset
 * ke zona aplikasi (WaktuKlien::normalisasi) sehingga toko WITA/WIT tidak bergeser satu–dua jam saat
 * server memilih sesi dari waktu ini. Jalur per baris lama tetap memakai waktuKlien() tanpa zona.
 */
function waktuKlienZona(waktu = new Date()) {
  if (waktu === null) return null // new Date(null) = 1970 — waktu kosong bukan "awal zaman"
  const d = waktu instanceof Date ? waktu : new Date(waktu)
  if (Number.isNaN(d.getTime())) return null
  const menit = -d.getTimezoneOffset()
  const abs = Math.abs(menit)
  const dua = (n) => String(n).padStart(2, '0')
  return `${waktuKlien(d)}${menit >= 0 ? '+' : '-'}${dua(Math.floor(abs / 60))}:${dua(abs % 60)}`
}

/** Kunci pemilik baris: "<email huruf kecil>@<host server>"; null bila salah satunya tak diketahui. */
function kunciPemilik(email, baseUrl) {
  const e = typeof email === 'string' ? email.trim().toLowerCase() : ''
  if (!e) return null
  let host = ''
  try { host = new URL(String(baseUrl || '')).host } catch { host = '' }
  return host ? `${e}@${host}` : null
}

/** Rujukan transaksi lokal pada jalur baris ("/transaksi/lokal:<ref>/refund", ter-encode atau tidak) → <ref>. */
function refIndukLokal(jalur) {
  const seg = String(jalur || '').split('/')
  if (seg[1] !== 'transaksi' || !seg[2]) return null
  let id
  try { id = decodeURIComponent(seg[2]) } catch { return null }
  return id.startsWith('lokal:') && id.length > 6 ? id.slice(6) : null
}

/** Bentuk berkas antrean yang sah (objek dengan `pesan` berupa array). */
function bentukAntreanSah(d) {
  return !!d && typeof d === 'object' && !Array.isArray(d) && Array.isArray(d.pesan)
}

const statusAktif = (p) => p.status === STATUS.MENUNGGU || p.status === STATUS.MENGIRIM || p.status === STATUS.TINJAU

class Antrean {
  /**
   * @param {object} o
   * @param {string|null} o.berkas      null = hanya memori (tes)
   * @param {() => string} [o.buatId]   pembuat id perangkat (bawaan UUID v4 acak)
   * @param {(galat: {jenis: 'simpan'|'muat', pesan: string, detail?: string, berkasRusak?: string[]}) => void} [o.onGalat]
   *        dipanggil saat berkas gagal ditulis / rusak saat dimuat — ipc.js meneruskan ke
   *        status UI dan laporan diagnostik. Penjualan TIDAK boleh hilang diam-diam.
   */
  constructor({ berkas = null, sekarang = () => Date.now(), fsImpl = nodeFs, onGalat = null, buatId = () => crypto.randomUUID() } = {}) {
    this.berkas = berkas
    this.sekarang = sekarang
    this.fsImpl = fsImpl
    this.onGalat = onGalat
    this.pesan = []        // urut naik
    this.transaksi = {}    // clientRef → { tokoId, nomorLokal, struk, waktuKlien, ... }
    this.delta = []        // { clientRef, idProduk, delta }
    this._urut = 0
    this._perangkat = null // { id, seqTerakhir, syncBatchVersi }
    this.galatSimpan = null    // { pesan, detail, pada } — penulisan terakhir gagal (data hanya di memori)
    this.peringatanMuat = null // { pesan, berkasRusak, pada } — berkas rusak saat aplikasi dibuka
    this._muat()
    if (!this._perangkat) {
      this._perangkat = {
        id: String(buatId()),
        seqTerakhir: this.pesan.reduce((m, p) => Math.max(m, p.deviceSeq || 0), 0),
        syncBatchVersi: 0
      }
    }
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
      for (const p of this.pesan) {
        // Proses mati saat MENGIRIM → kembalikan ke MENUNGGU agar dicoba lagi.
        if (p.status === STATUS.MENGIRIM) p.status = STATUS.MENUNGGU
        // Baris berkas lama tanpa nomor urut perangkat: pakai urut agar tetap diproses server SEBELUM
        // baris baru (op tanpa device_seq disortir ke akhir grup perangkatnya).
        if (!Number.isInteger(p.deviceSeq)) p.deviceSeq = Number(p.urut) || 0
      }
      const pr = d.perangkat && typeof d.perangkat === 'object' ? d.perangkat : null
      if (pr && typeof pr.id === 'string' && pr.id) {
        const maksSeq = this.pesan.reduce((m, p) => Math.max(m, p.deviceSeq || 0), 0)
        this._perangkat = {
          id: pr.id,
          seqTerakhir: Math.max(Math.floor(Number(pr.seqTerakhir) || 0), maksSeq),
          syncBatchVersi: Math.floor(Number(pr.syncBatchVersi) || 0)
        }
      }
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
      tulisAtomik(this.berkas, JSON.stringify({ versi: 2, perangkat: this._perangkat, pesan: this.pesan, transaksi: this.transaksi, delta: this.delta }), { fsImpl: this.fsImpl })
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

  /** Identitas perangkat untuk operasi batch (salinan). */
  perangkat() { return { ...this._perangkat } }

  /** Simpan versi sinkron batch terakhir dari /config agar start dingin langsung memakai mode yang benar. */
  aturPerangkat({ syncBatchVersi } = {}) {
    const v = Math.floor(Number(syncBatchVersi) || 0)
    if (v !== this._perangkat.syncBatchVersi) {
      this._perangkat.syncBatchVersi = v
      this.simpan()
    }
    return this.perangkat()
  }

  /**
   * Antrekan pesan (+ transaksi lokal & delta stok) dalam satu penulisan. clientRef selalu unik: bila sudah
   * ada, baris itu dikembalikan apa adanya (tanpa baris, transaksi, delta, atau nomor urut perangkat baru).
   */
  antrekan({ clientRef, jenis, tokoId = null, path: jalur, body, status = STATUS.MENUNGGU, galat = null, pemilik = null }, { transaksi = null, deltaStok = {} } = {}) {
    const ada = this.cari(clientRef)
    if (ada) return ada
    const p = {
      urut: ++this._urut,
      // Nomor urut perangkat untuk server (device_seq): disimpan bersama barisnya dan tak pernah turun.
      deviceSeq: ++this._perangkat.seqTerakhir,
      clientRef,
      jenis,
      tokoId,
      pemilik,
      path: jalur,
      body,
      dibuat: this.sekarang(),
      status,
      percobaan: 0,
      cobaLagiSetelah: null,
      galat,
      kode: null,
      kirimUlangKe: 0,
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

  /** Perbarui banyak baris dalam SATU tulis ke disk (segmen batch). Mengembalikan jumlah baris yang ada. */
  perbaruiBanyak(daftar) {
    let n = 0
    for (const { clientRef, patch } of daftar || []) {
      const p = this.cari(clientRef)
      if (!p) continue
      Object.assign(p, patch)
      n++
    }
    if (n > 0) this.simpan()
    return n
  }

  /** Baris lama tanpa pemilik (sebelum Fase 4) diklaim akun pertama yang dikenali. */
  klaimTanpaPemilik(pemilik) {
    if (!pemilik) return 0
    let n = 0
    for (const p of this.pesan) {
      if (!p.pemilik) { p.pemilik = pemilik; n++ }
    }
    if (n > 0) this.simpan()
    return n
  }

  /** Terkirim: simpan hasil (+ nomor lokal), buang transaksi lokal & delta stoknya. */
  selesai(clientRef, hasil) {
    const p = this.cari(clientRef)
    if (!p) return
    const t = this.transaksi[clientRef]
    p.status = STATUS.TERKIRIM
    // Nomor lokal (L-…) ikut hasil: panel Sinkronisasi menampilkan "L-… → nomor server".
    p.hasil = hasil && typeof hasil === 'object' && t && t.nomorLokal && !hasil.nomorLokal
      ? { ...hasil, nomorLokal: t.nomorLokal }
      : (hasil || null)
    p.terkirimPada = this.sekarang()
    p.cobaLagiSetelah = null
    p.galat = null
    p.kode = null
    delete this.transaksi[clientRef]
    this.delta = this.delta.filter((d) => d.clientRef !== clientRef)
    this._pangkas()
    this.simpan()
  }

  /** Riwayat terkirim dipangkas agar berkas tak membengkak — kecuali induk yang masih dirujuk. */
  _pangkas() {
    const dirujuk = new Set()
    for (const x of this.pesan) {
      if (x.status === STATUS.TERKIRIM) continue
      const ref = refIndukLokal(x.path)
      if (ref) dirujuk.add(ref)
    }
    const terkirim = this.pesan.filter((x) => x.status === STATUS.TERKIRIM && !dirujuk.has(x.clientRef))
    if (terkirim.length > MAKS_TERKIRIM) {
      const buang = new Set(terkirim.slice(0, terkirim.length - MAKS_TERKIRIM).map((x) => x.clientRef))
      this.pesan = this.pesan.filter((x) => !buang.has(x.clientRef))
    }
  }

  /**
   * Batalkan (pengguna): buang pesan, transaksi lokal, delta stok — berantai ke turunannya
   * (refund/pembatalan atas transaksi lokal tak bermakna tanpa induknya). Mengembalikan jumlah baris dibuang.
   */
  batalkan(clientRef) {
    const buang = new Set([clientRef])
    // Induk yang sudah TERKIRIM punya nomor server — turunannya tetap bisa diselesaikan, jadi tidak ikut dibuang.
    const terkirim = new Set(this.pesan.filter((p) => p.status === STATUS.TERKIRIM).map((p) => p.clientRef))
    let bertambah = true
    while (bertambah) {
      bertambah = false
      for (const p of this.pesan) {
        const induk = refIndukLokal(p.path)
        if (induk && buang.has(induk) && !terkirim.has(induk) && !buang.has(p.clientRef)) { buang.add(p.clientRef); bertambah = true }
      }
    }
    const sebelum = this.pesan.length
    this.pesan = this.pesan.filter((p) => !buang.has(p.clientRef))
    for (const ref of buang) delete this.transaksi[ref]
    this.delta = this.delta.filter((d) => !buang.has(d.clientRef))
    this.simpan()
    return sebelum - this.pesan.length
  }

  /**
   * Ringkasan per toko. `pemilik` diberikan → baris akun lain dihitung terpisah (`milikLain`) dan tidak
   * masuk menunggu/tinjau; tanpa `pemilik` → semua baris (penjaga ganti server & keluar akun).
   */
  ringkas(tokoId = null, pemilik = undefined) {
    const cocok = (p) => tokoId == null || p.tokoId == null || p.tokoId === tokoId
    let menunggu = 0; let tinjau = 0; let milikLain = 0
    for (const p of this.pesan) {
      if (!cocok(p) || !statusAktif(p)) continue
      if (pemilik != null && p.pemilik !== pemilik) { milikLain++; continue }
      if (p.status === STATUS.TINJAU) tinjau++
      else menunggu++
    }
    const r = { menunggu, tinjau, total: menunggu + tinjau }
    if (pemilik != null) r.milikLain = milikLain
    return r
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

  /** Struk lokal yang belum terkirim; `pemilik` diberikan → hanya milik akun itu (Riwayat). */
  transaksiTertunda(tokoId = null, pemilik = undefined) {
    return Object.values(this.transaksi)
      .filter((t) => tokoId == null || t.tokoId == null || t.tokoId === tokoId)
      .filter((t) => {
        if (pemilik == null) return true
        const p = this.cari(t.clientRef)
        return !!p && p.pemilik === pemilik
      })
      .sort((a, b) => String(b.waktuKlien).localeCompare(String(a.waktuKlien)))
  }

  transaksiLokal(clientRef) { return this.transaksi[clientRef] || null }

  /** Baris terkirim sejak `sejak` (ms) yang tercatat server dengan peringatan SELISIH_STOK (pita status). */
  selisihTerkini(sejak, pemilik = undefined) {
    return this.pesan.filter((p) => p.status === STATUS.TERKIRIM &&
      (Number(p.terkirimPada) || 0) >= sejak &&
      (pemilik == null || p.pemilik === pemilik) &&
      p.hasil && Array.isArray(p.hasil.peringatan) && p.hasil.peringatan.includes('SELISIH_STOK')).length
  }

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

module.exports = {
  Antrean,
  STATUS,
  LABEL,
  MAKS_TERKIRIM,
  labelJenis,
  buatClientRef,
  waktuKlien,
  waktuKlienZona,
  kunciPemilik,
  refIndukLokal,
  badanWaktuRapi,
  bentukAntreanSah
}
