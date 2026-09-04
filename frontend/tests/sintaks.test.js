'use strict'

// Jaring pengaman: SETIAP berkas JS renderer & main harus lolos parser Node.
// Satu kesalahan sintaks di modul mana pun menggagalkan seluruh aplikasi
// (import ESM gagal) dan build APK Capacitor (esbuild transpile). electron-
// builder tidak memeriksa JS, jadi tanpa test ini exe rusak bisa terbit.

const test = require('node:test')
const assert = require('node:assert/strict')
const { spawnSync } = require('node:child_process')
const fs = require('node:fs')
const path = require('node:path')

function daftar(dir) {
  const out = []
  for (const nama of fs.readdirSync(dir)) {
    const p = path.join(dir, nama)
    if (fs.statSync(p).isDirectory()) out.push(...daftar(p))
    else if (p.endsWith('.js')) out.push(p)
  }
  return out
}

for (const akar of ['src/renderer/js', 'src/main', 'src/preload']) {
  const dir = path.join(__dirname, '..', akar)
  for (const file of daftar(dir)) {
    test(`sintaks sah: ${path.relative(path.join(__dirname, '..'), file)}`, () => {
      const r = spawnSync(process.execPath, ['--check', file], { encoding: 'utf8' })
      assert.equal(r.status, 0, r.stderr)
    })
  }
}
