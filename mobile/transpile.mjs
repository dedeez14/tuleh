// Transpile semua JS di www/js ke target WebView Android lama (Android 10 =
// Chrome 77) agar sintaks modern (?., ??, logical-assign, dll.) jalan. Dijalankan
// SETELAH www dirakit, SEBELUM `cap sync`. Menjaga import/export ESM (native
// Chrome 61+) — hanya menurunkan sintaks operator, bukan mem-bundle.
//
// Pakai:  node transpile.mjs <dir-www-js>   (default: www/js)

import esbuild from 'esbuild'
import { readdirSync, statSync, readFileSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'

const ROOT = process.argv[2] || 'www/js'
const TARGET = 'es2017' // Chrome 63+ (Android 10 factory WebView = Chrome 77)

function walk (dir) {
  const out = []
  for (const name of readdirSync(dir)) {
    const p = join(dir, name)
    if (statSync(p).isDirectory()) out.push(...walk(p))
    else if (p.endsWith('.js')) out.push(p)
  }
  return out
}

const files = walk(ROOT)
let n = 0
for (const file of files) {
  const code = readFileSync(file, 'utf8')
  // Tanpa `format` → esbuild pertahankan struktur modul (import/export tetap),
  // hanya menurunkan sintaks > es2017 (mis. ?. ?? ke bentuk lama).
  const res = await esbuild.transform(code, { target: TARGET, loader: 'js', legalComments: 'none' })
  writeFileSync(file, res.code, 'utf8')
  n++
}
console.log(`[transpile] ${n} berkas JS → ${TARGET} (kompatibel Android 10 / Chrome 77)`)
