// Turunan status langganan tenant (Sistem Mitra, kontrak §6.5).
// Dipakai bersama oleh notifikasi (notif.js) dan banner Beranda (app.js)
// agar aturan ambang & pesan konsisten di satu tempat.
//
// Ambang peringatan "segera berakhir" TIDAK ditanam di aplikasi: dibaca dari
// /langganan/status → `ambang_peringatan_hari` (master data server, kontrak #3).
// Server lama tanpa field itu → tidak ada peringatan "segera berakhir" (jangan mengarang).

/** Ambang hari dari server; null bila tidak dikirim / tidak sah. */
export function ambangPeringatanHari(langganan) {
  const raw = langganan && langganan.ambang_peringatan_hari
  if (raw == null || raw === '' || typeof raw === 'boolean') return null
  const n = Number(raw)
  return Number.isFinite(n) && n >= 0 ? n : null
}

/**
 * ringkasLangganan(langganan) → { level, perluAksi, judul, detail, sisaHari, nama }
 * level: 'none' (data tak ada) | 'ok' | 'segera' | 'grace' | 'kedaluwarsa'
 * perluAksi=true menandai keadaan yang perlu ditonjolkan (notif + banner).
 */
export function ringkasLangganan(langganan) {
  if (!langganan || typeof langganan !== 'object') {
    return { level: 'none', perluAksi: false, sisaHari: null }
  }
  const status = String(langganan.status || '').toUpperCase()
  // null/undefined/'' → tak diketahui (JANGAN dianggap 0, karena Number(null)===0
  // akan salah memicu peringatan "segera berakhir").
  const raw = langganan.sisa_hari
  const sisaHari = (raw == null || raw === '' || !Number.isFinite(Number(raw))) ? null : Number(raw)
  const nama = langganan.plan_nama || 'Langganan'

  if (status === 'KEDALUWARSA') {
    return {
      level: 'kedaluwarsa', perluAksi: true, sisaHari, nama,
      judul: 'Langganan berakhir',
      detail: `Paket ${nama} telah berakhir. Perpanjang untuk melanjutkan layanan.`
    }
  }
  if (status === 'GRACE') {
    return {
      level: 'grace', perluAksi: true, sisaHari, nama,
      judul: 'Masa tenggang langganan',
      detail: `Paket ${nama} dalam masa tenggang. Segera perpanjang agar layanan tidak terhenti.`
    }
  }
  const ambang = ambangPeringatanHari(langganan)
  if (status === 'AKTIF' && sisaHari !== null && ambang !== null && sisaHari <= ambang) {
    return {
      level: 'segera', perluAksi: true, sisaHari, nama,
      judul: 'Langganan segera berakhir',
      detail: `Paket ${nama} tersisa ${sisaHari} hari. Perpanjang sebelum jatuh tempo.`
    }
  }
  // Aktif & sehat (atau status lain yang tak perlu peringatan)
  return { level: 'ok', perluAksi: false, sisaHari, nama }
}

/**
 * Model layar "Langganan berakhir" dari sinyal 402 (kontrak #2) — pesan & URL dari server.
 * URL perpanjang hanya dipakai bila https; kosong/tidak sah → tanpa tombol (bukan URL karangan).
 */
export function modelKunciLangganan(info) {
  const i = info && typeof info === 'object' ? info : {}
  const pesan = typeof i.pesan === 'string' && i.pesan.trim()
    ? i.pesan.trim()
    : 'Langganan usaha ini sudah berakhir. Data tetap bisa dilihat, tetapi transaksi baru tidak dapat disimpan sampai langganan diperpanjang.'
  let url = null
  if (typeof i.perpanjang_url === 'string') {
    try {
      const u = new URL(i.perpanjang_url)
      if (u.protocol === 'https:' && u.hostname && !u.username && !u.password) url = u.toString()
    } catch { url = null }
  }
  return { judul: 'Langganan berakhir', pesan, perpanjangUrl: url }
}
