// Logika layar Jadwal (gym/klinik): navigasi hari, label kuota, validasi formulir slot.
// Murni — tanpa DOM, tanpa jaringan — agar bisa diuji dan dipakai apa adanya di
// desktop maupun Android Capacitor. Nilai pasti (sisa kuota) tetap datang dari server.

const HARI = ['Minggu', 'Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu']
const BULAN = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des']

/** Tanggal lokal hari ini sebagai 'YYYY-MM-DD' (bukan toISOString — itu UTC). */
export function hariIni(d = new Date()) {
  const p = (n) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`
}

/** Geser tanggal 'YYYY-MM-DD' sebanyak n hari — lewat UTC agar bebas DST. */
export function geserTanggal(iso, n) {
  const d = new Date(`${iso}T00:00:00Z`)
  d.setUTCDate(d.getUTCDate() + Number(n || 0))
  return d.toISOString().slice(0, 10)
}

/** 'Hari ini · Senin, 21 Sep 2026' */
export function labelTanggal(iso, acuan = hariIni()) {
  const d = new Date(`${iso}T00:00:00Z`)
  const tanggal = `${HARI[d.getUTCDay()]}, ${d.getUTCDate()} ${BULAN[d.getUTCMonth()]} ${d.getUTCFullYear()}`
  const relatif = iso === acuan
    ? 'Hari ini'
    : iso === geserTanggal(acuan, 1) ? 'Besok' : iso === geserTanggal(acuan, -1) ? 'Kemarin' : ''
  return relatif ? `${relatif} · ${tanggal}` : tanggal
}

/** Slot tanpa kuota tidak pernah penuh. */
export function slotPenuh(slot) {
  return slot?.kuota !== null && slot?.kuota !== undefined && Number(slot.sisa_kuota) <= 0
}

export function labelKuota(slot) {
  const terpakai = Number(slot?.peserta_count) || 0
  if (slot?.kuota === null || slot?.kuota === undefined) return `${terpakai} peserta · tanpa batas`
  return `${terpakai} / ${slot.kuota} peserta${slotPenuh(slot) ? ' · penuh' : ''}`
}

/** Jam mulai → nama; slot BATAL selalu di bawah (tidak menghalangi kelas yang berjalan). */
export function urutSlot(rows) {
  return [...(rows || [])].sort((a, b) => {
    const batal = (r) => (String(r.status || '').toUpperCase() === 'BATAL' ? 1 : 0)
    return batal(a) - batal(b) ||
      String(a.jam_mulai || '').localeCompare(String(b.jam_mulai || '')) ||
      String(a.nama || '').localeCompare(String(b.nama || ''), 'id')
  })
}

/**
 * Validasi isian formulir → payload kanal `jadwal:simpan`/`jadwal:ubah`.
 * Melempar Error berpesan Indonesia (ditampilkan apa adanya di toast/field).
 */
export function susunSlot({ nama, tanggal, jamMulai, jamSelesai, kuota, pengajar, catatan } = {}) {
  const teks = (v) => String(v ?? '').trim()
  if (!teks(nama)) throw new Error('Nama jadwal wajib diisi.')
  if (!teks(tanggal)) throw new Error('Tanggal wajib diisi.')
  if (!teks(jamMulai)) throw new Error('Jam mulai wajib diisi.')
  if (teks(jamSelesai) && teks(jamSelesai) <= teks(jamMulai)) throw new Error('Jam selesai harus setelah jam mulai.')
  const angka = teks(kuota) === '' ? null : Number(kuota)
  if (angka !== null && (!Number.isFinite(angka) || angka < 1)) throw new Error('Kuota minimal 1 peserta — kosongkan bila tanpa batas.')
  return {
    nama: teks(nama),
    tanggal: teks(tanggal),
    jamMulai: teks(jamMulai),
    jamSelesai: teks(jamSelesai),
    kuota: angka,
    pengajar: teks(pengajar),
    catatan: teks(catatan)
  }
}
