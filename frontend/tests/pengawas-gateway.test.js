'use strict'

// Siklus hidup gateway lokal: pakai ulang hanya bila upstream & versi sama; proses keluar →
// kembali ke koneksi langsung SEGERA lalu nyala ulang dengan mundur; gateway tak menjawab →
// sama; hentikan() membatalkan nyala ulang.

const test = require('node:test')
const assert = require('node:assert/strict')
const { EventEmitter } = require('node:events')

const { buatPengawasGateway, jedaNyalaUlang } = require('../src/main/lib/pengawas-gateway')

const UP = 'https://toko.contoh.test'

function prosesPalsu() {
  const p = new EventEmitter()
  p.stdout = new EventEmitter()
  p.stderr = new EventEmitter()
  p.dibunuh = false
  p.kill = () => { p.dibunuh = true; p.emit('exit', null, 'SIGTERM') }
  return p
}

function rakit({ versiApp = '0.9.40', sehat = {}, adaBinary = true, binary = { ada: adaBinary } } = {}) {
  const log = []
  const perubahan = []
  const jadwal = []
  const proses = []
  const health = { ...sehat } // port → data /healthz
  const env = []
  let jam = 0
  const pengawas = buatPengawasGateway({
    exePath: () => '/app/mpos-backend',
    existsSync: () => binary.ada,
    spawn: (_exe, e) => {
      env.push(e)
      const p = prosesPalsu()
      const port = Number(e.MPOS_LISTEN.split(':')[1])
      // "menyala": healthz melapor versi dari env (build tanpa ldflags)
      health[port] = { app: 'mpos-backend', upstream: e.MPOS_UPSTREAM, version: e.MPOS_VERSION }
      p.on('exit', () => { delete health[port] })
      proses.push(p)
      return p
    },
    probe: async (port) => health[port] || null,
    versiApp,
    onBerubah: (st) => perubahan.push(st),
    log: (b) => log.push(b),
    ports: [8787, 8788],
    sleep: async () => { jam += 250 },
    sekarang: () => jam,
    jadwal: (fn, ms) => { const t = { fn, ms }; jadwal.push(t); return t },
    batalJadwal: (t) => { t.batal = true }
  })
  return { pengawas, log, perubahan, jadwal, proses, health, env, binary }
}

test('menyalakan binary bawaan dengan MPOS_UPSTREAM + MPOS_VERSION aplikasi', async () => {
  const { pengawas, env, perubahan } = rakit()
  const r = await pengawas.pastikan(UP)
  assert.deepEqual(r, { ok: true, port: 8787, external: false })
  assert.deepEqual(env[0], { MPOS_LISTEN: '127.0.0.1:8787', MPOS_UPSTREAM: UP, MPOS_VERSION: '0.9.40' })
  assert.equal(perubahan.at(-1).running, true)
  assert.equal(pengawas.status().version, '0.9.40')
})

test('gateway eksternal versi BERBEDA tidak dipakai ulang; versi sama dipakai ulang', async () => {
  const beda = rakit({ sehat: { 8787: { app: 'mpos-backend', upstream: UP, version: '0.9.30' } } })
  const r = await beda.pengawas.pastikan(UP)
  assert.equal(r.port, 8788, 'port 8787 berisi gateway versi lama → nyalakan sendiri di port lain')
  assert.equal(r.external, false)
  assert.ok(beda.log.some((b) => /0\.9\.30/.test(b)))

  const sama = rakit({ sehat: { 8787: { app: 'mpos-backend', upstream: UP, version: '0.9.40' } } })
  const r2 = await sama.pengawas.pastikan(UP)
  assert.deepEqual(r2, { ok: true, port: 8787, external: true })
  assert.equal(sama.proses.length, 0)
})

test('proses keluar tak diminta → status tidak berjalan SEGERA, lalu nyala ulang dengan mundur', async () => {
  const { pengawas, proses, perubahan, jadwal } = rakit()
  await pengawas.pastikan(UP)
  proses[0].emit('exit', 2, null) // gateway crash
  assert.equal(perubahan.at(-1).running, false, 'aplikasi kembali ke koneksi langsung')
  assert.equal(jadwal.length, 1)
  assert.equal(jadwal[0].ms, jedaNyalaUlang(1))

  jadwal[0].fn()
  await new Promise((r) => setImmediate(r))
  await new Promise((r) => setImmediate(r))
  assert.equal(pengawas.status().running, true)
  assert.equal(pengawas.status().percobaanUlang, 0, 'berhasil → hitungan mundur direset')
  assert.equal(proses.length, 2)
})

test('nyala ulang gagal → dijadwalkan lagi dengan mundur makin panjang', async () => {
  const ctx = rakit()
  await ctx.pengawas.pastikan(UP)
  ctx.proses[0].emit('exit', 1, null)
  ctx.binary.ada = false // mis. binary dikarantina antivirus
  ctx.jadwal[0].fn()
  await new Promise((r) => setImmediate(r))
  await new Promise((r) => setImmediate(r))
  assert.equal(ctx.jadwal.length, 2)
  assert.equal(ctx.jadwal[1].ms, jedaNyalaUlang(2))
  assert.ok(ctx.jadwal[1].ms > ctx.jadwal[0].ms)
  assert.equal(ctx.pengawas.status().running, false)
  assert.deepEqual([jedaNyalaUlang(1), jedaNyalaUlang(2), jedaNyalaUlang(9)], [1000, 5000, 300000])
})

test('laporGagal (koneksi ditolak) → kembali langsung + nyala ulang terjadwal; hentikan() membatalkannya', async () => {
  const { pengawas, perubahan, jadwal, proses } = rakit()
  await pengawas.pastikan(UP)
  pengawas.laporGagal()
  assert.equal(perubahan.at(-1).running, false)
  assert.equal(proses[0].dibunuh, true)
  assert.equal(jadwal.length, 1)
  pengawas.hentikan()
  assert.equal(jadwal[0].batal, true)
  assert.equal(pengawas.status().menungguNyalaUlang, false)
})

test('hentikan() saat berjalan: proses dimatikan TANPA nyala ulang', async () => {
  const { pengawas, proses, jadwal } = rakit()
  await pengawas.pastikan(UP)
  pengawas.hentikan()
  assert.equal(proses[0].dibunuh, true)
  assert.equal(jadwal.length, 0)
  assert.equal(pengawas.status().running, false)
})

test('upstream lokal / tak valid tidak menyalakan gateway', async () => {
  const { pengawas, proses } = rakit()
  assert.equal((await pengawas.pastikan('http://localhost:8000')).reason, 'upstream lokal')
  assert.equal((await pengawas.pastikan('bukan url')).reason, 'upstream tidak valid')
  assert.equal(proses.length, 0)
})

test('stdout/stderr gateway diteruskan ke log', async () => {
  const { pengawas, proses, log } = rakit()
  await pengawas.pastikan(UP)
  proses[0].stdout.emit('data', 'level=INFO msg=req path=/api/pos/v1/ping\n')
  proses[0].stderr.emit('data', 'panic: x\n')
  assert.ok(log.some((b) => b.startsWith('[gateway:out]') && b.includes('/ping')))
  assert.ok(log.some((b) => b.startsWith('[gateway:err]') && b.includes('panic')))
})
