'use strict'

// Tahap 4 — simulasi demo Produk & Jasa CRUD + tipe/harga_beli + KASIR null beli.

const test = require('node:test')
const assert = require('node:assert/strict')

const demo = require('../src/main/demo.js')
const H = demo.handlers

test.beforeEach(() => { demo.start(); H['toko:select']({ id: 'TOKO-1' }) })
test.afterEach(() => { delete process.env.IPOS_SMOKE_ROLE })

test('create PRODUK muncul di list (tipe=SEMUA) dgn harga_beli', () => {
  const r = H['produk:create']({ nama: 'Roti Tawar', tipe: 'PRODUK', hargaBeli: 8000, hargaJual: 12000 })
  assert.equal(r.ok, true)
  assert.equal(r.data.tipe, 'PRODUK')
  assert.equal(r.data.harga_beli, 8000)
  assert.equal(r.data.kelola_stok, true)
  const list = H['produk:list']({ tipe: 'SEMUA', perPage: 100 }).data
  assert.ok(list.find((p) => p.id === r.data.id))
})

test('create JASA → kelola_stok false & harga_beli null', () => {
  const r = H['produk:create']({ nama: 'Jasa Antar', tipe: 'JASA', hargaJual: 15000 })
  assert.equal(r.data.tipe, 'JASA')
  assert.equal(r.data.kelola_stok, false)
  assert.equal(r.data.harga_beli, null)
})

test('create validasi: nama & harga jual wajib', () => {
  assert.equal(H['produk:create']({ nama: '', hargaJual: 1000 }).status, 422)
  assert.equal(H['produk:create']({ nama: 'X', hargaJual: -5 }).status, 422)
})

test('update kirim hanya field berubah', () => {
  const c = H['produk:create']({ nama: 'Item A', tipe: 'PRODUK', hargaBeli: 5000, hargaJual: 9000 })
  const u = H['produk:update']({ id: c.data.id, hargaJual: 11000 }) // hanya harga jual
  assert.equal(u.ok, true)
  assert.equal(u.data.harga_jual, 11000)
  assert.equal(u.data.harga_beli, 5000) // tak berubah
  assert.equal(u.data.nama, 'Item A')
})

test('remove menonaktifkan (hilang dari katalog demo)', () => {
  const c = H['produk:create']({ nama: 'Item Hapus', hargaJual: 9000 })
  assert.equal(H['produk:remove']({ id: c.data.id }).ok, true)
  assert.ok(!H['produk:list']({ tipe: 'SEMUA', perPage: 100 }).data.find((p) => p.id === c.data.id))
})

test('KASIR: produk:list menull-kan harga_beli (rahasia dagang)', () => {
  process.env.IPOS_SMOKE_ROLE = 'KASIR'
  const list = H['produk:list']({ tipe: 'SEMUA', perPage: 100 }).data
  assert.ok(list.length > 0)
  assert.ok(list.every((p) => p.harga_beli === null))
})

test('OWNER: produk:list menyertakan harga_beli', () => {
  const list = H['produk:list']({ tipe: 'PRODUK', perPage: 100 }).data
  assert.ok(list.some((p) => p.harga_beli != null))
})
