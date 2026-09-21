'use strict'

// Paritas desktop ↔ Android (0.9.33). Renderer yang SAMA berjalan di Electron (preload.js → ipc.js)
// dan di WebView Android (mobile-bridge.js). Setiap metode yang dipanggil renderer harus ada di
// kedua permukaan, dan jembatan Android membentuk permintaan HTTP dari kontrak bersama — bukan
// salinan pemetaan kedua yang bisa menyimpang.

const test = require('node:test')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const vm = require('node:vm')

const AKAR = path.join(__dirname, '..')
const kontrak = require('../src/shared/kontrak-kanal.js')

function permukaanDesktop () {
  let terekspos = null
  const electron = {
    contextBridge: { exposeInMainWorld: (_nama, api) => { terekspos = api } },
    ipcRenderer: { invoke: () => Promise.resolve(), on: () => {}, removeListener: () => {} }
  }
  const kode = fs.readFileSync(path.join(AKAR, 'src/preload/preload.js'), 'utf8')
  vm.runInNewContext(kode, { require: (m) => (m === 'electron' ? electron : require(m)) })
  return terekspos
}

function jembatanAndroid ({ tokoAktif = null, respons = { success: true, data: [] }, status = 200 } = {}) {
  const panggilan = []
  const prefs = { token: 'tkn', activeTokoId: tokoAktif }
  const ctx = {
    console, URL, AbortController, setTimeout, clearTimeout, Promise, Blob, FormData, encodeURIComponent,
    fetch: (url, opsi) => {
      panggilan.push({ url: new URL(url), metode: opsi.method, body: opsi.body })
      return Promise.resolve({ ok: status >= 200 && status < 300, status, text: () => Promise.resolve(JSON.stringify(respons)) })
    }
  }
  ctx.window = ctx
  ctx.Capacitor = { Plugins: { Preferences: {
    get: ({ key }) => Promise.resolve({ value: prefs[key] == null ? null : prefs[key] }),
    set: ({ key, value }) => { prefs[key] = value; return Promise.resolve() },
    remove: ({ key }) => { delete prefs[key]; return Promise.resolve() }
  } } }
  vm.createContext(ctx)
  vm.runInContext(fs.readFileSync(path.join(AKAR, 'src/shared/kontrak-kanal.js'), 'utf8'), ctx)
  vm.runInContext(fs.readFileSync(path.join(AKAR, '../mobile/www-src/js/mobile-bridge.js'), 'utf8'), ctx)
  return { api: ctx.iposAPI, panggilan, prefs }
}

// Objek dari konteks vm punya prototipe realm lain → normalkan sebelum deepEqual.
const polos = (v) => JSON.parse(JSON.stringify(v))

function daun (obj, awalan = '') {
  const out = []
  for (const k of Object.keys(obj || {})) {
    const v = obj[k]
    if (typeof v === 'function') out.push(awalan + k)
    else if (v && typeof v === 'object') out.push(...daun(v, awalan + k + '.'))
  }
  return out.sort()
}

test('setiap metode permukaan desktop tersedia di jembatan Android', () => {
  const desktop = daun(permukaanDesktop())
  const android = new Set(daun(jembatanAndroid().api))
  const hilang = desktop.filter((m) => !android.has(m))
  assert.deepEqual(hilang, [], 'metode desktop yang tak ada di Android')
})

test('setiap kanal kontrak terpasang di kedua permukaan', () => {
  const desktop = new Set(daun(permukaanDesktop()))
  const android = new Set(daun(jembatanAndroid().api))
  for (const kanal of Object.keys(kontrak.KANAL)) {
    const p = kontrak.KANAL[kanal].permukaan
    assert.ok(desktop.has(p), `desktop: ${p}`)
    assert.ok(android.has(p), `android: ${p}`)
  }
})

test('Android: permintaan dibentuk dari kontrak + toko aktif disisipkan', async () => {
  const { api, panggilan } = jembatanAndroid({ tokoAktif: 'TOKO-ENK' })
  await api.trx.list({ sesiId: 'SESI-1', tanggalDari: '2026-09-01' })
  const u = panggilan[0].url
  assert.equal(u.pathname, '/api/pos/v1/transaksi')
  assert.equal(u.searchParams.get('sesi_id'), 'SESI-1')
  assert.equal(u.searchParams.get('tanggal_dari'), '2026-09-01')
  assert.equal(u.searchParams.get('toko_id'), 'TOKO-ENK')

  await api.table.tambah({ nomor: '12' })
  assert.equal(panggilan[1].metode, 'POST')
  assert.equal(panggilan[1].url.pathname, '/api/pos/v1/tables')
  assert.deepEqual(JSON.parse(panggilan[1].body), { nomor: '12' })

  await api.sesi.buka({ gudangId: 'G1', kasAwal: 100000 })
  assert.equal(JSON.parse(panggilan[2].body).toko_id, 'TOKO-ENK', 'sesi diikat ke toko aktif yang dimuat dari penyimpanan')
})

test('Android: masukan tak sah kembali sebagai amplop galat, bukan exception', async () => {
  const { api, panggilan } = jembatanAndroid()
  const r = await api.sesi.tutup({ id: 'S1' })
  assert.equal(r.ok, false)
  assert.match(r.message, /wajib/i)
  assert.equal(panggilan.length, 0)
})

test('Android: preferensi cetak tersimpan di Preferences; tanpa printer sistem & antrean offline', async () => {
  const { api, prefs } = jembatanAndroid()
  assert.deepEqual(polos((await api.settings.getCetak()).data), { printer: '', langsung: false, otomatis: false })
  const r = await api.settings.setCetak({ otomatis: true })
  assert.equal(r.data.otomatis, true)
  assert.equal(JSON.parse(prefs.cetak).otomatis, true)
  assert.deepEqual(polos((await api.app.printers()).data), [])
  const info = (await api.app.info()).data
  assert.equal(info.kemampuan.antreanOffline, false)
  assert.equal(info.kemampuan.printerSistem, false)
  const st = (await api.offline.status()).data
  assert.equal(st.menunggu, 0)
  assert.equal(typeof api.offline.onStatus(() => {}), 'function')
})

// Layar yang sama berjalan di Android: dialog persetujuan membaca `data.terkunci_detik` dari amplop
// 429 untuk hitung mundur. Amplop gagal yang membuang `data` membuatnya diam-diam cuma bisa bilang
// "coba lagi nanti" di Android sementara di desktop hitung mundurnya jalan (paritas dengan klien-http).
test('Android: amplop gagal membawa data dari server (hitung mundur kunci PIN)', async () => {
  const { api } = jembatanAndroid({
    status: 429,
    respons: { success: false, data: { terkunci_detik: 47 }, meta: null, message: 'Terlalu banyak PIN salah. Coba lagi dalam 47 detik.', errors: { kode: ['PIN_TERKUNCI'] } }
  })
  const r = await api.keamanan.otorisasi({ pemberiId: 'U1', pin: '0000', aksi: 'transaksi.batal', transaksiId: 'T1' })
  assert.equal(r.ok, false)
  assert.equal(r.status, 429)
  assert.deepEqual(polos(r.data), { terkunci_detik: 47 })
  assert.deepEqual(polos(r.errors), { kode: ['PIN_TERKUNCI'] })
  assert.match(r.message, /47 detik/)

  const kosong = jembatanAndroid({ status: 404, respons: { success: false, message: 'Tidak ditemukan.' } })
  assert.equal((await kosong.api.trx.struk({ id: 'X' })).data, null, 'tanpa data dari server → null')
})

test('build Android memuat kontrak bersama sebelum jembatan (CI & skrip lokal)', () => {
  const html = fs.readFileSync(path.join(AKAR, '../mobile/www-src/index.html'), 'utf8')
  const iKontrak = html.indexOf('js/kontrak-kanal.js')
  const iJembatan = html.indexOf('js/mobile-bridge.js')
  assert.ok(iKontrak > 0 && iKontrak < iJembatan, 'index.html: kontrak-kanal.js dimuat sebelum mobile-bridge.js')
  const ci = fs.readFileSync(path.join(AKAR, '../.github/workflows/release.yml'), 'utf8')
  assert.match(ci, /cp frontend\/src\/shared\/kontrak-kanal\.js "\$WWW\/js\/kontrak-kanal\.js"/)
  const ps1 = fs.readFileSync(path.join(AKAR, '../mobile/build-android.ps1'), 'utf8')
  assert.match(ps1, /frontend\\src\\shared\\kontrak-kanal\.js/)
})
