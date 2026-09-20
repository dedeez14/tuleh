'use strict'

// Kontrak kanal refund (server 2026-09-13, app 0.9.37): struk lengkap (qty_bisa_refund, refunds[]) dan
// refund per item lewat gateway. Satu kontrak dipakai desktop (ipc.js) & Android Capacitor (mobile-bridge.js).

const test = require('node:test')
const assert = require('node:assert/strict')
const kontrak = require('../src/shared/kontrak-kanal.js')

test('trx:struk → GET /transaksi/{id}/struk', () => {
  assert.deepEqual(kontrak.bentuk('trx:struk', { id: 'T1' }), { metode: 'GET', jalur: '/transaksi/T1/struk', query: undefined })
})

test('trx:refund → POST body sesuai kontrak server (items id+kuantitas, metode, alasan, kembali_stok, client_ref, waktu_klien)', () => {
  const m = kontrak.bentuk('trx:refund', {
    id: 'T1',
    baris: [{ id: 'I1', kuantitas: 1 }, { id: 'I2', kuantitas: 0.5 }],
    metode: 'TUNAI',
    alasan: 'Rasa tidak sesuai',
    kembaliStok: false,
    clientRef: 'r-1',
    waktuKlien: '2026-09-20T10:00:00'
  })
  assert.equal(m.metode, 'POST')
  assert.equal(m.jalur, '/transaksi/T1/refund')
  assert.deepEqual(JSON.parse(JSON.stringify(m.body)), {
    items: [{ id: 'I1', kuantitas: 1 }, { id: 'I2', kuantitas: 0.5 }],
    metode: 'TUNAI',
    alasan: 'Rasa tidak sesuai',
    kembali_stok: false,
    client_ref: 'r-1',
    waktu_klien: '2026-09-20T10:00:00'
  })
})

test('trx:refund: kembali_stok bawaan true; client_ref opsional; isian tak lengkap ditolak sebelum ke server', () => {
  const m = kontrak.bentuk('trx:refund', { id: 'T1', baris: [{ id: 'I1', kuantitas: 2 }], metode: 'QRIS', alasan: 'Rusak' })
  assert.equal(m.body.kembali_stok, true)
  assert.equal('client_ref' in JSON.parse(JSON.stringify(m.body)), false)
  assert.throws(() => kontrak.bentuk('trx:refund', { id: 'T1', baris: [], metode: 'TUNAI', alasan: 'Rusak' }), /minimal satu item/)
  assert.throws(() => kontrak.bentuk('trx:refund', { id: 'T1', baris: [{ id: 'I1', kuantitas: 0 }], metode: 'TUNAI', alasan: 'Rusak' }), /lebih dari nol/)
  assert.throws(() => kontrak.bentuk('trx:refund', { id: 'T1', baris: [{ id: 'I1', kuantitas: 1 }], metode: 'TUNAI' }), /wajib/)
  assert.throws(() => kontrak.bentuk('trx:refund', { id: 'T1', baris: [{ id: 'I1', kuantitas: 1 }], alasan: 'Rusak' }), /wajib/)
})

test('permukaan preload desktop memuat trx.struk & trx.refund (paritas dengan jembatan Android)', () => {
  const fs = require('node:fs')
  const path = require('node:path')
  const preload = fs.readFileSync(path.join(__dirname, '../src/preload/preload.js'), 'utf8')
  assert.match(preload, /struk: invoke\('trx:struk'\)/)
  assert.match(preload, /refund: invoke\('trx:refund'\)/)
})
