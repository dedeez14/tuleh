'use strict'

// `waktu_klien` yang dikirim ke server MOVERA.
//
// Server menyimpannya apa adanya ke kolom MySQL `datetime`
// (`client_created_at`). Nilai dari `toISOString()` — "2026-09-12T07:25:40.635Z"
// — ditolak dengan SQLSTATE[22007] 1292 "Incorrect datetime value", dan seluruh
// transaksi gagal: kasir tidak bisa menyelesaikan penjualan. Uji ini menjaga
// formatnya (waktu lokal kasir, detik penuh, tanpa zona).

const test = require('node:test')
const assert = require('node:assert/strict')

const { waktuKlien, badanWaktuRapi } = require('../src/main/offline/antrean')

test('waktuKlien: waktu lokal kasir, detik penuh, tanpa zona & milidetik', () => {
  assert.equal(waktuKlien(new Date(2026, 8, 12, 14, 25, 41, 635)), '2026-09-12T14:25:41')
  assert.equal(waktuKlien(new Date(2026, 0, 5, 7, 8, 9)), '2026-01-05T07:08:09')
})

test('waktuKlien: tanpa argumen tetap berformat sama & tanpa "Z"', () => {
  const teks = waktuKlien()
  assert.match(teks, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$/)
  assert.ok(!teks.includes('Z'))
})

test('badanWaktuRapi: baris antrean lama (…Z) dirapikan ke jam toko', () => {
  const utc = new Date('2026-09-12T07:25:40.635Z')
  const badan = badanWaktuRapi({ items: [], waktu_klien: '2026-09-12T07:25:40.635Z' })
  assert.equal(badan.waktu_klien, waktuKlien(utc))
  assert.match(badan.waktu_klien, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$/)
})

test('badanWaktuRapi: badan tanpa/dengan waktu tak terbaca dibiarkan apa adanya', () => {
  const tanpa = { items: [] }
  assert.equal(badanWaktuRapi(tanpa), tanpa, 'objek yang sama, tanpa salinan sia-sia')
  assert.equal(badanWaktuRapi({ waktu_klien: 'entah' }).waktu_klien, 'entah')
  const sudahRapi = { waktu_klien: '2026-09-12T14:25:41' }
  assert.equal(badanWaktuRapi(sudahRapi), sudahRapi)
})
