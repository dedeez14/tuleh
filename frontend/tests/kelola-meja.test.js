'use strict'

// Kelola Meja (desktop 0.9.27): tambah / ubah nomor / nonaktifkan lewat mesin
// demo, mengikuti aturan server MOVERA — kode QR tidak berubah saat meja
// di-rename, dan meja dengan bon terbuka tidak boleh dinonaktifkan.

const test = require('node:test')
const assert = require('node:assert/strict')

const demo = require('../src/main/demo.js')

function mulai(tokoId = 'TOKO-2') {
  demo.start()
  demo.handlers['toko:select']({ id: tokoId })
}

test.beforeEach(() => mulai())

test('daftar meja: aktif saja; ?semua=1 memuat yang nonaktif', () => {
  const awal = demo.handlers['table:list']({})
  assert.equal(awal.ok, true)
  const jumlahAwal = awal.data.length
  assert.ok(jumlahAwal > 0)

  const target = awal.data[jumlahAwal - 1]
  const off = demo.handlers['table:nonaktifkan']({ id: target.id })
  assert.equal(off.ok, true, off.message)
  assert.equal(off.data.aktif, false)

  assert.equal(demo.handlers['table:list']({}).data.length, jumlahAwal - 1)
  assert.equal(demo.handlers['table:list']({ semua: true }).data.length, jumlahAwal)
})

test('tambah meja: nomor wajib, unik, dan langsung muncul di daftar', () => {
  assert.equal(demo.handlers['table:tambah']({ nomor: '  ' }).status, 422)

  const r = demo.handlers['table:tambah']({ nomor: '99' })
  assert.equal(r.ok, true, r.message)
  assert.equal(r.data.nomor, '99')
  assert.ok(r.data.kode, 'kode QR dibuat server')
  assert.ok(demo.handlers['table:list']({}).data.some((t) => t.nomor === '99'))

  const bentrok = demo.handlers['table:tambah']({ nomor: '99' })
  assert.equal(bentrok.status, 409)
  assert.match(bentrok.message, /sudah dipakai/i)
})

test('ubah nomor TIDAK mengubah kode QR (stiker yang tertempel tetap sah)', () => {
  const meja = demo.handlers['table:list']({}).data[0]
  const kodeLama = meja.kode

  const r = demo.handlers['table:ubah']({ id: meja.id, nomor: 'A1' })
  assert.equal(r.ok, true, r.message)
  assert.equal(r.data.nomor, 'A1')
  assert.equal(r.data.kode, kodeLama)

  assert.equal(demo.handlers['table:ubah']({ id: 'MEJA-TIDAK-ADA', nomor: 'X' }).status, 404)
})

test('meja dengan bon terbuka tidak bisa dinonaktifkan; pesannya menyebut bonnya', () => {
  // Mesin demo sudah menyemai beberapa bon berjalan — pakai salah satunya.
  const peta = demo.handlers['bill:peta']({})
  assert.equal(peta.ok, true)
  const terisi = peta.data.tables.find((m) => m.bill)
  assert.ok(terisi, 'demo bakso menyemai bon berjalan')

  const r = demo.handlers['table:nonaktifkan']({ id: terisi.id })
  assert.equal(r.status, 409)
  assert.match(r.message, new RegExp(`Meja ${terisi.nomor}`))
  assert.match(r.message, /belum dibayar/i)
  assert.equal(demo.handlers['table:list']({}).data.some((t) => t.id === terisi.id), true)
})

test('meja kosong bisa dinonaktifkan dan hilang dari peta kasir', () => {
  const peta = demo.handlers['bill:peta']({})
  const kosong = peta.data.tables.find((m) => !m.bill)
  assert.ok(kosong, 'ada meja tanpa bon')

  const r = demo.handlers['table:nonaktifkan']({ id: kosong.id })
  assert.equal(r.ok, true, r.message)
  assert.equal(demo.handlers['bill:peta']({}).data.tables.some((m) => m.id === kosong.id), false)
})
