'use strict'

// E2E alur POS universal pada mesin demo (tanpa Electron):
// kasir → antrian → lacak QR, dan QR meja → Menunggu Bayar → konfirmasi.
// Port tracker diisolasi agar tidak bentrok dengan aplikasi yang berjalan.

process.env.MPOS_TRACK_PORT = '8807'

const test = require('node:test')
const assert = require('node:assert/strict')

const demo = require('../src/main/demo.js')
const tracker = require('../src/main/tracker.js')
const qr = require('../src/main/qr.js')

const PORT = process.env.MPOS_TRACK_PORT
const asal = `http://127.0.0.1:${PORT}`

test.before(async () => {
  demo.start()
  demo.handlers['toko:select']({ id: 'TOKO-2' })
  tracker.start({
    tracking: demo.trackingInfo,
    menu: demo.menuInfo,
    createOrder: demo.createTableOrder,
    queueBoard: demo.queueBoardInfo
  })
  await new Promise((resolve) => setTimeout(resolve, 300))
})

test.after(() => {
  tracker.stop()
  demo.stop()
})

test('checkout kasir menerbitkan nomor antrian + token lacak', async () => {
  // Katalog per toko: ambil item pertama dari katalog toko aktif (bakso)
  const p = demo.handlers['produk:list']({}).data[0]
  assert.match(p.id, /^BSO-/) // memastikan katalog bakso yang aktif, bukan minimarket
  const co = demo.handlers['trx:checkout']({
    items: [{ idProduk: p.id, harga: p.harga_jual, kuantitas: 2 }],
    tipePembayaran: 'TUNAI',
    dibayar: p.harga_jual * 2
  })
  assert.equal(co.ok, true)
  assert.match(co.data.no_antrian, /^A-\d{3}$/)
  assert.match(co.data.token_lacak, /^[0-9a-f]{32}$/)

  // Halaman lacak pelanggan hidup dan memuat nomor antrian
  const res = await fetch(`${asal}/t/${co.data.token_lacak}`)
  const html = await res.text()
  assert.equal(res.status, 200)
  assert.ok(html.includes(co.data.no_antrian))
  assert.ok(html.includes('Bakso Mantap Demo'))
})

test('token lacak palsu ditolak 404', async () => {
  const res = await fetch(`${asal}/t/${'0'.repeat(32)}`)
  assert.equal(res.status, 404)
})

test('QR SVG data URI valid', () => {
  const uri = qr.svgDataUri(`${asal}/t/contoh`)
  assert.ok(uri.startsWith('data:image/svg+xml'))
  assert.ok(uri.length > 500)
})

test('alur QR meja (warung open bill): pesan dari HP → langsung ke bon meja + dapur', async () => {
  const kode = demo.handlers['table:list']({}).data[0].kode // MEJA-1
  const p = demo.handlers['produk:list']({}).data[0]

  // Menu tampil untuk kode sah (berisi katalog bakso); kode palsu 404
  const menuRes = await fetch(`${asal}/o/${kode}`)
  assert.equal(menuRes.status, 200)
  assert.ok((await menuRes.text()).includes(`q_${p.id}`))
  assert.equal((await fetch(`${asal}/o/TIDAK-ADA`)).status, 404)

  // Pelanggan memesan dari HP
  const postRes = await fetch(`${asal}/o/${kode}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ nama: 'Budi Uji', [`q_${p.id}`]: '2' }).toString()
  })
  assert.equal(postRes.status, 200)
  const token = (await postRes.text()).match(/\/t\/([0-9a-f]{32})/)[1]

  // Warung open bill: pesanan langsung ke dapur (ANTRIAN), dikenali dari MEJA,
  // dibayar via bon di akhir (bukan pay-first MENUNGGU_BAYAR).
  const order = demo.handlers['order:list']({}).data.find((o) => o.token_lacak === token)
  assert.equal(order.stage, 'ANTRIAN')
  assert.equal(order.no_antrian, null)
  assert.equal(order.bayar, 'BON')
  assert.match(order.meja, /Meja 1/)

  // Meja 1 terisi di peta; bon memuat pesanan pelanggan
  const meja1 = demo.handlers['bill:peta']({}).data.tables.find((t) => t.nomor === '1')
  assert.ok(meja1.bill)
  assert.ok(meja1.bill.total > 0)

  // Halaman lacak menampilkan keterangan bon meja
  const lacak = await (await fetch(`${asal}/t/${token}`)).text()
  assert.ok(lacak.includes('bon meja'))

  // Papan antrian TV ikut menampilkan pesanan meja (label MEJA, tanpa antrian)
  const papan = demo.queueBoardInfo()
  assert.ok(papan.rows.some((r) => r.meja && /^Meja /.test(r.label)))
  const tv = await (await fetch(`${asal}/antrian`)).text()
  assert.ok(tv.includes('Meja 1'))
})

test('bon meja kasir: buka → 2 ronde (agregasi) → cetak bill → bayar → meja kosong; gabung 2 meja', () => {
  const meja8 = demo.handlers['bill:peta']({}).data.tables.find((t) => t.nomor === '8')
  assert.equal(meja8.bill, null) // MEJA-8 tidak di-seed
  const prod = demo.handlers['produk:list']({}).data

  const buka = demo.handlers['bill:buka']({ mejaId: meja8.id, pax: 4 })
  assert.equal(buka.ok, true)
  assert.equal(buka.data.status, 'BUKA')
  const billId = buka.data.id

  // Ronde 1 → tiket dapur berlabel MEJA, tanpa nomor antrian, bayar BON
  const r1 = demo.handlers['bill:tambahRonde']({ id: billId, items: [{ idProduk: prod[0].id, kuantitas: 2 }] })
  assert.equal(r1.ok, true)
  assert.match(r1.data.order.meja, /Meja 8/)
  assert.equal(r1.data.order.bayar, 'BON')
  assert.equal(r1.data.order.no_antrian, null)

  // Ronde 2 (pesanan susulan) → item sama teragregasi jadi satu baris
  const r2 = demo.handlers['bill:tambahRonde']({ id: billId, items: [{ idProduk: prod[0].id, kuantitas: 1 }, { idProduk: prod[6].id, kuantitas: 2 }] })
  assert.equal(r2.data.bill.ronde, 2)
  assert.equal(r2.data.bill.items.find((it) => it.idProduk === prod[0].id).kuantitas, 3)

  // Cetak pra-bon (belum bayar) — status BILL, total sama dengan bon berjalan
  const cetak = demo.handlers['bill:cetak']({ id: billId })
  assert.equal(cetak.ok, true)
  assert.equal(cetak.data.bill.status, 'BILL')
  assert.equal(cetak.data.prabon.grand_total, r2.data.bill.total)

  // Bayar → struk terbit, meja kosong lagi, bayar ulang ditolak
  const bayar = demo.handlers['bill:bayar']({ id: billId, tipePembayaran: 'QRIS' })
  assert.equal(bayar.ok, true)
  assert.equal(bayar.data.struk.grand_total, r2.data.bill.total)
  assert.match(bayar.data.struk.meja, /Meja 8/)
  assert.equal(demo.handlers['bill:peta']({}).data.tables.find((t) => t.nomor === '8').bill, null)
  assert.equal(demo.handlers['bill:bayar']({ id: billId }).status, 404)

  // Gabung dua meja kosong (rombongan) → satu bon lintas-meja
  const kosong = demo.handlers['bill:peta']({}).data.tables.filter((t) => !t.bill).slice(0, 2)
  const bA = demo.handlers['bill:buka']({ mejaId: kosong[0].id, pax: 2 }).data
  demo.handlers['bill:tambahRonde']({ id: bA.id, items: [{ idProduk: prod[1].id, kuantitas: 1 }] })
  const bB = demo.handlers['bill:buka']({ mejaId: kosong[1].id, pax: 3 }).data
  demo.handlers['bill:tambahRonde']({ id: bB.id, items: [{ idProduk: prod[2].id, kuantitas: 1 }] })
  const gab = demo.handlers['bill:gabung']({ idUtama: bA.id, idGabung: bB.id })
  assert.equal(gab.ok, true)
  assert.equal(gab.data.meja_ids.length, 2)
  assert.equal(gab.data.pax, 5)
  const petaG = demo.handlers['bill:peta']({}).data.tables
  assert.equal(petaG.find((t) => t.id === kosong[0].id).bill.id, petaG.find((t) => t.id === kosong[1].id).bill.id)
})

test('bon meja: pelunasan mengurangi stok barang ber-kelola-stok', () => {
  const kerupuk = demo.handlers['produk:list']({}).data.find((p) => p.kelola_stok) // TMB-001
  assert.ok(kerupuk)
  const stokAwal = kerupuk.stok
  const meja = demo.handlers['bill:peta']({}).data.tables.find((t) => !t.bill)
  const bill = demo.handlers['bill:buka']({ mejaId: meja.id, pax: 2 }).data
  demo.handlers['bill:tambahRonde']({ id: bill.id, items: [{ idProduk: kerupuk.id, kuantitas: 3 }] })
  assert.equal(demo.handlers['bill:bayar']({ id: bill.id, tipePembayaran: 'TUNAI' }).ok, true)
  const stokAkhir = demo.handlers['produk:list']({}).data.find((p) => p.id === kerupuk.id).stok
  assert.equal(stokAkhir, stokAwal - 3)
})

test('transisi papan pesanan berurutan & menolak lompatan', () => {
  const orderId = demo.handlers['order:list']({}).data.find((o) => o.stage === 'ANTRIAN').id
  assert.equal(demo.handlers['order:transition']({ id: orderId, to: 'READY' }).status, 409)
  assert.equal(demo.handlers['order:transition']({ id: orderId, to: 'DIPROSES' }).ok, true)
})

test('laundry: layanan kiloan menerima berat desimal & katalog per toko', () => {
  demo.handlers['toko:select']({ id: 'TOKO-3' })

  // Katalog toko laundry — bukan bakso/minimarket
  const daftar = demo.handlers['produk:list']({}).data
  assert.ok(daftar.every((p) => p.id.startsWith('LDR-')))
  const kiloan = daftar.find((p) => p.satuan === 'Kg')
  assert.ok(kiloan)

  // Checkout 4.5 kg
  const co = demo.handlers['trx:checkout']({
    items: [{ idProduk: kiloan.id, harga: kiloan.harga_jual, kuantitas: 4.5 }],
    tipePembayaran: 'TUNAI',
    dibayar: 100000
  })
  assert.equal(co.ok, true)
  assert.equal(co.data.items[0].kuantitas, 4.5)
  assert.equal(co.data.subtotal, 4.5 * kiloan.harga_jual)
  assert.match(co.data.no_antrian, /^L-\d{3}$/) // nota laundry masuk papan proses
})

test('laundry: nota bayar-saat-ambil → pelunasan menerbitkan struk & menyerahkan', () => {
  // (toko aktif masih TOKO-3 dari test sebelumnya)
  const kiloan = demo.handlers['produk:list']({}).data.find((p) => p.satuan === 'Kg')

  const simpan = demo.handlers['order:simpanNota']({
    items: [{ idProduk: kiloan.id, harga: kiloan.harga_jual, kuantitas: 3 }]
  })
  assert.equal(simpan.ok, true)
  assert.equal(simpan.data.order.bayar, 'BELUM')
  assert.match(simpan.data.order.no_antrian, /^L-\d{3}$/)
  assert.equal(simpan.data.nota.status, 'BELUM LUNAS')
  assert.equal(simpan.data.nota.grand_total, 3 * kiloan.harga_jual)

  // Muncul di papan dengan tanda belum bayar
  const diPapan = demo.handlers['order:list']({}).data.find((o) => o.id === simpan.data.order.id)
  assert.equal(diPapan.bayar, 'BELUM')

  // Pelunasan: struk terbit, order lunas & selesai; pelunasan ganda ditolak
  const lunas = demo.handlers['order:lunasi']({ id: simpan.data.order.id, tipePembayaran: 'QRIS' })
  assert.equal(lunas.ok, true)
  assert.equal(lunas.data.order.bayar, 'LUNAS')
  assert.equal(lunas.data.order.stage, 'SELESAI')
  assert.equal(lunas.data.struk.tipe_pembayaran, 'QRIS')
  assert.equal(lunas.data.struk.grand_total, 3 * kiloan.harga_jual)
  assert.equal(demo.handlers['order:lunasi']({ id: simpan.data.order.id }).status, 409)
})
