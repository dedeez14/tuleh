'use strict'

// Dialog persetujuan (Tahap B §2c): kapan persetujuan diminta, label tombolnya, dan validasi isian
// sebelum PIN dikirim ke server (PIN tidak pernah disimpan di perangkat).

const test = require('node:test')
const assert = require('node:assert/strict')

let O
test.before(async () => { O = await import('../src/renderer/js/lib/otorisasi.js') })

test('perluPersetujuan: hanya bila pengguna TIDAK punya haknya sendiri', () => {
  assert.equal(O.perluPersetujuan('transaksi.batal', { punyaHak: false }), true)
  assert.equal(O.perluPersetujuan('transaksi.batal', { punyaHak: true }), false)
  assert.equal(O.perluPersetujuan('gudang.hapus', { punyaHak: false }), false, 'aksi di luar daftar tak bisa didelegasikan')
})

test('labelAksi memberi tahu kasir bahwa persetujuan diperlukan', () => {
  assert.equal(O.labelAksi('transaksi.batal', true), 'Batalkan Transaksi')
  assert.equal(O.labelAksi('transaksi.batal', false), 'Batalkan Transaksi (perlu persetujuan)')
  assert.equal(O.labelAksi('transaksi.refund', false), 'Refund (perlu persetujuan)')
})

test('validasiIsianOtorisasi: pemberi wajib dipilih, PIN 4–8 digit', () => {
  assert.equal(O.validasiIsianOtorisasi({ pemberiId: 'U1', pin: '2468' }), '')
  assert.match(O.validasiIsianOtorisasi({ pemberiId: '', pin: '2468' }), /Pilih pemberi/)
  assert.match(O.validasiIsianOtorisasi({ pemberiId: 'U1', pin: '12' }), /4–8 digit/)
  assert.match(O.validasiIsianOtorisasi({ pemberiId: 'U1', pin: 'abcd' }), /4–8 digit/)
})

// Kunci PIN (server KeamananController::terkunciPin) menjawab 429 dengan data.terkunci_detik.
// Dialog memakainya untuk hitung mundur; tanpa angka itu, kalimat server yang dipakai apa adanya.
test('pesanTerkunci: hitung mundur dari data.terkunci_detik, jatuh ke pesan server bila tak ada', () => {
  assert.match(O.pesanTerkunci({ status: 429, data: { terkunci_detik: 47 }, message: 'x' }), /47 detik/)
  assert.equal(O.pesanTerkunci({ status: 429, message: 'Terlalu banyak PIN salah.' }), 'Terlalu banyak PIN salah.')
  assert.equal(O.pesanTerkunci({ status: 422, data: { terkunci_detik: 47 }, message: 'PIN salah. Sisa percobaan: 3.' }), '', 'bukan 429 → bukan urusan hitung mundur')
})

test('detikTerkunci: hanya angka positif yang masuk akal', () => {
  assert.equal(O.detikTerkunci({ status: 429, data: { terkunci_detik: 47 } }), 47)
  assert.equal(O.detikTerkunci({ status: 429, data: { terkunci_detik: '47' } }), 47)
  for (const buruk of [{ status: 429 }, { status: 429, data: null }, { status: 429, data: { terkunci_detik: 0 } }, { status: 429, data: { terkunci_detik: 'x' } }, { status: 500, data: { terkunci_detik: 9 } }]) {
    assert.equal(O.detikTerkunci(buruk), 0, JSON.stringify(buruk))
  }
})
