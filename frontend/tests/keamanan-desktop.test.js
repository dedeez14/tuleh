'use strict'

// Pengerasan keamanan desktop: kebijakan izin Chromium, validasi URL eksternal, domain
// halaman selesai bayar dari server (bukan literal), permintaan firewall sesuai kebutuhan,
// dan binary cloudflared ter-pin + terverifikasi SHA-256.

const test = require('node:test')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const crypto = require('node:crypto')

const { izinkan, tandaiJendelaBayar, lepasJendelaBayar } = require('../src/main/lib/izin')
const { urlHttpsAman, domainServer, hostMilik } = require('../src/main/lib/url-aman')
const { buatFirewall } = require('../src/main/firewall')
const { pastikanCloudflared, manifestSah, manifest } = require('../src/main/lib/cloudflared')

const AKAR = path.join(__dirname, '..')

test('izin: aplikasi (file://) hanya notifikasi & salin; kamera/mikrofon/lokasi ditolak', () => {
  const app = { asalUrl: 'file:///C:/Program%20Files/Tuleh/resources/app.asar/src/renderer/index.html', webContentsId: 1 }
  assert.equal(izinkan('notifications', app), true)
  assert.equal(izinkan('clipboard-sanitized-write', app), true)
  for (const p of ['media', 'geolocation', 'clipboard-read', 'midi', 'hid', 'serial', 'usb', 'pointerLock', 'openExternal', 'display-capture']) {
    assert.equal(izinkan(p, app), false, p)
  }
})

test('izin: halaman https hanya boleh menyalin bila jendela bayar yang terdaftar', () => {
  const bayar = { asalUrl: 'https://app.midtrans.com/snap/v4/redirection/abc', webContentsId: 42 }
  assert.equal(izinkan('clipboard-sanitized-write', bayar), false, 'belum ditandai')
  tandaiJendelaBayar(42)
  assert.equal(izinkan('clipboard-sanitized-write', bayar), true)
  assert.equal(izinkan('notifications', bayar), false)
  assert.equal(izinkan('media', bayar), false)
  lepasJendelaBayar(42)
  assert.equal(izinkan('clipboard-sanitized-write', bayar), false)
  assert.equal(izinkan('notifications', { asalUrl: 'http://127.0.0.1:8791/display', webContentsId: 3 }), false)
})

test('urlHttpsAman: hanya https tanpa kredensial', () => {
  assert.equal(urlHttpsAman('https://contoh.test/perpanjang?x=1'), 'https://contoh.test/perpanjang?x=1')
  for (const u of ['http://contoh.test', 'javascript:alert(1)', 'file:///etc/passwd', 'https://u:p@contoh.test', '', null, 'https://', 'x'.repeat(3000)]) {
    assert.equal(urlHttpsAman(u), null, String(u).slice(0, 30))
  }
})

test('domain halaman selesai bayar diturunkan dari server yang dipakai (tanpa domain tertanam)', () => {
  assert.equal(domainServer('https://tokosaya.contoh.test'), 'contoh.test')
  assert.equal(domainServer('https://contoh.test'), 'contoh.test')
  assert.equal(domainServer('bukan url'), null)
  const domains = [domainServer('https://tokosaya.contoh.test'), null]
  assert.equal(hostMilik('https://pos.contoh.test/bayar/selesai', domains), true)
  assert.equal(hostMilik('https://contoh.test.jahat.test/bayar', domains), false)
  assert.equal(hostMilik('https://bukancontoh.test/bayar', domains), false)
  const ipc = fs.readFileSync(path.join(AKAR, 'src/main/ipc.js'), 'utf8')
  assert.doesNotMatch(ipc, /tatreport\\?\.com/i, 'ipc.js tidak boleh memuat domain tertanam')
})

test('firewall: tidak diminta saat start; permintaan otomatis yang ditolak tidak diulang di sesi yang sama', async () => {
  const main = fs.readFileSync(path.join(AKAR, 'src/main/main.js'), 'utf8')
  assert.doesNotMatch(main, /firewall'\)\.ensure\(/, 'main.js tidak boleh meminta firewall saat start')

  let diminta = 0
  let ada = false
  let setuju = false
  const fw = buatFirewall({ platform: 'win32', cekAturan: async () => ada, tambahAturan: async () => { diminta++; if (setuju) ada = true; return setuju } })
  assert.equal((await fw.ensure()).ok, false)
  assert.equal(diminta, 1)
  assert.equal((await fw.ensure()).reason, 'ditolak-sesi-ini')
  assert.equal(diminta, 1, 'tidak memunculkan UAC lagi otomatis')
  setuju = true
  assert.equal((await fw.ensure({ paksa: true })).ok, true, 'tombol eksplisit pengguna boleh meminta lagi')
  assert.equal(diminta, 2)
  assert.deepEqual(await fw.ensure(), { ok: true, added: false, already: true })

  const nonWin = buatFirewall({ platform: 'linux', cekAturan: async () => { throw new Error('tak boleh dipanggil') } })
  assert.equal((await nonWin.ensure()).reason, 'not-windows')
})

test('cloudflared: manifest ter-pin sah & tunnel.js tidak memakai "latest"', () => {
  assert.equal(manifestSah(manifest), true)
  assert.match(manifest.url, new RegExp(`/download/${manifest.versi.replace(/\./g, '\\.')}/`))
  assert.ok(Array.isArray(manifest.cara_memperbarui) && manifest.cara_memperbarui.length >= 3)
  const tunnel = fs.readFileSync(path.join(AKAR, 'src/main/tunnel.js'), 'utf8')
  assert.doesNotMatch(tunnel, /releases\/latest/)
  assert.doesNotMatch(tunnel, /[a-f0-9]{64}/, 'hash hanya di manifest')
})

function fetchPalsu(isi, status = 200) {
  let dipanggil = 0
  const fn = async () => { dipanggil++; return { ok: status === 200, status, arrayBuffer: async () => isi.buffer.slice(isi.byteOffset, isi.byteOffset + isi.byteLength) } }
  fn.jumlah = () => dipanggil
  return fn
}

test('cloudflared: unduhan hash cocok dipasang; tidak cocok DITOLAK; binary lama tak cocok diganti', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'tuleh-cf-'))
  const tujuan = path.join(dir, 'bin', 'cloudflared.exe')
  const isi = Buffer.from('binary cloudflared palsu')
  const m = { versi: '1.2.3', url: 'https://contoh.test/cf.exe', sha256: crypto.createHash('sha256').update(isi).digest('hex') }

  const palsu = await pastikanCloudflared({ lokasi: [tujuan], fetch: fetchPalsu(Buffer.from('dirusak')), manifest: m }).catch((e) => e)
  assert.match(String(palsu && palsu.message), /SHA-256 tidak cocok/)
  assert.equal(fs.existsSync(tujuan), false, 'binary tak terverifikasi tidak dipasang')

  const f = fetchPalsu(isi)
  assert.equal(await pastikanCloudflared({ lokasi: [tujuan], fetch: f, manifest: m }), tujuan)
  assert.equal(f.jumlah(), 1)
  assert.equal(await pastikanCloudflared({ lokasi: [tujuan], fetch: f, manifest: m }), tujuan)
  assert.equal(f.jumlah(), 1, 'binary sah yang ada dipakai tanpa unduh ulang')

  fs.writeFileSync(tujuan, 'versi latest lama yang tak terverifikasi')
  assert.equal(await pastikanCloudflared({ lokasi: [tujuan], fetch: f, manifest: m }), tujuan)
  assert.equal(f.jumlah(), 2, 'binary lama tak cocok → unduh versi ter-pin')
  assert.equal(fs.readFileSync(tujuan, 'utf8'), 'binary cloudflared palsu')

  await assert.rejects(pastikanCloudflared({ lokasi: [tujuan], fetch: f, manifest: { ...m, sha256: 'bukan-hash' } }), /Manifest/)
})
