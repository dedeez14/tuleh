// Navigasi grid dengan panah (roving focus) — dipakai katalog kasir.
// Murni terhadap DOM minimal (elemen dengan getBoundingClientRect), jadi bisa
// diuji dengan objek tiruan.

/** Jumlah kolom = banyaknya kartu yang sebaris dengan kartu pertama. */
export function hitungKolom(kartu) {
  if (!kartu.length) return 1
  const y0 = Math.round(kartu[0].getBoundingClientRect().top)
  let n = 0
  for (const k of kartu) {
    if (Math.round(k.getBoundingClientRect().top) !== y0) break
    n++
  }
  return Math.max(1, n)
}

/**
 * Indeks tujuan untuk tombol panah/Home/End. Kanan/kiri berhenti di ujung
 * (tidak melompat baris) agar prediksi kasir sederhana; atas/bawah tetap di
 * kolom yang sama, dan baris terakhir yang pendek dijepit ke kartu terakhir.
 */
export function indeksTujuan(key, indeks, jumlah, kolom) {
  if (jumlah <= 0) return -1
  switch (key) {
    case 'ArrowRight': return Math.min(jumlah - 1, indeks + 1)
    case 'ArrowLeft': return Math.max(0, indeks - 1)
    case 'ArrowDown': return indeks + kolom < jumlah ? indeks + kolom : (indeks === jumlah - 1 ? indeks : jumlah - 1)
    case 'ArrowUp': return indeks - kolom >= 0 ? indeks - kolom : indeks
    case 'Home': return 0
    case 'End': return jumlah - 1
    default: return -1
  }
}

/** Apakah keydown adalah karakter cetak tunggal tanpa modifier (untuk lompat ke pencarian). */
export function karakterCetak(e) {
  return typeof e.key === 'string' && e.key.length === 1 && !e.ctrlKey && !e.altKey && !e.metaKey
}
