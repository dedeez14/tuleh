'use strict'

// Unit test analisis stok (kategori habis/menipis/aman + saran restok).

const test = require('node:test')
const assert = require('node:assert/strict')

let S
const store = {}
test.before(async () => {
  // localStorage minimal untuk stok-store
  global.localStorage = {
    getItem: (k) => (k in store ? store[k] : null),
    setItem: (k, v) => { store[k] = String(v) },
    removeItem: (k) => { delete store[k] }
  }
  S = await import('../src/renderer/js/lib/stok-store.js')
})

test.beforeEach(() => { for (const k of Object.keys(store)) delete store[k] })

test('kategori habis/menipis/aman sesuai ambang default (5)', () => {
  const rows = [
    { id: 'A', kode: 'A1', produk: 'Habis', stok: 0 },
    { id: 'B', kode: 'B1', produk: 'Menipis', stok: 3 },
    { id: 'C', kode: 'C1', produk: 'Aman', stok: 20 }
  ]
  const r = S.analisisStok(rows, 'TOKO-X')
  assert.equal(r.habis.length, 1)
  assert.equal(r.menipis.length, 1)
  assert.equal(r.aman.length, 1)
  assert.equal(r.alerts.length, 2) // habis + menipis
})

test('ambang per produk mengubah status', () => {
  S.setMin('TOKO-X', 'B', 2) // stok 3 > min 2 → aman
  const rows = [{ id: 'B', kode: 'B1', produk: 'X', stok: 3 }]
  const r = S.analisisStok(rows, 'TOKO-X')
  assert.equal(r.aman.length, 1)
  assert.equal(r.alerts.length, 0)
})

test('saran restok positif untuk item menipis & habis; alerts terurut stok naik', () => {
  const rows = [
    { id: 'A', kode: 'A', produk: 'Menipis', stok: 4 },
    { id: 'B', kode: 'B', produk: 'Habis', stok: 0 }
  ]
  const r = S.analisisStok(rows, 'TOKO-X')
  r.alerts.forEach((a) => assert.ok(a.saran >= 1))
  assert.equal(r.alerts[0].stok, 0) // paling kritis dulu
})

test('getMin default 5 bila belum diatur', () => {
  assert.equal(S.getMin('TOKO-Y', 'apapun'), 5)
})
