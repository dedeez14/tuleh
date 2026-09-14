'use strict'

// Kontrak kanal untuk produk per toko & mode jual (server 2026-09-14): nominal ikut checkout, mode jual bisa
// dikembalikan ke otomatis, dan toko produk lewat /produk-toko/{id} (bukan /produk/{id}/toko — bentrok di gateway Go).

const test = require('node:test')
const assert = require('node:assert/strict')
const kontrak = require('../src/shared/kontrak-kanal.js')

test('checkout membawa nominal hanya pada baris per rupiah', () => {
  const m = kontrak.bentuk('trx:checkout', {
    items: [
      { idProduk: 'A', harga: 7000, kuantitas: 2.85, nominal: 20000 },
      { idProduk: 'B', harga: 5000, kuantitas: 2 }
    ],
    tipePembayaran: 'TUNAI',
    dibayar: 30000
  })
  const baris = JSON.parse(JSON.stringify(m.body.items))
  assert.equal(baris[0].nominal, 20000)
  assert.equal(baris[0].kuantitas, 2.85, 'kuantitas tetap dikirim untuk server lama')
  assert.equal('nominal' in baris[1], false)
})

test('produk:update — mode jual null = kembali otomatis, tidak disebut = tidak diubah', () => {
  const kosong = JSON.parse(JSON.stringify(kontrak.bentuk('produk:update', { id: 'P1', modeJual: null }).body))
  assert.deepEqual(kosong, { mode_jual: null })
  const tanpa = JSON.parse(JSON.stringify(kontrak.bentuk('produk:update', { id: 'P1', nama: 'Beras' }).body))
  assert.deepEqual(tanpa, { nama: 'Beras' })
  const satuan = JSON.parse(JSON.stringify(kontrak.bentuk('produk:update', { id: 'P1', satuanId: 'S9', modeJual: 'UKUR_NOMINAL' }).body))
  assert.deepEqual(satuan, { satuan_id: 'S9', mode_jual: 'UKUR_NOMINAL' })
})

test('produk:create membawa satuan, mode jual, dan toko', () => {
  const body = JSON.parse(JSON.stringify(kontrak.bentuk('produk:create', {
    nama: 'Cuci Kiloan', tipe: 'JASA', hargaJual: 7000, satuanId: 'S-KG', modeJual: 'UKUR_NOMINAL', tokoIds: ['T1']
  }).body))
  assert.equal(body.satuan_id, 'S-KG')
  assert.equal(body.mode_jual, 'UKUR_NOMINAL')
  assert.deepEqual(body.toko_ids, ['T1'])
})

test('toko produk & master mode jual', () => {
  assert.deepEqual(kontrak.bentuk('produk:toko', { id: 'P1' }), { metode: 'GET', jalur: '/produk-toko/P1', query: undefined })
  const put = kontrak.bentuk('produk:aturToko', { id: 'P1', tokoIds: [] })
  assert.equal(put.metode, 'PUT')
  assert.equal(put.jalur, '/produk-toko/P1')
  assert.deepEqual(put.body, { toko_ids: [] })
  assert.throws(() => kontrak.bentuk('produk:aturToko', { id: 'P1' }))
  assert.equal(kontrak.bentuk('master:modeJual', {}).jalur, '/mode-jual')
})
