'use strict'

// Nomor lokal & struk lokal untuk transaksi yang dibuat saat offline.
// Nomor: L-<AWALAN>-yyMMdd-NNNN per hari per komputer; AWALAN = 4 karakter pertama id perangkat antrean
// (padanan Android NomorLokal) supaya struk dua kasir/instal ulang di hari yang sama tidak kembar.
// Struk: bentuk yang sama dengan jawaban /transaksi/checkout server agar layar
// struk, riwayat, dan cetak ulang tidak perlu tahu asalnya.

const fs = require('node:fs')
const path = require('node:path')

class NomorLokal {
  constructor({ berkas = null } = {}) {
    this.berkas = berkas
    this.data = {}
    try { this.data = JSON.parse(fs.readFileSync(berkas, 'utf8')) || {} } catch { /* kosong */ }
  }

  berikutnya(sekarang = new Date(), awalan = '') {
    const d = new Date(sekarang)
    const yy = String(d.getFullYear()).slice(2)
    const mm = String(d.getMonth() + 1).padStart(2, '0')
    const dd = String(d.getDate()).padStart(2, '0')
    const hari = `${yy}${mm}${dd}`
    const n = (this.data[hari] || 0) + 1
    this.data = { [hari]: n } // hari lain dibuang: hitungan mulai dari 1 tiap hari
    if (this.berkas) {
      try {
        fs.mkdirSync(path.dirname(this.berkas), { recursive: true })
        fs.writeFileSync(this.berkas, JSON.stringify(this.data))
      } catch { /* abaikan */ }
    }
    const a = String(awalan || '').replace(/[^0-9A-Za-z]/g, '').slice(0, 4).toUpperCase()
    return a ? `L-${a}-${hari}-${String(n).padStart(4, '0')}` : `L-${hari}-${String(n).padStart(4, '0')}`
  }
}

const round2 = (n) => Math.round((Number(n) || 0) * 100) / 100

/**
 * Susun struk lokal dari badan checkout + data tampilan item.
 * items: [{ id_produk, harga, kuantitas, diskon_persen, pajak_persen }]
 * tampilan: [{ id_produk, nama, satuan }]
 */
function buatStrukLokal({ nomor, body, tampilan = [], kasir = null, pelangganNama = null, waktu = new Date() }) {
  const namaOleh = new Map(tampilan.map((t) => [String(t.id_produk), t]))
  const items = (body.items || []).map((it) => {
    const t = namaOleh.get(String(it.id_produk)) || {}
    const harga = Number(it.harga) || 0
    const qty = Number(it.kuantitas) || 0
    const diskon = Number(it.diskon_persen) || 0
    const pajak = Number(it.pajak_persen) || 0
    const bruto = harga * qty
    const potongan = bruto * diskon / 100
    const dpp = bruto - potongan
    const pjk = dpp * pajak / 100
    const baris = {
      id_produk: it.id_produk,
      nama: t.nama || `Produk ${it.id_produk}`,
      satuan: t.satuan || '',
      kuantitas: qty,
      harga,
      diskon_persen: diskon,
      pajak_persen: pajak,
      subtotal: round2(dpp + pjk),
      _bruto: bruto, _diskon: potongan, _pajak: pjk
    }
    // Baris per rupiah: kuantitas pastinya dihitung ulang server dari nominal → refund sebagian menunggu tersinkron.
    if (Number(it.nominal) > 0) baris.per_nominal = true
    return baris
  })
  const subtotal = round2(items.reduce((s, i) => s + i._bruto, 0))
  const totalDiskon = round2(items.reduce((s, i) => s + i._diskon, 0))
  const totalPajak = round2(items.reduce((s, i) => s + i._pajak, 0))
  const grand = round2(subtotal - totalDiskon + totalPajak)
  const dibayar = Number(body.dibayar) || grand
  const tunai = String(body.tipe_pembayaran || 'TUNAI').toUpperCase() === 'TUNAI'
  for (const i of items) { delete i._bruto; delete i._diskon; delete i._pajak }
  return {
    id: null,
    nomor,
    tanggal: new Date(waktu).toISOString(),
    status: 'BELUM SINKRON',
    belum_sinkron: true,
    kasir,
    pelanggan: pelangganNama,
    tipe_pembayaran: body.tipe_pembayaran || 'TUNAI',
    catatan: body.catatan || null,
    items,
    subtotal,
    total_diskon: totalDiskon,
    total_pajak: totalPajak,
    grand_total: grand,
    dibayar,
    kembalian: tunai ? round2(Math.max(0, dibayar - grand)) : 0
  }
}

const CATATAN_CADANGAN = 'Belum tersinkron — struk lengkap tersedia setelah sinkron.'

/**
 * Struk CADANGAN untuk penjualan yang sudah diantrekan tetapi struk lokalnya gagal disusun (penyiapan antre
 * melempar): renderer selalu menerima objek struk yang aman dibaca (grand_total, dibayar, kembalian, items).
 * Isi dihitung dari badan checkout bila bisa (tampilan rusak diabaikan); bila badan pun rusak → struk minimal.
 * Tanpa nomor: nomor lokal mungkin tak terbuat — nomor resmi menyusul setelah sinkron.
 */
function strukCadangan({ body, tampilan = [], kasir = null, pelangganNama = null, waktu = new Date() } = {}) {
  const b = body && typeof body === 'object' ? body : {}
  const items = Array.isArray(b.items) ? b.items.filter((i) => i && typeof i === 'object') : []
  const bersih = Array.isArray(tampilan) ? tampilan.filter((t) => t && typeof t === 'object') : []
  let s = null
  for (const tpl of [bersih, []]) {
    try {
      s = buatStrukLokal({ nomor: null, body: { ...b, items }, tampilan: tpl, kasir, pelangganNama, waktu })
      break
    } catch { s = null }
  }
  if (!s) {
    let tanggal = null
    try { tanggal = new Date(waktu).toISOString() } catch { tanggal = null }
    s = {
      id: null, nomor: null, tanggal, status: 'BELUM SINKRON', belum_sinkron: true, kasir, pelanggan: pelangganNama,
      tipe_pembayaran: typeof b.tipe_pembayaran === 'string' && b.tipe_pembayaran ? b.tipe_pembayaran : 'TUNAI',
      catatan: null, items: [], subtotal: 0, total_diskon: 0, total_pajak: 0, grand_total: 0,
      dibayar: Number(b.dibayar) || 0, kembalian: 0
    }
  }
  return { ...s, nomor: null, catatan_kaki: CATATAN_CADANGAN }
}

module.exports = { NomorLokal, buatStrukLokal, strukCadangan }
