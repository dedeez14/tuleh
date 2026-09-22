'use strict'

// Uang muka (DP) pesanan bayar-nanti — logika murni layar kasir & papan pesanan (Fase 3, desktop 0.9.40).

const test = require('node:test')
const assert = require('node:assert/strict')

let D
test.before(async () => { D = await import('../src/renderer/js/lib/dp-form.js') })

const rp = (n) => 'Rp' + Number(n).toLocaleString('id-ID')

test('mode bayar: Lunas saja, kecuali alur toko PAYMENT_OR_LATER', () => {
  assert.deepEqual(D.modeBayarTersedia({ transactionFlow: ['PAYMENT'] }), ['LUNAS'])
  assert.deepEqual(D.modeBayarTersedia(null), ['LUNAS'])
  assert.deepEqual(D.modeBayarTersedia({ transactionFlow: ['PAYMENT_OR_LATER'] }), ['LUNAS', 'NANTI', 'DP'])
})

test('total nota = harga × kuantitas (sama dengan hitungan server, tanpa diskon/pajak)', () => {
  assert.equal(D.totalNota([{ harga: 28000, kuantitas: 1 }, { harga: 5000, kuantitas: 2.5 }]), 40500)
  assert.equal(D.totalNota([]), 0)
})

test('validasi uang muka: > 0, < total, metode wajib', () => {
  assert.equal(D.validasiUangMuka({ jumlah: 0, total: 28000, metode: 'TUNAI' }), 'Isi uang muka lebih dari Rp0.')
  assert.equal(D.validasiUangMuka({ jumlah: NaN, total: 28000, metode: 'TUNAI' }), 'Isi uang muka lebih dari Rp0.')
  assert.match(D.validasiUangMuka({ jumlah: 28000, total: 28000, metode: 'TUNAI' }), /kurang dari total/)
  assert.match(D.validasiUangMuka({ jumlah: 30000, total: 28000, metode: 'TUNAI' }), /kurang dari total/)
  assert.equal(D.validasiUangMuka({ jumlah: 10000, total: 28000, metode: '' }), 'Pilih metode pembayaran uang muka.')
  assert.equal(D.validasiUangMuka({ jumlah: 10000, total: 28000, metode: 'QRIS' }), null)
})

test('susun nota: NANTI tanpa dp; DP membawa jumlah & metode; mode lain ditolak', () => {
  const items = [{ idProduk: 'P1', harga: 28000, kuantitas: 1 }]
  assert.deepEqual(D.susunNota({ mode: 'NANTI', items, idPelanggan: 'C1', catatan: 'x', clientRef: 'r1' }),
    { bayar: 'NANTI', items, idPelanggan: 'C1', catatan: 'x', clientRef: 'r1' })
  assert.deepEqual(D.susunNota({ mode: 'DP', items, uangMuka: 10000, metodeUangMuka: 'TUNAI', clientRef: 'r2' }),
    { bayar: 'DP', items, idPelanggan: undefined, catatan: undefined, clientRef: 'r2', dp: { jumlah: 10000, tipePembayaran: 'TUNAI' } })
  assert.throws(() => D.susunNota({ mode: 'LUNAS', items }), /Bayar nanti atau Uang muka/)
})

test('ringkas bayar kartu papan', () => {
  assert.equal(D.ringkasBayar({ bayar: 'DP', dibayar: 10000, sisa: 18000, total: 28000 }, rp), `DP ${rp(10000)} · sisa ${rp(18000)}`)
  assert.equal(D.ringkasBayar({ bayar: 'BELUM', dibayar: 0, sisa: 28000, total: 28000 }, rp), `Belum bayar · ${rp(28000)}`)
  assert.equal(D.ringkasBayar({ bayar: 'BELUM', total: 28000 }, rp), `Belum bayar · ${rp(28000)}`, 'server lama tanpa sisa')
  assert.equal(D.ringkasBayar({ bayar: 'LUNAS', total: 28000 }, rp), '')
  assert.equal(D.ringkasBayar({ bayar: 'BON', total: 28000 }, rp), '')
})

test('perlu dilunasi: BELUM & DP saja (BON lewat bill)', () => {
  assert.equal(D.perluDilunasi({ bayar: 'DP' }), true)
  assert.equal(D.perluDilunasi({ bayar: 'BELUM' }), true)
  assert.equal(D.perluDilunasi({ bayar: 'LUNAS' }), false)
  assert.equal(D.perluDilunasi({ bayar: 'BON' }), false)
  assert.equal(D.perluDilunasi(null), false)
})
