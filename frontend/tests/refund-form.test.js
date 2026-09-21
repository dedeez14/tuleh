'use strict'

// Formulir refund Riwayat (desktop & Android Capacitor): baris bersisa, validasi sebelum ke server, perkiraan dana.

const test = require('node:test')
const assert = require('node:assert/strict')

let F
const struk = {
  id: 'T1', nomor: 'POS-000051', status: 'SELESAI', tipe_pembayaran: 'TUNAI',
  items: [
    { id: 'I1', nama: 'Kopi Susu', satuan: 'cup', kuantitas: 2, subtotal: 36000, qty_refund: 0, qty_bisa_refund: 2 },
    { id: 'I2', nama: 'Cuci Kiloan', satuan: 'kg', kuantitas: 2.5, subtotal: 17500, qty_refund: 2.5, qty_bisa_refund: 0 },
    { id: 'I3', nama: 'Beras', satuan: 'kg', kuantitas: 3, subtotal: 45000, qty_refund: 1, qty_bisa_refund: 2 }
  ]
}

test.before(async () => { F = await import('../src/renderer/js/lib/refund-form.js') })

test('barisRefund: hanya baris bersisa; langkah 1 untuk hitungan, desimal untuk terukur; nilai per unit dari subtotal', () => {
  const b = F.barisRefund(struk)
  assert.deepEqual(b.map((x) => x.id), ['I1', 'I3'])
  assert.equal(b[0].langkah, 1)
  assert.equal(b[1].langkah, 0.01, 'kg = terukur, langkah 0,01')
  assert.equal(b[0].nilaiPerUnit, 18000)
  assert.equal(b[1].nilaiPerUnit, 15000)
  assert.equal(b[1].sisa, 2)
})

test('bisaDirefund: dibatalkan / belum sinkron / lokal / tanpa sisa = tidak', () => {
  assert.equal(F.bisaDirefund(struk), true)
  assert.equal(F.bisaDirefund({ ...struk, status: 'DIBATALKAN' }), false)
  assert.equal(F.bisaDirefund({ ...struk, belum_sinkron: true }), false)
  assert.equal(F.bisaDirefund({ ...struk, id: 'lokal:abc' }), false)
  assert.equal(F.bisaDirefund({ ...struk, items: [struk.items[1]] }), false)
  assert.equal(F.bisaDirefund(null), false)
})

test('perkiraanRefund dari qty terpilih (nilai pasti tetap dari server)', () => {
  assert.equal(F.perkiraanRefund(struk, { I1: 1, I3: 0.5 }), 18000 + 7500)
  assert.equal(F.perkiraanRefund(struk, {}), 0)
})

test('susunPermintaanRefund: payload kanal trx:refund; validasi sisa, alasan, metode', () => {
  const p = F.susunPermintaanRefund(struk, { qty: { I1: 1, I3: 0 }, metode: 'TUNAI', alasan: ' Tumpah ', kembaliStok: false })
  assert.deepEqual(p, { id: 'T1', baris: [{ id: 'I1', kuantitas: 1 }], metode: 'TUNAI', alasan: 'Tumpah', kembaliStok: false })
  assert.equal(F.susunPermintaanRefund(struk, { qty: { I1: 1 }, metode: 'TUNAI', alasan: 'Tumpah' }).kembaliStok, true)
  assert.throws(() => F.susunPermintaanRefund(struk, { qty: { I1: 3 }, metode: 'TUNAI', alasan: 'Tumpah' }), /melebihi sisa/)
  assert.throws(() => F.susunPermintaanRefund(struk, { qty: {}, metode: 'TUNAI', alasan: 'Tumpah' }), /minimal satu item/)
  assert.throws(() => F.susunPermintaanRefund(struk, { qty: { I1: 1 }, metode: 'TUNAI', alasan: 'ok' }), /minimal 3/)
  assert.throws(() => F.susunPermintaanRefund(struk, { qty: { I1: 1 }, alasan: 'Tumpah' }), /wajib dipilih/)
})

test('susunPermintaanRefund: barang hitungan wajib bulat; barang terukur dibulatkan ke langkah satuannya', () => {
  assert.throws(() => F.susunPermintaanRefund(struk, { qty: { I1: 0.5 }, metode: 'TUNAI', alasan: 'Tumpah' }), /bilangan bulat/)
  const p = F.susunPermintaanRefund(struk, { qty: { I3: 0.555 }, metode: 'TUNAI', alasan: 'Tumpah' })
  assert.deepEqual(p.baris, [{ id: 'I3', kuantitas: 0.56 }])
  // I3 (Beras, kg, sisa 2, langkah 0,01): 2,01 sudah kelipatan langkah jadi dibulatkan ke
  // dirinya sendiri (2,01), lalu melebihi sisa 2 — memastikan pemeriksaan sisa jalan setelah
  // pembulatan (2,004 dipakai spec awal ternyata dibulatkan turun jadi 2, jadi tak berguna di sini).
  assert.throws(() => F.susunPermintaanRefund(struk, { qty: { I3: 2.01 }, metode: 'TUNAI', alasan: 'Tumpah' }), /melebihi sisa/)
})
