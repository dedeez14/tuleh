'use strict'

// Label tahap lifecycle di papan pesanan. Dipisah ke lib murni supaya bisa
// diuji tanpa DOM/bridge (orders.js mengimpor api.js yang butuh window.iposAPI).

const test = require('node:test')
const assert = require('node:assert/strict')

let mod

test.before(async () => {
  mod = await import('../src/renderer/js/lib/stage-label.js')
})

test('stageLabel: tahap jasa baru (bengkel/salon/cuci kendaraan) punya label manusiawi', () => {
  assert.equal(mod.stageLabel('PEMERIKSAAN'), 'Pemeriksaan')
  assert.equal(mod.stageLabel('PENGERJAAN'), 'Pengerjaan')
  assert.equal(mod.stageLabel('DILAYANI'), 'Dilayani')
  // Fallback Title Case akan memberi "Finishing" — label server "Finishing & Poles".
  assert.equal(mod.stageLabel('FINISHING'), 'Finishing & Poles')
})

test('stageLabel: label lama tetap, tahap tak dikenal jadi Title Case, kosong aman', () => {
  assert.equal(mod.stageLabel('SIAP_AMBIL'), 'Siap Diambil')
  assert.equal(mod.stageLabel('MENUNGGU_BAYAR'), 'Menunggu Bayar')
  assert.equal(mod.stageLabel('READY'), 'Siap')
  assert.equal(mod.stageLabel('TAHAP_BARU_X'), 'Tahap Baru X')
  assert.equal(mod.stageLabel(''), '')
  assert.equal(mod.stageLabel(undefined), '')
})
