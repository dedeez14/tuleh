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

test('metode QRIS: panel QR tampil di kolom kanan, tanpa blok kembalian', () => {
  const html = V.customerViewHTML({
    store: { nama: 'X' },
    items: [{ nama: 'A', qty: 1, harga: 25000, subtotal: 25000 }],
    totals: { grandTotal: 25000 },
    payment: { metode: 'QRIS', dibayar: 25000, kembalian: 0, qris: 'https://cdn.x/qris.png' }
  })
  assert.match(html, /cd--bayar/)
  assert.match(html, /cd__side--qris/)
  assert.match(html, /Pindai QRIS/)
  assert.match(html, /<img class="cd__qr" src="https:\/\/cdn\.x\/qris\.png"/)
  assert.match(html, /Rp\s?25\.000/)
  assert.doesNotMatch(html, /Kembalian/)
})

test('metode TRANSFER: daftar rekening tampil untuk pelanggan (ter-escape)', () => {
  const html = V.customerViewHTML({
    store: { nama: 'X' },
    items: [{ nama: 'A', qty: 1, harga: 25000, subtotal: 25000 }],
    totals: { grandTotal: 25000 },
    payment: {
      metode: 'TRANSFER', dibayar: 25000, kembalian: 0,
      bank: [{ bank: 'BCA', rekening: '1234567890', atas_nama: 'Toko <X>' }]
    }
  })
  assert.match(html, /cd__side--transfer/)
  assert.match(html, /Transfer ke rekening/)
  assert.match(html, /BCA/)
  assert.match(html, /1234567890/)
  assert.match(html, /a\.n\. Toko &lt;X&gt;/)
  assert.doesNotMatch(html, /Kembalian/)
})

test('TRANSFER tanpa rekening tetap aman: minta tanya kasir', () => {
  const html = V.customerViewHTML({
    store: { nama: 'X' },
    items: [{ nama: 'A', qty: 1, harga: 1000, subtotal: 1000 }],
    totals: { grandTotal: 1000 },
    payment: { metode: 'TRANSFER', dibayar: 1000, kembalian: 0, bank: [] }
  })
  assert.match(html, /tanyakan nomor rekening/)
})

test('QRIS_AUTO memakai QR dinamis dan keterangan cek otomatis', () => {
  const html = V.customerViewHTML({
    store: { nama: 'X' },
    items: [{ nama: 'A', qty: 1, harga: 1000, subtotal: 1000 }],
    totals: { grandTotal: 1000 },
    payment: { metode: 'QRIS_AUTO', dibayar: 1000, kembalian: 0, qris: 'data:image/svg+xml;base64,AAA' }
  })
  assert.match(html, /data:image\/svg\+xml;base64,AAA/)
  assert.match(html, /dicek otomatis/)
})

test('TUNAI tetap tampil dibayar & kembalian, tanpa panel samping', () => {
  const html = V.customerViewHTML({
    store: { nama: 'X' },
    items: [{ nama: 'A', qty: 1, harga: 1000, subtotal: 1000 }],
    totals: { grandTotal: 1000 },
    payment: { metode: 'TUNAI', dibayar: 5000, kembalian: 4000 }
  })
  assert.doesNotMatch(html, /cd--bayar/)
  assert.match(html, /Kembalian/)
})
