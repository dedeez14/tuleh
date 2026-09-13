'use strict'

// Resolver akses tunggal (0.9.33): matriks bawaan per pos_role mengikuti spesifikasi §A4,
// `akses` dari server menang mutlak, peran tak dikenal → Kasir (gagal-tertutup).

const test = require('node:test')
const assert = require('node:assert/strict')

let A

test.before(async () => {
  A = await import('../src/renderer/js/akses.js')
})

const KUNCI = [
  'dashboard.lihat', 'kasir.transaksi', 'pesanan.kelola', 'pesanan.void', 'transaksi.riwayat_semua',
  'transaksi.batal', 'sesi.lihat_semua', 'sesi.tutup_lain', 'produk.lihat', 'produk.harga_beli',
  'produk.kelola', 'inventory.kelola', 'pelanggan.kelola', 'pengeluaran.kelola', 'laporan.lihat',
  'toko.meja_stasiun', 'toko.buat', 'pengaturan.usaha', 'pengaturan.pembayaran', 'pengaturan.keamanan',
  'langganan.kelola', 'peran.kelola', 'pengguna.kelola'
]
const milik = (posRole) => KUNCI.filter((k) => A.bisa(k, { posRole }))

test('OWNER memiliki semua kunci', () => {
  assert.deepEqual(milik('OWNER'), KUNCI)
})

test('MANAGER: semua kecuali wewenang pemilik', () => {
  const tanpa = KUNCI.filter((k) => !A.bisa(k, { posRole: 'MANAGER' }))
  assert.deepEqual(tanpa.sort(), [
    'langganan.kelola', 'pengaturan.keamanan', 'pengaturan.pembayaran', 'pengaturan.usaha',
    'pengguna.kelola', 'peran.kelola', 'toko.buat'
  ])
  for (const k of ['transaksi.riwayat_semua', 'sesi.lihat_semua', 'sesi.tutup_lain', 'pesanan.kelola']) {
    assert.ok(A.bisa(k, { posRole: 'MANAGER' }), `Manager memantau kasir: ${k}`)
  }
})

test('KASIR: hanya operasional harian', () => {
  assert.deepEqual(milik('KASIR'), ['kasir.transaksi', 'pesanan.kelola', 'produk.lihat'])
})

test('peran kosong / tak dikenal diperlakukan sebagai Kasir (gagal-tertutup)', () => {
  for (const posRole of [null, undefined, '', 'SUPERVISOR']) {
    assert.deepEqual(milik(posRole), milik('KASIR'), String(posRole))
  }
})

test('akses dari server menjadi satu-satunya sumber, mengalahkan pos_role', () => {
  const st = { posRole: 'OWNER', akses: ['kasir.transaksi', 'laporan.lihat'] }
  assert.equal(A.bisa('laporan.lihat', st), true)
  assert.equal(A.bisa('pengaturan.usaha', st), false, 'kunci di luar array = tidak boleh walau OWNER')
  assert.equal(A.isManajemen(st), true)
})

test('huruf kecil pos_role tetap dikenali; label peran', () => {
  assert.equal(A.bisa('laporan.lihat', { posRole: 'manager' }), true)
  assert.equal(A.labelPeran('OWNER'), 'Owner')
  assert.equal(A.labelPeran('manager'), 'Manager')
  assert.equal(A.labelPeran(null), 'Kasir')
})

// Penjaga §A0.4: logika peran hanya boleh ada di akses.js — layar lain bertanya ke bisa(kunci).
test('tidak ada pengecekan peran di luar akses.js (renderer & jembatan Android)', () => {
  const fs = require('node:fs')
  const path = require('node:path')
  const akar = path.join(__dirname, '..')
  const berkas = []
  const jelajah = (dir) => {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      const p = path.join(dir, e.name)
      if (e.isDirectory()) jelajah(p)
      else if (e.name.endsWith('.js')) berkas.push(p)
    }
  }
  jelajah(path.join(akar, 'src/renderer/js'))
  const bridge = path.join(akar, '../mobile/www-src/js')
  if (fs.existsSync(bridge)) jelajah(bridge)
  const pelanggar = []
  for (const p of berkas) {
    if (p.endsWith(path.join('renderer', 'js', 'akses.js'))) continue
    fs.readFileSync(p, 'utf8').split('\n').forEach((baris, i) => {
      if (/^\s*(\/\/|\*)/.test(baris)) return
      if (/posRole\s*===|===\s*'(OWNER|MANAGER|KASIR)'|MANAGEMENT_ROLES|bolehKelolaMeja/.test(baris)) {
        pelanggar.push(`${path.relative(akar, p)}:${i + 1}: ${baris.trim()}`)
      }
    })
  }
  assert.deepEqual(pelanggar, [])
})
