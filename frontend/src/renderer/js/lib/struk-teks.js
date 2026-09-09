// Struk sebagai teks polos lebar tetap (32 kolom) untuk dibagikan lewat
// WhatsApp / disalin. Murni: tanpa DOM & state, agar mudah diuji.

import { fmtIDR as _fmtIDR, fmtNumber, fmtDateTime } from '../utils/format.js'

// Spasi biasa, bukan NBSP: WhatsApp/teks polos merender NBSP tidak konsisten.
const fmtIDR = (v) => _fmtIDR(v).replace(/ /g, ' ')
import { labelPembayaranStruk } from './qris-flow.js'
import { labelKuantitas } from './satuan-terukur.js'

export const TANDA_DEMO = 'MODE DEMO — BUKAN BUKTI PEMBAYARAN'

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
  if (isDemo) { tengah(TANDA_DEMO); garis() }
  tengah(String(company?.nama || 'Tuléh').toUpperCase())
  if (company?.alamat) bungkus(company.alamat).forEach(tengah)
  if (company?.telepon) tengah(`Telp ${company.telepon}`)
  garis()
  dua('No', String(struk.nomor || '-'))
  dua('Waktu', fmtDateTime(struk.tanggal))
  if (struk.kasir) dua('Kasir', String(struk.kasir))
  if (struk.pelanggan) dua('Pelanggan', String(struk.pelanggan))
  garis()
  for (const it of struk.items || []) {
    bungkus(it.nama).forEach((t) => b.push(t))
    const disk = Number(it.diskon_persen) > 0 ? ` -${fmtNumber(it.diskon_persen)}%` : ''
    dua(`  ${labelKuantitas(it.kuantitas, it.satuan)} x ${fmtIDR(it.harga)}${disk}`, fmtIDR(it.subtotal))
  }
  garis()
  dua('Subtotal', fmtIDR(struk.subtotal))
  if (Number(struk.total_diskon) > 0) dua('Diskon', `-${fmtIDR(struk.total_diskon)}`)
  if (Number(struk.total_pajak) > 0) dua('Pajak', fmtIDR(struk.total_pajak))
  dua('TOTAL', fmtIDR(struk.grand_total))
  if (struk.status !== 'BELUM DIBAYAR') {
    dua(labelPembayaranStruk(struk), fmtIDR(struk.dibayar))
    dua('Kembalian', fmtIDR(struk.kembalian))
  }
  garis()
  tengah(String(footer || '').trim() || 'Terima kasih atas kunjungan Anda')
  if (isDemo) { garis(); tengah(TANDA_DEMO) }
  return b.join('\n')
}

