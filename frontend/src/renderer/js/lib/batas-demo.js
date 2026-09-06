// Batasan Mode Demo di sisi tampilan: fitur yang mengeluarkan data dari
// aplikasi (ekspor, bagikan, akses internet publik) dinonaktifkan agar demo
// tetap untuk mencoba, bukan untuk berjualan. Batas transaksi per hari ada di
// mesin demo (main/demo.js) karena di sanalah transaksi dicatat.

import { getState } from '../state.js'
import { toast } from '../components/ui.js'

export const PESAN_DEMO_TERKUNCI = 'Tidak tersedia di Mode Demo. Masuk dengan akun berlangganan untuk memakainya.'

/** true bila sedang Mode Demo; sekaligus menampilkan pesan bila [beriTahu]. */
export function terkunciDemo({ beriTahu = true } = {}) {
  if (!getState().demo) return false
  if (beriTahu) toast(PESAN_DEMO_TERKUNCI, 'info')
  return true
}
