// Kemampuan perangkat dari app:info — layar menyembunyikan fitur yang tak didukung platform,
// tanpa pernah bertanya "ini Electron atau Android".
//   antreanOffline: transaksi/pengeluaran/stok masuk diantrekan saat offline (gateway lokal desktop)
//   printerSistem : daftar printer OS & cetak senyap tanpa dialog
//   laporanLog    : "Kirim laporan ke dukungan" berisi log berkas (desktop)

import { api } from '../api.js'

let cache = null

/** Tanpa field `kemampuan` (desktop lama) = kemampuan penuh desktop. */
export async function kemampuanPlatform() {
  if (cache) return cache
  const r = await api.app.info()
  const k = r && r.ok && r.data && r.data.kemampuan ? r.data.kemampuan : {}
  cache = { antreanOffline: k.antreanOffline !== false, printerSistem: k.printerSistem !== false, laporanLog: k.laporanLog !== false }
  return cache
}
