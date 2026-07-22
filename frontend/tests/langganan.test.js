'use strict'

// Unit test turunan status langganan (Sistem Mitra §6.5).
// ringkasLangganan() dipakai bersama oleh notifikasi & banner Beranda.

const test = require('node:test')
const assert = require('node:assert/strict')

let L
test.before(async () => {
  L = await import('../src/renderer/js/langganan.js')
})

test('data kosong/null → level none, tanpa aksi', () => {
  // Arrange & Act
  const r = L.ringkasLangganan(null)
  // Assert
  assert.equal(r.level, 'none')
  assert.equal(r.perluAksi, false)
})

test('aktif dengan sisa banyak → ok, tanpa aksi', () => {
  const r = L.ringkasLangganan({ status: 'AKTIF', sisa_hari: 21, plan_nama: 'Tuléh Pro' })
  assert.equal(r.level, 'ok')
  assert.equal(r.perluAksi, false)
})

test('aktif dengan sisa <= ambang → segera + perlu aksi + detail menyebut hari', () => {
  const r = L.ringkasLangganan({ status: 'AKTIF', sisa_hari: L.AMBANG_PERINGATAN_HARI, plan_nama: 'Pro' })
  assert.equal(r.level, 'segera')
  assert.equal(r.perluAksi, true)
  assert.match(r.detail, new RegExp(`${L.AMBANG_PERINGATAN_HARI} hari`))
})

test('status GRACE → perlu aksi', () => {
  const r = L.ringkasLangganan({ status: 'GRACE', sisa_hari: 0 })
  assert.equal(r.level, 'grace')
  assert.equal(r.perluAksi, true)
})

test('status KEDALUWARSA → perlu aksi', () => {
  const r = L.ringkasLangganan({ status: 'KEDALUWARSA', sisa_hari: 0 })
  assert.equal(r.level, 'kedaluwarsa')
  assert.equal(r.perluAksi, true)
})

test('aktif tapi sisa_hari tak valid → tetap ok (tak memicu peringatan)', () => {
  const r = L.ringkasLangganan({ status: 'AKTIF', sisa_hari: null })
  assert.equal(r.level, 'ok')
  assert.equal(r.perluAksi, false)
})

test('status huruf kecil tetap dikenali (case-insensitive)', () => {
  const r = L.ringkasLangganan({ status: 'kedaluwarsa', sisa_hari: 0 })
  assert.equal(r.level, 'kedaluwarsa')
})
