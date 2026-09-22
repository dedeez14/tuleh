'use strict'

// Struk teks (bagikan WhatsApp / salin): lebar tetap 32 kolom, nilai rata
// kanan, nama panjang dibungkus per kata, tanda Mode Demo di kepala & kaki.

const test = require('node:test')
const assert = require('node:assert/strict')

let M
const struk = {
  nomor: 'POS-000051',
  tanggal: '2026-09-06T14:05:00',
  kasir: 'Dede',
  tipe_pembayaran: 'TUNAI',
  items: [
    { nama: 'Kopi Susu Gula Aren Spesial Ukuran Besar', kuantitas: 2, harga: 18000, subtotal: 36000 },
    { nama: 'Roti Bakar', kuantitas: 1, harga: 15000, subtotal: 15000, diskon_persen: 10 }
  ],
  subtotal: 51000, total_diskon: 1500, total_pajak: 0, grand_total: 49500, dibayar: 100000, kembalian: 50500
}
const company = { nama: 'Warung Kopi Tuléh', alamat: 'Jl. Melati No. 5, Bandung', telepon: '0812-0000-1111' }

test.before(async () => { M = await import('../src/renderer/js/lib/struk-teks.js') })

test('buildReceiptText: 32 kolom, rata kanan, bungkus per kata, tanpa tanda demo', () => {
  const teks = M.buildReceiptText(struk, { company, footer: 'Sampai jumpa lagi' })
  const baris = teks.split('\n')
  for (const b of baris) assert.ok(b.length <= 32, `baris kepanjangan: "${b}"`)
  assert.equal(baris[0].trim(), 'WARUNG KOPI TULÉH')
  assert.ok(teks.includes('No                    POS-000051'))
  assert.ok(teks.includes('Kopi Susu Gula Aren Spesial'))
  assert.ok(/TOTAL\s+Rp 49\.500/.test(teks))
  assert.ok(/Kembalian\s+Rp 50\.500/.test(teks))
  assert.ok(teks.includes('-10%'))
  assert.ok(!teks.includes('MODE DEMO'))
  assert.ok(teks.trim().endsWith('Sampai jumpa lagi'))
})

test('buildReceiptText: Mode Demo bertanda di kepala dan kaki', () => {
  const teks = M.buildReceiptText(struk, { company, demo: true })
  const baris = teks.split('\n')
  assert.equal(baris[0].trim(), M.TANDA_DEMO)
  assert.ok(teks.trim().endsWith(M.TANDA_DEMO))
})

test('buildReceiptText: pra-bon tanpa baris bayar; struk kosong → teks kosong', () => {
  const teks = M.buildReceiptText({ ...struk, status: 'BELUM DIBAYAR' }, { company })
  assert.ok(!teks.includes('Kembalian'))
  assert.equal(M.buildReceiptText(null), '')
})

test('buildReceiptText: barang timbang mencetak satuannya', () => {
  // "0,74 x Rp 27.000" tidak memberi tahu pelanggan 0,74 dari apa.
  const teks = M.buildReceiptText({
    ...struk,
    items: [{ nama: 'Mangga Harum Manis', kuantitas: 0.74, harga: 27000, subtotal: 19980, satuan: 'kg' }]
  }, { company })
  assert.ok(teks.includes('0,74 kg x Rp 27.000'), teks)
  // Barang hitungan tetap polos.
  assert.ok(M.buildReceiptText(struk, { company }).includes('2 x Rp 18.000'))
})

const refundContoh = {
  id: 'R1', nomor: 'RF-000003', tanggal: '2026-09-20T10:15:00', metode: 'TUNAI', metode_nama: 'Tunai',
  alasan: 'Rasa tidak sesuai pesanan pelanggan', oleh: 'Manager Toko', subtotal: 18000, total_pajak: 0, total: 18000,
  items: [{ item_id: 'I1', nama: 'Kopi Susu Gula Aren Spesial Ukuran Besar', satuan: 'cup', kuantitas: 1, total: 18000, kembali_stok: true }]
}

test('strukRefund + buildReceiptText: nota refund 32 kolom, menyebut transaksi asal, alasan, metode; tanpa baris bayar', () => {
  const nota = M.strukRefund(struk, refundContoh)
  assert.equal(nota.status, 'REFUND')
  assert.equal(nota.transaksi_nomor, 'POS-000051')
  assert.equal(nota.items[0].harga, 18000)
  assert.equal(nota.grand_total, 18000)
  const teks = M.buildReceiptText(nota, { company })
  for (const b of teks.split('\n')) assert.ok(b.length <= 32, `baris kepanjangan: "${b}"`)
  assert.ok(teks.includes('NOTA REFUND'))
  assert.ok(teks.includes('RF-000003'))
  assert.ok(teks.includes('Transaksi' + ' '.repeat(13) + 'POS-000051'))
  assert.ok(teks.includes('Oleh'))
  assert.ok(teks.includes('TOTAL REFUND'))
  assert.ok(teks.includes('Alasan: Rasa tidak sesuai'))
  assert.ok(teks.includes('Dana telah dikembalikan'))
  assert.ok(!teks.includes('Kembalian'), 'nota refund tanpa baris bayar/kembalian')
})

test('struk transaksi dengan refund: blok Refund per dokumen + NILAI BERSIH; tanpa refund tidak ada blok', () => {
  assert.ok(!M.buildReceiptText(struk, { company }).includes('NILAI BERSIH'))
  const teks = M.buildReceiptText({ ...struk, total_refund: 18000, nilai_bersih: 31500, refunds: [refundContoh] }, { company })
  for (const b of teks.split('\n')) assert.ok(b.length <= 32, `baris kepanjangan: "${b}"`)
  assert.ok(teks.includes('Refund RF-000003'))
  assert.ok(teks.includes('18.000'))
  assert.ok(teks.includes('NILAI BERSIH'))
  assert.ok(teks.includes('31.500'))
})

test('nota bayar nanti: hanya Sisa — tanpa "BAYAR SAAT AMBIL Rp0 / Kembalian Rp0"', () => {
  const t = M.buildReceiptText({ ...struk, status: 'BELUM LUNAS', tipe_pembayaran: 'BAYAR SAAT AMBIL', dibayar: 0, kembalian: 0, uang_muka: 0, sisa: 49500 })
  assert.match(t, /Sisa\s+Rp\s?49\.500/)
  assert.doesNotMatch(t, /Kembalian/)
  assert.doesNotMatch(t, /BAYAR SAAT AMBIL/)
})

test('nota uang muka: "Uang muka (metode)" lalu Sisa', () => {
  const t = M.buildReceiptText({ ...struk, status: 'UANG MUKA', tipe_pembayaran: 'TUNAI', dibayar: 10000, kembalian: 0, uang_muka: 10000, sisa: 39500 })
  assert.match(t, /Uang muka \(TUNAI\)\s+Rp\s?10\.000/)
  assert.match(t, /Sisa\s+Rp\s?39\.500/)
  assert.doesNotMatch(t, /Kembalian/)
  for (const baris of t.split('\n')) assert.ok(baris.length <= 32, `baris > 32 kolom: "${baris}"`)
})

test('struk pelunasan ber-DP: Uang muka dikurangkan, lalu yang dibayar saat serah', () => {
  const t = M.buildReceiptText({ ...struk, status: 'SELESAI', tipe_pembayaran: 'QRIS', dibayar: 49500, kembalian: 0, uang_muka: 10000 })
  assert.match(t, /Uang muka\s+-Rp\s?10\.000/)
  assert.match(t, /QRIS\s+Rp\s?39\.500/)
  assert.match(t, /Kembalian\s+Rp\s?0/)
})

test('barisPembayaran: pra-bon kosong; transaksi biasa = bayar + kembalian (tak berubah)', () => {
  assert.deepEqual(M.barisPembayaran({ ...struk, status: 'BELUM DIBAYAR' }), [])
  assert.deepEqual(M.barisPembayaran({ ...struk, status: 'SELESAI' }).map((r) => r.label), ['TUNAI', 'Kembalian'])
})
