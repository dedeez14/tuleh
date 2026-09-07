'use strict'

// Antrean kirim (offline fase 2, padanan Android `core/offline/antrean.dart`):
// permintaan tulis yang gagal karena jaringan disimpan berurutan dan dikirim
// satu per satu saat server terjangkau. Satu berkas JSON di userData berisi
// pesan antrean, transaksi lokal (struk untuk riwayat/cetak ulang), dan delta
// stok yang belum terkirim.

const fs = require('node:fs')
const path = require('node:path')
const crypto = require('node:crypto')

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

class Antrean {
  constructor({ berkas = null, sekarang = () => Date.now() } = {}) {
    this.berkas = berkas
    this.sekarang = sekarang
    this.pesan = []        // urut naik
    this.transaksi = {}    // clientRef → { tokoId, nomorLokal, struk, waktuKlien, ... }
    this.delta = []        // { clientRef, idProduk, delta }
    this._urut = 0
    this._muat()
  }

  _muat() {
    if (!this.berkas) return
    try {
      const d = JSON.parse(fs.readFileSync(this.berkas, 'utf8'))
      this.pesan = Array.isArray(d.pesan) ? d.pesan : []
      this.transaksi = d.transaksi && typeof d.transaksi === 'object' ? d.transaksi : {}
      this.delta = Array.isArray(d.delta) ? d.delta : []
      this._urut = this.pesan.reduce((m, p) => Math.max(m, p.urut || 0), 0)
      // Proses mati saat MENGIRIM → kembalikan ke MENUNGGU agar dicoba lagi.
      for (const p of this.pesan) if (p.status === STATUS.MENGIRIM) p.status = STATUS.MENUNGGU
    } catch { /* kosong */ }
  }

  simpan() {
    if (!this.berkas) return
    try {
      fs.mkdirSync(path.dirname(this.berkas), { recursive: true })
      const tmp = `${this.berkas}.tmp`
      fs.writeFileSync(tmp, JSON.stringify({ pesan: this.pesan, transaksi: this.transaksi, delta: this.delta }))
      fs.renameSync(tmp, this.berkas)
    } catch { /* tetap di memori */ }
  }

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

module.exports = { Antrean, STATUS, labelJenis, buatClientRef }
