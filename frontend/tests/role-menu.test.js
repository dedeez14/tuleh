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

test('login demo membawa pos_role (default OWNER)', () => {
  const r = demo.start()
  assert.equal(r.ok, true)
  assert.equal(r.data.pos_role, 'OWNER')
})

test('auth:me demo membawa pos_role', () => {
  process.env.IPOS_SMOKE_ROLE = 'MANAGER'
  assert.equal(demo.handlers['auth:me']().data.pos_role, 'MANAGER')
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

test('setiap menu punya route_key & roles (kontrak render app)', () => {
  demo.start()
  for (const m of demo.handlers['toko:manifest']({ id: 'TOKO-1' }).data.menus) {
    assert.equal(typeof m.route_key, 'string')
    assert.ok(Array.isArray(m.roles) && m.roles.length > 0)
  }
})
