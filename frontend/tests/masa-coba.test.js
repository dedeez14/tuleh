'use strict'

// Masa coba Mode Demo 7 hari, dihitung dengan waktu server (Blueprint:
// pembatasan demo agar pengguna beralih ke akun berbayar).

const test = require('node:test')
const assert = require('node:assert/strict')
const mc = require('../src/main/lib/masa-coba.js')

const ID = 'mesin-uji'
const T0 = new Date('2026-09-05T03:00:00Z')
const hari = (n) => new Date(T0.getTime() + n * mc.HARI_MS)

test('mulai pertama kali WAJIB waktu server', () => {
  const tanpa = mc.periksa({ catatan: null, waktuServer: null, perangkat: T0, identitas: ID, mulaiBaru: true })
  assert.equal(tanpa.kode, 'BUTUH_KONEKSI')
  const dengan = mc.periksa({ catatan: null, waktuServer: T0, perangkat: hari(-30), identitas: ID, mulaiBaru: true })
  assert.equal(dengan.kode, 'AKTIF')
  assert.equal(dengan.sisaHari, 7)
  assert.equal(dengan.catatan.mulai, T0.toISOString(), 'mulai dari server, bukan jam perangkat')
})

test('hari ke-1 sampai ke-7 aktif, hari ke-8 berakhir', () => {
  const cat = mc.buatCatatan({ mulai: T0, identitas: ID })
  assert.equal(mc.periksa({ catatan: cat, waktuServer: hari(0.5), perangkat: hari(0.5), identitas: ID }).sisaHari, 7)
  assert.equal(mc.periksa({ catatan: cat, waktuServer: hari(6.5), perangkat: hari(6.5), identitas: ID }).sisaHari, 1)
  const akhir = mc.periksa({ catatan: cat, waktuServer: hari(7), perangkat: hari(7), identitas: ID })
  assert.equal(akhir.kode, 'BERAKHIR')
  assert.equal(akhir.sisaHari, 0)
})

test('offline: jam perangkat dimundurkan tidak memperpanjang masa coba', () => {
  let cat = mc.buatCatatan({ mulai: T0, identitas: ID })
  // Terlihat server pada hari ke-6 → serverTerakhir maju.
  const h6 = mc.periksa({ catatan: cat, waktuServer: hari(6), perangkat: hari(6), identitas: ID })
  cat = h6.catatan
  assert.equal(cat.serverTerakhir, hari(6).toISOString())
  // Offline, jam perangkat dimundurkan ke hari ke-1 → tetap dihitung hari ke-6.
  const curang = mc.periksa({ catatan: cat, waktuServer: null, perangkat: hari(1), identitas: ID })
  assert.equal(curang.sumberWaktu, 'server_terakhir')
  assert.equal(curang.sisaHari, 1)
  // Offline, jam perangkat maju ke hari ke-9 → berakhir (memajukan hanya merugikan diri sendiri).
  const maju = mc.periksa({ catatan: cat, waktuServer: null, perangkat: hari(9), identitas: ID })
  assert.equal(maju.kode, 'BERAKHIR')
})

test('catatan yang diubah tangan → RUSAK (dianggap berakhir)', () => {
  const cat = mc.buatCatatan({ mulai: T0, identitas: ID })
  const diubah = { ...cat, mulai: hari(30).toISOString() }
  assert.equal(mc.periksa({ catatan: diubah, waktuServer: hari(1), perangkat: hari(1), identitas: ID }).kode, 'RUSAK')
  // Catatan dari mesin lain (identitas berbeda) juga tidak sah.
  assert.equal(mc.periksa({ catatan: cat, waktuServer: hari(1), perangkat: hari(1), identitas: 'mesin-lain' }).kode, 'RUSAK')
  assert.equal(mc.periksa({ catatan: 'bukan objek', waktuServer: hari(1), perangkat: hari(1), identitas: ID }).kode, 'RUSAK')
})

test('pemeriksaan tanpa mulaiBaru pada perangkat yang belum pernah demo → aktif, tanpa catatan', () => {
  const r = mc.periksa({ catatan: null, waktuServer: null, perangkat: T0, identitas: ID })
  assert.equal(r.kode, 'AKTIF')
  assert.equal(r.belumMulai, true)
  assert.equal(r.catatan, null)
})

// ---- Lapis 2/3: gabungan dengan jawaban server /demo/perangkat ----

test('server tak ada (null) → hasil lokal apa adanya', () => {
  const cat = mc.buatCatatan({ mulai: T0, identitas: ID })
  const lokal = mc.periksa({ catatan: cat, waktuServer: hari(1), perangkat: hari(1), identitas: ID })
  assert.deepEqual(mc.gabungkan(lokal, null, { identitas: ID }), lokal)
})

test('server mengenal perangkat dengan mulai lebih awal → masa coba mengikuti server (pasang ulang tidak mengulang)', () => {
  // Aplikasi baru dipasang ulang: lokal belum punya catatan (mulaiBaru dengan waktu server hari ke-6).
  const lokal = mc.periksa({ catatan: null, waktuServer: hari(6), perangkat: hari(6), identitas: ID, mulaiBaru: true })
  assert.equal(lokal.sisaHari, 7, 'lokal mengira baru mulai')
  const server = { status: 'AKTIF', butuh_identitas: false, mulai: T0.toISOString(), berakhir_pada: hari(7).toISOString(), sisa_hari: 1, waktu_server: hari(6).toISOString() }
  const g = mc.gabungkan(lokal, server, { identitas: ID })
  assert.equal(g.kode, 'AKTIF')
  assert.equal(g.sisaHari, 1)
  assert.equal(g.catatan.mulai, T0.toISOString(), 'catatan lokal ditulis ulang dengan mulai server')
  assert.equal(mc.catatanSah(g.catatan, ID), true)
})

test('server menyatakan BERAKHIR / DIBLOKIR → menang atas lokal', () => {
  const lokal = mc.periksa({ catatan: null, waktuServer: hari(1), perangkat: hari(1), identitas: ID, mulaiBaru: true })
  const berakhir = mc.gabungkan(lokal, { status: 'BERAKHIR', mulai: hari(-10).toISOString(), waktu_server: hari(1).toISOString() }, { identitas: ID })
  assert.equal(berakhir.kode, 'BERAKHIR')
  assert.equal(berakhir.sisaHari, 0)
  const blokir = mc.gabungkan(lokal, { status: 'DIBLOKIR', waktu_server: hari(1).toISOString() }, { identitas: ID })
  assert.equal(blokir.kode, 'DIBLOKIR')
})

test('server minta identitas → BUTUH_IDENTITAS (aplikasi menjalankan OTP)', () => {
  const lokal = mc.periksa({ catatan: null, waktuServer: hari(0), perangkat: hari(0), identitas: ID, mulaiBaru: true })
  const g = mc.gabungkan(lokal, { status: 'BELUM_VERIFIKASI', butuh_identitas: true, mulai: null, waktu_server: hari(0).toISOString() }, { identitas: ID })
  assert.equal(g.kode, 'BUTUH_IDENTITAS')
})

test('mulai lokal lebih awal dari server → lokal yang dipakai (tidak ada yang bisa "memundurkan" ke server)', () => {
  const cat = mc.buatCatatan({ mulai: hari(-3), identitas: ID })
  const lokal = mc.periksa({ catatan: cat, waktuServer: hari(0), perangkat: hari(0), identitas: ID })
  const g = mc.gabungkan(lokal, { status: 'AKTIF', mulai: hari(0).toISOString(), waktu_server: hari(0).toISOString() }, { identitas: ID })
  assert.equal(g.sisaHari, 4)
  assert.equal(g.catatan.mulai, hari(-3).toISOString())
})

test('pilihCatatan: dari beberapa salinan, yang sah dengan mulai paling awal', () => {
  const awal = mc.buatCatatan({ mulai: hari(-5), identitas: ID })
  const baru = mc.buatCatatan({ mulai: hari(0), identitas: ID })
  const palsu = { ...mc.buatCatatan({ mulai: hari(-30), identitas: ID }), tanda: 'x' }
  assert.equal(mc.pilihCatatan([baru, palsu, awal], ID).mulai, awal.mulai)
  assert.equal(mc.pilihCatatan([palsu], ID), null)
  assert.equal(mc.pilihCatatan([], ID), null)
})
