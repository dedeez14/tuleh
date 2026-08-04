'use strict'

// Tahap 6 — simulasi demo pembayaran langganan (Midtrans Snap). bayar → invoice
// + redirect_url; status berubah AKTIF (periode baru) setelah jeda webhook demo.

const test = require('node:test')
const assert = require('node:assert/strict')

const demo = require('../src/main/demo.js')
const H = demo.handlers

test.beforeEach(() => { delete process.env.IPOS_SMOKE_LANGGANAN; demo.start() })

test('bayar mengembalikan invoice + redirect_url (kontrak §2)', () => {
  const r = H['langganan:bayar']()
  assert.equal(r.ok, true)
  assert.ok(r.data.invoice && typeof r.data.invoice.nomor === 'string')
  assert.equal(typeof r.data.invoice.harga_total, 'number')
  assert.match(String(r.data.pembayaran.redirect_url), /^https:\/\//)
})

test('status tetap "menunggu" tepat setelah bayar (belum lunas)', () => {
  const sebelum = H['langganan:status']().data.sisa_hari
  H['langganan:bayar']()
  const segera = H['langganan:status']().data.sisa_hari
  assert.equal(segera, sebelum) // < jeda webhook → belum berubah
})

test('setelah jeda webhook → status AKTIF, periode diperpanjang', async () => {
  H['langganan:bayar']()
  await new Promise((r) => setTimeout(r, 3100))
  const s = H['langganan:status']().data
  assert.equal(s.status, 'AKTIF')
  assert.equal(s.sisa_hari, 30)
  assert.ok(s.periode_akhir) // periode baru terisi
})

test('reset demo membersihkan status "lunas"', async () => {
  H['langganan:bayar']()
  await new Promise((r) => setTimeout(r, 3100))
  assert.equal(H['langganan:status']().data.sisa_hari, 30)
  demo.start() // re-seed → demoLunasAt = 0
  assert.notEqual(H['langganan:status']().data.sisa_hari, 30)
})
