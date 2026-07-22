// Turunan status langganan tenant (Sistem Mitra, kontrak §6.5).
// Dipakai bersama oleh notifikasi (notif.js) dan banner Beranda (app.js)
// agar aturan ambang & pesan konsisten di satu tempat.

// Ambang peringatan "segera berakhir" (hari). Diselaraskan dengan keputusan
// produk; bisa dinaikkan/diturunkan tanpa mengubah pemakainya.
export const AMBANG_PERINGATAN_HARI = 7

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
  if (status === 'AKTIF' && sisaHari !== null && sisaHari <= AMBANG_PERINGATAN_HARI) {
    return {
      level: 'segera', perluAksi: true, sisaHari, nama,
      judul: 'Langganan segera berakhir',
      detail: `Paket ${nama} tersisa ${sisaHari} hari. Perpanjang sebelum jatuh tempo.`
    }
  }
  // Aktif & sehat (atau status lain yang tak perlu peringatan)
  return { level: 'ok', perluAksi: false, sisaHari, nama }
}
