'use strict'

// firstError() memilih KALIMAT untuk kasir, bukan kode mesin: amplop 409 SESI_BEDA_TOKO hanya
// membawa errors.kode = ['SESI_BEDA_TOKO'] — yang boleh dibaca program, bukan dipampang di layar.

const test = require('node:test')
const assert = require('node:assert/strict')

let A
test.before(async () => {
  globalThis.window = { iposAPI: {} } // api.js butuh jembatan preload saat diimpor
  A = await import('../src/renderer/js/api.js')
})
test.after(() => { delete globalThis.window })

test('kode mesin dilewati, pesan server yang tampil', () => {
  assert.equal(A.firstError({
    ok: false, status: 409, message: 'Sesi kasir Anda dibuka di toko Toko Pusat.',
    errors: { kode: ['SESI_BEDA_TOKO'] }
  }), 'Sesi kasir Anda dibuka di toko Toko Pusat.')
  // Kunci lain yang nilainya kode mesin (huruf besar/underscore) juga bukan kalimat.
  assert.equal(A.firstError({
    ok: false, status: 402, message: 'Langganan berakhir.', errors: { langganan: ['BERAKHIR'] }
  }), 'Langganan berakhir.')
})

test('galat validasi 422 tetap menampilkan pesan bidangnya', () => {
  assert.equal(A.firstError({
    ok: false, status: 422, message: 'Data tidak valid.',
    errors: { kode: ['SESI_BEDA_TOKO'], kuantitas: ['Kuantitas harus lebih dari 0.'] }
  }), 'Kuantitas harus lebih dari 0.', 'kunci kode dilewati, bidang berikutnya dipakai')
  assert.equal(A.firstError({
    ok: false, status: 422, message: 'Data tidak valid.', errors: { nama: ['Nama wajib diisi.'] }
  }), 'Nama wajib diisi.')
})

test('tanpa errors & tanpa message tetap ada kalimat', () => {
  assert.equal(A.firstError({ ok: false, status: 500, message: '', errors: null }), 'Terjadi kesalahan.')
  assert.equal(A.firstError({ ok: true, data: null }), '')
  assert.equal(A.firstError(null), '')
})
