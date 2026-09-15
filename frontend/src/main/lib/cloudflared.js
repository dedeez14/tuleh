'use strict'

// Penyedia binary cloudflared ter-pin (versi + SHA-256 dari lib/cloudflared-manifest.json).
// Binary yang sudah ada diverifikasi dulu; tidak cocok (versi lama "latest" / rusak /
// dirusak) → unduh versi ter-pin ke berkas sementara, verifikasi, baru dipasang.
// Tanpa Electron agar teruji (fetch & fs disuntik).

const nodeFs = require('node:fs')
const path = require('node:path')
const crypto = require('node:crypto')
const manifestBawaan = require('./cloudflared-manifest.json')

function sha256Berkas(p, fsImpl = nodeFs) {
  return crypto.createHash('sha256').update(fsImpl.readFileSync(p)).digest('hex')
}

function manifestSah(m) {
  return !!m && typeof m.url === 'string' && m.url.startsWith('https://') &&
    typeof m.sha256 === 'string' && /^[a-f0-9]{64}$/.test(m.sha256) && typeof m.versi === 'string' && m.versi.length > 0
}

/**
 * @param {object} o
 * @param {string[]} o.lokasi   kandidat jalur binary (yang pertama = tujuan unduhan)
 * @param {typeof fetch} o.fetch
 */
async function pastikanCloudflared({ lokasi, fetch, manifest = manifestBawaan, fsImpl = nodeFs }) {
  if (!manifestSah(manifest)) throw new Error('Manifest cloudflared tidak sah (versi/url/sha256).')
  const hashDiharapkan = manifest.sha256.toLowerCase()

  for (const p of lokasi) {
    try {
      if (fsImpl.existsSync(p) && sha256Berkas(p, fsImpl) === hashDiharapkan) return p
    } catch { /* tidak terbaca → anggap tidak ada */ }
  }

  const tujuan = lokasi[0]
  if (!tujuan) throw new Error('Lokasi binary tidak tersedia.')
  fsImpl.mkdirSync(path.dirname(tujuan), { recursive: true })

  const res = await fetch(manifest.url)
  if (!res || !res.ok) throw new Error(`Gagal mengunduh cloudflared ${manifest.versi} (HTTP ${res ? res.status : 0}).`)
  const buf = Buffer.from(await res.arrayBuffer())
  const hash = crypto.createHash('sha256').update(buf).digest('hex')
  if (hash !== hashDiharapkan) {
    throw new Error(`Verifikasi cloudflared ${manifest.versi} gagal: SHA-256 tidak cocok. Binary tidak dipasang.`)
  }
  const tmp = `${tujuan}.unduh`
  fsImpl.writeFileSync(tmp, buf)
  fsImpl.renameSync(tmp, tujuan)
  return tujuan
}

module.exports = { pastikanCloudflared, sha256Berkas, manifestSah, manifest: manifestBawaan }
