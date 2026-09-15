'use strict'

// Penjaga alur rilis (.github/workflows/release.yml): tes lulus SEBELUM build/rilis,
// gateway Go wajib ter-build (bukan best-effort) dengan versi aplikasi via ldflags,
// dan dependensi frontend dipasang dari lockfile.

const test = require('node:test')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')

const AKAR = path.join(__dirname, '..')
const ci = fs.readFileSync(path.join(AKAR, '../.github/workflows/release.yml'), 'utf8')

function job(nama) {
  const m = ci.match(new RegExp(`\\n  ${nama}:\\n([\\s\\S]*?)(?=\\n  [a-z-]+:\\n|$)`))
  assert.ok(m, `job ${nama} ada`)
  return m[1]
}

test('job tests menjalankan tes Node dan go vet/go test', () => {
  const t = job('tests')
  assert.match(t, /node --test tests\/\*\.test\.js/)
  assert.match(t, /go vet \.\/\.\.\./)
  assert.match(t, /go test[^\n]*\.\/\.\.\./)
})

test('build desktop, android, dan rilis bergantung pada tests', () => {
  for (const nama of ['desktop', 'android', 'release']) {
    assert.match(job(nama), /needs: \[[^\]]*\btests\b[^\]]*\]/, `${nama} needs tests`)
  }
})

test('gateway Go wajib: tanpa continue-on-error, versi via ldflags, binary diperiksa sebelum dikemas', () => {
  const d = job('desktop')
  assert.doesNotMatch(d, /continue-on-error/)
  assert.match(d, /-X main\.appVersion=\$VER/)
  assert.match(d, /mpos-backend\.exe/)
  const iCek = d.indexOf('Pastikan binary gateway')
  const iKemas = d.indexOf('electron-builder')
  assert.ok(iCek > 0 && iCek < iKemas, 'pemeriksaan binary sebelum electron-builder')
})

test('frontend dipasang dengan npm ci (lockfile ada)', () => {
  assert.ok(fs.existsSync(path.join(AKAR, 'package-lock.json')))
  assert.match(job('desktop'), /npm ci/)
})
