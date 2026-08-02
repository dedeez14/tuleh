'use strict'

// Tahap 2 — simulasi demo Inventory: stok masuk/opname mengubah stok & mengisi
// riwayat (jumlah bertanda); quick customer menormalkan no WA & pakai ulang.

const test = require('node:test')
const assert = require('node:assert/strict')

const demo = require('../src/main/demo.js')
const H = demo.handlers

function produkBerstok() {
  return H['produk:list']({ tipe: 'PRODUK', perPage: 100 }).data.find((p) => p.kelola_stok)
}

test.before(() => { demo.start(); H['toko:select']({ id: 'TOKO-1' }) })

test('stok-masuk menambah stok & menerbitkan entri MASUK', () => {
  const p = produkBerstok()
  const awal = p.stok
  const r = H['inventory:stokMasuk']({ idProduk: p.id, jumlah: 5 })
  assert.equal(r.ok, true)
  assert.equal(r.data.tipe, 'MASUK')
  assert.equal(r.data.jumlah, 5)
  assert.equal(r.data.stok_sekarang, awal + 5)
  const riw = H['inventory:riwayat']({ perPage: 5 })
  assert.equal(riw.data[0].tipe, 'MASUK')
  assert.equal(riw.data[0].jumlah, 5) // bertanda positif
  assert.ok(riw.meta && typeof riw.meta.total === 'number')
})

test('opname mengurangi stok dgn jumlah bertanda negatif', () => {
  const p = produkBerstok()
  const awal = p.stok
  const r = H['inventory:opname']({ idProduk: p.id, jumlah: 2 })
  assert.equal(r.ok, true)
  assert.equal(r.data.tipe, 'OPNAME')
  assert.equal(r.data.jumlah, -2)
  assert.equal(r.data.stok_sekarang, awal - 2)
  assert.equal(H['inventory:riwayat']({ perPage: 1 }).data[0].jumlah, -2)
})

test('opname melebihi stok → 422 dengan pesan jelas', () => {
  const p = produkBerstok()
  const r = H['inventory:opname']({ idProduk: p.id, jumlah: p.stok + 9999 })
  assert.equal(r.ok, false)
  assert.equal(r.status, 422)
  assert.match(r.message, /tidak mencukupi/i)
})

test('stok-masuk untuk item JASA → 422 (tanpa gudang)', () => {
  H['toko:select']({ id: 'TOKO-3' }) // laundry = JASA
  const jasa = H['produk:list']({ perPage: 100 }).data[0]
  const r = H['inventory:stokMasuk']({ idProduk: jasa.id, jumlah: 3 })
  assert.equal(r.ok, false)
  assert.equal(r.status, 422)
  H['toko:select']({ id: 'TOKO-1' })
})

test('pelanggan quick: normalkan 08→62, wa_link, dan pakai ulang nomor', () => {
  const r = H['pelanggan:quick']({ nama: 'Ibu Sari', noWhatsapp: '0812-3456-7890' })
  assert.equal(r.ok, true)
  assert.equal(r.data.telepon, '6281234567890')
  assert.match(r.data.wa_link, /wa\.me\/6281234567890$/)
  const lagi = H['pelanggan:quick']({ nama: 'Ibu Sari (lagi)', noWhatsapp: '+6281234567890' })
  assert.equal(lagi.data.id, r.data.id) // nomor sama → pelanggan yang sama
})

test('produk:list tipe=PRODUK tak mengembalikan JASA', () => {
  H['toko:select']({ id: 'TOKO-3' })
  const prod = H['produk:list']({ tipe: 'PRODUK', perPage: 100 }).data
  assert.ok(prod.every((p) => p.tipe !== 'JASA'))
  H['toko:select']({ id: 'TOKO-1' })
})
