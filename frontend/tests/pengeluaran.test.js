'use strict'

// Tahap 3 — simulasi demo Pengeluaran & Laporan Keuangan (server-backed).
// laba = omset − pengeluaran; input/hapus pengeluaran memengaruhi laba.

const test = require('node:test')
const assert = require('node:assert/strict')

const demo = require('../src/main/demo.js')
const H = demo.handlers

const bulanIni = () => new Date().toISOString().slice(0, 7)

test.before(() => { demo.start(); H['toko:select']({ id: 'TOKO-1' }) })

test('laporan keuangan: bentuk & laba = omset − pengeluaran', () => {
  const r = H['laporan:keuangan']({ bulan: bulanIni() })
  assert.equal(r.ok, true)
  const d = r.data
  for (const k of ['bulan', 'omset', 'jumlah_transaksi', 'pengeluaran', 'laba']) assert.ok(k in d, `ada ${k}`)
  assert.equal(d.laba, d.omset - d.pengeluaran)
})

test('list pengeluaran punya meta {bulan,total,jumlah} & tersegel per toko', () => {
  const r = H['pengeluaran:list']({ bulan: bulanIni() })
  assert.ok(r.meta && r.meta.bulan === bulanIni())
  assert.equal(typeof r.meta.total, 'number')
  assert.equal(r.meta.jumlah, r.data.length)
})

test('create pengeluaran menaikkan total & menurunkan laba; delete mengembalikan', () => {
  const bln = bulanIni()
  const sebelum = H['laporan:keuangan']({ bulan: bln }).data
  const c = H['pengeluaran:create']({ keterangan: 'UJI SEWA', nominal: 123000 })
  assert.equal(c.ok, true)
  assert.equal(c.data.nominal, 123000)
  const sesudah = H['laporan:keuangan']({ bulan: bln }).data
  assert.equal(sesudah.pengeluaran, sebelum.pengeluaran + 123000)
  assert.equal(sesudah.laba, sebelum.laba - 123000)
  // hapus → kembali
  assert.equal(H['pengeluaran:remove']({ id: c.data.id }).ok, true)
  const akhir = H['laporan:keuangan']({ bulan: bln }).data
  assert.equal(akhir.pengeluaran, sebelum.pengeluaran)
})

test('create pengeluaran validasi: keterangan & nominal wajib', () => {
  assert.equal(H['pengeluaran:create']({ keterangan: '', nominal: 1000 }).status, 422)
  assert.equal(H['pengeluaran:create']({ keterangan: 'X', nominal: 0 }).status, 422)
})

test('demo bulan berjalan menampilkan laba positif (UMKM sehat)', () => {
  const d = H['laporan:keuangan']({ bulan: bulanIni() }).data
  assert.ok(d.laba >= 0, `laba ${d.laba} harus >= 0`)
  assert.ok(d.pengeluaran > 0, 'ada contoh pengeluaran')
})
