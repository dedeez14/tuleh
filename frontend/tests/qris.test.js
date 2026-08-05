'use strict'

// Tahap 3 — Pembayaran QRIS dinamis (Midtrans). Menguji:
//  1) helper murni (lib/qris-flow.js): kondisional Midtrans, peta status,
//     countdown, label struk, dan keputusan fallback 409;
//  2) mesin demo: alur poll → LUNAS lalu checkout membawa qris_tagihan_id,
//     serta penjagaan 422 (total tak cocok / belum lunas).
// Prinsip: lapis DASAR (checkout tanpa qris_tagihan_id) tetap utuh.

const test = require('node:test')
const assert = require('node:assert/strict')
const demo = require('../src/main/demo.js')

let Q // modul ESM lib/qris-flow.js (import dinamis dari test CJS)

test.before(async () => {
  Q = await import('../src/renderer/js/lib/qris-flow.js')
  demo.start() // seed + sesi kasir terbuka per toko (activeTokoId default TOKO-1)
})
test.after(() => demo.stop())

// ---------- Helper murni: lib/qris-flow.js ----------

test('midtransBoleh hanya true saat midtrans_aktif', () => {
  assert.equal(Q.midtransBoleh({ midtrans_aktif: true }), true)
  assert.equal(Q.midtransBoleh({ midtrans_aktif: false }), false)
  assert.equal(Q.midtransBoleh({}), false)
  assert.equal(Q.midtransBoleh(null), false)
  assert.equal(Q.midtransBoleh(undefined), false)
})

test('qrisAksi memetakan status server ke aksi klien', () => {
  assert.equal(Q.qrisAksi('LUNAS'), 'lunas')
  assert.equal(Q.qrisAksi('lunas'), 'lunas')
  assert.equal(Q.qrisAksi('KEDALUWARSA'), 'kedaluwarsa')
  assert.equal(Q.qrisAksi('GAGAL'), 'gagal')
  assert.equal(Q.qrisAksi('MENUNGGU'), 'menunggu')
  assert.equal(Q.qrisAksi(''), 'menunggu')
  assert.equal(Q.qrisAksi(undefined), 'menunggu')
})

test('formatSisa memformat m:ss dan tidak pernah negatif', () => {
  assert.equal(Q.formatSisa(0), '0:00')
  assert.equal(Q.formatSisa(5), '0:05')
  assert.equal(Q.formatSisa(65), '1:05')
  assert.equal(Q.formatSisa(600), '10:00')
  assert.equal(Q.formatSisa(-10), '0:00')
})

test('sisaDetik hitung mundur relatif now (ms), tak negatif', () => {
  const exp = '2026-01-01T00:15:00.000Z'
  const t0 = Date.parse('2026-01-01T00:00:00.000Z')
  assert.equal(Q.sisaDetik(exp, t0), 900)
  assert.equal(Q.sisaDetik(exp, Date.parse('2026-01-01T00:20:00.000Z')), 0) // sudah lewat
  assert.equal(Q.sisaDetik('bukan-tanggal', t0), 0) // ISO tak valid → 0
})

test('labelPembayaranStruk membedakan QRIS terverifikasi vs manual', () => {
  assert.equal(Q.labelPembayaranStruk({ qris_tagihan_id: 'QRD-1', tipe_pembayaran: 'QRIS' }), 'QRIS (terverifikasi)')
  assert.equal(Q.labelPembayaranStruk({ tipe_pembayaran: 'QRIS' }), 'QRIS')
  assert.equal(Q.labelPembayaranStruk({ tipe_pembayaran: 'TUNAI' }), 'TUNAI')
  assert.equal(Q.labelPembayaranStruk({}), 'TUNAI')
})

test('harusFallbackStatis hanya untuk 409 (Midtrans mati mendadak)', () => {
  assert.equal(Q.harusFallbackStatis({ ok: false, status: 409 }), true)
  assert.equal(Q.harusFallbackStatis({ ok: false, status: 502 }), false) // Midtrans tolak → bukan fallback
  assert.equal(Q.harusFallbackStatis({ ok: false, status: 422 }), false)
  assert.equal(Q.harusFallbackStatis({ ok: true, status: 409 }), false)
  assert.equal(Q.harusFallbackStatis(null), false)
})

// ---------- Mesin demo: buat tagihan → poll → LUNAS ----------

function produkTanpaPajak() {
  const list = demo.handlers['produk:list']({}).data
  return list.find((p) => !Number(p.pajak_persen) && Number(p.harga_jual) > 0)
}

test('demo QRIS: tagihan MENUNGGU lalu LUNAS setelah beberapa poll', () => {
  const t = demo.handlers['qris:buatTagihan']({ jumlah: 25000 })
  assert.equal(t.ok, true)
  assert.equal(t.data.status, 'MENUNGGU')
  assert.match(t.data.id, /^QRD-/)
  assert.ok(t.data.qr_string, 'qr_string harus ada untuk dirender jadi QR')
  assert.ok(t.data.expired_at, 'expired_at harus ada untuk countdown')

  const s1 = demo.handlers['qris:statusTagihan']({ id: t.data.id })
  assert.equal(s1.data.status, 'MENUNGGU')
  const s2 = demo.handlers['qris:statusTagihan']({ id: t.data.id })
  assert.equal(s2.data.status, 'LUNAS')
})

test('demo QRIS: statusTagihan 404 untuk id tak dikenal', () => {
  const r = demo.handlers['qris:statusTagihan']({ id: 'QRD-tidak-ada' })
  assert.equal(r.ok, false)
  assert.equal(r.status, 404)
})

// ---------- Checkout terverifikasi membawa qris_tagihan_id ----------

test('checkout QRIS terverifikasi membawa qris_tagihan_id ke struk', () => {
  const p = produkTanpaPajak()
  assert.ok(p, 'butuh satu produk tanpa pajak agar total bulat = harga_jual')
  const jumlah = Number(p.harga_jual) // qty 1, diskon 0, pajak 0

  const t = demo.handlers['qris:buatTagihan']({ jumlah })
  demo.handlers['qris:statusTagihan']({ id: t.data.id })
  const lunas = demo.handlers['qris:statusTagihan']({ id: t.data.id })
  assert.equal(lunas.data.status, 'LUNAS')

  const co = demo.handlers['trx:checkout']({
    items: [{ idProduk: p.id, harga: p.harga_jual, kuantitas: 1 }],
    tipePembayaran: 'QRIS',
    dibayar: jumlah,
    qrisTagihanId: t.data.id
  })
  assert.equal(co.ok, true)
  assert.equal(co.data.tipe_pembayaran, 'QRIS')
  assert.equal(co.data.qris_tagihan_id, t.data.id)
  assert.equal(Q.labelPembayaranStruk(co.data), 'QRIS (terverifikasi)')
})

test('checkout QRIS 422 bila total keranjang tak cocok tagihan', () => {
  const p = produkTanpaPajak()
  const t = demo.handlers['qris:buatTagihan']({ jumlah: Number(p.harga_jual) + 1000 }) // sengaja beda
  demo.handlers['qris:statusTagihan']({ id: t.data.id })
  demo.handlers['qris:statusTagihan']({ id: t.data.id }) // → LUNAS
  const co = demo.handlers['trx:checkout']({
    items: [{ idProduk: p.id, harga: p.harga_jual, kuantitas: 1 }],
    tipePembayaran: 'QRIS',
    dibayar: Number(p.harga_jual),
    qrisTagihanId: t.data.id
  })
  assert.equal(co.ok, false)
  assert.equal(co.status, 422)
})

test('checkout QRIS 422 bila tagihan belum LUNAS', () => {
  const p = produkTanpaPajak()
  const jumlah = Number(p.harga_jual)
  const t = demo.handlers['qris:buatTagihan']({ jumlah }) // TANPA poll → masih MENUNGGU
  const co = demo.handlers['trx:checkout']({
    items: [{ idProduk: p.id, harga: p.harga_jual, kuantitas: 1 }],
    tipePembayaran: 'QRIS',
    dibayar: jumlah,
    qrisTagihanId: t.data.id
  })
  assert.equal(co.ok, false)
  assert.equal(co.status, 422)
})

// ---------- Lapis DASAR tetap utuh (tanpa qris_tagihan_id) ----------

test('checkout tanpa qris_tagihan_id tetap jalan & label QRIS manual', () => {
  const p = produkTanpaPajak()
  const co = demo.handlers['trx:checkout']({
    items: [{ idProduk: p.id, harga: p.harga_jual, kuantitas: 1 }],
    tipePembayaran: 'QRIS',
    dibayar: Number(p.harga_jual)
  })
  assert.equal(co.ok, true)
  assert.equal(co.data.qris_tagihan_id, null)
  assert.equal(Q.labelPembayaranStruk(co.data), 'QRIS')
})
