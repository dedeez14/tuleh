'use strict'

// Keranjang terikat toko tempat item pertama masuk (Tahap B §2a): ganti toko dengan keranjang
// berisi wajib bertanya, dan 409 SESI_BEDA_TOKO dari server dikenali dari kode mesinnya.

const test = require('node:test')
const assert = require('node:assert/strict')

let K
test.before(async () => { K = await import('../src/renderer/js/lib/keranjang-toko.js') })
test.beforeEach(() => { K.catatKeranjang({ jumlah: 0, tokoId: null, kosongkan: null }) })

test('keranjangLain: hanya bila ada isi DAN tokonya berbeda', () => {
  assert.equal(K.keranjangLain('T2'), false, 'keranjang kosong = bebas pindah')
  K.catatKeranjang({ jumlah: 2, tokoId: 'T1' })
  assert.equal(K.keranjangLain('T2'), true)
  assert.equal(K.keranjangLain('T1'), false)
  assert.deepEqual(K.ringkasKeranjang(), { jumlah: 2, tokoId: 'T1' })
  K.catatKeranjang({ jumlah: 0, tokoId: null })
  assert.equal(K.keranjangLain('T2'), false)
})

test('kosongkanKeranjang memanggil pengosong layar kasir lalu melupakan isinya', () => {
  let dipanggil = 0
  K.catatKeranjang({ jumlah: 3, tokoId: 'T1', kosongkan: () => { dipanggil += 1 } })
  K.kosongkanKeranjang()
  assert.equal(dipanggil, 1)
  assert.equal(K.keranjangLain('T2'), false)
  K.kosongkanKeranjang() // aman dipanggil dua kali
  assert.equal(dipanggil, 2)
})

test('kodeGalat & tokoSesi membaca amplop 409 server (errors.kode + meta.sesi_toko)', () => {
  const g409 = { ok: false, status: 409, message: 'Sesi kasir Anda dibuka di toko Toko Pusat.', errors: { kode: ['SESI_BEDA_TOKO'] }, meta: { sesi_toko: { id: 'T1', nama: 'Toko Pusat' } } }
  assert.equal(K.kodeGalat(g409), 'SESI_BEDA_TOKO')
  assert.deepEqual(K.tokoSesi(g409), { id: 'T1', nama: 'Toko Pusat' })
  // 409 "belum ada sesi" lama: tanpa kode & tanpa meta → jangan tawarkan pindah toko.
  assert.equal(K.kodeGalat({ ok: false, status: 409, message: 'Belum ada sesi kasir.', errors: null, meta: null }), '')
  assert.equal(K.tokoSesi({ ok: false, status: 409, errors: null, meta: null }), null)
  assert.equal(K.kodeGalat(null), '')
})
