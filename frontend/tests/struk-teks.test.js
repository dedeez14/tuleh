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
