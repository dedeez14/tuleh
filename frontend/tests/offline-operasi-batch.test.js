'use strict'

// Operasi /sync/v2/batch dari baris antrean desktop (Fase 4, rancangan §B–§C): pemetaan per jenis,
// client_ref batch deterministik (ikut generasi kirim ulang), hasil item, dan penulisan ulang rujukan
// transaksi lokal untuk kiriman per baris.

const test = require('node:test')
const assert = require('node:assert/strict')
const crypto = require('node:crypto')
const B = require('../src/main/offline/operasi-batch')

const ZONA = /[+-]\d{2}:\d{2}$/

test('jalur & jenis batch: rute baru v2, lima jenis antrean desktop', () => {
  assert.equal(B.JALUR_SYNC_BATCH, '/sync/v2/batch')
  assert.deepEqual(B.JENIS_BATCH, { CHECKOUT: 'checkout', REFUND: 'refund', BATAL: 'batal', BILL_BAYAR: 'bills.settle', ORDER_TRANSISI: 'orders.transition' })
  assert.equal(B.BATAS_OP_SEGMEN, 25)
})

test('opDariBaris CHECKOUT: badan utuh + offline:true, toko & nomor lokal, waktu ber-zona, umur_detik', () => {
  const p = {
    clientRef: 'c1', jenis: 'CHECKOUT', tokoId: 'T-enc', path: '/transaksi/checkout', deviceSeq: 41, dibuat: 1000000,
    body: { items: [{ id_produk: 'P1', harga: 12000, kuantitas: 5 }], tipe_pembayaran: 'TUNAI', dibayar: 70000, diskon_nominal: 2000, client_ref: 'c1', waktu_klien: '2026-09-24T10:15:02' }
  }
  const op = B.opDariBaris(p, { deviceId: 'dev-1', kini: 1000000 + 125500, nomorLokal: 'L-DEV1-260924-0007' })
  assert.equal(op.idempotency_key, 'c1')
  assert.equal(op.device_id, 'dev-1')
  assert.equal(op.device_seq, 41)
  assert.equal(op.type, 'checkout')
  assert.equal(op.umur_detik, 125)
  assert.equal(op.payload.offline, true)
  assert.equal(op.payload.toko_id, 'T-enc')
  assert.equal(op.payload.nomor_lokal, 'L-DEV1-260924-0007')
  assert.equal(op.payload.diskon_nominal, 2000, 'diskon tidak dibuang (dulu dibuang sync v1)')
  assert.equal(op.payload.client_ref, 'c1')
  assert.match(op.payload.waktu_klien, /^2026-09-24T10:15:02/)
  assert.match(op.payload.waktu_klien, ZONA)
  assert.equal(new Date(op.payload.waktu_klien).getTime(), new Date('2026-09-24T10:15:02').getTime())
  assert.equal(p.body.offline, undefined, 'baris antrean tidak diubah')
  assert.equal(B.opDariBaris({ ...p, body: { ...p.body, nomor_lokal: 'L-X-1' } }, { deviceId: 'dev-1', kini: 1000000 }).payload.nomor_lokal, 'L-X-1', 'nomor di badan diutamakan')
})

test('opDariBaris REFUND/BATAL: transaksi lokal → transaksi_ref; tersinkron → transaksi_id', () => {
  const lokal = B.opDariBaris({ clientRef: 'rf-1', jenis: 'REFUND', tokoId: 'T1', path: '/transaksi/lokal%3Ac1/refund', deviceSeq: 42, dibuat: 5000, body: { items: [{ baris: 1, kuantitas: 1 }], metode: 'TUNAI', alasan: 'Rusak', kembali_stok: true, client_ref: 'rf-1' } }, { deviceId: 'd', kini: 5000 })
  assert.equal(lokal.type, 'refund')
  assert.equal(lokal.payload.transaksi_ref, 'c1')
  assert.equal(lokal.payload.transaksi_id, undefined)
  assert.deepEqual(lokal.payload.items, [{ baris: 1, kuantitas: 1 }])
  assert.match(lokal.payload.waktu_klien, ZONA, 'tanpa waktu_klien di badan → waktu baris dibuat')
  const batal = B.opDariBaris({ clientRef: 'b-1', jenis: 'BATAL', tokoId: 'T1', path: '/transaksi/eyJpdiI6%3D%3D/batal', deviceSeq: 43, dibuat: 5000, body: { alasan: 'Salah input', client_ref: 'b-1' } }, { deviceId: 'd', kini: 5000 })
  assert.equal(batal.type, 'batal')
  assert.equal(batal.payload.transaksi_id, 'eyJpdiI6==')
  assert.equal(batal.payload.transaksi_ref, undefined)
  assert.equal(batal.payload.alasan, 'Salah input')
})

test('opDariBaris BILL_BAYAR / ORDER_TRANSISI: id dari jalur; toko untuk semua tipe', () => {
  const bon = B.opDariBaris({ clientRef: 's-1', jenis: 'BILL_BAYAR', tokoId: 'T2', path: '/bills/B%2F7/settle', deviceSeq: 44, dibuat: 1, body: { tipe_pembayaran: 'QRIS', dibayar: null } }, { deviceId: 'd', kini: 1 })
  assert.equal(bon.type, 'bills.settle')
  assert.equal(bon.payload.bon_id, 'B/7')
  assert.equal(bon.payload.toko_id, 'T2')
  assert.equal(bon.payload.client_ref, 's-1', 'client_ref payload selalu = idempotency_key')
  const psn = B.opDariBaris({ clientRef: 'o-1', jenis: 'ORDER_TRANSISI', tokoId: null, path: '/orders/O9/transition', deviceSeq: 45, dibuat: 1, body: { to: 'SELESAI', tipe_pembayaran: 'TUNAI' } }, { deviceId: 'd', kini: 1 })
  assert.equal(psn.type, 'orders.transition')
  assert.equal(psn.payload.order_id, 'O9')
  assert.equal(psn.payload.to, 'SELESAI')
  assert.equal('toko_id' in psn.payload, false, 'baris tanpa toko → server memakai toko sesi')
})

test('opDariBaris: device_seq hanya bila bilangan bulat ≥ 0; jenis non-batch ditolak', () => {
  const op = B.opDariBaris({ clientRef: 'x', jenis: 'CHECKOUT', path: '/transaksi/checkout', dibuat: 1, body: {} }, { deviceId: 'd', kini: 1 })
  assert.equal('device_seq' in op, false)
  assert.throws(() => B.opDariBaris({ clientRef: 'p', jenis: 'PENGELUARAN', path: '/pengeluaran', body: {} }, { deviceId: 'd' }), /tidak dikirim lewat batch/)
})

test('clientRefBatch: deterministik dari perangkat + komposisi urutan kirim + generasi kirim ulang', () => {
  const baris = [{ jenis: 'CHECKOUT', clientRef: 'a' }, { jenis: 'REFUND', clientRef: 'b', kirimUlangKe: 0 }]
  const r1 = B.clientRefBatch('dev', baris)
  assert.match(r1, /^[0-9a-f]{64}$/)
  assert.equal(B.sidikKomposisi(baris), 'checkout:a:0\nrefund:b:0')
  assert.equal(r1, crypto.createHash('sha256').update('dev|checkout:a:0\nrefund:b:0').digest('hex'), 'rumus tetap antar rilis')
  assert.equal(B.clientRefBatch('dev', baris.map((x) => ({ ...x }))), r1)
  assert.notEqual(B.clientRefBatch('dev', [baris[0], { ...baris[1], kirimUlangKe: 1 }]), r1, 'kirim ulang = ref baru → dinilai ulang server')
  assert.notEqual(B.clientRefBatch('dev', baris, 1), r1, 'garam untuk 409 BATCH_REF_BENTROK')
  assert.notEqual(B.clientRefBatch('dev-lain', baris), r1)
  assert.notEqual(B.clientRefBatch('dev', [baris[1], baris[0]]), r1, 'urutan kirim ikut')
})

test('ukuranJson = byte UTF-8 JSON', () => {
  assert.equal(B.ukuranJson({ a: 'é' }), Buffer.byteLength('{"a":"é"}'))
})

test('hasilDariItem: bentuk hasil baris TERKIRIM', () => {
  const h = B.hasilDariItem({ idempotency_key: 'k', type: 'checkout', accepted: true, server_id: 'enc-1', nomor: 'POS/1', kode: 'OK', idempoten: true, peringatan: ['SELISIH_STOK'], data: { grand_total: 1 } })
  assert.deepEqual(h, { id: 'enc-1', nomor: 'POS/1', kode: 'OK', tipe: 'checkout', peringatan: ['SELISIH_STOK'], idempoten: true, _idempoten: true, data: { grand_total: 1 } })
  assert.deepEqual(B.hasilDariItem({ accepted: true }), { id: null, nomor: null, kode: 'OK', tipe: null, peringatan: [], idempoten: false, _idempoten: false, data: null })
})

test('gantiRujukanLokal: jalur → id server induk; baris → id item dari hasil batch atau struk per baris', () => {
  const anak = { path: '/transaksi/lokal%3Ac1/refund', body: { items: [{ baris: 1, kuantitas: 2 }], metode: 'TUNAI', alasan: 'Rusak' } }
  const indukBatch = { hasil: { id: 'SRV/1', data: { items: [{ baris: 0, id: 'I-a' }, { baris: 1, id: 'I-b' }] } } }
  assert.deepEqual(B.gantiRujukanLokal(anak, indukBatch), { path: '/transaksi/SRV%2F1/refund', body: { items: [{ id: 'I-b', kuantitas: 2 }], metode: 'TUNAI', alasan: 'Rusak' } })
  const indukPerBaris = { hasil: { id: 'S2', items: [{ id: 'J-a' }, { id: 'J-b' }] } }
  assert.deepEqual(B.gantiRujukanLokal(anak, indukPerBaris).body.items, [{ id: 'J-b', kuantitas: 2 }])
  assert.deepEqual(B.gantiRujukanLokal({ path: '/transaksi/lokal:c1/batal', body: { alasan: 'x' } }, indukPerBaris), { path: '/transaksi/S2/batal', body: { alasan: 'x' } })
  assert.equal(B.gantiRujukanLokal(anak, { hasil: { id: 'S3', dipulihkan: true } }), null, 'baris tak diketahui')
  assert.equal(B.gantiRujukanLokal(anak, { hasil: null }), null)
  assert.equal(anak.path, '/transaksi/lokal%3Ac1/refund', 'baris asal tidak diubah')
})

test('label kode & peringatan untuk kasir; kode asing apa adanya', () => {
  assert.equal(B.labelKode('OTORISASI_WAJIB'), 'Butuh persetujuan atasan — ulangi saat online')
  assert.equal(B.labelKode('PELUNASAN_HARUS_REFUND'), 'Transaksi pelunasan — gunakan Refund')
  assert.equal(B.labelKode('KODE_BARU'), 'KODE_BARU')
  assert.deepEqual(B.labelPeringatan(['SELISIH_STOK', 'SESI_TUTUP', 'BARU']), ['Selisih stok', 'Masuk sesi yang sudah ditutup', 'BARU'])
  assert.deepEqual(B.labelPeringatan(null), [])
})

// ── Paritas Flutter (`mobile-flutter/test/offline_operasi_batch_test.dart`) — digest dikunci identik ──

test('paritas Flutter: digest client_ref batch tetap (vektor yang sama dengan tes Dart)', () => {
  const baris = [{ jenis: 'CHECKOUT', clientRef: 'a' }, { jenis: 'REFUND', clientRef: 'b', kirimUlangKe: 0 }]
  assert.equal(B.clientRefBatch('dev', baris), 'fe481eea9f58de368b53f096384781ea43950b643012811349ddede35f5cf3cd')
  assert.equal(B.clientRefBatch('dev', baris, 1), '0e60b3cd99e807769359fd279851932cb17696d348ebb4b85781b8ccc777d2a5')
})

test('normalisasi tepi sidik (acuan paritas): garam ≤ 0 / bukan angka = tanpa akhiran, garam pecahan dipotong', () => {
  const baris = [{ jenis: 'CHECKOUT', clientRef: 'a' }, { jenis: 'REFUND', clientRef: 'b' }]
  const r0 = B.clientRefBatch('dev', baris)
  assert.equal(B.clientRefBatch('dev', baris, -1), r0, 'garam negatif = 0 (bukan "|-1")')
  assert.equal(B.clientRefBatch('dev', baris, 0.9), r0, 'garam 0,9 dipotong → 0')
  assert.equal(B.clientRefBatch('dev', baris, NaN), r0)
  assert.equal(B.clientRefBatch('dev', baris, 'x'), r0)
  assert.equal(B.clientRefBatch('dev', baris, 1.7), B.clientRefBatch('dev', baris, 1), 'garam 1,7 dipotong → 1')
})

test('normalisasi tepi sidik: kirimUlangKe dipotong (Math.trunc), tak valid = 0; jenis non-batch dikecualikan', () => {
  assert.equal(B.sidikKomposisi([{ jenis: 'REFUND', clientRef: 'b', kirimUlangKe: 1.7 }]), 'refund:b:1')
  assert.equal(B.sidikKomposisi([{ jenis: 'REFUND', clientRef: 'b', kirimUlangKe: -0.5 }]), 'refund:b:0', 'bukan "-0"')
  assert.equal(B.sidikKomposisi([{ jenis: 'REFUND', clientRef: 'b', kirimUlangKe: '2' }]), 'refund:b:2')
  for (const v of [undefined, null, NaN, Infinity, '1.5', 'x', true]) {
    assert.equal(B.sidikKomposisi([{ jenis: 'REFUND', clientRef: 'b', kirimUlangKe: v }]), 'refund:b:0', `kirimUlangKe ${String(v)}`)
  }
  const campur = [{ jenis: 'CHECKOUT', clientRef: 'a' }, { jenis: 'PENGELUARAN', clientRef: 'x' }, { jenis: 'REFUND', clientRef: 'b' }]
  assert.equal(B.sidikKomposisi(campur), 'checkout:a:0\nrefund:b:0', 'tanpa baris "undefined:x:0"')
  assert.equal(B.clientRefBatch('dev', campur), 'fe481eea9f58de368b53f096384781ea43950b643012811349ddede35f5cf3cd')
})

test('opDariBaris tepi: id jalur gagal di-decode → null; waktu_klien tak terurai → waktu baris dibuat', () => {
  const batal = B.opDariBaris({ clientRef: 'b-2', jenis: 'BATAL', path: '/transaksi/%E0%A4%A/batal', dibuat: 1, body: { alasan: 'x' } }, { deviceId: 'd', kini: 1 })
  assert.equal(batal.payload.transaksi_id, null)
  assert.equal(batal.payload.transaksi_ref, undefined)
  const bon = B.opDariBaris({ clientRef: 's-2', jenis: 'BILL_BAYAR', path: '/bills/%ZZ/settle', dibuat: 1, body: {} }, { deviceId: 'd', kini: 1 })
  assert.equal(bon.payload.bon_id, null)
  const dibuat = new Date('2026-09-24T08:00:00').getTime()
  const op = B.opDariBaris({ clientRef: 'c-2', jenis: 'CHECKOUT', path: '/transaksi/checkout', dibuat, body: { waktu_klien: 'bukan-waktu' } }, { deviceId: 'd', kini: dibuat })
  assert.match(op.payload.waktu_klien, /^2026-09-24T08:00:00/)
  assert.match(op.payload.waktu_klien, ZONA)
})
