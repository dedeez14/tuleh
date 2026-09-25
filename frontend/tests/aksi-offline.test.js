'use strict'

// Gerbang tombol Batal/Refund di Riwayat (Fase 4; renderer yang sama dipakai desktop & Android Capacitor):
// offline hanya di platform berantrean & hanya dengan hak sendiri (token PIN butuh server); transaksi lokal
// selalu lewat antrean; Batal disembunyikan untuk pelunasan pesanan.

const test = require('node:test')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')

let A
test.before(async () => { A = await import('../src/renderer/js/lib/aksi-offline.js') })

test('online → jalur biasa (PIN atasan bila perlu), tidak diantrekan', () => {
  assert.deepEqual(A.putusanAksi({ aksi: 'transaksi.batal', online: true, antreanOffline: true, punyaHak: false, lokal: false }), { boleh: true, antre: false, pesan: null })
  assert.deepEqual(A.putusanAksi({ aksi: 'transaksi.refund', online: undefined, antreanOffline: false, punyaHak: false, lokal: false }), { boleh: true, antre: false, pesan: null }, 'status belum diketahui = anggap online (perilaku lama)')
})

test('offline desktop: punya hak → diantrekan; tanpa hak → butuh persetujuan (hanya online)', () => {
  assert.deepEqual(A.putusanAksi({ aksi: 'transaksi.refund', online: false, antreanOffline: true, punyaHak: true, lokal: false }), { boleh: true, antre: true, pesan: null })
  const r = A.putusanAksi({ aksi: 'transaksi.batal', online: false, antreanOffline: true, punyaHak: false, lokal: false })
  assert.equal(r.boleh, false)
  assert.equal(r.pesan, 'Butuh persetujuan atasan — hanya bisa saat online.')
})

test('offline Android (tanpa antrean) → pesan lama per aksi', () => {
  assert.equal(A.putusanAksi({ aksi: 'transaksi.refund', online: false, antreanOffline: false, punyaHak: true, lokal: false }).pesan, 'Refund hanya bisa dilakukan saat terhubung ke server.')
  assert.equal(A.putusanAksi({ aksi: 'transaksi.batal', online: false, antreanOffline: false, punyaHak: true, lokal: false }).pesan, 'Pembatalan hanya bisa dilakukan saat terhubung ke server.')
})

test('transaksi lokal: selalu lewat antrean (online maupun offline) dan butuh hak sendiri', () => {
  assert.deepEqual(A.putusanAksi({ aksi: 'transaksi.batal', online: true, antreanOffline: true, punyaHak: true, lokal: true }), { boleh: true, antre: true, pesan: null })
  assert.match(A.putusanAksi({ aksi: 'transaksi.refund', online: true, antreanOffline: true, punyaHak: false, lokal: true }).pesan, /tunggu transaksi ini tersinkron/)
  assert.equal(A.putusanAksi({ aksi: 'transaksi.refund', online: false, antreanOffline: false, punyaHak: true, lokal: true }).boleh, false)
})

test('tampilkanBatal: dibatalkan / pelunasan pesanan / ber-uang-muka disembunyikan', () => {
  assert.equal(A.tampilkanBatal({ status: 'SELESAI' }), true)
  assert.equal(A.tampilkanBatal({ status: 'DIBATALKAN' }), false)
  assert.equal(A.tampilkanBatal({ status: 'SELESAI', pelunasan_pesanan: true }), false)
  assert.equal(A.tampilkanBatal({ status: 'SELESAI', uang_muka: 10000 }), false)
  assert.equal(A.tampilkanBatal({ status: 'BELUM SINKRON', belum_sinkron: true }), true)
  assert.equal(A.tampilkanBatal(null), false)
})

test('adalahLokal: id lokal: atau penanda belum_sinkron', () => {
  assert.equal(A.adalahLokal({ id: 'lokal:abc' }), true)
  assert.equal(A.adalahLokal({ id: 'T1', belum_sinkron: true }), true)
  assert.equal(A.adalahLokal({ id: 'T1' }), false)
  assert.equal(A.adalahLokal(null), false)
})

test('Riwayat memakai gerbang aksi offline & tidak lagi mengirim waktu toISOString()', () => {
  const src = fs.readFileSync(path.join(__dirname, '../src/renderer/js/screens/history.js'), 'utf8')
  assert.match(src, /putusanAksi\(\{ aksi: 'transaksi\.refund'/)
  assert.match(src, /putusanAksi\(\{ aksi: 'transaksi\.batal'/)
  assert.match(src, /tampilkanBatal\(struk\)/)
  assert.doesNotMatch(src, /toISOString\(\)/)
})
