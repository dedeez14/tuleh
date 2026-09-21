// Formulir refund di Riwayat (desktop & Android Capacitor memakai renderer yang sama):
// baris yang masih bisa direfund, validasi sebelum ke server, dan perkiraan dana kembali.
// Murni (tanpa DOM/state) agar bisa diuji; nilai PASTI (diskon transaksi & pajak) dihitung server.

import { apakahTerukur, langkahSatuan, bulatkanKuantitas, labelKuantitas } from './satuan-terukur.js'

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
        terukur: apakahTerukur(it.satuan),
        langkah: apakahTerukur(it.satuan) ? langkahSatuan(it.satuan) : 1,
        // Nilai yang dibayar per unit (subtotal baris / qty) — untuk perkiraan di layar.
        nilaiPerUnit: terjual > 0 ? (Number(it.subtotal) || 0) / terjual : 0
      }
    })
}

/** Status transaksi yang uangnya sudah diterima — hanya ini yang bisa dikembalikan. */
const STATUS_BISA_REFUND = ['SELESAI', 'LUNAS']

/** Transaksi masih bisa direfund: sudah dibayar & tersinkron, dan ada sisa baris. */
export function bisaDirefund(struk) {
  if (!struk || !STATUS_BISA_REFUND.includes(String(struk.status || '').toUpperCase())) return false
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
 *
 * Kuantitas ikut langkah satuannya (paritas dengan app Android): barang
 * hitungan (tidak terukur, mis. cup) wajib bilangan bulat; barang terukur
 * (mis. kg, gram, ml — lihat `apakahTerukur`) dibulatkan ke kelipatan
 * langkah satuannya (bisa < 1 seperti kg, atau > 1 seperti gram/ml) sebelum
 * diperiksa terhadap sisa dan dikirim ke server.
 */
export function susunPermintaanRefund(struk, { qty = {}, metode, alasan, kembaliStok = true } = {}) {
  const baris = []
  for (const b of barisRefund(struk)) {
    let n = Number(qty[b.id]) || 0
    if (n <= 0) continue
    if (b.terukur) {
      n = bulatkanKuantitas(n, b.satuan)
      if (n <= 0) continue
    } else {
      if (!Number.isInteger(n)) throw new Error(`Jumlah refund ${b.nama} harus bilangan bulat.`)
    }
    if (n > b.sisa + 1e-9) throw new Error(`Jumlah refund ${b.nama} melebihi sisa (${labelKuantitas(b.sisa, b.satuan)}).`)
    baris.push({ id: b.id, kuantitas: n })
  }
  if (baris.length === 0) throw new Error('Pilih minimal satu item yang direfund.')
  const alasanBersih = String(alasan || '').trim()
  if (alasanBersih.length < 3) throw new Error('Alasan refund minimal 3 karakter.')
  if (!metode) throw new Error('Metode pengembalian dana wajib dipilih.')
  return { id: struk.id, baris, metode, alasan: alasanBersih, kembaliStok: !!kembaliStok }
}
