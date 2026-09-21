'use strict'

// Muat ulang identitas (Tahap B §2b): hak akses & peran bisa diubah pemilik saat app terbuka.
// /auth/me dipanggil ulang saat app kembali ke depan (throttle 60 detik) dan sekali setelah 403.

const test = require('node:test')
const assert = require('node:assert/strict')

let I
test.before(async () => { I = await import('../src/renderer/js/lib/identitas.js') })

test('perluMuatUlang: hanya sekali per 60 detik, kecuali dipaksa', () => {
  assert.equal(I.perluMuatUlang(0, 1000), true, 'belum pernah dimuat')
  assert.equal(I.perluMuatUlang(100000, 130000), false, '30 detik sejak terakhir')
  assert.equal(I.perluMuatUlang(100000, 160000), true, 'tepat 60 detik')
  assert.equal(I.perluMuatUlang(100000, 130000, { paksa: true }), true)
  assert.equal(I.perluMuatUlang(100000, 110000, { jeda: 5000 }), true)
})

test('patchIdentitas: bidang dari server; akses bukan array = tanpa hak (gagal-tertutup)', () => {
  const p = I.patchIdentitas({
    user: { id: 'U1', name: 'Manajer' }, akses: ['transaksi.batal'], peran: { nama: 'Manager' },
    company: { nama: 'Warung' }, branch: null, sesi_aktif: { id: 'S1', kas_awal: 0 }
  })
  assert.equal(p.user.name, 'Manajer')
  assert.deepEqual(p.akses, ['transaksi.batal'])
  assert.equal(p.peran.nama, 'Manager')
  assert.equal(p.sessionId, 'S1')
  assert.deepEqual(I.patchIdentitas({ user: { id: 'U1' }, akses: 'transaksi.batal' }).akses, null)
  assert.equal(I.patchIdentitas({ user: { id: 'U1' } }).session, null, 'sesi ditutup di perangkat lain ikut hilang')
})

test('manifestBerubah: hanya bila versi manifest toko AKTIF naik/turun', () => {
  const tokos = [{ id: 'T1', manifest_version: 4 }, { id: 'T2', manifest_version: 9 }]
  assert.equal(I.manifestBerubah({ id: 'T1', manifest_version: 3 }, tokos), true)
  assert.equal(I.manifestBerubah({ id: 'T1', manifest_version: 4 }, tokos), false)
  assert.equal(I.manifestBerubah({ id: 'T9', manifest_version: 1 }, tokos), false, 'toko tak ada di daftar = jangan muat ulang')
  assert.equal(I.manifestBerubah(null, tokos), false)
  assert.equal(I.manifestBerubah({ id: 'T1' }, null), false)
})

test('api.js membungkus panggilan biasa untuk menangkap 403, tanpa merusak langganan on…()', async () => {
  let lepas = 0
  globalThis.window = {
    iposAPI: {
      trx: { list: async () => ({ ok: false, status: 403, message: 'Tidak berhak.' }) },
      auth: { me: async () => ({ ok: true, data: { user: { id: 'U1' } } }) },
      offline: { onStatus: () => () => { lepas += 1 } }
    }
  }
  const A = await import('../src/renderer/js/api.js')
  let kena = 0
  A.pasangTolakHak(() => { kena += 1 })
  assert.equal((await A.api.trx.list()).status, 403)
  assert.equal(kena, 1, 'gerbang 403 dipanggil')
  assert.equal((await A.api.auth.me()).ok, true)
  assert.equal(kena, 1, 'jawaban sukses tidak memicu gerbang')
  A.api.offline.onStatus(() => {})()
  assert.equal(lepas, 1, 'fungsi on… tetap mengembalikan pelepas, bukan Promise')
  delete globalThis.window
})
