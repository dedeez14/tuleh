'use strict'

// Kontrak kesiapan produksi 2026-09-15 di sisi aplikasi lama (renderer bersama + jembatan
// Android Capacitor) dan Mode Demo:
//   #1 diagnostik (Android lama langsung ke server), #2 402 → layar langganan,
//   #3 ambang dari server (Mode Demo), #4 /app/versi platform=android-legacy + migrasi.

const test = require('node:test')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const vm = require('node:vm')

const AKAR = path.join(__dirname, '..')

function jembatanAndroid (respons) {
  const panggilan = []
  const prefs = { token: 'tkn' }
  const ctx = {
    console, URL, AbortController, setTimeout, clearTimeout, Promise, Blob, FormData, encodeURIComponent,
    fetch: (url, opsi) => {
      panggilan.push({ url: new URL(url), metode: opsi.method, headers: opsi.headers, body: opsi.body })
      const r = typeof respons === 'function' ? respons(url) : respons
      return Promise.resolve({ ok: r.status >= 200 && r.status < 300, status: r.status, text: () => Promise.resolve(JSON.stringify(r.body)) })
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
  return { api: ctx.iposAPI, panggilan }
}

test('#4 Android lama: /app/versi membawa platform=android-legacy (query & header X-Tuleh-Platform)', async () => {
  const { api, panggilan } = jembatanAndroid({ status: 200, body: { success: true, data: { wajib: false } } })
  await api.app.checkUpdate()
  const p = panggilan[0]
  assert.equal(p.url.pathname, '/api/pos/v1/app/versi')
  assert.equal(p.url.searchParams.get('platform'), 'android-legacy')
  assert.ok(p.url.searchParams.get('versi'))
  assert.equal(p.headers['X-Tuleh-Platform'], 'android-legacy')
  const info = (await api.app.info()).data
  assert.equal(info.platformApi, 'android-legacy')
  assert.equal(info.kemampuan.laporanLog, false)
})

test('#4 desktop: kontrak app:checkUpdate membawa platform dari konteks; tanpa platform tidak dikirim', () => {
  const kontrak = require('../src/shared/kontrak-kanal.js')
  assert.equal(kontrak.bentuk('app:checkUpdate', {}, { versiApp: '0.9.40', platform: 'desktop' }).query.platform, 'desktop')
  assert.equal(kontrak.bentuk('app:checkUpdate', {}, { versiApp: '0.9.40' }).query.platform, undefined)
})

test('#4 modelMigrasi: hanya android-legacy + aktif; URL wajib https; teks dari server', async () => {
  const { modelMigrasi } = await import('../src/renderer/js/lib/migrasi.js')
  const info = { migrasi: { aktif: true, judul: ' Pindah ke aplikasi baru ', pesan: 'Aplikasi ini tidak diperbarui lagi.', url: 'https://contoh.test/unduh' } }
  assert.deepEqual(modelMigrasi(info, 'android-legacy'), { judul: 'Pindah ke aplikasi baru', pesan: 'Aplikasi ini tidak diperbarui lagi.', url: 'https://contoh.test/unduh' })
  assert.equal(modelMigrasi(info, 'desktop'), null)
  assert.equal(modelMigrasi({ migrasi: { ...info.migrasi, aktif: false } }, 'android-legacy'), null)
  assert.equal(modelMigrasi({}, 'android-legacy'), null)
  assert.equal(modelMigrasi({ migrasi: { ...info.migrasi, url: 'http://contoh.test' } }, 'android-legacy').url, null)
  assert.equal(modelMigrasi({ migrasi: { ...info.migrasi, url: 'intent://x' } }, 'android-legacy').url, null)
})

test('#2 Android lama: 402 dari penulisan → onTerkunci menerima pesan + URL server; amplop membawa meta', async () => {
  const body = { success: false, data: null, message: 'Langganan berakhir.', errors: { langganan: ['BERAKHIR'] }, meta: { langganan: { status: 'KEDALUWARSA', perpanjang_url: 'https://contoh.test/perpanjang' } } }
  const { api } = jembatanAndroid({ status: 402, body })
  let info = null
  api.langganan.onTerkunci((i) => { info = i })
  const r = await api.pengeluaran.create({ keterangan: 'Es', nominal: 5000 })
  assert.equal(r.ok, false)
  assert.equal(r.status, 402)
  assert.equal(r.meta.langganan.perpanjang_url, 'https://contoh.test/perpanjang')
  assert.equal(info.pesan, 'Langganan berakhir.')
  assert.equal(info.perpanjang_url, 'https://contoh.test/perpanjang')
})

test('#1 Android lama: laporGalat → POST /diagnostik berbentuk kontrak (platform android-legacy)', async () => {
  const { api, panggilan } = jembatanAndroid({ status: 202, body: { success: true, data: { id: 1 } } })
  const r = await api.diagnostik.laporGalat({ pesan: 'TypeError: x', stack: 'at y', layar: 'Kasir' })
  assert.equal(r.ok, true)
  const p = panggilan[0]
  assert.equal(p.metode, 'POST')
  assert.equal(p.url.pathname, '/api/pos/v1/diagnostik')
  const b = JSON.parse(p.body)
  assert.equal(b.platform, 'android-legacy')
  assert.equal(b.jenis, 'error')
  assert.equal(b.pesan, 'TypeError: x')
  assert.equal(b.konteks.layar, 'Kasir')
  assert.ok(b.client_ref && b.terjadi_pada && b.versi)
  const ulang = jembatanAndroid({ status: 202, body: { success: true } })
  await ulang.api.diagnostik.laporGalat({ pesan: 'TypeError: x', stack: 'at y' })
  assert.equal(JSON.parse(ulang.panggilan[0].body).client_ref, b.client_ref, 'galat sama di hari sama → client_ref sama (dedupe server)')
})

test('Mode Demo: status langganan membawa ambang & blokir_tulis; IPOS_SMOKE_LANGGANAN=blokir → 402 hanya pada kanal tulis', () => {
  const demo = require('../src/main/demo.js')
  const lama = process.env.IPOS_SMOKE_LANGGANAN
  try {
    delete process.env.IPOS_SMOKE_LANGGANAN
    demo.start()
    const s = demo.handlers['langganan:status']().data
    assert.equal(typeof s.ambang_peringatan_hari, 'number')
    assert.equal(s.blokir_tulis, false)
    assert.equal(demo.langgananDiblokir('trx:checkout'), null, 'tanpa simulasi → tidak ada 402')

    process.env.IPOS_SMOKE_LANGGANAN = 'blokir'
    assert.equal(demo.handlers['langganan:status']().data.blokir_tulis, true)
    const b = demo.langgananDiblokir('trx:checkout')
    assert.equal(b.status, 402)
    assert.deepEqual(b.errors, { langganan: ['BERAKHIR'] })
    assert.match(b.meta.langganan.perpanjang_url, /^https:\/\//)
    for (const kanal of ['pengeluaran:create', 'inventory:stokMasuk', 'produk:update', 'bill:bayar', 'pengaturan:uploadLogo', 'table:nonaktifkan']) {
      assert.equal(demo.langgananDiblokir(kanal).status, 402, kanal)
    }
    for (const kanal of ['produk:list', 'trx:list', 'langganan:bayar', 'langganan:status', 'cs:kontak', 'auth:logout', 'laporan:stok', 'offline:batalkan']) {
      assert.equal(demo.langgananDiblokir(kanal), null, kanal)
    }
  } finally {
    if (lama === undefined) delete process.env.IPOS_SMOKE_LANGGANAN; else process.env.IPOS_SMOKE_LANGGANAN = lama
    demo.stop()
  }
})

test('tanpa literal kontak/brand/ambang di renderer & proses utama (kecuali data simulasi Mode Demo)', () => {
  const daftar = (dir) => fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
    const p = path.join(dir, e.name)
    return e.isDirectory() ? daftar(p) : (p.endsWith('.js') ? [p] : [])
  })
  const berkas = [...daftar(path.join(AKAR, 'src/renderer/js')), ...daftar(path.join(AKAR, 'src/main')), path.join(AKAR, '../mobile/www-src/js/mobile-bridge.js')]
    .filter((p) => !/demo(-data)?\.js$|qrcode-generator\.js$/.test(p))
  const temuan = []
  for (const p of berkas) {
    const baris = fs.readFileSync(p, 'utf8').split('\n')
    baris.forEach((b, i) => {
      if (/^\s*(\/\/|\*)/.test(b)) return // komentar dokumentasi
      // Nomor WA/telepon, email, domain & URL langganan tertanam; konstanta ambang; merek server dalam teks.
      if (/wa\.me\/\d|(?:\+?62|\b0)8\d{7,}|tuleh\.id|[\w.-]+@(?:gmail|tuleh|tatreport)\.|tatreport\.com\/langganan/i.test(b) ||
          /AMBANG_PERINGATAN_HARI|\bMOVERA\b/.test(b)) {
        temuan.push(`${path.relative(AKAR, p)}:${i + 1}: ${b.trim().slice(0, 120)}`)
      }
    })
  }
  assert.deepEqual(temuan, [])
})
