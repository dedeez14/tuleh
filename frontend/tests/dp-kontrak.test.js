'use strict'

// Kontrak kanal nota bayar-nanti & uang muka (server Fase 3 2026-09-22) — satu kontrak dipakai desktop (ipc.js)
// dan Android Capacitor (mobile-bridge.js).

const test = require('node:test')
const assert = require('node:assert/strict')
const kontrak = require('../src/shared/kontrak-kanal.js')

const items = [{ idProduk: 'P1', harga: 28000, kuantitas: 1 }]
const badan = (m) => JSON.parse(JSON.stringify(m.body))

test('order:simpanNota tanpa bayar = NANTI seperti dulu (klien lama aman), tanpa kunci dp', () => {
  const m = kontrak.bentuk('order:simpanNota', { items })
  assert.equal(m.metode, 'POST')
  assert.equal(m.jalur, '/orders')
  const b = badan(m)
  assert.equal(b.bayar, 'NANTI')
  assert.equal('dp' in b, false)
  assert.deepEqual(b.items, [{ id_produk: 'P1', harga: 28000, kuantitas: 1 }])
})

test('order:simpanNota DP membawa dp{jumlah, tipe_pembayaran} + client_ref', () => {
  const b = badan(kontrak.bentuk('order:simpanNota', {
    items, bayar: 'DP', dp: { jumlah: 10000, tipePembayaran: 'QRIS' }, clientRef: 'dp-1', waktuKlien: '2026-09-22T10:00:00'
  }))
  assert.equal(b.bayar, 'DP')
  assert.deepEqual(b.dp, { jumlah: 10000, tipe_pembayaran: 'QRIS' })
  assert.equal(b.client_ref, 'dp-1')
  assert.equal(b.waktu_klien, '2026-09-22T10:00:00')
})

test('order:simpanNota DP tanpa jumlah/metode atau jumlah ≤ 0 ditolak sebelum dikirim', () => {
  assert.throws(() => kontrak.bentuk('order:simpanNota', { items, bayar: 'DP', dp: { tipePembayaran: 'TUNAI' } }))
  assert.throws(() => kontrak.bentuk('order:simpanNota', { items, bayar: 'DP', dp: { jumlah: 0, tipePembayaran: 'TUNAI' } }), /lebih dari Rp0/)
  assert.throws(() => kontrak.bentuk('order:simpanNota', { items, bayar: 'DP', dp: { jumlah: 5000 } }))
  assert.throws(() => kontrak.bentuk('order:simpanNota', { items, bayar: 'LUNAS' }), /Cara bayar nota/)
})

test('order:list meneruskan saringan bayar', () => {
  const m = kontrak.bentuk('order:list', { bayar: 'BELUM,DP' })
  assert.equal(m.jalur, '/orders')
  assert.equal(JSON.parse(JSON.stringify(m.query)).bayar, 'BELUM,DP')
})
