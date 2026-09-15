'use strict'

// Permintaan tulis dengan jalur offline (dipakai ipc.js untuk checkout, pengeluaran,
// stok masuk). Keputusan per jawaban mengikuti kontrak "Klien — perilaku wajib":
//   - diketahui offline                 → antrekan langsung;
//   - sukses                            → kembalikan apa adanya (+ clientRef);
//   - gangguan (jaringan/timeout/5xx/408/429/galat gateway) → antrekan, dikirim ulang
//     otomatis (server menolak duplikat lewat `client_ref`);
//   - 402 langganan diblokir            → kembalikan apa adanya, TIDAK diantrekan
//     (layar "Langganan berakhir" dipicu klien HTTP);
//   - penolakan server lain (4xx)       → kembalikan apa adanya.
// Antrean gagal disimpan ke disk → hasil tetap tertunda (data di memori & terus dicoba),
// tetapi membawa `peringatan` agar kasir tahu jangan menutup aplikasi.

const { adalahGangguan } = require('../lib/klasifikasi-http')

/**
 * @param {object} o
 * @param {object} o.offline      modul offline ({ koneksi, antrean, STATUS, buatClientRef, waktuKlien })
 * @param {(jalur: string, body: object) => Promise<object>} o.kirim  api.post terbungkus (withAuthWatch)
 * @param {() => string|null} o.tokoAktif
 * @param {() => void} [o.setelahAntre]  kirim status offline ke renderer
 */
function buatTulisAtauAntre({ offline, kirim, tokoAktif, setelahAntre = () => {} }) {
  return async function tulisAtauAntre({ jenis, jalur, body, transaksi = null, deltaStok = {} }) {
    const clientRef = offline.buatClientRef()
    const badan = { ...body, client_ref: clientRef, waktu_klien: offline.waktuKlien() }
    if (offline.koneksi.online) {
      const r = await kirim(jalur, badan)
      if (r.ok) return { ...r, clientRef }
      if (!adalahGangguan(r)) return r // ditolak server / langganan: tampilkan apa adanya
    }
    offline.antrean.antrekan({
      clientRef, jenis, tokoId: tokoAktif(), path: jalur, body: badan,
      status: offline.STATUS.MENUNGGU
    }, { transaksi, deltaStok })
    setelahAntre()
    const hasil = { ok: true, status: 202, data: null, meta: null, message: '', tertunda: true, clientRef }
    const masalah = offline.antrean.galatSimpan
    if (masalah) hasil.peringatan = masalah.pesan
    return hasil
  }
}

module.exports = { buatTulisAtauAntre }
