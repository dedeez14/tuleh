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
 *   payment : { metode, dibayar, kembalian } | null
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

  // Layar sambutan (keranjang kosong)
  if (!items.length) {
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

  const bayarBlok = pay ? `
    <div class="cd__pay">
      <div class="cd__line cd__line--pay"><span>Dibayar${pay.metode ? ` · ${esc(pay.metode)}` : ''}</span><span class="num">${fmtIDR(pay.dibayar)}</span></div>
      <div class="cd__line cd__line--change"><span>Kembalian</span><span class="num">${fmtIDR(pay.kembalian)}</span></div>
    </div>` : ''

  return `
    <div class="cd cd--order">
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
    </div>`
}
