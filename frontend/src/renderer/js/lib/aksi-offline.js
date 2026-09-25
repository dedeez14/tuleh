// Gerbang tombol Batal/Refund di Riwayat (Fase 4). Renderer yang sama berjalan di desktop (berantrean) dan
// Android Capacitor (tanpa antrean) — keputusan memakai kemampuan platform, bukan "ini Electron atau bukan".
//   online              : jalur biasa (dialog PIN atasan bila tak punya hak).
//   offline + antrean   : hanya bila pengguna punya hak sendiri — token persetujuan PIN butuh server, jadi
//                         mustahil didapat offline; permintaan diantrekan.
//   transaksi lokal     : selalu lewat antrean (server belum mengenal transaksinya) → selalu butuh hak sendiri.
// Murni (tanpa DOM/state) agar bisa diuji.

export function adalahLokal(struk) {
  return !!struk && (struk.belum_sinkron === true || String(struk.id || '').startsWith('lokal:'))
}

/** Batal disembunyikan untuk transaksi pelunasan pesanan (server menolak; uang harus kembali lewat Refund). */
export function tampilkanBatal(struk) {
  if (!struk) return false
  if (String(struk.status || '').toUpperCase() === 'DIBATALKAN') return false
  if (struk.pelunasan_pesanan === true) return false
  if (Number(struk.uang_muka) > 0) return false
  return true
}

const PESAN_HANYA_ONLINE = {
  'transaksi.batal': 'Pembatalan hanya bisa dilakukan saat terhubung ke server.',
  'transaksi.refund': 'Refund hanya bisa dilakukan saat terhubung ke server.'
}

/**
 * @param {{aksi: 'transaksi.batal'|'transaksi.refund', online: boolean|undefined, antreanOffline: boolean, punyaHak: boolean, lokal: boolean}} o
 * @returns {{boleh: boolean, antre: boolean, pesan: string|null}}  antre=true → tanpa dialog PIN, diantrekan
 */
export function putusanAksi({ aksi, online, antreanOffline, punyaHak, lokal }) {
  if (lokal) {
    if (!antreanOffline) return { boleh: false, antre: false, pesan: 'Transaksi ini belum tersinkron.' }
    if (!punyaHak) return { boleh: false, antre: false, pesan: 'Butuh persetujuan atasan — tunggu transaksi ini tersinkron, lalu ulangi saat online.' }
    return { boleh: true, antre: true, pesan: null }
  }
  if (online !== false) return { boleh: true, antre: false, pesan: null }
  if (!antreanOffline) return { boleh: false, antre: false, pesan: PESAN_HANYA_ONLINE[aksi] || 'Hanya bisa dilakukan saat terhubung ke server.' }
  if (!punyaHak) return { boleh: false, antre: false, pesan: 'Butuh persetujuan atasan — hanya bisa saat online.' }
  return { boleh: true, antre: true, pesan: null }
}
