'use strict'

// Bidang usaha jasa dengan alur khas (Sep 2026): bengkel, doorsmeer, salon/barbershop
// — cermin manifest_override server (Blueprint §5.1, §9.5). Semuanya di atas alur
// service_job; wajah aplikasi ditentukan manifest (lifecycle, stasiun, katalog),
// bukan kode khusus per bidang. Diuji pada mesin demo: manifest lengkap, label
// tahap, alur kasir → papan → selesai, nota bayar-saat-ambil, dan stok sparepart.
// (Kasus khusus bengkel yang lebih rinci: tests/demo-bengkel.test.js.)

const test = require('node:test')
const assert = require('node:assert/strict')

const demo = require('../src/main/demo.js')

const JASA = [
  { id: 'TOKO-4', code: 'bengkel', nama: 'Bengkel Jaya Demo', prefix: /^B-\d{3}$/, papan: 'proses' },
  { id: 'TOKO-5', code: 'doorsmeer', nama: 'Doorsmeer Kinclong Demo', prefix: /^D-\d{3}$/, papan: 'proses', seedTerhubung: true },
  { id: 'TOKO-6', code: 'salon', nama: 'Barbershop Rapi Demo', prefix: /^S-\d{3}$/, papan: 'antrian', seedTerhubung: true }
]
const pilih = (id) => demo.handlers['toko:select']({ id })
const manifestOf = (id) => demo.handlers['toko:manifest']({ id }).data

test.before(() => { demo.start() })
test.after(() => { demo.stop() })

test('toko:list memuat 6 toko demo; tiga bidang jasa ber-archetype service_*', () => {
  const list = demo.handlers['toko:list']().data
  assert.equal(list.length, 6)
  for (const b of JASA) {
    const t = list.find((x) => x.id === b.id)
    assert.ok(t, `${b.id} ada`)
    assert.equal(t.nama, b.nama)
    assert.equal(t.bidang_usaha.code, b.code)
    assert.match(t.bidang_usaha.archetype, /^service/)
    assert.match(t.bidang_usaha.kategori, /Jasa/)
  }
})

test('manifest bidang jasa: rantai tahap utuh, papan, stasiun, bayar-saat-ambil', () => {
  for (const b of JASA) {
    const m = manifestOf(b.id)
    assert.equal(m.vertical_code, b.code)
    const states = m.lifecycle.states
    assert.ok(states.length >= 3, `${b.code}: lifecycle ≥ 3 tahap`)
    assert.equal(states[0], 'ANTRIAN')
    assert.equal(states[states.length - 1], 'SELESAI')
    // Setiap tahap punya transisi ke tahap berikutnya (kontrak §14)
    states.slice(0, -1).forEach((s, i) => {
      const ada = m.lifecycle.transitions.some((t) => t.from === s && t.to === states[i + 1])
      assert.ok(ada, `${b.code}: transisi ${s} → ${states[i + 1]}`)
    })
    assert.ok(m.menus.some((x) => x.id === b.papan), `${b.code}: menu ${b.papan}`)
    assert.ok(m.capabilities.includes('stages') && m.capabilities.includes('customer_tracking'), `${b.code}: capabilities`)
    assert.ok(m.transaction_flow.includes('PAYMENT_OR_LATER'), `${b.code}: bayar saat ambil`)
    assert.ok(m.station_types.length >= 2 && m.station_types[0].type === 'cashier', `${b.code}: station_types`)
  }
})

test('setiap tahap bidang jasa punya label untuk papan antrian & halaman lacak', () => {
  for (const b of JASA) {
    pilih(b.id)
    const papan = demo.queueBoardInfo()
    assert.ok(papan, `${b.code}: papan antrian tersedia`)
    assert.equal(papan.tokoNama, b.nama)
    for (const s of manifestOf(b.id).lifecycle.states) {
      assert.equal(typeof papan.labels[s], 'string', `${b.code}: label ${s}`)
      assert.ok(papan.labels[s].length > 0)
    }
  }
})

test('seed: tiap toko jasa punya stasiun sesuai manifest & pesanan hidup di papan', () => {
  for (const b of JASA) {
    pilih(b.id)
    const jenisSah = manifestOf(b.id).station_types.map((t) => t.type)
    const stasiun = demo.handlers['station:list']().data
    assert.ok(stasiun.length >= 2, `${b.code}: stasiun terseed`)
    assert.ok(stasiun.every((s) => jenisSah.includes(s.type)), `${b.code}: jenis stasiun sah`)

    const papan = demo.handlers['order:list']({}).data
    assert.ok(papan.length >= 3, `${b.code}: pesanan hidup terseed`)
    assert.ok(papan.every((o) => o.toko_id === b.id && b.prefix.test(o.no_antrian)), `${b.code}: prefix antrian`)
    // Item seed terhubung ke katalog agar pelunasan nota menghasilkan struk yang benar
    if (b.seedTerhubung) {
      assert.ok(papan.every((o) => o.items.every((i) => i.idProduk && i.harga > 0)), `${b.code}: item seed ber-idProduk`)
    }
  }
})

test('doorsmeer: checkout kasir → antrian D-xxx → transisi urut sampai selesai', () => {
  pilih('TOKO-5')
  const daftar = demo.handlers['produk:list']({}).data
  assert.ok(daftar.every((p) => p.id.startsWith('DSM-')))
  const cuci = daftar.find((p) => p.kode === 'MBL-001')
  const co = demo.handlers['trx:checkout']({
    items: [{ idProduk: cuci.id, harga: cuci.harga_jual, kuantitas: 1 }],
    tipePembayaran: 'QRIS',
    dibayar: cuci.harga_jual
  })
  assert.equal(co.ok, true)
  assert.match(co.data.no_antrian, /^D-\d{3}$/)
  assert.ok(co.data.token_lacak)

  const order = demo.handlers['order:list']({}).data.find((o) => o.no_antrian === co.data.no_antrian)
  assert.equal(order.stage, 'ANTRIAN')
  assert.equal(order.bayar, 'LUNAS')

  // Lompat tahap ditolak; urutan manifest dipatuhi sampai SELESAI
  assert.equal(demo.handlers['order:transition']({ id: order.id, to: 'FINISHING' }).status, 409)
  for (const to of ['PENCUCIAN', 'PENGERINGAN', 'FINISHING', 'SIAP_AMBIL', 'SELESAI']) {
    const r = demo.handlers['order:transition']({ id: order.id, to })
    assert.equal(r.ok, true, `→ ${to}`)
    assert.equal(r.data.stage, to)
  }
  assert.equal(demo.handlers['order:transition']({ id: order.id }).status, 409)

  // Halaman lacak pelanggan: tahap, label, & nama toko benar
  const lacak = demo.trackingInfo(co.data.token_lacak)
  assert.equal(lacak.order.stage, 'SELESAI')
  assert.equal(lacak.tokoNama, 'Doorsmeer Kinclong Demo')
  assert.deepEqual(lacak.states, manifestOf('TOKO-5').lifecycle.states)
  assert.equal(lacak.labels.FINISHING, 'Finishing & Poles')
})

test('salon/barbershop: katalog campur jasa + produk; nota bayar-setelah-cukur dilunasi di akhir', () => {
  pilih('TOKO-6')
  const daftar = demo.handlers['produk:list']({}).data
  assert.ok(daftar.every((p) => p.id.startsWith('SLN-')))
  const jasa = daftar.filter((p) => p.tipe === 'JASA')
  const produk = daftar.filter((p) => p.tipe === 'PRODUK')
  assert.ok(jasa.length >= 5 && produk.length >= 2)
  assert.ok(jasa.every((p) => p.harga_beli === null && !p.kelola_stok), 'jasa: tanpa harga beli & stok')
  assert.ok(produk.every((p) => p.kelola_stok && p.harga_beli > 0), 'produk: berstok & ber-harga beli')
  // Kasir bisa menyaring jasa saja / produk saja (kontrak ?tipe=)
  assert.equal(demo.handlers['produk:list']({ tipe: 'JASA' }).data.length, jasa.length)
  assert.equal(demo.handlers['produk:list']({ tipe: 'PRODUK' }).data.length, produk.length)

  const potong = daftar.find((p) => p.kode === 'PTG-001')
  const simpan = demo.handlers['order:simpanNota']({
    items: [{ idProduk: potong.id, harga: potong.harga_jual, kuantitas: 1 }]
  })
  assert.equal(simpan.ok, true)
  assert.match(simpan.data.order.no_antrian, /^S-\d{3}$/)
  assert.equal(simpan.data.order.bayar, 'BELUM')
  assert.equal(simpan.data.order.stage, 'ANTRIAN')

  // Kapster memanggil → DILAYANI; kasir melunasi saat selesai → SELESAI + struk
  const id = simpan.data.order.id
  assert.equal(demo.handlers['order:transition']({ id, to: 'DILAYANI' }).ok, true)
  const lunas = demo.handlers['order:lunasi']({ id, tipePembayaran: 'TUNAI' })
  assert.equal(lunas.ok, true)
  assert.equal(lunas.data.order.stage, 'SELESAI')
  assert.equal(lunas.data.order.bayar, 'LUNAS')
  assert.equal(lunas.data.struk.grand_total, potong.harga_jual)
  assert.equal(lunas.data.struk.no_antrian, simpan.data.order.no_antrian)
})

test('bengkel: suku cadang mengurangi stok saat checkout, jasa tidak; nomor B-xxx', () => {
  pilih('TOKO-4')
  const daftar = demo.handlers['produk:list']({}).data
  assert.ok(daftar.every((p) => p.id.startsWith('BKL-')))
  const servis = daftar.find((p) => p.kode === 'JSV-001')
  const oli = daftar.find((p) => p.kode === 'OLI-001')
  assert.equal(servis.tipe, 'JASA')
  assert.equal(oli.tipe, 'PRODUK')
  const stokAwal = oli.stok

  const co = demo.handlers['trx:checkout']({
    items: [
      { idProduk: servis.id, harga: servis.harga_jual, kuantitas: 1 },
      { idProduk: oli.id, harga: oli.harga_jual, kuantitas: 2 }
    ],
    tipePembayaran: 'TUNAI',
    dibayar: 200000
  })
  assert.equal(co.ok, true)
  assert.match(co.data.no_antrian, /^B-\d{3}$/)
  assert.equal(co.data.grand_total, servis.harga_jual + 2 * oli.harga_jual)

  assert.equal(demo.handlers['produk:detail']({ id: oli.id }).data.stok, stokAwal - 2)
  // Laporan stok hanya memuat suku cadang/oli berstok, bukan jasa
  const lap = demo.handlers['laporan:stok']().data
  assert.ok(lap.some((r) => r.id === oli.id && r.stok === stokAwal - 2))
  assert.ok(!lap.some((r) => r.id === servis.id))
})

test('seed nota belum-bayar (doorsmeer) dapat dilunasi dengan struk yang benar', () => {
  pilih('TOKO-5')
  const belum = demo.handlers['order:list']({}).data.find((o) => o.bayar === 'BELUM')
  assert.ok(belum, 'ada nota bayar-saat-ambil di seed doorsmeer')
  const lunas = demo.handlers['order:lunasi']({ id: belum.id, tipePembayaran: 'QRIS' })
  assert.equal(lunas.ok, true)
  assert.ok(Number.isFinite(lunas.data.struk.grand_total) && lunas.data.struk.grand_total > 0)
  assert.equal(lunas.data.struk.grand_total, belum.total)
  assert.equal(lunas.data.order.stage, 'SELESAI')
})
