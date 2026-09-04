'use strict'

// Kolom uang berformat ribuan saat diketik (padanan RupiahInputFormatter
// Android) — tanpa mematikan singkatan kasir "350rb" / "1,5jt" (parseAmount).

const test = require('node:test')
const assert = require('node:assert/strict')

let r, f
test.before(async () => {
  r = await import('../src/renderer/js/utils/rupiah-input.js')
  f = await import('../src/renderer/js/utils/format.js')
})

test('formatRibuan: 50000 → 50.000, nol di depan dibuang', () => {
  assert.equal(r.formatRibuan('50000'), '50.000')
  assert.equal(r.formatRibuan('1250000'), '1.250.000')
  assert.equal(r.formatRibuan('007'), '7')
  assert.equal(r.formatRibuan('0'), '0')
  assert.equal(r.formatRibuan(''), '')
})

test('formatNilaiInput hanya menyentuh angka; singkatan kasir dibiarkan', () => {
  assert.equal(r.formatNilaiInput('50000'), '50.000')
  assert.equal(r.formatNilaiInput('50.000'), null, 'sudah rapi → tidak diubah')
  assert.equal(r.formatNilaiInput('350rb'), null)
  assert.equal(r.formatNilaiInput('1,5jt'), null)
  assert.equal(r.formatNilaiInput(''), null)
})

test('hasil format tetap terbaca parseAmount dengan nilai yang sama', () => {
  for (const raw of ['50000', '1250000', '999']) {
    assert.equal(f.parseAmount(r.formatRibuan(raw)), Number(raw))
  }
})

test('harga promo: harga_efektif dipakai hanya saat promo aktif', async () => {
  const h = await import('../src/renderer/js/utils/harga.js')
  assert.equal(h.hargaJual({ harga_jual: 4000, harga_efektif: 3500, promo_aktif: true }), 3500)
  assert.equal(h.hargaNormalSaatPromo({ harga_jual: 4000, harga_efektif: 3500, promo_aktif: true }), 4000)
  assert.equal(h.hargaJual({ harga_jual: 4000, harga_efektif: 4000, promo_aktif: false }), 4000)
  assert.equal(h.hargaNormalSaatPromo({ harga_jual: 4000, harga_efektif: 4000, promo_aktif: false }), null)
  assert.equal(h.hargaJual({ harga_jual: '18000' }), 18000)
  assert.equal(h.hargaJual(null), 0)
})
