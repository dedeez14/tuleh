'use strict'

// Muat ulang identitas (Tahap B §2b): hak akses & peran bisa diubah pemilik saat app terbuka.
// /auth/me dipanggil ulang saat app kembali ke depan (throttle 60 detik) dan sesudah 403 (dengan
// jeda sendiri, supaya layar yang polling tidak membanjiri server).

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

// Layar yang polling (Inventory tiap 10 dtk, papan pesanan tiap 4 dtk) bisa kena 403 terus-menerus
// bila haknya dicabut. Tanpa jeda sendiri, jalur `paksa` memanggil /auth/me setiap kali — selamanya.
test('perluMuatUlang: jalur paksa punya jeda sendiri, bukan lubang tanpa dasar', () => {
  assert.equal(I.perluMuatUlang(100000, 130000, { paksa: true, terakhirPaksaMs: 0 }), true, 'paksa pertama')
  assert.equal(I.perluMuatUlang(100000, 130000, { paksa: true, terakhirPaksaMs: 129000 }), false, '1 dtk sejak paksa terakhir')
  assert.equal(I.perluMuatUlang(100000, 200000, { paksa: true, terakhirPaksaMs: 129000 }), true, 'jeda paksa terlewati')
  assert.equal(I.perluMuatUlang(100000, 131000, { paksa: true, terakhirPaksaMs: 129000, jedaPaksa: 1500 }), true)
  assert.ok(I.JEDA_PAKSA_MS >= 10000, 'jeda paksa harus melebihi polling tercepat layar (4-10 dtk)')
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

// id toko = ciphertext non-deterministik: toko yang sama dikirim dengan id berbeda di /tokos dan di
// /auth/me. Tanpa pencocokan kode/nama, cabang ini mati diam-diam.
test('manifestBerubah: cocok lewat kode lalu nama walau id berbeda tiap respons', () => {
  const tokos = [{ id: 'eyJB', kode: 'TK-001', nama: 'Toko Pusat', manifest_version: 7 }]
  assert.equal(I.manifestBerubah({ id: 'eyJA', kode: 'TK-001', nama: 'Toko Pusat', manifest_version: 6 }, tokos), true)
  assert.equal(I.manifestBerubah({ id: 'eyJA', kode: 'TK-001', nama: 'Toko Pusat', manifest_version: 7 }, tokos), false)
  const tanpaKode = [{ id: 'eyJB', nama: 'Toko Pusat', manifest_version: 7 }]
  assert.equal(I.manifestBerubah({ id: 'eyJA', nama: '  toko pusat ', manifest_version: 6 }, tanpaKode), true, 'nama dirapikan')
  assert.equal(I.manifestBerubah({ id: 'eyJA', nama: 'Cabang Dua', manifest_version: 6 }, tanpaKode), false, 'toko lain = bukan urusannya')
})

test('kunciAkses: perbandingan tak peduli urutan daftar dari server', () => {
  assert.equal(I.kunciAkses(['b', 'a']), I.kunciAkses(['a', 'b']), 'urutan berbeda = hak yang sama')
  assert.notEqual(I.kunciAkses(['a']), I.kunciAkses(['a', 'b']))
  assert.notEqual(I.kunciAkses(null), I.kunciAkses([]), 'belum dimuat bukan sama dengan tanpa hak')
})

test('layarTujuan: layar yang haknya hilang dijatuhkan ke Beranda', () => {
  const ada = ['home', 'pos', 'history', 'settings']
  assert.equal(I.layarTujuan('history', ada), null, 'masih boleh = biarkan')
  assert.equal(I.layarTujuan('inventory', ada), 'home', 'kartunya hilang dari Beranda')
  assert.equal(I.layarTujuan('home', ada), null)
  assert.equal(I.layarTujuan('inventory', null), null, 'daftar tak diketahui = jangan usir (gagal-terbuka)')
  assert.equal(I.layarTujuan('inventory', []), null)
  // Layar tanpa kartu Beranda (Kelola Meja dibuka dari peta meja, atau pintasan papan tik):
  // tak pernah ada di daftar, jadi tak boleh dianggap "haknya hilang".
  assert.equal(I.layarTujuan('tables', ada, ['home', 'pos', 'history', 'settings', 'inventory']), null)
  assert.equal(I.layarTujuan('inventory', ada, ['home', 'pos', 'history', 'settings', 'inventory']), 'home', 'tadinya berpintu, kini tidak')
  assert.equal(I.layarTujuan('history', ada, ['home', 'pos', 'history']), null)
})

test('putusanIdentitas: jawaban gagal/offline tidak menyentuh akses & sesi', () => {
  const st = { akses: ['kasir.transaksi'], toko: { id: 'T1', manifest_version: 2 }, screen: 'pos' }
  for (const me of [null, { ok: false, status: 0, message: 'Tidak ada koneksi.' }, { ok: true, data: null }, { ok: true, data: {} }]) {
    const p = I.putusanIdentitas(me, st)
    assert.equal(p.patch, null, JSON.stringify(me))
    assert.equal(p.perluRender, false)
    assert.equal(p.perluManifest, false)
    assert.equal(p.keLayar, null)
  }
})

test('putusanIdentitas: hak berubah, gambar ulang DAN muat ulang manifest (menu disaring server)', () => {
  const me = { ok: true, data: { user: { id: 'U1' }, akses: ['kasir.transaksi'], tokos: [{ id: 'T1', nama: 'Toko', manifest_version: 2 }] } }
  const st = { akses: ['kasir.transaksi', 'inventory.kelola'], toko: { id: 'T1', nama: 'Toko', manifest_version: 2 }, screen: 'pos' }
  const p = I.putusanIdentitas(me, st)
  assert.deepEqual(p.patch.akses, ['kasir.transaksi'])
  assert.equal(p.perluRender, true)
  assert.equal(p.perluManifest, true, 'manifest_version tak bergerak saat hak peran berubah')
  // Hak sama persis (urutan beda) → tenang saja.
  const tenang = I.putusanIdentitas(me, { ...st, akses: ['kasir.transaksi'] })
  assert.equal(tenang.perluRender, false)
  assert.equal(tenang.perluManifest, false)
  assert.deepEqual(tenang.patch.akses, ['kasir.transaksi'], 'patch tetap diberikan (sesi & peran ikut segar)')
})

test('putusanIdentitas: versi manifest naik (dicocokkan lewat kode), muat ulang tanpa gambar ulang hak', () => {
  const me = { ok: true, data: { user: { id: 'U1' }, akses: ['kasir.transaksi'], tokos: [{ id: 'eyJB', kode: 'TK-001', nama: 'Toko', manifest_version: 9 }] } }
  const st = { akses: ['kasir.transaksi'], toko: { id: 'eyJA', kode: 'TK-001', nama: 'Toko', manifest_version: 8 }, screen: 'pos' }
  const p = I.putusanIdentitas(me, st)
  assert.equal(p.perluManifest, true)
  assert.equal(p.perluRender, false, 'hak tak berubah, tak perlu menggambar ulang kerangka')
})

test('putusanIdentitas: layar yang hilang haknya dibawa pulang ke Beranda', () => {
  const me = { ok: true, data: { user: { id: 'U1' }, akses: ['kasir.transaksi'] } }
  const st = {
    akses: ['kasir.transaksi'], toko: null, screen: 'inventory',
    layarTersedia: ['home', 'pos', 'settings'], layarSebelumnya: ['home', 'pos', 'settings', 'inventory']
  }
  assert.equal(I.putusanIdentitas(me, st).keLayar, 'home')
  assert.equal(I.putusanIdentitas(me, { ...st, screen: 'pos' }).keLayar, null)
  assert.equal(I.putusanIdentitas(me, { ...st, screen: 'tables' }).keLayar, null, 'layar tanpa kartu dibiarkan')
  // Tanpa perubahan apa pun (daftar sebelum = sesudah) tak seorang pun diusir.
  assert.equal(I.putusanIdentitas(me, { ...st, layarSebelumnya: st.layarTersedia }).keLayar, null)
})

test('api.js membungkus panggilan biasa untuk menangkap 403, tanpa merusak langganan on...()', async () => {
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
  // Gerbang menggambar ulang layar - itu tak boleh terjadi di tengah `await` pemanggil, yang masih
  // memegang elemen DOM-nya. Jadi: ditunda ke antrean tugas berikutnya, dan tidak di-await.
  assert.equal(kena, 0, 'gerbang tidak dijalankan di dalam await pemanggil')
  await new Promise((r) => setTimeout(r, 0))
  assert.equal(kena, 1, 'gerbang 403 dipanggil sesudah pemanggil selesai')
  assert.equal((await A.api.auth.me()).ok, true)
  await new Promise((r) => setTimeout(r, 0))
  assert.equal(kena, 1, 'jawaban sukses tidak memicu gerbang')
  A.api.offline.onStatus(() => {})()
  assert.equal(lepas, 1, 'fungsi on... tetap mengembalikan pelepas, bukan Promise')
  delete globalThis.window
})
