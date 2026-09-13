'use strict'

// Resolver akses tunggal: satu-satunya tempat layar bertanya hak akses (desktop & Android).

const test = require('node:test')
const assert = require('node:assert/strict')

let A

test.before(async () => {
  A = await import('../src/renderer/js/akses.js')
})

// 0.9.34 — hak akses adalah master data server (katalog pos_hak_akses × permission role, diatur Owner).
// App TIDAK punya matriks peran: `akses` dari login/me satu-satunya sumber; tanpa itu = tanpa hak.

test('bisa() hanya membaca akses dari server', () => {
  const st = { akses: ['kasir.transaksi', 'laporan.lihat'] }
  assert.equal(A.bisa('laporan.lihat', st), true)
  assert.equal(A.bisa('transaksi.batal', st), false, 'kunci di luar daftar = tidak boleh')
  assert.equal(A.isManajemen(st), true)
})

test('tanpa akses dari server (belum dimuat / respons rusak) = tidak ada hak (gagal-tertutup)', () => {
  for (const st of [{}, { akses: null }, { akses: 'laporan.lihat' }, { posRole: 'OWNER' }]) {
    assert.equal(A.bisa('laporan.lihat', st), false, JSON.stringify(st))
  }
})

test('nama peran dari server; kosong bila tak dikirim', () => {
  assert.equal(A.namaPeran({ peran: { nama: 'Barista Senior' } }), 'Barista Senior')
  assert.equal(A.namaPeran({}), '—')
})

// Penjaga §A0.4: logika peran hanya boleh ada di akses.js — layar lain bertanya ke bisa(kunci).
test('tidak ada nama peran tertanam di renderer & jembatan Android', () => {
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
    fs.readFileSync(p, 'utf8').split('\n').forEach((baris, i) => {
      if (/^\s*(\/\/|\*)/.test(baris)) return
      // Tak ada nama peran tertanam di mana pun — termasuk akses.js (0.9.34).
      if (/posRole|pos_role|'(OWNER|MANAGER|KASIR)'|MATRIKS_AKSES|MANAGEMENT_ROLES|bolehKelolaMeja/.test(baris)) {
        pelanggar.push(`${path.relative(akar, p)}:${i + 1}: ${baris.trim()}`)
      }
    })
  }
  assert.deepEqual(pelanggar, [])
})
