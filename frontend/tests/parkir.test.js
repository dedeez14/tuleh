'use strict'

// Parkir keranjang (kasir desktop): simpan/lanjutkan keranjang per toko,
// batas jumlah, penomoran, dan pemulihan baris memakai katalog terbaru.

const test = require('node:test')
const assert = require('node:assert/strict')

let P

class MemStorage {
  constructor() { this.m = new Map() }
  getItem(k) { return this.m.has(k) ? this.m.get(k) : null }
  setItem(k, v) { this.m.set(k, String(v)) }
}

const kopi = { id: 'P1', nama: 'Kopi', harga_jual: 18000, stok: 10, kelola_stok: true, gambar: 'data:...besar' }
const roti = { id: 'P2', nama: 'Roti', harga_jual: 15000 }

test.before(async () => {
  P = await import('../src/renderer/js/lib/parkir.js')
})

test('tambahParkir membuat entri bernomor urut tanpa mengubah daftar asal', () => {
  const awal = []
  const { daftar, entri } = P.tambahParkir(awal, {
    items: [{ produk: kopi, kuantitas: 2, diskonPersen: 0 }, { produk: roti, kuantitas: 1 }],
    pelanggan: { id: 'C1', nama: 'Budi', telepon: '0812' }
  }, 1000)
  assert.equal(awal.length, 0)
  assert.equal(daftar.length, 1)
  assert.equal(entri.nomor, 1)
  assert.equal(entri.waktu, 1000)
  assert.equal(entri.pelanggan.nama, 'Budi')
  assert.equal(entri.items[0].produk.gambar, undefined, 'salinan produk tanpa bidang besar')
  const { daftar: d2, entri: e2 } = P.tambahParkir(daftar, { items: [{ produk: roti, kuantitas: 3 }] }, 2000)
  assert.equal(e2.nomor, 2)
  assert.equal(d2.length, 2)
})

test('tambahParkir menolak keranjang kosong dan daftar penuh', () => {
  assert.equal(P.tambahParkir([], { items: [] }).entri, null)
  let daftar = []
  for (let i = 0; i < P.MAKS_PARKIR; i++) daftar = P.tambahParkir(daftar, { items: [{ produk: roti, kuantitas: 1 }] }, i).daftar
  const penuh = P.tambahParkir(daftar, { items: [{ produk: roti, kuantitas: 1 }] })
  assert.equal(penuh.entri, null)
  assert.match(penuh.alasan, /Maksimal 20/)
})

test('ringkasParkir menghitung baris, qty, dan total dengan diskon', () => {
  const { entri } = P.tambahParkir([], { items: [{ produk: kopi, kuantitas: 2, diskonPersen: 50 }, { produk: roti, kuantitas: 1 }] })
  assert.deepEqual(P.ringkasParkir(entri), { baris: 2, qty: 3, total: 18000 + 15000 })
})

test('pulihkanBaris memakai produk katalog terbaru bila ada, salinan bila tidak', () => {
  const { entri } = P.tambahParkir([], { items: [{ produk: kopi, kuantitas: 2 }, { produk: roti, kuantitas: 1 }] })
  const kopiBaru = { ...kopi, harga_jual: 20000, stok: 3 }
  const baris = P.pulihkanBaris(entri, [kopiBaru])
  assert.equal(baris[0].produk.harga_jual, 20000)
  assert.equal(baris[0].kuantitas, 2)
  assert.equal(baris[1].produk.nama, 'Roti')
})

test('simpan/baca per toko lewat storage; data rusak → kosong', () => {
  const st = new MemStorage()
  const { daftar } = P.tambahParkir([], { items: [{ produk: roti, kuantitas: 1 }] }, 5)
  P.simpanParkir(st, 'T1', daftar)
  assert.equal(P.bacaParkir(st, 'T1').length, 1)
  assert.equal(P.bacaParkir(st, 'T2').length, 0)
  st.setItem(P.kunciParkir('T3'), '{rusak')
  assert.deepEqual(P.bacaParkir(st, 'T3'), [])
  assert.equal(P.hapusParkir(daftar, daftar[0].id).length, 0)
})
