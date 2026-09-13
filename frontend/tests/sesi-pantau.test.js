'use strict'

// Pantau Sesi Kasir (0.9.33): satu toko banyak kasir, tiap kasir bersesi sendiri.
// Server mengirim sesi SEMUA kasir toko ke Owner/Manager (dengan milik_saya), Kasir hanya miliknya.

const test = require('node:test')
const assert = require('node:assert/strict')

let S

test.before(async () => {
  S = await import('../src/renderer/js/lib/sesi-pantau.js')
})

const saya = { id: 'a', nomor: 'SK-001', status: 'BUKA', kasir: 'Manager', milik_saya: true, jumlah_transaksi: 1, total_penjualan: 10000 }
const ani = { id: 'b', nomor: 'SK-002', status: 'BUKA', kasir: 'Ani', milik_saya: false, jumlah_transaksi: 3, total_penjualan: 45000 }
const budiTutup = { id: 'c', nomor: 'SK-003', status: 'TUTUP', kasir: 'Budi', milik_saya: false, jumlah_transaksi: 5, total_penjualan: 90000 }

test('sesiAktifSaya: TIDAK pernah memilih sesi kasir lain walau hanya itu yang buka', () => {
  assert.equal(S.sesiAktifSaya([ani, budiTutup], null), null)
  assert.equal(S.sesiAktifSaya([ani, budiTutup], { nomor: 'SK-002' }), null, 'nomor cocok tapi milik kasir lain')
})

test('sesiAktifSaya: cocok nomor sesi aktif, atau satu-satunya sesi buka milik sendiri', () => {
  assert.equal(S.sesiAktifSaya([ani, saya], { nomor: 'SK-001' }), saya)
  assert.equal(S.sesiAktifSaya([ani, saya], null), saya)
})

test('sesiAktifSaya: server lama tanpa milik_saya tetap memakai pencocokan nomor', () => {
  const lama = { id: 'z', nomor: 'SK-009', status: 'BUKA' }
  assert.equal(S.sesiAktifSaya([lama], { nomor: 'SK-009' }), lama)
})

test('ringkasSesi: jumlah kasir bertugas & penjualan sesi berjalan', () => {
  assert.deepEqual(S.ringkasSesi([saya, ani, budiTutup]), { berjalan: 2, transaksiBerjalan: 4, penjualanBerjalan: 55000 })
  assert.deepEqual(S.ringkasSesi(null), { berjalan: 0, transaksiBerjalan: 0, penjualanBerjalan: 0 })
})

test('saringStatusSesi: kosong = semua, BUKA/TUTUP = sesuai status', () => {
  const rows = [saya, ani, budiTutup]
  assert.equal(S.saringStatusSesi(rows, ''), rows)
  assert.deepEqual(S.saringStatusSesi(rows, 'TUTUP'), [budiTutup])
})

test('bolehTutupDariDaftar: sesi sendiri lewat kartu atas; sesi lain butuh wewenang', () => {
  assert.equal(S.bolehTutupDariDaftar(ani, true), true)
  assert.equal(S.bolehTutupDariDaftar(ani, false), false)
  assert.equal(S.bolehTutupDariDaftar(saya, true), false, 'sesi sendiri ditutup dari kartu sesi aktif')
  assert.equal(S.bolehTutupDariDaftar(budiTutup, true), false)
})
