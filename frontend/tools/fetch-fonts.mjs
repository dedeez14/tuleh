// Mengunduh font self-hosted (Plus Jakarta Sans + IBM Plex Mono, subset latin)
// dan menulis @font-face ke assets/fonts/fonts.css.
//
// Dijalankan otomatis lewat `npm install` (postinstall). Aman dijalankan
// berulang; tidak pernah menggagalkan instalasi (best-effort). Bila offline
// atau tulisan diblokir (mis. Controlled Folder Access), aplikasi tetap jalan
// dengan font sistem (Segoe UI Variable).

import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const OUT_DIR = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'src', 'renderer', 'assets', 'fonts')
const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36'
const CSS_URL = 'https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:ital,wght@0,200..800;1,200..800&family=IBM+Plex+Mono:wght@400;500;600&display=swap'

async function main() {
  const res = await fetch(CSS_URL, { headers: { 'User-Agent': UA } })
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  const css = await res.text()

  const blocks = [...css.matchAll(/\/\* ([a-z-]+) \*\/\s*@font-face\s*\{([^}]+)\}/g)]
  const latin = blocks.filter(([, subset]) => subset === 'latin')
  if (latin.length === 0) throw new Error('Tidak ada blok subset latin ditemukan.')

  fs.mkdirSync(OUT_DIR, { recursive: true })

  let out = '/* Font self-hosted (subset latin) — dihasilkan oleh tools/fetch-fonts.mjs */\n'
  for (const [, , body] of latin) {
    const family = body.match(/font-family:\s*'([^']+)'/)[1]
    const style = body.match(/font-style:\s*(\w+)/)[1]
    const weight = body.match(/font-weight:\s*([\d ]+)/)[1].trim()
    const url = body.match(/url\((https:[^)]+)\)/)[1]
    const slug = family.toLowerCase().replace(/\s+/g, '-')
    const file = `${slug}-${style}-${weight.replace(/\s+/g, '-')}-latin.woff2`
    const target = path.join(OUT_DIR, file)

    const needsDownload = !fs.existsSync(target) || fs.statSync(target).size < 1000
    if (needsDownload) {
      const fontRes = await fetch(url, { headers: { 'User-Agent': UA } })
      if (!fontRes.ok) throw new Error(`Gagal unduh ${file}: HTTP ${fontRes.status}`)
      fs.writeFileSync(target, Buffer.from(await fontRes.arrayBuffer()))
      console.log(`  unduh: ${file}`)
    }

    out += `\n@font-face {\n  font-family: '${family}';\n  font-style: ${style};\n  font-weight: ${weight};\n  font-display: swap;\n  src: url('./${file}') format('woff2');\n}\n`
  }

  fs.writeFileSync(path.join(OUT_DIR, 'fonts.css'), out, 'utf8')
  console.log('[fetch-fonts] Font self-hosted siap.')
}

main().catch((err) => {
  console.warn(`[fetch-fonts] Dilewati (${err.message}). Aplikasi memakai font sistem.`)
})
