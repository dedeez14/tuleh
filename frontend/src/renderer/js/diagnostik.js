// Penangkap galat renderer → laporan dukungan (kontrak #1) lewat jembatan
// (desktop: preload IPC → main/diagnostik.js; Android lama: langsung ke server).
// Diimpor PALING AWAL oleh app.js agar galat saat memuat modul lain ikut tertangkap.
// Galat yang sama dalam satu sesi dilaporkan sekali (anti-banjir); main/server juga
// menyingkirkan duplikat lewat client_ref.

const sudahDilapor = new Set()
const MAKS_LAPORAN_PER_SESI = 20

function jembatan() {
  const b = window.iposAPI
  return b && b.diagnostik && typeof b.diagnostik.laporGalat === 'function' ? b.diagnostik : null
}

function layarAktif() {
  try {
    const el = document.getElementById('tb-screen')
    return (el && el.textContent) || (location.search.includes('display=customer') ? 'display-pelanggan' : '')
  } catch { return '' }
}

/** Kirim laporan galat (dipakai juga oleh kode yang menangkap galat sendiri). */
export function laporGalat({ jenis = 'error', pesan, stack = '' }) {
  const d = jembatan()
  if (!d) return
  const kunci = `${jenis}|${pesan}|${String(stack).slice(0, 300)}`
  if (sudahDilapor.has(kunci) || sudahDilapor.size >= MAKS_LAPORAN_PER_SESI) return
  sudahDilapor.add(kunci)
  try {
    Promise.resolve(d.laporGalat({ jenis, pesan: String(pesan || '').slice(0, 4000), stack: String(stack || '').slice(0, 40000), layar: layarAktif() })).catch(() => {})
  } catch { /* jembatan gagal — jangan memicu galat baru */ }
}

export function pasangPenangkapGalat() {
  window.addEventListener('error', (e) => {
    const err = e && e.error
    laporGalat({
      pesan: (err && err.message) || (e && e.message) || 'Galat skrip',
      stack: (err && err.stack) || (e && e.filename ? `${e.filename}:${e.lineno}:${e.colno}` : '')
    })
  })
  window.addEventListener('unhandledrejection', (e) => {
    const r = e && e.reason
    laporGalat({
      pesan: (r && r.message) || (typeof r === 'string' ? r : 'Promise ditolak tanpa ditangani'),
      stack: (r && r.stack) || ''
    })
  })
}

pasangPenangkapGalat()
