// Struk sebagai teks polos lebar tetap (32 kolom) untuk dibagikan lewat
// WhatsApp / disalin. Murni: tanpa DOM & state, agar mudah diuji.

import { fmtIDR as _fmtIDR, fmtNumber, fmtDateTime } from '../utils/format.js'

// Spasi biasa, bukan NBSP: WhatsApp/teks polos merender NBSP tidak konsisten.
const fmtIDR = (v) => _fmtIDR(v).replace(/ /g, ' ')
import { labelPembayaranStruk } from './qris-flow.js'
import { labelKuantitas } from './satuan-terukur.js'

export const TANDA_DEMO = 'MODE DEMO — BUKAN BUKTI PEMBAYARAN'

/**
 * Objek struk untuk NOTA REFUND dari struk transaksi + satu dokumen refund
 * (respons POST /transaksi/{id}/refund atau elemen struk.refunds[]). Bentuknya
 * sama dengan struk transaksi (items/subtotal/grand_total) sehingga
 * buildReceiptText/buildReceiptHTML cukup mengenali status 'REFUND'.
 */
export function strukRefund(struk, refund) {
  const items = (refund?.items || []).map((it) => {
    const kuantitas = Number(it.kuantitas) || 0
    const total = Number(it.total) || 0
    return {
      nama: it.nama,
      kuantitas,
      satuan: it.satuan,
      harga: kuantitas > 0 ? total / kuantitas : total,
      subtotal: total,
      kembali_stok: it.kembali_stok !== false
    }
  })
  return {
    status: 'REFUND',
    id: refund?.id,
    nomor: refund?.nomor,
    tanggal: refund?.tanggal,
    kasir: refund?.oleh,
    pelanggan: struk?.pelanggan,
    pelanggan_telepon: struk?.pelanggan_telepon,
    transaksi_nomor: struk?.nomor,
    metode: refund?.metode,
    metode_nama: refund?.metode_nama || refund?.metode,
    alasan: refund?.alasan,
    items,
    subtotal: Number(refund?.subtotal) || 0,
    total_pajak: Number(refund?.total_pajak) || 0,
    total_diskon: 0,
    grand_total: Number(refund?.total) || 0
  }
}

/** Susunannya mengikuti struk cetak; Mode Demo bertanda di kepala & kaki. */
export function buildReceiptText(struk, { kolom = 32, demo = false, company = null, footer = '' } = {}) {
  if (!struk) return ''
  const isDemo = !!demo
  const b = []
  const tengah = (t) => b.push(t.length >= kolom ? t : ' '.repeat(Math.floor((kolom - t.length) / 2)) + t)
  const garis = () => b.push('-'.repeat(kolom))
  const dua = (kiri, kanan) => {
    const maks = kolom - kanan.length - 1
    const l = maks < 1 ? kiri : kiri.slice(0, maks)
    b.push(maks < 1 ? `${kiri} ${kanan}` : l + ' '.repeat(kolom - l.length - kanan.length) + kanan)
  }
  const bungkus = (teks) => {
    const out = []
    let baris = ''
    for (const kata of String(teks).split(/\s+/)) {
      if (!kata) continue
      if ((baris + ' ' + kata).trim().length > kolom) { if (baris) out.push(baris); baris = kata.slice(0, kolom) }
      else baris = (baris + ' ' + kata).trim()
    }
    if (baris) out.push(baris)
    return out
  }
  const isRefund = struk.status === 'REFUND'
  if (isDemo) { tengah(TANDA_DEMO); garis() }
  tengah(String(company?.nama || 'Tuléh').toUpperCase())
  if (company?.alamat) bungkus(company.alamat).forEach(tengah)
  if (company?.telepon) tengah(`Telp ${company.telepon}`)
  garis()
  if (isRefund) { tengah('NOTA REFUND'); garis() }
  dua('No', String(struk.nomor || '-'))
  if (isRefund) dua('Transaksi', String(struk.transaksi_nomor || '-'))
  dua('Waktu', fmtDateTime(struk.tanggal))
  if (struk.kasir) dua(isRefund ? 'Oleh' : 'Kasir', String(struk.kasir))
  if (struk.pelanggan) dua('Pelanggan', String(struk.pelanggan))
  garis()
  for (const it of struk.items || []) {
    bungkus(it.nama).forEach((t) => b.push(t))
    const disk = Number(it.diskon_persen) > 0 ? ` -${fmtNumber(it.diskon_persen)}%` : ''
    dua(`  ${labelKuantitas(it.kuantitas, it.satuan)} x ${fmtIDR(it.harga)}${disk}`, fmtIDR(it.subtotal))
    if (Number(it.nominal_diminta) > 0) b.push(`  (diminta ${fmtIDR(it.nominal_diminta)})`)
  }
  garis()
  if (isRefund) {
    dua('TOTAL REFUND', fmtIDR(struk.grand_total))
    dua('Dikembalikan via', String(struk.metode_nama || struk.metode || '-'))
    bungkus(`Alasan: ${struk.alasan || '-'}`).forEach((t) => b.push(t))
    garis()
    tengah('Dana telah dikembalikan')
    if (isDemo) { garis(); tengah(TANDA_DEMO) }
    return b.join('\n')
  }
  dua('Subtotal', fmtIDR(struk.subtotal))
  if (Number(struk.total_diskon) > 0) dua('Diskon', `-${fmtIDR(struk.total_diskon)}`)
  if (Number(struk.total_pajak) > 0) dua('Pajak', fmtIDR(struk.total_pajak))
  dua('TOTAL', fmtIDR(struk.grand_total))
  if (struk.status !== 'BELUM DIBAYAR') {
    dua(labelPembayaranStruk(struk), fmtIDR(struk.dibayar))
    dua('Kembalian', fmtIDR(struk.kembalian))
  }
  // Refund yang sudah tercatat atas transaksi ini (server: total_refund, nilai_bersih, refunds[]).
  if (Number(struk.total_refund) > 0) {
    garis()
    for (const r of struk.refunds || []) dua(`Refund ${r.nomor || ''}`.trim(), `-${fmtIDR(r.total)}`)
    dua('NILAI BERSIH', fmtIDR(struk.nilai_bersih))
  }
  garis()
  tengah(String(footer || '').trim() || 'Terima kasih atas kunjungan Anda')
  if (isDemo) { garis(); tengah(TANDA_DEMO) }
  return b.join('\n')
}

