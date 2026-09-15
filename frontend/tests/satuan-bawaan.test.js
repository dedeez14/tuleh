'use strict'

// Satuan bawaan produk (server 2026-09-15, agen INTI): item baru tanpa satuan memakai
// satuan bawaan usaha; belum diatur → 422 errors.satuan_id. Pengaturan Usaha membaca
// `satuan_bawaan` dan menulis `satuan_bawaan_id` (id terenkripsi dari /satuan).

const test = require('node:test')
const assert = require('node:assert/strict')

const kontrak = require('../src/shared/kontrak-kanal.js')
const demo = require('../src/main/demo.js')

let G, S
test.before(async () => {
  G = await import('../src/renderer/js/lib/galat-form.js')
  S = await import('../src/renderer/js/lib/satuan-bawaan.js')
  demo.start()
})
test.after(() => demo.stop())

test('galatKolom: pesan pertama kolom dari amplop 422; kosong bila tidak ada', () => {
  const r = { ok: false, status: 422, message: 'x', errors: { satuan_id: ['Pilih satuan.'], nama: ['Wajib'] } }
  assert.equal(G.galatKolom(r, 'satuan_id'), 'Pilih satuan.')
  assert.equal(G.galatKolom(r, 'harga'), '')
  assert.equal(G.galatKolom({ ok: true }, 'satuan_id'), '')
  assert.equal(G.galatKolom({ ok: false, errors: null }, 'satuan_id'), '')
})

test('cocokkanSatuanBawaan: id terenkripsi berbeda tiap jawaban → cocok lewat kode lalu nama', () => {
  const daftar = [{ id: 'enc-a1', kode: 'PCS', nama: 'Pcs' }, { id: 'enc-b1', kode: 'KG', nama: 'Kilogram' }]
  assert.equal(S.cocokkanSatuanBawaan(daftar, { id: 'enc-zz', kode: 'KG', nama: 'Kilogram' }).id, 'enc-b1')
  assert.equal(S.cocokkanSatuanBawaan(daftar, { id: 'enc-zz', nama: 'Pcs' }).id, 'enc-a1')
  assert.equal(S.cocokkanSatuanBawaan(daftar, null), null)
  assert.equal(S.cocokkanSatuanBawaan(daftar, { id: 'x', kode: 'LTR', nama: 'Liter' }), null)
})

test('kontrak: PUT /pengaturan/usaha meneruskan satuan_bawaan_id; kosong → null (belum diatur)', () => {
  const pilih = kontrak.bentuk('pengaturan:usahaSimpan', { satuan_bawaan_id: 'enc-123' })
  assert.deepEqual(pilih.body, { satuan_bawaan_id: 'enc-123' })
  assert.deepEqual(kontrak.bentuk('pengaturan:usahaSimpan', { satuan_bawaan_id: '' }).body, { satuan_bawaan_id: null })
  assert.equal('satuan_bawaan_id' in kontrak.bentuk('pengaturan:usahaSimpan', { nama: 'Toko' }).body, false, 'tidak disebut = tidak diubah')
})

test('Mode Demo: satuan bawaan dipakai item tanpa satuan; dikosongkan → 422 errors.satuan_id', () => {
  const H = demo.handlers
  const usaha = H['pengaturan:usahaGet']().data
  assert.ok(usaha.satuan_bawaan && usaha.satuan_bawaan.kode, 'demo punya satuan bawaan')

  const pakaiBawaan = H['produk:create']({ nama: 'Item tanpa satuan', hargaJual: 5000 })
  assert.equal(pakaiBawaan.ok, true)
  assert.equal(pakaiBawaan.data.satuan, usaha.satuan_bawaan.nama)

  assert.equal(H['pengaturan:usahaSimpan']({ satuan_bawaan_id: null }).data.satuan_bawaan, null)
  const ditolak = H['produk:create']({ nama: 'Item lagi', hargaJual: 5000 })
  assert.equal(ditolak.ok, false)
  assert.equal(ditolak.status, 422)
  assert.match(G.galatKolom(ditolak, 'satuan_id'), /satuan/i)

  const satuan = H['master:satuan']().data
  const dgnSatuan = H['produk:create']({ nama: 'Item bersatuan', hargaJual: 5000, satuanId: satuan[1].id })
  assert.equal(dgnSatuan.ok, true)
  assert.equal(dgnSatuan.data.satuan, satuan[1].nama)

  const asing = H['pengaturan:usahaSimpan']({ satuan_bawaan_id: 'TIDAK-ADA' })
  assert.equal(asing.status, 422)
  assert.ok(G.galatKolom(asing, 'satuan_bawaan_id'))
  assert.equal(H['pengaturan:usahaSimpan']({ satuan_bawaan_id: satuan[0].id }).data.satuan_bawaan.id, satuan[0].id)
})
