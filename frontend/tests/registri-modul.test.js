'use strict'

// Registri route_key → layar (0.9.33). Menu Beranda desktop & Android disusun dari fungsi murni yang
// SAMA atas manifest server. Semua route_key yang dapat dikirim server (config/pos_archetypes.php +
// pos_verticals.php) harus berujung ke layar, dan setiap arketipe punya pintu transaksi.

const test = require('node:test')
const assert = require('node:assert/strict')

let R

test.before(async () => {
  R = await import('../src/renderer/js/lib/registri-modul.js')
})

const menu = (ids) => ids.map((id, i) => ({ id, routeKey: id, label: '', order: i + 1 }))

// Menu OWNER per arketipe server (route_key, urutan server).
const ARKETIPE = {
  inventory_sale: ['dashboard', 'kasir', 'produk', 'inventory', 'riwayat', 'sesi', 'pelanggan', 'pengeluaran', 'laporan', 'pengaturan'],
  fnb_kot: ['dashboard', 'kasir', 'antrian', 'produk', 'inventory', 'riwayat', 'sesi', 'pelanggan', 'pengeluaran', 'laporan', 'pengaturan'],
  service_lifecycle: ['dashboard', 'order', 'antrian', 'layanan', 'inventory', 'riwayat', 'sesi', 'pelanggan', 'pengeluaran', 'laporan', 'pengaturan'],
  membership: ['dashboard', 'kasir', 'member', 'jadwal', 'riwayat', 'sesi', 'pelanggan', 'pengeluaran', 'laporan', 'pengaturan'],
  hospitality: ['dashboard', 'kamar', 'reservasi', 'riwayat', 'sesi', 'pelanggan', 'pengeluaran', 'laporan', 'pengaturan']
}

test('setiap route_key server (kecuali yang tercatat belum ada) punya layar', () => {
  const semua = new Set(Object.values(ARKETIPE).flat())
  for (const key of semua) {
    if (key === 'dashboard') continue
    assert.ok(R.MODULES[key] && R.MODULES[key].screen, `route_key tanpa layar: ${key}`)
  }
})

test('setiap arketipe punya kartu transaksi (layar kasir) di Beranda', () => {
  for (const [nama, ids] of Object.entries(ARKETIPE)) {
    const kartu = R.susunModul({ menus: menu(ids), manajemen: true })
    assert.ok(kartu.some((k) => k.screen === 'pos'), `${nama}: tidak ada pintu transaksi`)
  }
})

test('urutan & label mengikuti manifest; route_key tak dikenal dilewati dan dilaporkan', () => {
  const peringatan = []
  const kartu = R.susunModul({
    menus: [
      { id: 'riwayat', routeKey: 'riwayat', label: 'Riwayat Nota', order: 2 },
      { id: 'order', routeKey: 'order', label: 'Order Cucian', order: 1 },
      { id: 'x', routeKey: 'teleportasi', label: 'X', order: 3 }
    ],
    manajemen: false,
    peringatan: (k) => peringatan.push(k)
  })
  assert.deepEqual(kartu.map((k) => [k.id, k.title]), [['order', 'Order Cucian'], ['riwayat', 'Riwayat Nota']])
  assert.deepEqual(peringatan, ['teleportasi'])
})

test('fitur ekstra app hanya untuk manajemen; manifest kosong memakai set inti', () => {
  const ids = (k) => k.map((x) => x.id)
  assert.ok(ids(R.susunModul({ menus: menu(['kasir']), manajemen: true })).includes('keuangan'))
  assert.ok(!ids(R.susunModul({ menus: menu(['kasir']), manajemen: false })).includes('keuangan'))
  assert.deepEqual(ids(R.susunModul({ menus: [], manajemen: false })), ['kasir', 'riwayat', 'sesi', 'produk', 'pelanggan', 'laporan', 'pengaturan'])
})

test('kartu utama = pintu transaksi', () => {
  assert.equal(R.kartuUtama('kasir'), true)
  assert.equal(R.kartuUtama('order'), true)
  assert.equal(R.kartuUtama('riwayat'), false)
})

test('route_key jadwal (gym & klinik) berujung ke layar Jadwal', () => {
  assert.equal(R.MODULES.jadwal.screen, 'jadwal')
  const kartu = R.susunModul({ menus: menu(ARKETIPE.membership), manajemen: false })
  assert.ok(kartu.some((k) => k.id === 'jadwal'), 'kartu Jadwal muncul di Beranda membership')
})

test('dua route_key untuk satu tujuan (membership: member + pelanggan) → satu kartu, yang lebih dulu menang', () => {
  const kartu = R.susunModul({ menus: menu(ARKETIPE.membership), manajemen: false })
  const kePelanggan = kartu.filter((k) => k.screen === 'customers')
  assert.equal(kePelanggan.length, 1, 'hanya satu kartu ke layar pelanggan')
  assert.equal(kePelanggan[0].id, 'member')
  assert.equal(kePelanggan[0].title, 'Member')
  assert.ok(kartu.some((k) => k.id === 'jadwal') && kartu.some((k) => k.id === 'sesi'), 'kartu lain tetap ada')
  // Papan yang berbagi layar tetapi beda mode TIDAK ikut tertelan.
  const papan = R.susunModul({
    menus: [
      { id: 'dapur', routeKey: 'dapur', label: '', order: 1 },
      { id: 'antrian', routeKey: 'antrian', label: '', order: 2 }
    ],
    manajemen: false
  })
  assert.deepEqual(papan.map((k) => k.id), ['dapur', 'antrian'])
})
