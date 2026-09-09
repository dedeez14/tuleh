'use strict'

// Penjualan terukur (per kilo / per nominal). Aturan pembulatannya sama persis
// dengan sisi Android — lihat PENJUALAN-TERUKUR.md.

const test = require('node:test')
const assert = require('node:assert/strict')

let S

test.before(async () => {
  S = await import('../src/renderer/js/lib/satuan-terukur.js')
})

test('satuan terukur dikenali; yang lain diperlakukan seperti biasa', () => {
  for (const s of ['kg', 'Kg', ' KG ', 'liter', 'gram', 'ons', 'meter', 'ml']) {
    assert.equal(S.apakahTerukur(s), true, s)
  }
  for (const s of ['pcs', 'pack', 'porsi', '', null, undefined, 'butir']) {
    assert.equal(S.apakahTerukur(s), false, String(s))
  }
  assert.equal(S.langkahSatuan('kg'), 0.01)
  assert.equal(S.langkahSatuan('pcs'), 1, 'barang hitungan: langkah 1')
})

test('pembulatan kuantitas mengikuti langkah satuan', () => {
  assert.equal(S.bulatkanKuantitas(0.744, 'kg'), 0.74)
  assert.equal(S.bulatkanKuantitas(0.746, 'kg'), 0.75)
  assert.equal(S.bulatkanKuantitas(2.5, 'ons'), 2.5)
  assert.equal(S.bulatkanKuantitas(255, 'gram'), 260, 'gram melangkah 10')
  // Tidak boleh muncul ekor floating point.
  assert.equal(S.bulatkanKuantitas(0.3, 'kg'), 0.3)
  assert.equal(S.bulatkanKuantitas(0, 'kg'), 0)
  assert.equal(S.bulatkanKuantitas(-2, 'kg'), 0)
})

test('nominal → kuantitas dibulatkan KE BAWAH agar tak melebihi uang pelanggan', () => {
  // Mangga Rp 27.000/kg, pelanggan minta Rp 20.000.
  const qty = S.kuantitasDariNominal(20000, 27000, 'kg')
  assert.equal(qty, 0.74)
  assert.equal(S.totalBaris(qty, 27000), 19980)
  assert.ok(S.totalBaris(qty, 27000) <= 20000, 'tidak pernah melebihi nominal')

  // Pembagian bulat tetap bulat.
  assert.equal(S.kuantitasDariNominal(50000, 25000, 'kg'), 2)
})

test('nominal di bawah satu langkah ditolak (0) dan minimalnya bisa disebutkan', () => {
  assert.equal(S.kuantitasDariNominal(200, 27000, 'kg'), 0)
  assert.equal(S.minimalNominal(27000, 'kg'), 270)
  assert.equal(S.minimalNominal(12500, 'kg'), 125)
})

test('harga tak sah tidak pernah membagi nol', () => {
  assert.equal(S.kuantitasDariNominal(20000, 0, 'kg'), 0)
  assert.equal(S.kuantitasDariNominal(20000, -5, 'kg'), 0)
  assert.equal(S.kuantitasDariNominal(0, 27000, 'kg'), 0)
})

test('uang selalu bulat rupiah', () => {
  assert.equal(S.totalBaris(0.74, 27000), 19980)
  assert.equal(S.totalBaris(0.333, 10000), 3330)
  assert.equal(S.totalBaris(1.005, 999), 1004) // 1003.995 → 1004
})
