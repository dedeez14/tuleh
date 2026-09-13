'use strict'

// Tahap 1 — peran (pos_role) & menu dari manifest. Menguji simulasi demo yang
// mencerminkan server: login/me membawa pos_role; toko:manifest mengirim menus
// SUDAH terfilter peran + role + premium_features.

const test = require('node:test')
const assert = require('node:assert/strict')

const demo = require('../src/main/demo.js')

// Menu manajemen (hanya OWNER/MANAGER) vs operasional (semua peran) — §3.2.
const MENU_MANAJEMEN = ['dashboard', 'inventory', 'pelanggan', 'pengeluaran', 'laporan', 'pengaturan']
const ids = (manifest) => manifest.data.menus.map((m) => m.id)

test.afterEach(() => { delete process.env.IPOS_SMOKE_ROLE })

test('login demo membawa akses & peran seperti server (default pemilik: semua hak)', () => {
  const r = demo.start()
  assert.equal(r.ok, true)
  assert.ok(Array.isArray(r.data.akses) && r.data.akses.includes('peran.kelola'))
  assert.equal(typeof r.data.peran.nama, 'string')
})

test('auth:me demo membawa akses sesuai peran demo', () => {
  process.env.IPOS_SMOKE_ROLE = 'KASIR'
  const me = demo.handlers['auth:me']().data
  assert.deepEqual(me.akses, ['kasir.transaksi', 'pesanan.kelola', 'produk.lihat'])
  process.env.IPOS_SMOKE_ROLE = 'MANAGER'
  assert.ok(demo.handlers['auth:me']().data.akses.includes('transaksi.batal'))
})

test('OWNER: manifest kirim semua menu manajemen + role + premium_features', () => {
  demo.start() // default OWNER
  const man = demo.handlers['toko:manifest']({ id: 'TOKO-1' })
  assert.equal(man.ok, true)
  assert.equal(man.data.role, 'OWNER')
  for (const m of MENU_MANAJEMEN) assert.ok(ids(man).includes(m), `OWNER harus lihat ${m}`)
  assert.equal(man.data.premium_features.length, 3)
  assert.ok(man.data.premium_features.every((f) => f.enabled === false))
})

test('KASIR: manifest HANYA menu operasional (tanpa manajemen)', () => {
  process.env.IPOS_SMOKE_ROLE = 'KASIR'
  const man = demo.handlers['toko:manifest']({ id: 'TOKO-1' })
  assert.equal(man.data.role, 'KASIR')
  const menu = ids(man)
  // Kasir minimarket menerima persis operasional ini (§3.2)
  assert.deepEqual(menu.sort(), ['kasir', 'produk', 'riwayat', 'sesi'].sort())
  for (const m of MENU_MANAJEMEN) assert.ok(!menu.includes(m), `KASIR tidak boleh lihat ${m}`)
})

test('KASIR F&B tetap melihat antrian/dapur/meja (operasional)', () => {
  process.env.IPOS_SMOKE_ROLE = 'KASIR'
  const menu = ids(demo.handlers['toko:manifest']({ id: 'TOKO-2' }))
  for (const m of ['kasir', 'dapur', 'antrian', 'meja', 'riwayat', 'sesi']) {
    assert.ok(menu.includes(m), `KASIR F&B harus lihat ${m}`)
  }
  assert.ok(!menu.includes('laporan'))
})

test('setiap menu punya route_key & required_permission (kontrak render app)', () => {
  demo.start()
  for (const m of demo.handlers['toko:manifest']({ id: 'TOKO-1' }).data.menus) {
    assert.equal(typeof m.route_key, 'string')
    assert.match(m.required_permission, /^pos\.[a-z_]+\.[a-z_]+$/)
    assert.equal(m.roles, undefined)
  }
})
