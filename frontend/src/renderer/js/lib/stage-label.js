// Label manusiawi untuk kode tahap lifecycle (papan pesanan, dsb.).
// Tahap di luar peta → Title Case otomatis, sehingga bidang usaha baru yang
// dikirim server tetap terbaca TANPA rilis app; peta ini hanya memperbaiki
// ejaan/istilah (mis. FINISHING → "Finishing & Poles" mengikuti label server).
// Dipisah dari orders.js supaya bisa diuji tanpa DOM/bridge.

export const STAGE_LABELS = {
  MENUNGGU_BAYAR: 'Menunggu Bayar',
  ANTRIAN: 'Antrian',
  DIPROSES: 'Diproses',
  READY: 'Siap',
  PENCUCIAN: 'Pencucian',
  PENGERINGAN: 'Pengeringan',
  LIPAT: 'Lipat & Kemas',
  SIAP_AMBIL: 'Siap Diambil',
  SELESAI: 'Selesai',
  // Jasa kendaraan & salon (MOVERA config/pos_verticals.php manifest_override)
  PEMERIKSAAN: 'Pemeriksaan',
  PENGERJAAN: 'Pengerjaan',
  DILAYANI: 'Dilayani',
  FINISHING: 'Finishing & Poles'
}

export function stageLabel(stage) {
  if (STAGE_LABELS[stage]) return STAGE_LABELS[stage]
  return String(stage || '')
    .toLowerCase()
    .split('_')
    .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
    .join(' ')
}
