'use strict'

const assert = require('node:assert/strict')
const fs = require('node:fs')

function verifySmoke(report, version) {
  assert.equal(report.loaded, true, 'Jendela aplikasi gagal dimuat')
  assert.equal(report.rendererReady, true, 'Boot renderer belum selesai')
  assert.equal(report.demo, true, 'Pengujian harus memakai Mode Demo')
  assert.equal(report.version, version, 'Versi aplikasi tidak sesuai rilis')
  assert.equal(report.gateway?.running, true, 'Gateway bawaan tidak berjalan')
  assert.equal(report.gateway?.version, version, 'Versi gateway tidak sesuai aplikasi')
  assert.equal(report.gateway?.external, false, 'Tes harus menjalankan gateway bawaan installer')
  assert.equal(report.gateway?.upstream, 'https://tuleh-smoke.invalid', 'Profil pengujian harus terisolasi')
  assert.ok(Array.isArray(report.log), 'Log renderer tidak tersedia')
  const errors = report.log.filter((line) => /^(\[3\]|\[error\]|did-fail-load:)/i.test(line))
  assert.deepEqual(errors, [], 'Ada galat pada renderer hasil instalasi')
}

module.exports = { verifySmoke }

if (require.main === module) {
  const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8').replace(/^\uFEFF/, ''))
  verifySmoke(report, require('../package.json').version)
  console.log(`Installer ${report.version}: boot demo dan gateway terverifikasi.`)
}
