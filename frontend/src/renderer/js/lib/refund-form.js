// Formulir refund di Riwayat (desktop & Android Capacitor memakai renderer yang sama):
// baris yang masih bisa direfund, validasi sebelum ke server, dan perkiraan dana kembali.
// Murni (tanpa DOM/state) agar bisa diuji; nilai PASTI (diskon transaksi & pajak) dihitung server.

import { apakahTerukur, langkahSatuan } from './satuan-terukur.js'

/** Baris struk yang masih punya sisa refund, dengan langkah input sesuai satuannya. */
export function barisRefund(struk) {
  return (struk?.items || [])
    .filter((it) => Number(it.qty_bisa_refund) > 0)
    .map((it) => {
      const terjual = Number(it.kuantitas) || 0
      return {
        id: it.id,
        nama: it.nama,
        satuan: it.satuan || '',
        sisa: Number(it.qty_bisa_refund),
        terjual,
        langkah: apakahTerukur(it.satuan) ? langkahSatuan(it.satuan) : 1,
        // Nilai yang dibayar per unit (subtotal baris / qty) — untuk perkiraan di layar.
        nilaiPerUnit: terjual > 0 ? (Number(it.subtotal) || 0) / terjual : 0
      }
    })
}

/** Transaksi masih bisa direfund: tidak dibatalkan, sudah tersinkron, dan ada sisa baris. */
export function bisaDirefund(struk) {
  if (!struk || String(struk.status || '').toUpperCase() === 'DIBATALKAN') return false
  if (struk.belum_sinkron || String(struk.id || '').startsWith('lokal:')) return false
  return barisRefund(struk).length > 0
}

/** Perkiraan dana kembali dari qty terpilih ({ [id baris]: qty }). */
export function perkiraanRefund(struk, qty) {
  return barisRefund(struk).reduce((s, b) => s + (Number(qty?.[b.id]) || 0) * b.nilaiPerUnit, 0)
}

/**
 * Validasi isian → payload kanal trx:refund. Melempar Error berpesan Indonesia
 * (ditampilkan apa adanya di toast) bila isian tidak lengkap.
 */
export function susunPermintaanRefund(struk, { qty = {}, metode, alasan, kembaliStok = true } = {}) {
  const baris = []
  for (const b of barisRefund(struk)) {
    const n = Number(qty[b.id]) || 0
    if (n <= 0) continue
    if (n > b.sisa + 1e-9) throw new Error(`Jumlah refund ${b.nama} melebihi sisa (${b.sisa}).`)
    baris.push({ id: b.id, kuantitas: n })
  }
  if (baris.length === 0) throw new Error('Pilih minimal satu item yang direfund.')
  const alasanBersih = String(alasan || '').trim()
  if (alasanBersih.length < 3) throw new Error('Alasan refund minimal 3 karakter.')
  if (!metode) throw new Error('Metode pengembalian dana wajib dipilih.')
  return { id: struk.id, baris, metode, alasan: alasanBersih, kembaliStok: !!kembaliStok }
}
