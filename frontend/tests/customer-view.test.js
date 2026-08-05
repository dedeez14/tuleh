'use strict'

// Display Pelanggan — render murni customerViewHTML(state) untuk 3 keadaan:
// sambutan (kosong), pesanan berjalan (item+total+bayar), dan terima kasih.

const test = require('node:test')
const assert = require('node:assert/strict')

let V // modul ESM components/customer-view.js

test.before(async () => {
  V = await import('../src/renderer/js/components/customer-view.js')
})

test('sambutan saat keranjang kosong', () => {
  const html = V.customerViewHTML({ store: { nama: 'Toko Kopi' } })
  assert.match(html, /cd--welcome/)
  assert.match(html, /Selamat datang/)
  assert.match(html, /Toko Kopi/)
})

test('pesanan berjalan menampilkan item, subtotal & total', () => {
  const html = V.customerViewHTML({
    store: { nama: 'Toko Kopi' },
    items: [
      { nama: 'Americano', qty: 2, harga: 15000, subtotal: 30000 },
      { nama: 'Cappuccino', qty: 1, harga: 20000, subtotal: 20000 }
    ],
    totals: { grandTotal: 50000, qtyCount: 3 }
  })
  assert.match(html, /cd--order/)
  assert.match(html, /Americano/)
  assert.match(html, /Cappuccino/)
  assert.match(html, /2×/)                 // kuantitas
  assert.match(html, /Rp\s?50\.000/)       // total
  assert.doesNotMatch(html, /Kembalian/)   // belum bayar
})

test('menampilkan dibayar & kembalian saat ada payment', () => {
  const html = V.customerViewHTML({
    store: { nama: 'X' },
    items: [{ nama: 'A', qty: 1, harga: 50000, subtotal: 50000 }],
    totals: { grandTotal: 50000 },
    payment: { metode: 'TUNAI', dibayar: 100000, kembalian: 50000 }
  })
  assert.match(html, /Dibayar/)
  assert.match(html, /TUNAI/)
  assert.match(html, /Kembalian/)
  assert.match(html, /Rp\s?50\.000/)
})

test('layar terima kasih saat done=true', () => {
  const html = V.customerViewHTML({
    store: { nama: 'X' },
    done: true,
    totals: { grandTotal: 75000 },
    payment: { metode: 'QRIS', dibayar: 75000, kembalian: 0 }
  })
  assert.match(html, /cd--thanks/)
  assert.match(html, /Terima kasih/)
  assert.match(html, /Rp\s?75\.000/)
})

test('done dengan kembalian menampilkan nilai kembalian', () => {
  const html = V.customerViewHTML({
    store: { nama: 'X' }, done: true,
    totals: { grandTotal: 30000 },
    payment: { metode: 'TUNAI', dibayar: 50000, kembalian: 20000 }
  })
  assert.match(html, /Kembalian/)
  assert.match(html, /Rp\s?20\.000/)
})

test('idle dengan promoVideo menampilkan <video> layar penuh (bukan sambutan)', () => {
  const html = V.customerViewHTML({ store: { nama: 'X' }, promoVideo: 'https://cdn.x/promo.mp4' })
  assert.match(html, /cd--promo/)
  assert.match(html, /<video[^>]+src="https:\/\/cdn\.x\/promo\.mp4"/)
  assert.match(html, /autoplay/)
  assert.match(html, /loop/)
  assert.doesNotMatch(html, /Selamat datang/)
})

test('promoVideo diabaikan bila keranjang berisi (tetap layar pesanan)', () => {
  const html = V.customerViewHTML({
    store: { nama: 'X' }, promoVideo: 'https://cdn.x/promo.mp4',
    items: [{ nama: 'A', qty: 1, harga: 1000, subtotal: 1000 }], totals: { grandTotal: 1000 }
  })
  assert.match(html, /cd--order/)
  assert.doesNotMatch(html, /<video/)
})

test('aman terhadap state kosong / undefined', () => {
  assert.doesNotThrow(() => V.customerViewHTML())
  assert.doesNotThrow(() => V.customerViewHTML({}))
  assert.match(V.customerViewHTML({}), /cd--welcome/)
})

test('meng-escape nama produk (anti-XSS)', () => {
  const html = V.customerViewHTML({
    store: { nama: 'X' },
    items: [{ nama: '<img src=x onerror=alert(1)>', qty: 1, harga: 1000, subtotal: 1000 }],
    totals: { grandTotal: 1000 }
  })
  assert.doesNotMatch(html, /<img src=x/)
  assert.match(html, /&lt;img/)
})
