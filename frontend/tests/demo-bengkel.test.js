'use strict'

// Toko demo BENGKEL (TOKO-4) — cermin manifest_override server (MOVERA
// config/pos_verticals.php): ANTRIAN → PEMERIKSAAN → PENGERJAAN → SIAP_AMBIL →
// SELESAI, prefix antrian B, stasiun mekanik, item per jasa (tanpa timbangan).

const test = require('node:test')
const assert = require('node:assert/strict')

const demo = require('../src/main/demo.js')

test.before(() => {
  demo.start()
  const sel = demo.handlers['toko:select']({ id: 'TOKO-4' })
  assert.equal(sel.ok, true, 'toko demo bengkel harus bisa dipilih')
})

test.after(() => demo.stop())

test('toko demo bengkel terdaftar dengan bidang usaha bengkel', () => {
  const t = demo.handlers['toko:list']().data.find((x) => x.id === 'TOKO-4')
  assert.ok(t, 'TOKO-4 ada di daftar toko')
  assert.equal(t.bidang_usaha.code, 'bengkel')
})

test('manifest bengkel: tahapan, stasiun mekanik, bayar saat ambil, tanpa timbangan', () => {
  const m = demo.handlers['toko:manifest']({ id: 'TOKO-4' }).data
  assert.deepEqual(m.lifecycle.states, ['ANTRIAN', 'PEMERIKSAAN', 'PENGERJAAN', 'SIAP_AMBIL', 'SELESAI'])
  assert.ok(m.station_types.some((s) => s.type === 'mechanic'))
  assert.equal(m.item_config.weighable, false)
  assert.ok(m.transaction_flow.includes('PAYMENT_OR_LATER'))
  assert.ok(m.menus.some((x) => x.id === 'proses'), 'papan proses tersedia')
})

test('katalog bengkel: jasa tanpa stok + suku cadang berstok', () => {
  const rows = demo.handlers['produk:list']({ tipe: 'SEMUA' }).data
  assert.ok(rows.length >= 6)
  assert.ok(rows.every((p) => /^BKL-/.test(p.id)), 'katalog bengkel yang aktif, bukan toko lain')
  assert.ok(rows.some((p) => p.kelola_stok === true), 'ada suku cadang berstok')
  assert.ok(rows.some((p) => p.kelola_stok === false), 'ada jasa tanpa stok')
  // Tipe & harga beli cermin server: jasa = JASA tanpa harga beli, suku cadang = PRODUK.
  for (const p of rows) {
    if (p.kelola_stok) {
      assert.equal(p.tipe, 'PRODUK', `${p.nama} suku cadang bertipe PRODUK`)
      assert.ok(p.harga_beli > 0, `${p.nama} punya harga beli`)
    } else {
      assert.equal(p.tipe, 'JASA', `${p.nama} jasa bertipe JASA`)
      assert.equal(p.harga_beli, null, `${p.nama} jasa tanpa harga beli`)
    }
  }
})

test('checkout bengkel menerbitkan antrian B-xxx dan order maju tahap demi tahap', () => {
  const p = demo.handlers['produk:list']({ tipe: 'SEMUA' }).data[0]
  const co = demo.handlers['trx:checkout']({
    items: [{ idProduk: p.id, harga: p.harga_jual, kuantitas: 1 }],
    tipePembayaran: 'TUNAI',
    dibayar: p.harga_jual
  })
  assert.equal(co.ok, true)
  assert.match(co.data.no_antrian, /^B-\d{3}$/)

  const order = demo.handlers['order:list']({ stage: 'ANTRIAN' }).data.find((o) => o.no_antrian === co.data.no_antrian)
  assert.ok(order, 'order masuk papan di tahap ANTRIAN')

  const lompat = demo.handlers['order:transition']({ id: order.id, to: 'PENGERJAAN' })
  assert.equal(lompat.ok, false)
  assert.match(lompat.message, /Berikutnya harus PEMERIKSAAN/)

  for (const to of ['PEMERIKSAAN', 'PENGERJAAN', 'SIAP_AMBIL', 'SELESAI']) {
    const r = demo.handlers['order:transition']({ id: order.id, to })
    assert.equal(r.ok, true, `transisi ke ${to}`)
    assert.equal(r.data.stage, to)
  }
})

test('papan proses bengkel sudah terisi contoh di tahap pemeriksaan & pengerjaan', () => {
  const stages = demo.handlers['order:list']({}).data.map((o) => o.stage)
  assert.ok(stages.includes('PEMERIKSAAN'))
  assert.ok(stages.includes('PENGERJAAN'))
})
