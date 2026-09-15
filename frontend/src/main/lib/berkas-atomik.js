'use strict'

// Penulisan berkas JSON yang tahan mati listrik / proses dibunuh:
//   1. tulis ke <berkas>.tmp, fsync (isi benar-benar di disk sebelum dipakai);
//   2. generasi sebelumnya dipindah ke <berkas>.bak;
//   3. rename .tmp → <berkas> (atomik pada NTFS/ext4), fsync folder (best-effort).
// Pembacaan: berkas utama rusak → coba .bak; keduanya rusak → berkas rusak DIPINDAH ke
// samping (<nama>.rusak-<cap waktu>.json), tidak pernah ditimpa kosong.
//
// `fsImpl` bisa disuntik (tes: simulasi disk penuh / tulis parsial).

const nodeFs = require('node:fs')
const path = require('node:path')

function fsyncFolder(fsImpl, dir) {
  let fd = null
  try {
    fd = fsImpl.openSync(dir, 'r')
    fsImpl.fsyncSync(fd)
  } catch { /* Windows tidak mengizinkan fsync folder — rename NTFS sudah dijurnal */ } finally {
    if (fd !== null) { try { fsImpl.closeSync(fd) } catch { /* abaikan */ } }
  }
}

/**
 * Tulis `isi` (string) secara atomik. Melempar Error bila gagal — pemanggil WAJIB
 * memberi tahu pengguna, bukan diam-diam menyimpan di memori.
 */
function tulisAtomik(berkas, isi, { fsImpl = nodeFs, cadangan = true } = {}) {
  const dir = path.dirname(berkas)
  fsImpl.mkdirSync(dir, { recursive: true })
  const tmp = `${berkas}.tmp`
  const fd = fsImpl.openSync(tmp, 'w')
  try {
    fsImpl.writeSync(fd, isi)
    fsImpl.fsyncSync(fd)
  } finally {
    fsImpl.closeSync(fd)
  }
  if (cadangan && fsImpl.existsSync(berkas)) {
    fsImpl.renameSync(berkas, `${berkas}.bak`)
  }
  fsImpl.renameSync(tmp, berkas)
  fsyncFolder(fsImpl, dir)
}

function capWaktu(tanggal) {
  return tanggal.toISOString().replace(/[:.]/g, '-')
}

/** Pindahkan berkas rusak ke samping; mengembalikan jalur barunya (null bila gagal). */
function pindahkanRusak(berkas, { fsImpl = nodeFs, sekarang = () => new Date(), label = '', namaDasar = berkas } = {}) {
  const dir = path.dirname(berkas)
  const dasar = path.basename(namaDasar, '.json')
  const tujuan = path.join(dir, `${dasar}${label}.rusak-${capWaktu(sekarang())}.json`)
  try {
    fsImpl.renameSync(berkas, tujuan)
    return tujuan
  } catch {
    return null
  }
}

/**
 * Baca JSON dengan pemulihan dari .bak.
 * @param {string} berkas
 * @param {(data: any) => boolean} sah  validasi bentuk (mis. objek antrean)
 * @returns {{ data: any|null, sumber: 'utama'|'sementara'|'cadangan'|'kosong', peringatan: string|null, berkasRusak: string[] }}
 */
function bacaDenganPemulihan(berkas, sah, { fsImpl = nodeFs, sekarang = () => new Date(), nama = 'Berkas data' } = {}) {
  const bak = `${berkas}.bak`
  const berkasRusak = []

  const coba = (p) => {
    let teks
    try {
      teks = fsImpl.readFileSync(p, 'utf8')
    } catch (err) {
      return { ada: !(err && err.code === 'ENOENT'), rusak: !(err && err.code === 'ENOENT'), data: null }
    }
    try {
      const data = JSON.parse(teks)
      return sah(data) ? { ada: true, rusak: false, data } : { ada: true, rusak: true, data: null }
    } catch {
      return { ada: true, rusak: true, data: null }
    }
  }

  const utama = coba(berkas)
  if (utama.data !== null) return { data: utama.data, sumber: 'utama', peringatan: null, berkasRusak }

  if (!utama.ada) {
    // Proses mati di antara "utama → .bak" dan ".tmp → utama": .tmp sudah di-fsync
    // dan merupakan generasi terbaru bila isinya utuh.
    const tmp = coba(`${berkas}.tmp`)
    if (tmp.data !== null) return { data: tmp.data, sumber: 'sementara', peringatan: null, berkasRusak }
  }

  if (utama.rusak) {
    const dipindah = pindahkanRusak(berkas, { fsImpl, sekarang })
    if (dipindah) berkasRusak.push(dipindah)
  }

  const cadangan = coba(bak)
  if (cadangan.data !== null) {
    return {
      data: cadangan.data,
      sumber: 'cadangan',
      peringatan: utama.rusak ? `${nama} rusak; dipulihkan dari salinan cadangan terakhir.` : null,
      berkasRusak
    }
  }
  if (cadangan.rusak) {
    // .bak rusak juga dipindah agar penulisan berikutnya tidak menimpanya.
    const dipindah = pindahkanRusak(bak, { fsImpl, sekarang, label: '.bak', namaDasar: berkas })
    if (dipindah) berkasRusak.push(dipindah)
  }
  if (utama.rusak || cadangan.rusak) {
    return {
      data: null,
      sumber: 'kosong',
      peringatan: `${nama} rusak dan tidak bisa dipulihkan. Berkas asli disimpan terpisah untuk diperiksa dukungan.`,
      berkasRusak
    }
  }
  return { data: null, sumber: 'kosong', peringatan: null, berkasRusak }
}

module.exports = { tulisAtomik, bacaDenganPemulihan, pindahkanRusak }
