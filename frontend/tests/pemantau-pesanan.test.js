'use strict'

// Pemantau pesanan meja (desktop) — logika deteksi yang sama dengan Android
// (DeteksiPesanan), diuji dengan bentuk data /orders & /bills server MOVERA.

const test = require('node:test')
const assert = require('node:assert/strict')

let d
test.before(async () => { d = await import('../src/renderer/js/utils/deteksi-pesanan.js') })

const rapikan = (s) => String(s).replace(/\u00a0/g, ' ')
const meja = (id, nomor, bill = null) => ({ id, nomor, kode: `M${nomor}`, bill })
const bill = (id, { total = 0, item = 0, status = 'BUKA' } = {}) => ({ id, total, jumlah_item: item, status, pax: 2 })

test('poll pertama hanya membuat potret, tanpa kejadian', () => {
  const h = d.bandingkan({
    sebelum: null,
    orders: [{ id: 'O1', stage: 'MENUNGGU_BAYAR', meja: 'Meja 3', total: 25000 }],
    tables: [meja('T1', '1', bill('B1', { total: 40000, item: 3 }))]
  })
  assert.equal(h.kejadian.length, 0)
  assert.equal(h.potret.pesanan.get('O1'), 'MENUNGGU_BAYAR')
  assert.equal(h.potret.meja.get('T1').total, 40000)
})

test('pesanan QR meja baru di /orders → menuju papan pesanan', () => {
  const awal = d.bandingkan({ sebelum: null }).potret
  const h = d.bandingkan({
    sebelum: awal,
    orders: [{ id: 'O7', stage: 'MENUNGGU_BAYAR', no_antrian: 'A-007', meja: 'Meja 5', bayar: 'BELUM', total: 52000 }]
  })
  assert.equal(h.kejadian.length, 1)
  const k = h.kejadian[0]
  assert.equal(k.jenis, d.JENIS.PESANAN_BARU)
  assert.equal(k.judul, 'Pesanan baru A-007')
  assert.equal(rapikan(k.isi), 'Meja 5 · Rp 52.000')
  assert.equal(k.tujuan, 'orders')
})

test('bon meja muncul, bertambah, minta bayar, lalu selesai', () => {
  let potret = d.bandingkan({ sebelum: null, tables: [meja('T1', '1'), meja('T2', '2')] }).potret

  let h = d.bandingkan({ sebelum: potret, tables: [meja('T1', '1', bill('B1', { total: 30000, item: 2 })), meja('T2', '2')] })
  assert.deepEqual(h.kejadian.map((k) => k.jenis), [d.JENIS.PESANAN_BARU])
  assert.equal(h.kejadian[0].judul, 'Meja 1: pesanan baru')
  assert.equal(rapikan(h.kejadian[0].isi), '2 item · Rp 30.000')
  assert.equal(h.kejadian[0].tujuan, 'peta-meja')
  potret = h.potret

  h = d.bandingkan({ sebelum: potret, tables: [meja('T1', '1', bill('B1', { total: 30000, item: 2 })), meja('T2', '2')] })
  assert.equal(h.kejadian.length, 0, 'tidak berubah → diam')

  h = d.bandingkan({ sebelum: potret, tables: [meja('T1', '1', bill('B1', { total: 45000, item: 3 })), meja('T2', '2')] })
  assert.equal(h.kejadian[0].jenis, d.JENIS.TAMBAH_PESANAN)
  assert.equal(rapikan(h.kejadian[0].isi), '+Rp 15.000 · total Rp 45.000')
  potret = h.potret

  h = d.bandingkan({ sebelum: potret, tables: [meja('T1', '1', bill('B1', { total: 45000, item: 3, status: 'BILL' })), meja('T2', '2')] })
  assert.equal(h.kejadian[0].jenis, d.JENIS.MINTA_BAYAR)
  assert.equal(h.kejadian[0].judul, 'Meja 1 minta bayar')
  potret = h.potret

  h = d.bandingkan({ sebelum: potret, tables: [meja('T1', '1', bill('B1', { total: 45000, item: 3, status: 'BILL' })), meja('T2', '2')] })
  assert.equal(h.kejadian.length, 0, 'masih BILL → tidak diulang')

  h = d.bandingkan({ sebelum: h.potret, tables: [meja('T1', '1'), meja('T2', '2')] })
  assert.equal(h.kejadian.length, 0)
  assert.equal(h.potret.meja.get('T1'), null)
})

test('bon baru tanpa item (kasir membuka meja sendiri) tidak dinotifikasi', () => {
  const potret = d.bandingkan({ sebelum: null, tables: [meja('T1', '1')] }).potret
  const h = d.bandingkan({ sebelum: potret, tables: [meja('T1', '1', bill('B9'))] })
  assert.equal(h.kejadian.length, 0)
})

test('baris rusak diabaikan, tidak melempar', () => {
  const h = d.bandingkan({
    sebelum: { pesanan: new Map(), meja: new Map() },
    orders: ['x', 1, null, { stage: 'A' }, { id: '', stage: 'B' }],
    tables: [null, 'y', { nomor: '3' }, { id: 'T', bill: 'bukan objek' }]
  })
  assert.equal(h.kejadian.length, 0)
  assert.equal(h.potret.pesanan.size, 0)
  assert.equal(h.potret.meja.get('T'), null)
})
