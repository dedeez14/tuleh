'use strict'

// Pencarian Riwayat desktop (0.9.23): dijalankan atas baris yang sudah dimuat,
// sehingga tetap bekerja saat offline dan atas struk lokal belum sinkron.
// Padanan saring_riwayat.dart di Android.

const test = require('node:test')
const assert = require('node:assert/strict')

let C

const tunai = { id: '1', nomor: '26-POS-000041', grand_total: 18500, tipe_pembayaran: 'TUNAI', status: 'SELESAI' }
const qris = { id: '2', nomor: '26-POS-000042', grand_total: 25000, tipe_pembayaran: 'QRIS', status: 'SELESAI' }
const batal = { id: '3', nomor: '26-POS-000043', grand_total: 7000, metode_bayar: 'TRANSFER', status: 'DIBATALKAN' }
const lokal = { id: 'lokal:abc', nomor: 'L-260908-0001', total: 12000, tipe_pembayaran: 'TUNAI', status: 'BELUM_SINKRON', belum_sinkron: true }
const semua = [tunai, qris, batal, lokal]

const nomor = (rows) => rows.map((r) => r.nomor)

test.before(async () => {
  C = await import('../src/renderer/js/lib/cari-riwayat.js')
})

test('kueri kosong mengembalikan daftar apa adanya', () => {
  assert.equal(C.cariRiwayat(semua, ''), semua)
  assert.equal(C.cariRiwayat(semua, '   '), semua)
  assert.deepEqual(C.cariRiwayat(null, 'x'), [])
})

test('cocok sebagian nomor nota tanpa peduli huruf besar/kecil', () => {
  assert.deepEqual(nomor(C.cariRiwayat(semua, '000042')), ['26-POS-000042'])
  assert.deepEqual(nomor(C.cariRiwayat(semua, 'l-260908')), ['L-260908-0001'])
})

test('cocok metode bayar dari kedua nama field server', () => {
  assert.deepEqual(nomor(C.cariRiwayat(semua, 'qris')), ['26-POS-000042'])
  assert.deepEqual(nomor(C.cariRiwayat(semua, 'transfer')), ['26-POS-000043'])
})

test('cocok status, termasuk struk lokal yang belum sinkron', () => {
  assert.deepEqual(nomor(C.cariRiwayat(semua, 'belum_sinkron')), ['L-260908-0001'])
  assert.deepEqual(nomor(C.cariRiwayat(semua, 'dibatalkan')), ['26-POS-000043'])
})

test('nominal dinormalkan: "Rp 25.000" sama dengan "25000"', () => {
  assert.deepEqual(nomor(C.cariRiwayat(semua, '25000')), ['26-POS-000042'])
  assert.deepEqual(nomor(C.cariRiwayat(semua, 'Rp 25.000')), ['26-POS-000042'])
  // total dari field `total` (struk lokal) ikut dicari
  assert.deepEqual(nomor(C.cariRiwayat(semua, '12000')), ['L-260908-0001'])
})

test('angkaSaja membuang pemisah ribuan dan simbol', () => {
  assert.equal(C.angkaSaja('Rp 1.250,50'), '125050')
  assert.equal(C.angkaSaja(''), '')
  assert.equal(C.angkaSaja(null), '')
})

test('tidak ada yang cocok → daftar kosong; urutan asal dipertahankan', () => {
  assert.deepEqual(C.cariRiwayat(semua, 'zzz'), [])
  assert.deepEqual(nomor(C.cariRiwayat(semua, '000')), nomor(semua.filter((r) => r.nomor.includes('000'))))
})

test('baris rusak tidak melempar', () => {
  assert.deepEqual(C.cariRiwayat([null, undefined, {}], 'apa'), [])
})
