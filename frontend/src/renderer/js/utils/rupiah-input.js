// Kolom uang yang memformat ribuan saat diketik: 50000 → 50.000 (padanan
// RupiahInputFormatter di Android). Hanya bila isinya angka/titik saja —
// singkatan kasir seperti "350rb" atau "1,5jt" (dipahami parseAmount) tidak
// disentuh, kursor dijaga tetap di posisi yang sama secara logis.

export function formatRibuan(digit) {
  const d = String(digit || '').replace(/\D/g, '').replace(/^0+(?=\d)/, '')
  return d.replace(/\B(?=(\d{3})+(?!\d))/g, '.')
}

/** Nilai berformat untuk sebuah string mentah; null bila tak perlu diformat. */
export function formatNilaiInput(raw) {
  const v = String(raw ?? '')
  if (v === '' || !/^[\d.\s]+$/.test(v)) return null
  const hasil = formatRibuan(v)
  return hasil === v ? null : hasil
}

/** Pasang pemformat ke <input>. Mengembalikan fungsi lepas. */
export function pasangFormatRupiah(input) {
  if (!input) return () => {}
  const onInput = () => {
    const sebelum = input.value
    const hasil = formatNilaiInput(sebelum)
    if (hasil == null) return
    // Pertahankan jumlah digit di kiri kursor.
    const kursor = input.selectionStart ?? sebelum.length
    const digitKiri = sebelum.slice(0, kursor).replace(/\D/g, '').length
    input.value = hasil
    let pos = 0
    let terlihat = 0
    while (pos < hasil.length && terlihat < digitKiri) {
      if (hasil[pos] !== '.') terlihat++
      pos++
    }
    try { input.setSelectionRange(pos, pos) } catch { /* input tanpa seleksi */ }
  }
  input.addEventListener('input', onInput)
  return () => input.removeEventListener('input', onInput)
}
