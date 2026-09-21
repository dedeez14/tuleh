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
  // Kode toko diteruskan bila server mengirimnya — dipakai pilihTokoSesi (id tak bisa dibandingkan).
  const berkode = { ok: false, status: 409, errors: { kode: ['SESI_BEDA_TOKO'] }, meta: { sesi_toko: { id: 'T1', kode: 'TK-001', nama: 'Toko Pusat' } } }
  assert.deepEqual(K.tokoSesi(berkode), { id: 'T1', kode: 'TK-001', nama: 'Toko Pusat' })
})

test('labelTombol409: pindah toko / buka sesi / bukan urusan kita', () => {
  const beda = { ok: false, status: 409, errors: { kode: ['SESI_BEDA_TOKO'] }, meta: { sesi_toko: { id: 'T1', nama: 'Toko Pusat' } } }
  assert.deepEqual(K.labelTombol409(beda), { mode: 'pindah', nama: 'Toko Pusat' })
  // 409 lama (belum ada sesi) atau server tanpa meta → tetap tawarkan buka sesi.
  assert.deepEqual(K.labelTombol409({ ok: false, status: 409, errors: null, meta: null }), { mode: 'buka-sesi' })
  assert.deepEqual(K.labelTombol409({ ok: false, status: 409, errors: { kode: ['SESI_BEDA_TOKO'] }, meta: null }), { mode: 'buka-sesi' })
  assert.equal(K.labelTombol409({ ok: false, status: 422, errors: null }), null)
  assert.equal(K.labelTombol409({ ok: true, status: 200 }), null)
  assert.equal(K.labelTombol409(null), null)
})

test('pilihTokoSesi: kode lebih kuat dari id (ciphertext non-deterministik)', () => {
  const daftar = [
    { id: 'eyJA', kode: 'TK-001', nama: 'Toko Pusat', bidang_usaha: { nama: 'Ritel' } },
    { id: 'eyJB', kode: 'TK-002', nama: 'Cabang Dua' }
  ]
  // id dari meta 409 BEDA dengan id daftar walau toko yang sama → kode yang menentukan.
  const lewatKode = K.pilihTokoSesi(daftar, { id: 'eyJZ', kode: 'TK-001', nama: 'Toko Pusat (Lama)' })
  assert.equal(lewatKode.nama, 'Toko Pusat')
  assert.equal(lewatKode.bidang_usaha.nama, 'Ritel', 'bidang usaha ikut dari daftar')
  assert.equal(lewatKode.id, 'eyJZ', 'id dari 409 dipakai — yang sah di server')
})

test('pilihTokoSesi: tanpa kode jatuh ke nama (rapi & tak peduli huruf besar)', () => {
  const daftar = [{ id: 'eyJA', nama: 'Toko Pusat' }, { id: 'eyJB', nama: 'Cabang Dua' }]
  const lewatNama = K.pilihTokoSesi(daftar, { id: 'eyJZ', nama: '  toko pusat ' })
  assert.equal(lewatNama.id, 'eyJZ')
  assert.equal(lewatNama.nama, 'Toko Pusat')
})

test('pilihTokoSesi: tak ada di daftar → pakai apa adanya dari 409, jangan tolak', () => {
  const sesi = { id: 'eyJZ', kode: 'TK-009', nama: 'Toko Baru' }
  assert.deepEqual(K.pilihTokoSesi([{ id: 'eyJA', kode: 'TK-001', nama: 'Toko Pusat' }], sesi), sesi)
  assert.deepEqual(K.pilihTokoSesi(null, sesi), sesi)
  assert.equal(K.pilihTokoSesi([], null), null)
})

test('batal konfirmasi ganti toko: keranjang tetap utuh & masih terikat toko lama', () => {
  let dikosongkan = 0
  K.catatKeranjang({ jumlah: 4, tokoId: 'T1', kosongkan: () => { dikosongkan += 1 } })
  assert.equal(K.keranjangLain('T2'), true, 'pemilih toko wajib bertanya dulu')
  // Kasir menekan "Batal" → app.js TIDAK memanggil kosongkanKeranjang().
  assert.equal(dikosongkan, 0)
  assert.deepEqual(K.ringkasKeranjang(), { jumlah: 4, tokoId: 'T1' })
  assert.equal(K.keranjangLain('T1'), false, 'tetap sah untuk tokonya sendiri')
})
