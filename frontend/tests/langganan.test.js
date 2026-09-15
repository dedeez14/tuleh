'use strict'

// Unit test turunan status langganan (Sistem Mitra §6.5).
// ringkasLangganan() dipakai bersama oleh notifikasi & banner Beranda.

const test = require('node:test')
const assert = require('node:assert/strict')

let L
test.before(async () => {
  L = await import('../src/renderer/js/langganan.js')
})

test('data kosong/null → level none, tanpa aksi', () => {
  // Arrange & Act
  const r = L.ringkasLangganan(null)
  // Assert
  assert.equal(r.level, 'none')
  assert.equal(r.perluAksi, false)
})

test('aktif dengan sisa banyak → ok, tanpa aksi', () => {
  const r = L.ringkasLangganan({ status: 'AKTIF', sisa_hari: 21, plan_nama: 'Tuléh Pro' })
  assert.equal(r.level, 'ok')
  assert.equal(r.perluAksi, false)
})

test('aktif dengan sisa <= ambang dari server → segera + perlu aksi + detail menyebut hari', () => {
  const r = L.ringkasLangganan({ status: 'AKTIF', sisa_hari: 5, ambang_peringatan_hari: 5, plan_nama: 'Pro' })
  assert.equal(r.level, 'segera')
  assert.equal(r.perluAksi, true)
  assert.match(r.detail, /5 hari/)
})

test('ambang mengikuti server (kontrak #3): sisa 10 dengan ambang 14 → segera; ambang 7 → ok', () => {
  assert.equal(L.ringkasLangganan({ status: 'AKTIF', sisa_hari: 10, ambang_peringatan_hari: 14 }).level, 'segera')
  assert.equal(L.ringkasLangganan({ status: 'AKTIF', sisa_hari: 10, ambang_peringatan_hari: 7 }).level, 'ok')
  assert.equal(L.ringkasLangganan({ status: 'AKTIF', sisa_hari: 0, ambang_peringatan_hari: '3' }).level, 'segera', 'angka berupa string tetap sah')
})

test('tanpa ambang_peringatan_hari (server lama / belum diisi) → TIDAK ada peringatan segera', () => {
  const r = L.ringkasLangganan({ status: 'AKTIF', sisa_hari: 1 })
  assert.equal(r.level, 'ok')
  assert.equal(r.perluAksi, false)
  assert.equal(L.ringkasLangganan({ status: 'AKTIF', sisa_hari: 1, ambang_peringatan_hari: null }).level, 'ok')
  assert.equal(L.ringkasLangganan({ status: 'AKTIF', sisa_hari: 1, ambang_peringatan_hari: 'x' }).level, 'ok')
  assert.equal(L.ambangPeringatanHari({ ambang_peringatan_hari: true }), null)
  assert.equal('AMBANG_PERINGATAN_HARI' in L, false, 'konstanta ambang tidak boleh ada di aplikasi')
})

test('modelKunciLangganan: pesan & URL dari server; URL non-https/kosong → tanpa tombol', () => {
  const m = L.modelKunciLangganan({ pesan: 'Langganan berakhir 1 Sep.', perpanjang_url: 'https://contoh.test/perpanjang?x=1' })
  assert.equal(m.judul, 'Langganan berakhir')
  assert.equal(m.pesan, 'Langganan berakhir 1 Sep.')
  assert.equal(m.perpanjangUrl, 'https://contoh.test/perpanjang?x=1')
  assert.equal(L.modelKunciLangganan({ perpanjang_url: 'http://contoh.test' }).perpanjangUrl, null)
  assert.equal(L.modelKunciLangganan({ perpanjang_url: 'javascript:alert(1)' }).perpanjangUrl, null)
  assert.equal(L.modelKunciLangganan({ perpanjang_url: 'https://user:pw@contoh.test' }).perpanjangUrl, null)
  assert.equal(L.modelKunciLangganan({}).perpanjangUrl, null)
  assert.ok(L.modelKunciLangganan(null).pesan.length > 0, 'pesan cadangan netral bila server tak mengirim teks')
  assert.doesNotMatch(L.modelKunciLangganan(null).pesan, /https?:|wa\.me|@/, 'cadangan tanpa kontak/URL tertanam')
})

test('status GRACE → perlu aksi', () => {
  const r = L.ringkasLangganan({ status: 'GRACE', sisa_hari: 0 })
  assert.equal(r.level, 'grace')
  assert.equal(r.perluAksi, true)
})

test('status KEDALUWARSA → perlu aksi', () => {
  const r = L.ringkasLangganan({ status: 'KEDALUWARSA', sisa_hari: 0 })
  assert.equal(r.level, 'kedaluwarsa')
  assert.equal(r.perluAksi, true)
})

test('aktif tapi sisa_hari tak valid → tetap ok (tak memicu peringatan)', () => {
  const r = L.ringkasLangganan({ status: 'AKTIF', sisa_hari: null })
  assert.equal(r.level, 'ok')
  assert.equal(r.perluAksi, false)
})

test('status huruf kecil tetap dikenali (case-insensitive)', () => {
  const r = L.ringkasLangganan({ status: 'kedaluwarsa', sisa_hari: 0 })
  assert.equal(r.level, 'kedaluwarsa')
})
