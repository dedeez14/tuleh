'use strict'

// Log berkas berotasi (proses utama, renderer, gateway) di app.getPath('logs').
// Batas ukuran & jumlah berkas adalah mekanika infrastruktur log, bukan data bisnis.
// Setiap baris DISAMARKAN (token, PIN, kata sandi, kunci) sebelum menyentuh disk.

const nodeFs = require('node:fs')
const path = require('node:path')
const { samarkan } = require('./samarkan')

const MAKS_BYTE_PER_BERKAS = 1024 * 1024 // 1 MB
const MAKS_BERKAS = 5                    // <nama>.log + <nama>.1.log … <nama>.4.log
const MAKS_BARIS = 8000                  // satu baris dipotong agar log tak meledak

function formatArg(a) {
  if (a instanceof Error) return a.stack || a.message
  if (typeof a === 'string') return a
  try { return JSON.stringify(a) } catch { return String(a) }
}

/**
 * @param {object} o
 * @param {string} o.dir
 * @param {number} [o.maksByte]
 * @param {number} [o.maksBerkas]
 */
function buatPencatat({ dir, maksByte = MAKS_BYTE_PER_BERKAS, maksBerkas = MAKS_BERKAS, fsImpl = nodeFs, sekarang = () => new Date() }) {
  const jalur = (nama, i = 0) => path.join(dir, i === 0 ? `${nama}.log` : `${nama}.${i}.log`)

  function putar(nama) {
    // Buang yang tertua, geser sisanya: main.3.log → main.4.log, …, main.log → main.1.log
    try { fsImpl.rmSync(jalur(nama, maksBerkas - 1), { force: true }) } catch { /* abaikan */ }
    for (let i = maksBerkas - 2; i >= 0; i--) {
      try { if (fsImpl.existsSync(jalur(nama, i))) fsImpl.renameSync(jalur(nama, i), jalur(nama, i + 1)) } catch { /* abaikan */ }
    }
  }

  /** Tulis satu baris ke <dir>/<nama>.log. Tidak pernah melempar. */
  function tulis(nama, level, ...args) {
    try {
      let teks = args.map(formatArg).join(' ')
      if (teks.length > MAKS_BARIS) teks = teks.slice(0, MAKS_BARIS) + ' …[dipotong]'
      const baris = `${sekarang().toISOString()} [${level}] ${samarkan(teks)}\n`
      fsImpl.mkdirSync(dir, { recursive: true })
      let ukuran = 0
      try { ukuran = fsImpl.statSync(jalur(nama)).size } catch { ukuran = 0 }
      if (ukuran > 0 && ukuran + Buffer.byteLength(baris) > maksByte) putar(nama)
      fsImpl.appendFileSync(jalur(nama), baris)
    } catch { /* log tidak boleh menjatuhkan aplikasi */ }
  }

  /**
   * Ekor log gabungan (terbaru di akhir) untuk laporan dukungan — sudah disamarkan.
   * @param {string[]} nama  mis. ['main', 'renderer', 'gateway']
   * @param {number} maksKarakter  total batas karakter
   */
  function ekor(nama, maksKarakter) {
    const bagian = []
    const jatah = Math.max(200, Math.floor(maksKarakter / Math.max(1, nama.length)))
    for (const n of nama) {
      let isi = ''
      for (let i = 0; i < maksBerkas && isi.length < jatah; i++) {
        try { isi = fsImpl.readFileSync(jalur(n, i), 'utf8') + isi } catch { break }
      }
      if (!isi) continue
      const potong = isi.length > jatah ? isi.slice(isi.length - jatah) : isi
      // Mulai dari baris utuh.
      const awal = isi.length > jatah ? potong.indexOf('\n') + 1 : 0
      bagian.push(`=== ${n}.log ===\n${samarkan(potong.slice(awal))}`)
    }
    const hasil = bagian.join('\n')
    return hasil.length > maksKarakter ? hasil.slice(hasil.length - maksKarakter) : hasil
  }

  return { tulis, ekor, dir }
}

/** Salin console.* proses utama ke log berkas (tetap tampil di terminal). */
function pasangKonsol(pencatat, nama = 'main', konsol = console) {
  for (const [metode, level] of [['log', 'info'], ['info', 'info'], ['warn', 'warn'], ['error', 'error']]) {
    const asli = konsol[metode].bind(konsol)
    konsol[metode] = (...args) => {
      pencatat.tulis(nama, level, ...args)
      try { asli(...args) } catch { /* stdout tertutup (EPIPE) */ }
    }
  }
}

module.exports = { buatPencatat, pasangKonsol, MAKS_BYTE_PER_BERKAS, MAKS_BERKAS }
