'use strict'

// Klien HTTP desktop di belakang gateway (kontrak "Klien — perilaku wajib"):
// galat gateway/5xx/408/429 = gangguan jaringan (offline, GET dari salinan), 402 = layar
// langganan (tidak diantrekan), 401/426/4xx lain = bukan gangguan.

const test = require('node:test')
const assert = require('node:assert/strict')

const { buatKlienHttp } = require('../src/main/lib/klien-http')
const { klasifikasi, adalahGangguan, JENIS } = require('../src/main/lib/klasifikasi-http')
const { SalinanBaca } = require('../src/main/offline/salinan')
const { Koneksi } = require('../src/main/offline')

function jawaban(status, body, headers = {}) {
  const h = new Headers(headers)
  return { status, ok: status >= 200 && status < 300, headers: h, text: async () => (body === undefined ? '' : JSON.stringify(body)) }
}

function rakit(respons) {
  const panggilan = []
  const antri = Array.isArray(respons) ? respons.slice() : null
  const fetch = async (url, init) => {
    panggilan.push({ url: new URL(url), init })
    const r = antri ? antri.shift() : respons
    if (typeof r === 'function') return r(url, init)
    if (r instanceof Error) throw r
    return r
  }
  const offline = { salinan: new SalinanBaca({ berkas: null }), koneksi: new Koneksi() }
  const klien = buatKlienHttp({ fetch, versiApp: () => '0.9.99', platform: 'desktop', offline })
  klien.setBaseUrl('https://toko.contoh.test')
  klien.setToken('rahasia')
  return { klien, offline, panggilan }
}

test('klasifikasi: tabel keputusan', () => {
  assert.equal(klasifikasi(0), JENIS.GANGGUAN)
  for (const s of [500, 502, 503, 504, 408, 429]) assert.equal(klasifikasi(s), JENIS.GANGGUAN, `HTTP ${s}`)
  assert.equal(klasifikasi(502, { 'X-Tuleh-Gateway': 'upstream-unreachable' }), JENIS.GANGGUAN)
  assert.equal(klasifikasi(404, { 'X-Tuleh-Gateway': 'route-unknown' }), JENIS.TOLAK)
  assert.equal(klasifikasi(402), JENIS.LANGGANAN)
  assert.equal(klasifikasi(401), JENIS.SESI)
  assert.equal(klasifikasi(426), JENIS.UPDATE)
  for (const s of [400, 403, 404, 409, 413, 422]) assert.equal(klasifikasi(s), JENIS.TOLAK, `HTTP ${s}`)
  assert.equal(klasifikasi(200, null, { success: false }), JENIS.TOLAK)
  assert.equal(klasifikasi(200, null, { success: true }), JENIS.SUKSES)
  assert.equal(adalahGangguan({ ok: false, status: -1 }), true)
  assert.equal(adalahGangguan({ ok: false, status: 402 }), false)
})

test('sukses GET: header versi+platform, toko aktif, salinan disimpan, tandai online', async () => {
  const { klien, offline, panggilan } = rakit(jawaban(200, { success: true, data: [1], meta: { page: 1 } }))
  offline.koneksi.tandaiOffline()
  klien.setActiveTokoId('T1')
  const r = await klien.get('/produk', { query: { q: 'a' } })
  assert.equal(r.ok, true)
  assert.deepEqual(r.data, [1])
  const { url, init } = panggilan[0]
  assert.equal(url.origin + url.pathname, 'https://toko.contoh.test/api/pos/v1/produk')
  assert.equal(url.searchParams.get('toko_id'), 'T1')
  assert.equal(init.headers['X-Tuleh-Version'], '0.9.99')
  assert.equal(init.headers['X-Tuleh-Platform'], 'desktop')
  assert.equal(init.headers.Authorization, 'Bearer rahasia')
  assert.equal(offline.koneksi.online, true)
  assert.ok(offline.salinan.ambil('T1', '/produk', { q: 'a', toko_id: 'T1' }))
})

test('gateway 502 upstream-unreachable pada GET → salinan disajikan & offline (BUKAN jawaban galat)', async () => {
  const { klien, offline } = rakit([
    jawaban(200, { success: true, data: [{ id: 'P1' }] }),
    jawaban(502, { success: false, message: 'Server tidak dapat dihubungi.' }, { 'X-Tuleh-Gateway': 'upstream-unreachable' })
  ])
  await klien.get('/produk')
  const r = await klien.get('/produk')
  assert.equal(r.ok, true)
  assert.equal(r.offline, true)
  assert.deepEqual(r.data, [{ id: 'P1' }])
  assert.equal(offline.koneksi.online, false)
})

test('gateway 502 pada GET tanpa salinan → amplop gangguan, offline', async () => {
  const { klien, offline } = rakit(jawaban(502, { success: false, message: 'Server tidak dapat dihubungi.' }, { 'X-Tuleh-Gateway': 'upstream-unreachable' }))
  const r = await klien.get('/pelanggan')
  assert.equal(r.ok, false)
  assert.equal(r.gangguan, true)
  assert.equal(r.status, 502)
  assert.equal(r.gateway, 'upstream-unreachable')
  assert.equal(offline.koneksi.online, false)
})

test('5xx/408/429 dari server (tanpa penanda gateway) pada POST → gangguan, pesan server dipertahankan', async () => {
  for (const status of [500, 503, 504, 408, 429]) {
    const { klien, offline } = rakit(jawaban(status, { success: false, message: `pesan ${status}` }))
    const r = await klien.post('/transaksi/checkout', { body: { a: 1 } })
    assert.equal(r.ok, false)
    assert.equal(r.gangguan, true, `HTTP ${status}`)
    assert.equal(r.status, status)
    assert.equal(r.message, `pesan ${status}`)
    assert.equal(offline.koneksi.online, false)
  }
})

test('jaringan putus (fetch melempar) → status 0 gangguan; timeout ditandai', async () => {
  const { klien } = rakit(new TypeError('fetch failed'))
  const r = await klien.post('/pengeluaran', { body: {} })
  assert.deepEqual([r.ok, r.status, r.gangguan], [false, 0, true])
  const abort = new Error('aborted'); abort.name = 'AbortError'
  const t = await rakit(abort).klien.post('/pengeluaran', { body: {} })
  assert.equal(t.timeout, true)
  assert.equal(t.gangguan, true)
})

test('402 langganan → bukan gangguan, handler menerima pesan+URL dari server, meta dipertahankan', async () => {
  const body = {
    success: false, data: null, message: 'Langganan berakhir sejak 1 Sep.',
    errors: { langganan: ['BERAKHIR'] },
    meta: { langganan: { status: 'KEDALUWARSA', perpanjang_url: 'https://contoh.test/perpanjang' } }
  }
  const { klien, offline } = rakit(jawaban(402, body))
  let info = null
  klien.setLanggananHandler((i) => { info = i })
  offline.koneksi.tandaiOffline()
  const r = await klien.post('/transaksi/checkout', { body: {} })
  assert.equal(r.ok, false)
  assert.equal(r.status, 402)
  assert.equal(r.gangguan, undefined)
  assert.deepEqual(r.errors, { langganan: ['BERAKHIR'] })
  assert.equal(r.meta.langganan.perpanjang_url, 'https://contoh.test/perpanjang')
  assert.deepEqual(info, { pesan: 'Langganan berakhir sejak 1 Sep.', status: 'KEDALUWARSA', perpanjangUrl: 'https://contoh.test/perpanjang' })
  assert.equal(offline.koneksi.online, true, 'server menjawab → online')
})

test('401 & 422 bukan gangguan; 426 memanggil handler update', async () => {
  const s401 = await rakit(jawaban(401, { success: false, message: 'Unauthenticated.' })).klien.get('/auth/me')
  assert.deepEqual([s401.status, s401.gangguan], [401, undefined])
  const s422 = await rakit(jawaban(422, { success: false, message: 'x', errors: { items: ['Stok kurang'] } })).klien.post('/transaksi/checkout', { body: {} })
  assert.deepEqual([s422.status, s422.gangguan, s422.errors.items[0]], [422, undefined, 'Stok kurang'])
  const { klien } = rakit(jawaban(426, { success: false, message: 'Perbarui' }))
  let pesan = null
  klien.setUpgradeHandler((m) => { pesan = m })
  await klien.get('/config')
  assert.equal(pesan, 'Perbarui')
})

test('404 route-unknown dari gateway: penolakan, tidak mengubah status online', async () => {
  const { klien, offline } = rakit(jawaban(404, { success: false, message: 'Endpoint tidak dikenal.' }, { 'X-Tuleh-Gateway': 'route-unknown' }))
  offline.koneksi.tandaiOffline()
  const r = await klien.put('/tables/M1', { body: {} })
  assert.deepEqual([r.ok, r.status, r.gangguan, r.gateway], [false, 404, undefined, 'route-unknown'])
  assert.equal(offline.koneksi.online, false, 'gateway menjawab ≠ server terjangkau')
})

test('gateway mati (koneksi ditolak) → lapor pengawas & ulang sekali langsung ke server', async () => {
  const tolak = new TypeError('fetch failed'); tolak.cause = { code: 'ECONNREFUSED' }
  const { klien, panggilan } = rakit([tolak, jawaban(200, { success: true, data: 'ok' })])
  let dilapor = 0
  klien.setGatewayGagalHandler(() => { dilapor++ })
  klien.setGateway('http://127.0.0.1:8787')
  const r = await klien.post('/pengeluaran', { body: { nominal: 1 } })
  assert.equal(r.ok, true)
  assert.equal(dilapor, 1)
  assert.equal(panggilan[0].url.host, '127.0.0.1:8787')
  assert.equal(panggilan[1].url.host, 'toko.contoh.test')
  assert.equal(klien.getGateway(), null)
})

test('waktuServer selalu langsung ke server walau gateway aktif', async () => {
  const { klien, panggilan } = rakit(() => ({ status: 200, ok: true, headers: new Headers({ date: 'Tue, 15 Sep 2026 03:00:00 GMT' }), text: async () => '{}' }))
  klien.setGateway('http://127.0.0.1:8787')
  const d = await klien.waktuServer()
  assert.equal(d.toISOString(), '2026-09-15T03:00:00.000Z')
  assert.equal(panggilan[0].url.host, 'toko.contoh.test')
  assert.equal(panggilan[0].url.searchParams.get('platform'), 'desktop')
})

test('pantauKoneksi:false (pengurai latar): 5xx tidak menandai aplikasi offline, tetap amplop gangguan', async () => {
  const { klien, offline } = rakit(jawaban(500, { success: false, message: 'bug pada muatan ini' }))
  const r = await klien.post('/transaksi/checkout', { body: {}, pantauKoneksi: false })
  assert.deepEqual([r.ok, r.status, r.gangguan], [false, 500, true])
  assert.equal(offline.koneksi.online, true)
})
