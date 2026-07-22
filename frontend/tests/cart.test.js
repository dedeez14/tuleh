'use strict'

const test = require('node:test')
const assert = require('node:assert/strict')

let cart

test.before(async () => {
  cart = await import('../src/renderer/js/lib/cart.js')
})

test('lineTotals menghitung bruto, diskon, pajak, total', () => {
  // Arrange
  const item = { harga: 18000, kuantitas: 2, diskonPersen: 10, pajakPersen: 11 }

  // Act
  const line = cart.lineTotals(item)

  // Assert
  assert.equal(line.bruto, 36000)
  assert.equal(line.diskon, 3600)
  assert.equal(line.dpp, 32400)
  assert.equal(line.pajak, 3564)
  assert.equal(line.total, 35964)
})

test('lineTotals aman terhadap input kosong/tidak valid', () => {
  const line = cart.lineTotals({ harga: 'abc', kuantitas: undefined })
  assert.deepEqual(line, { bruto: 0, diskon: 0, dpp: 0, pajak: 0, total: 0 })
})

test('cartTotals menjumlahkan banyak baris', () => {
  const items = [
    { harga: 10000, kuantitas: 1, diskonPersen: 0, pajakPersen: 0 },
    { harga: 5000, kuantitas: 3, diskonPersen: 0, pajakPersen: 0 }
  ]

  const totals = cart.cartTotals(items)

  assert.equal(totals.subtotal, 25000)
  assert.equal(totals.totalDiskon, 0)
  assert.equal(totals.totalPajak, 0)
  assert.equal(totals.grandTotal, 25000)
  assert.equal(totals.itemCount, 2)
  assert.equal(totals.qtyCount, 4)
})

test('cartTotals dengan diskon dan pajak campuran', () => {
  const items = [
    { harga: 18000, kuantitas: 2, diskonPersen: 10, pajakPersen: 11 },
    { harga: 7000, kuantitas: 1, diskonPersen: 0, pajakPersen: 0 }
  ]

  const totals = cart.cartTotals(items)

  assert.equal(totals.subtotal, 43000)
  assert.equal(totals.totalDiskon, 3600)
  assert.equal(totals.totalPajak, 3564)
  assert.equal(totals.grandTotal, 42964)
})

test('cartTotals keranjang kosong menghasilkan nol', () => {
  const totals = cart.cartTotals([])
  assert.equal(totals.grandTotal, 0)
  assert.equal(totals.itemCount, 0)
})

test('kembalian positif hanya saat lebih bayar', () => {
  assert.equal(cart.kembalian(50000, 42964), 7036)
  assert.equal(cart.kembalian(40000, 42964), 0)
  assert.equal(cart.kembalian(42964, 42964), 0)
})

test('shortfall menunjukkan kekurangan pembayaran', () => {
  assert.equal(cart.shortfall(40000, 42964), 2964)
  assert.equal(cart.shortfall(50000, 42964), 0)
})

test('quickCashOptions memberi uang pas + pembulatan pecahan', () => {
  const options = cart.quickCashOptions(42964)
  assert.equal(options[0], 42964) // uang pas selalu pertama (terkecil)
  assert.ok(options.includes(45000))
  assert.ok(options.includes(50000))
  assert.ok(options.includes(100000))
  // Terurut naik & unik
  const sorted = [...options].sort((a, b) => a - b)
  assert.deepEqual(options, sorted)
  assert.equal(new Set(options).size, options.length)
})

test('quickCashOptions kosong untuk total nol', () => {
  assert.deepEqual(cart.quickCashOptions(0), [])
})

test('clampQty membatasi qty terhadap stok bila kelola stok', () => {
  assert.equal(cart.clampQty(5, { kelolaStok: true, stok: 3 }), 3)
  assert.equal(cart.clampQty(2, { kelolaStok: true, stok: 3 }), 2)
  assert.equal(cart.clampQty(5, { kelolaStok: false, stok: 3 }), 5)
  assert.equal(cart.clampQty(-1, {}), 0)
  assert.equal(cart.clampQty('abc', {}), 0)
})
