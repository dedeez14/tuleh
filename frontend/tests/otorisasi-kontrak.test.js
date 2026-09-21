'use strict'

// PIN persetujuan (server 2026-09-21, app 0.9.38): kanal PIN saya + otorisasi, dan token
// persetujuan ikut pada pembatalan/refund. Satu kontrak dipakai desktop & Android Capacitor.

const test = require('node:test')
const assert = require('node:assert/strict')
const kontrak = require('../src/shared/kontrak-kanal.js')

test('kanal PIN saya: baca, simpan (4–8 digit), hapus dengan PIN lama', () => {
  assert.deepEqual(kontrak.bentuk('keamanan:pinSaya', {}), { metode: 'GET', jalur: '/keamanan/pin-saya', query: undefined })
  const simpan = kontrak.bentuk('keamanan:pinSimpan', { pin: '2468', pinLama: '1234' })
  assert.equal(simpan.metode, 'PUT')
  assert.equal(simpan.jalur, '/keamanan/pin-saya')
  assert.deepEqual(JSON.parse(JSON.stringify(simpan.body)), { pin: '2468', pin_lama: '1234' })
  assert.equal('pin_lama' in JSON.parse(JSON.stringify(kontrak.bentuk('keamanan:pinSimpan', { pin: '2468' }).body)), false)
  assert.throws(() => kontrak.bentuk('keamanan:pinSimpan', { pin: '12' }), /4–8 digit/)
  assert.throws(() => kontrak.bentuk('keamanan:pinSimpan', { pin: 'abcd' }), /4–8 digit/)

  // DELETE wajib membawa pin_lama (server fix 1f627b45): tanpa gerbang ini, "hapus lalu pasang
  // baru" adalah jalan pintas mengganti PIN manajer dari perangkat yang ditinggal terbuka.
  const hapus = kontrak.bentuk('keamanan:pinHapus', { pinLama: '1234' })
  assert.equal(hapus.metode, 'DELETE')
  assert.equal(hapus.jalur, '/keamanan/pin-saya')
  assert.deepEqual(JSON.parse(JSON.stringify(hapus.body)), { pin_lama: '1234' })
  assert.throws(() => kontrak.bentuk('keamanan:pinHapus', {}), /Isi PIN lama untuk menghapus PIN\./)
})

test('kanal otorisasi: daftar pemberi & tukar PIN jadi token', () => {
  assert.equal(kontrak.bentuk('keamanan:pemberi', {}).jalur, '/keamanan/pemberi-otorisasi')
  const m = kontrak.bentuk('keamanan:otorisasi', { pemberiId: 'U1', pin: '2468', aksi: 'transaksi.batal', transaksiId: 'T1' })
  assert.equal(m.metode, 'POST')
  assert.equal(m.jalur, '/keamanan/otorisasi')
  assert.deepEqual(JSON.parse(JSON.stringify(m.body)), { pemberi_id: 'U1', pin: '2468', aksi: 'transaksi.batal', transaksi_id: 'T1' })
  assert.throws(() => kontrak.bentuk('keamanan:otorisasi', { pin: '2468', aksi: 'transaksi.batal', transaksiId: 'T1' }), /wajib/)
  assert.throws(() => kontrak.bentuk('keamanan:otorisasi', { pemberiId: 'U1', pin: '2468', aksi: 'gudang.hapus', transaksiId: 'T1' }), /tidak dikenal/)
  // aksi refund juga sah (PosOtorisasi::AKSI di server).
  assert.equal(kontrak.bentuk('keamanan:otorisasi', { pemberiId: 'U1', pin: '2468', aksi: 'transaksi.refund', transaksiId: 'T1' }).body.aksi, 'transaksi.refund')
})

test('trx:batal & trx:refund membawa otorisasi_token bila ada', () => {
  const batal = kontrak.bentuk('trx:batal', { id: 'T1', alasan: 'Salah input', otorisasiToken: 'abc.def' })
  assert.equal(batal.jalur, '/transaksi/T1/batal')
  assert.deepEqual(JSON.parse(JSON.stringify(batal.body)), { alasan: 'Salah input', otorisasi_token: 'abc.def' })
  assert.deepEqual(JSON.parse(JSON.stringify(kontrak.bentuk('trx:batal', { id: 'T1' }).body)), {})
  const refund = kontrak.bentuk('trx:refund', { id: 'T1', baris: [{ id: 'I1', kuantitas: 1 }], metode: 'TUNAI', alasan: 'Rusak', otorisasiToken: 'abc.def' })
  assert.equal(refund.body.otorisasi_token, 'abc.def')
  assert.equal(kontrak.bentuk('trx:refund', { id: 'T1', baris: [{ id: 'I1', kuantitas: 1 }], metode: 'TUNAI', alasan: 'Rusak' }).body.otorisasi_token, undefined)
})

test('permukaan preload desktop memuat grup keamanan (paritas dengan jembatan Android)', () => {
  const preload = require('node:fs').readFileSync(require('node:path').join(__dirname, '../src/preload/preload.js'), 'utf8')
  for (const k of ['keamanan:pinSaya', 'keamanan:pinSimpan', 'keamanan:pinHapus', 'keamanan:pemberi', 'keamanan:otorisasi']) {
    assert.match(preload, new RegExp(`invoke\\('${k}'\\)`), k)
  }
})

// Badan pada DELETE bukan hal yang lazim: sebagian klien/proksi membuangnya diam-diam dan
// server lalu menjawab 422 "PIN lama salah atau tidak disertakan" tanpa sebab yang terlihat.
// Sisi Go dibuktikan di backend/proxy_test.go (TestProxyDeleteMembawaBadanJson).
test('klien HTTP desktop benar-benar mengirim badan JSON pada DELETE', async () => {
  const { buatKlienHttp } = require('../src/main/lib/klien-http')
  const { SalinanBaca } = require('../src/main/offline/salinan')
  const { Koneksi } = require('../src/main/offline')

  const panggilan = []
  const klien = buatKlienHttp({
    fetch: async (url, init) => {
      panggilan.push({ url: new URL(url), init })
      return { status: 200, ok: true, headers: new Headers({ 'Content-Type': 'application/json' }), text: async () => JSON.stringify({ success: true, data: { ada: false } }) }
    },
    versiApp: () => '0.9.99',
    platform: 'desktop',
    offline: { salinan: new SalinanBaca({ berkas: null }), koneksi: new Koneksi() }
  })
  klien.setBaseUrl('https://toko.contoh.test')
  klien.setToken('rahasia')

  const minta = kontrak.bentuk('keamanan:pinHapus', { pinLama: '1234' })
  const r = await klien.request(minta.metode, minta.jalur, { body: minta.body })
  assert.equal(r.ok, true)
  const { url, init } = panggilan[0]
  assert.equal(url.pathname, '/api/pos/v1/keamanan/pin-saya')
  assert.equal(init.method, 'DELETE')
  assert.equal(init.headers['Content-Type'], 'application/json')
  assert.deepEqual(JSON.parse(init.body), { pin_lama: '1234' })
})
