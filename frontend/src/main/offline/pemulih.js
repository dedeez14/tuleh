'use strict'

// Pemulihan otomatis baris CHECKOUT berstatus TINJAU karena timeout SETELAH
// data terkirim ("mungkin sudah sampai") — padanan Android pemulih_tinjau.dart.
// Dicocokkan ke daftar transaksi server pada hari itu: tepat satu cocok →
// TERKIRIM dengan nomor resmi; tidak ada → aman dikirim ulang (MENUNGGU);
// ganda → tetap TINJAU dengan petunjuk nomor kandidatnya.

const { STATUS } = require('./antrean')
const { PESAN_TIMEOUT_SETELAH_KIRIM } = require('./pengurai')

const JENDELA_MS = 15 * 60 * 1000

function tgl(d) {
  const x = new Date(d)
  return `${x.getFullYear()}-${String(x.getMonth() + 1).padStart(2, '0')}-${String(x.getDate()).padStart(2, '0')}`
}

function layakDipulihkan(p) {
  return p.status === STATUS.TINJAU && p.jenis === 'CHECKOUT' && String(p.galat || '').includes('setelah data dikirim')
}

function baris(m) {
  const raw = m.tanggal || m.created_at
  const t = raw ? Date.parse(raw) : NaN
  return {
    id: String(m.id ?? ''),
    nomor: String(m.nomor ?? m.no ?? '-'),
    total: Number(m.grand_total ?? m.total) || 0,
    metode: String(m.tipe_pembayaran ?? m.metode_bayar ?? '').toUpperCase(),
    dibatalkan: String(m.status || '').toUpperCase().includes('BATAL'),
    waktu: Number.isFinite(t) ? t : null
  }
}

class Pemulih {
  /**
   * @param {object} o
   * @param {import('./antrean').Antrean} o.antrean
   * @param {(tokoId: string|null, dari: string, sampai: string) => Promise<Array<object>|null>} o.ambilDaftar
   */
  constructor({ antrean, ambilDaftar, jendelaMs = JENDELA_MS }) {
    this.antrean = antrean
    this.ambilDaftar = ambilDaftar
    this.jendelaMs = jendelaMs
  }

  totalLokal(p) {
    const t = this.antrean.transaksiLokal(p.clientRef)
    if (t && t.struk && Number.isFinite(Number(t.struk.grand_total))) return Number(t.struk.grand_total)
    let total = 0
    for (const it of (p.body && p.body.items) || []) {
      total += (Number(it.harga) || 0) * (Number(it.kuantitas) || 0) * (1 - (Number(it.diskon_persen) || 0) / 100)
    }
    return total
  }

  /** Mengembalikan jumlah baris yang berubah status. */
  async jalankan() {
    const calon = this.antrean.semua().filter(layakDipulihkan)
    if (!calon.length) return 0
    let berubah = 0
    const cache = new Map()
    const diklaim = new Set()

    for (const p of calon) {
      const waktu = Date.parse((p.body && p.body.waktu_klien) || '') || p.dibuat
      const kunci = `${p.tokoId || ''}|${tgl(waktu)}`
      if (!cache.has(kunci)) {
        const dari = tgl(waktu - 86400000)
        const sampai = tgl(waktu + 86400000)
        let daftar = null
        try { daftar = await this.ambilDaftar(p.tokoId || null, dari, sampai) } catch { daftar = null }
        cache.set(kunci, Array.isArray(daftar) ? daftar.map(baris) : null)
      }
      const daftar = cache.get(kunci)
      if (!daftar) continue // gagal ditarik → jangan memutuskan

      const total = this.totalLokal(p)
      const tipe = String((p.body && p.body.tipe_pembayaran) || '').toUpperCase()
      const kandidat = daftar.filter((t) =>
        !diklaim.has(t.id) && !t.dibatalkan &&
        Math.abs(t.total - total) < 1 &&
        (!tipe || !t.metode || t.metode === tipe) &&
        t.waktu !== null && Math.abs(t.waktu - waktu) <= this.jendelaMs)

      if (kandidat.length === 1) {
        diklaim.add(kandidat[0].id)
        this.antrean.selesai(p.clientRef, { nomor: kandidat[0].nomor, id: kandidat[0].id, dipulihkan: true })
        berubah++
      } else if (kandidat.length === 0) {
        this.antrean.perbarui(p.clientRef, { status: STATUS.MENUNGGU, percobaan: 0, cobaLagiSetelah: null, galat: 'Dipastikan belum tercatat di server; dikirim ulang otomatis.' })
        berubah++
      } else {
        const nomor = kandidat.slice(0, 3).map((t) => t.nomor).join(', ')
        this.antrean.perbarui(p.clientRef, { galat: `Kemungkinan sudah tercatat sebagai ${nomor}. Periksa Riwayat, lalu Batalkan bila sudah ada atau Kirim ulang bila belum.` })
      }
    }
    return berubah
  }
}

module.exports = { Pemulih, layakDipulihkan, PESAN_TIMEOUT_SETELAH_KIRIM }
