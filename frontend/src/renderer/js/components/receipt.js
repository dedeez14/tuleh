// Struk — dipakai layar Kasir (setelah checkout) dan Riwayat (lihat ulang).
// buildReceiptHTML menghasilkan markup untuk pratinjau modal DAN untuk cetak.

import { esc, fmtIDR, fmtDateTime, fmtNumber } from '../utils/format.js'
import { api } from '../api.js'
import { getState } from '../state.js'
import { toast } from './ui.js'
import { labelPembayaranStruk } from '../lib/qris-flow.js'

/** Bangun HTML struk dari objek Struk API (+ data perusahaan dari state). */
export function buildReceiptHTML(struk) {
  const { company, branch, struk: strukCfg } = getState()
  // Kop: logo struk (fallback logo usaha); sembunyikan bila tampil_logo === false.
  const tampilLogo = strukCfg ? strukCfg.tampil_logo !== false : true
  const logoStruk = tampilLogo ? (strukCfg?.logo || company?.logo || '') : ''
  const footerCfg = (strukCfg?.footer || '').trim()
  const isVoid = struk.status === 'DIBATALKAN'
  // Pra-bon (bill hitungan bon meja) — belum dibayar; sembunyikan baris bayar/kembalian
  const isPrabon = struk.status === 'BELUM DIBAYAR'

  const itemRows = (struk.items || [])
    .map((item) => {
      const qtyLine = `${fmtNumber(item.kuantitas)} ${esc(item.satuan || '')} × ${fmtIDR(item.harga)}`
      const discount = Number(item.diskon_persen) > 0 ? ` (−${fmtNumber(item.diskon_persen)}%)` : ''
      return `
        <div class="receipt__item">
          <div class="receipt__item-name">${esc(item.nama)}</div>
          <div class="receipt__item-line">
            <span>${qtyLine}${discount}</span>
            <span class="num">${fmtIDR(item.subtotal)}</span>
          </div>
        </div>`
    })
    .join('')

  const row = (label, value, cls = '') => `
    <div class="receipt__row ${cls}">
      <span>${label}</span>
      <span class="num">${value}</span>
    </div>`

  return `
    <div class="receipt${isVoid ? ' receipt--void' : ''}">
      ${isVoid ? '<div class="receipt__void-stamp">DIBATALKAN</div>' : ''}
      <div class="receipt__head">
        ${logoStruk ? `<img class="receipt__logo" src="${esc(logoStruk)}" alt="" />` : ''}
        <div class="receipt__company">${esc(company?.nama || 'Tuléh')}</div>
        ${company?.alamat ? `<div class="receipt__meta">${esc(company.alamat)}</div>` : ''}
        ${company?.telepon ? `<div class="receipt__meta">Telp: ${esc(company.telepon)}</div>` : ''}
        ${branch?.nama ? `<div class="receipt__meta">${esc(branch.nama)}</div>` : ''}
      </div>
      <div class="receipt__sep"></div>
      ${isPrabon ? `<div class="receipt__antrian" style="background:#fdf1df;color:#b45309">BILL — BELUM DIBAYAR</div>` : ''}
      ${struk.meja ? `<div class="receipt__antrian">${esc(struk.meja)}${struk.pax ? ` · ${esc(struk.pax)} org` : ''}</div>` : ''}
      <div class="receipt__row"><span>No.</span><span class="mono">${esc(struk.nomor)}</span></div>
      ${struk.no_antrian ? `<div class="receipt__antrian">ANTRIAN: ${esc(struk.no_antrian)}</div>` : ''}
      <div class="receipt__row"><span>Tanggal</span><span>${fmtDateTime(struk.tanggal)}</span></div>
      ${struk.kasir ? `<div class="receipt__row"><span>Kasir</span><span>${esc(struk.kasir)}</span></div>` : ''}
      ${struk.pelanggan ? `<div class="receipt__row"><span>Pelanggan</span><span>${esc(struk.pelanggan)}</span></div>` : ''}
      <div class="receipt__sep"></div>
      ${itemRows}
      <div class="receipt__sep"></div>
      ${row('Subtotal', fmtIDR(struk.subtotal))}
      ${Number(struk.total_diskon) > 0 ? row('Diskon', `−${fmtIDR(struk.total_diskon)}`) : ''}
      ${Number(struk.total_pajak) > 0 ? row('Pajak', fmtIDR(struk.total_pajak)) : ''}
      ${row('TOTAL', fmtIDR(struk.grand_total), 'receipt__row--total')}
      ${isPrabon
        ? ''
        : `${row(esc(labelPembayaranStruk(struk)), fmtIDR(struk.dibayar))}
      ${row('Kembalian', fmtIDR(struk.kembalian))}`}
      <div class="receipt__sep"></div>
      ${struk.lacak_qr ? `
        <div class="receipt__track">
          <img class="receipt__track-qr" src="${esc(struk.lacak_qr)}" alt="QR lacak pesanan" />
          <div class="receipt__track-label">Scan untuk lacak status pesanan</div>
        </div>` : ''}
      <div class="receipt__foot">${isPrabon
        ? 'Ini bukan bukti bayar — silakan bayar di kasir'
        : esc(footerCfg || 'Terima kasih atas kunjungan Anda')}</div>
    </div>`
}

/** Cetak struk lewat dialog printer OS. */
export async function printReceipt(struk) {
  const printRoot = document.getElementById('print-root')
  if (!printRoot) return
  printRoot.innerHTML = buildReceiptHTML(struk)
  const result = await api.app.print()
  printRoot.innerHTML = ''
  if (!result.ok && result.message && !/dibatalkan|cancel/i.test(result.message)) {
    toast(`Gagal mencetak: ${result.message}`, 'error')
  }
}

/** Cetak kartu QR meja (untuk ditempel di meja) — nama toko, nomor meja, QR besar. */
export async function printQR({ nomor, tokoNama, url, qrUri }) {
  const printRoot = document.getElementById('print-root')
  if (!printRoot || !qrUri) return
  printRoot.innerHTML = `
    <div class="qrprint">
      <div class="qrprint__toko">${esc(tokoNama || 'Tuléh')}</div>
      <div class="qrprint__meja">MEJA ${esc(nomor)}</div>
      <img class="qrprint__img" src="${esc(qrUri)}" alt="QR Meja ${esc(nomor)}" />
      <div class="qrprint__cta">Pindai untuk Pesan Sendiri</div>
      <div class="qrprint__sub">Arahkan kamera HP ke kode QR di atas &rarr; pilih menu &rarr; kirim.
        Pesanan langsung masuk ke meja ini.</div>
      <div class="qrprint__url">${esc(url || '')}</div>
    </div>`
  const result = await api.app.print()
  printRoot.innerHTML = ''
  if (!result.ok && result.message && !/dibatalkan|cancel/i.test(result.message)) {
    toast(`Gagal mencetak: ${result.message}`, 'error')
  }
}
