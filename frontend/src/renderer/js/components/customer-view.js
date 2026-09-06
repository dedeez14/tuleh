// Tampilan Display Pelanggan — dipakai di DUA tempat dari satu render murni:
//  (1) jendela kedua desktop (customer-display.js), dan
//  (2) overlay layar-penuh Android (pos.js).
// Murni: HTML dari objek state, tanpa efek samping → mudah diuji.

import { esc, fmtIDR, fmtNumber } from '../utils/format.js'

/**
 * @param {object} state
 *   store   : { nama, logo }
 *   items   : [{ nama, qty, satuan, harga, subtotal }]
 *   totals  : { subtotal, totalDiskon, totalPajak, grandTotal, qtyCount }
 *   payment : { metode, dibayar, kembalian, qris?, bank? } | null
 *             qris : URL/data-URI gambar QR (QRIS statis atau QRIS otomatis)
 *             bank : [{ bank, rekening, atas_nama }] untuk metode TRANSFER
 *   done    : boolean  (transaksi selesai → layar terima kasih)
 */
export function customerViewHTML(state) {
  const s = state || {}
  const store = s.store || {}
  const items = Array.isArray(s.items) ? s.items : []
  const t = s.totals || {}
  const pay = s.payment || null
  const grand = Number(t.grandTotal) || 0

  const brand = `
    <div class="cd__brand">
      ${store.logo ? `<img class="cd__logo" src="${esc(store.logo)}" alt="" />` : ''}
      <span class="cd__store">${esc(store.nama || 'Tuléh')}</span>
    </div>`

  // Layar terima kasih (setelah transaksi tercatat)
  if (s.done) {
    return `
      <div class="cd cd--thanks">
        ${brand}
        <div class="cd__thanks-icon" aria-hidden="true">✓</div>
        <div class="cd__thanks-title">Terima kasih!</div>
        <div class="cd__thanks-sub">Pembayaran diterima</div>
        <div class="cd__thanks-grid">
          <div><span class="cd__k">Total</span><span class="cd__v num">${fmtIDR(grand)}</span></div>
          ${pay && Number(pay.kembalian) > 0
            ? `<div><span class="cd__k">Kembalian</span><span class="cd__v cd__v--change num">${fmtIDR(pay.kembalian)}</span></div>`
            : ''}
        </div>
      </div>`
  }

  // Layar sambutan (keranjang kosong). Bila ada video promosi → putar layar penuh.
  if (!items.length) {
    if (s.promoVideo) {
      return `
        <div class="cd cd--promo">
          <video class="cd__promo" src="${esc(s.promoVideo)}" autoplay muted loop playsinline></video>
        </div>`
    }
    return `
      <div class="cd cd--welcome">
        ${brand}
        <div class="cd__welcome-title">Selamat datang</div>
        <div class="cd__welcome-sub">Silakan, kami siap melayani Anda 🙏</div>
      </div>`
  }

  const rows = items.map((it) => `
    <div class="cd__row">
      <div class="cd__row-name">${esc(it.nama)}</div>
      <div class="cd__row-meta">
        <span class="cd__row-qty num">${fmtNumber(it.qty)}×</span>
        <span class="cd__row-price num">${fmtIDR(it.harga)}</span>
      </div>
      <div class="cd__row-sub num">${fmtIDR(it.subtotal)}</div>
    </div>`).join('')

  const potongan = Number(t.totalDiskon) > 0
    ? `<div class="cd__line"><span>Diskon</span><span class="num">−${fmtIDR(t.totalDiskon)}</span></div>` : ''
  const pajak = Number(t.totalPajak) > 0
    ? `<div class="cd__line"><span>Pajak</span><span class="num">${fmtIDR(t.totalPajak)}</span></div>` : ''

  // Panel instruksi non-tunai: QR untuk dipindai / rekening tujuan transfer.
  // Tampil di kolom kanan agar pelanggan bisa membayar sambil melihat pesanan.
  const instruksi = pay ? instruksiHTML(pay, grand) : ''

  const bayarBlok = pay && !instruksi ? `
    <div class="cd__pay">
      <div class="cd__line cd__line--pay"><span>Dibayar${pay.metode ? ` · ${esc(pay.metode)}` : ''}</span><span class="num">${fmtIDR(pay.dibayar)}</span></div>
      <div class="cd__line cd__line--change"><span>Kembalian</span><span class="num">${fmtIDR(pay.kembalian)}</span></div>
    </div>` : ''

  return `
    <div class="cd cd--order${instruksi ? ' cd--bayar' : ''}">
      <div class="cd__main">
        <div class="cd__top">
          ${brand}
          <div class="cd__count">${fmtNumber(t.qtyCount || items.reduce((a, i) => a + (Number(i.qty) || 0), 0))} item</div>
        </div>
        <div class="cd__items">${rows}</div>
        <div class="cd__foot">
          ${potongan}${pajak}
          <div class="cd__total">
            <span class="cd__total-k">Total</span>
            <span class="cd__total-v num">${fmtIDR(grand)}</span>
          </div>
          ${bayarBlok}
        </div>
      </div>
      ${instruksi}
    </div>`
}

/** Panel QRIS / Transfer untuk pelanggan; '' bila metode tidak butuh instruksi. */
export function instruksiHTML(pay, grand) {
  const p = pay || {}
  const banks = Array.isArray(p.bank) ? p.bank : []
  if (p.qris) {
    return `
      <aside class="cd__side cd__side--qris">
        <div class="cd__side-title">Pindai QRIS untuk membayar</div>
        <div class="cd__qr-frame"><img class="cd__qr" src="${esc(p.qris)}" alt="QRIS" /></div>
        <div class="cd__side-total num">${fmtIDR(grand)}</div>
        <div class="cd__side-sub">${p.metode === 'QRIS_AUTO'
          ? 'Pembayaran dicek otomatis setelah Anda memindai.'
          : 'Setelah pembayaran berhasil, tunjukkan bukti ke kasir.'}</div>
      </aside>`
  }
  if (p.metode === 'TRANSFER') {
    const daftar = banks.length
      ? banks.map((b) => `
          <div class="cd__bank">
            <div class="cd__bank-name">${esc(b.bank)}</div>
            <div class="cd__bank-rek num">${esc(b.rekening)}</div>
            <div class="cd__bank-an">a.n. ${esc(b.atas_nama)}</div>
          </div>`).join('')
      : `<div class="cd__side-sub">Silakan tanyakan nomor rekening ke kasir.</div>`
    return `
      <aside class="cd__side cd__side--transfer">
        <div class="cd__side-title">Transfer ke rekening</div>
        <div class="cd__banks">${daftar}</div>
        <div class="cd__side-total num">${fmtIDR(grand)}</div>
        <div class="cd__side-sub">Transfer sesuai nominal, lalu tunjukkan bukti ke kasir.</div>
      </aside>`
  }
  return ''
}
