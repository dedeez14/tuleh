// Deteksi pesanan meja baru — padanan `DeteksiPesanan` di aplikasi Android
// (mobile-flutter/lib/features/pemantau/domain/deteksi_pesanan.dart), agar
// desktop dan Android memberi notifikasi untuk kejadian yang sama:
//  - /orders: id pesanan baru (pesanan QR meja masuk sebagai order);
//  - /bills : bon muncul dengan item / total bertambah / status BILL.
// Murni (tanpa I/O) supaya bisa diuji dengan node:test.

import { fmtIDR } from './format.js'

export const JENIS = Object.freeze({
  PESANAN_BARU: 'pesananBaru',
  TAMBAH_PESANAN: 'tambahPesanan',
  MINTA_BAYAR: 'mintaBayar'
})

function num(v) {
  const n = Number(v)
  return Number.isFinite(n) ? n : 0
}

function potretBill(b) {
  return {
    billId: String(b.id ?? ''),
    total: num(b.total ?? b.grand_total),
    jumlahItem: Math.trunc(num(b.jumlah_item ?? b.items_count)),
    status: String(b.status ?? '')
  }
}

const mintaBayar = (m) => !!m && m.status.toUpperCase() === 'BILL'

function labelOrder(o) {
  const a = o.no_antrian ?? o.nomor_antrian ?? o.nomor
  return a == null ? '' : String(a)
}

function isiOrder(o) {
  const meja = o.meja ?? o.meja_label
  const pelanggan = o.pelanggan && typeof o.pelanggan === 'object' ? o.pelanggan.nama : o.pelanggan
  const total = num(o.total ?? o.grand_total)
  const bagian = []
  if (meja) bagian.push(String(meja))
  if (pelanggan) bagian.push(String(pelanggan))
  if (total > 0) bagian.push(fmtIDR(total))
  return bagian.length ? bagian.join(' · ') : 'Klik untuk membuka papan pesanan'
}

function isiMeja(m) {
  const bagian = []
  if (m.jumlahItem > 0) bagian.push(`${m.jumlahItem} item`)
  if (m.total > 0) bagian.push(fmtIDR(m.total))
  return bagian.join(' · ')
}

/**
 * bandingkan({ sebelum, orders, tables }) → { potret, kejadian[] }
 * `sebelum` null = poll pertama: hanya membuat potret, tanpa kejadian.
 * kejadian: { jenis, judul, isi, tujuan } — tujuan = id layar ('orders' | 'peta-meja').
 */
export function bandingkan({ sebelum = null, orders = [], tables = [] } = {}) {
  const pesanan = new Map()
  const meja = new Map()
  const kejadian = []
  const pertama = !sebelum

  for (const o of Array.isArray(orders) ? orders : []) {
    if (!o || typeof o !== 'object') continue
    const id = o.id == null ? '' : String(o.id)
    if (!id) continue
    pesanan.set(id, String(o.stage ?? ''))
    if (pertama || sebelum.pesanan.has(id)) continue
    kejadian.push({
      jenis: JENIS.PESANAN_BARU,
      judul: `Pesanan baru ${labelOrder(o)}`.trim(),
      isi: isiOrder(o),
      tujuan: 'orders'
    })
  }

  for (const t of Array.isArray(tables) ? tables : []) {
    if (!t || typeof t !== 'object') continue
    const id = t.id == null ? '' : String(t.id)
    if (!id) continue
    const nomor = String(t.nomor ?? t.kode ?? '?')
    const kini = t.bill && typeof t.bill === 'object' ? potretBill(t.bill) : null
    meja.set(id, kini)
    if (pertama || !kini) continue

    const lalu = sebelum.meja.get(id) || null
    const bonBaru = !lalu || lalu.billId !== kini.billId
    if (bonBaru && (kini.jumlahItem > 0 || kini.total > 0)) {
      kejadian.push({ jenis: JENIS.PESANAN_BARU, judul: `Meja ${nomor}: pesanan baru`, isi: isiMeja(kini), tujuan: 'peta-meja' })
    } else if (!bonBaru && (kini.jumlahItem > lalu.jumlahItem || kini.total > lalu.total)) {
      const tambah = kini.total - lalu.total
      kejadian.push({
        jenis: JENIS.TAMBAH_PESANAN,
        judul: `Meja ${nomor}: tambah pesanan`,
        isi: tambah > 0 ? `+${fmtIDR(tambah)} · total ${fmtIDR(kini.total)}` : isiMeja(kini),
        tujuan: 'peta-meja'
      })
    }
    if (mintaBayar(kini) && !mintaBayar(lalu)) {
      kejadian.push({ jenis: JENIS.MINTA_BAYAR, judul: `Meja ${nomor} minta bayar`, isi: `Total ${fmtIDR(kini.total)}`, tujuan: 'peta-meja' })
    }
  }

  return { potret: { pesanan, meja }, kejadian }
}
