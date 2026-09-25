'use strict'

// Permintaan tulis dengan jalur offline (dipakai ipc.js untuk semua kanal kontrak ber-`antrean`
// dan checkout). Keputusan per jawaban mengikuti kontrak "Klien — perilaku wajib":
//   - client_ref masih di antrean (belum terkirim) → tertunda lagi, tanpa kirim & tanpa baris kedua;
//   - diketahui offline / `langsungAntre` → antrekan langsung;
//   - sukses                            → kembalikan apa adanya (+ clientRef);
//   - gangguan (jaringan/timeout/5xx/408/429/galat gateway) → antrekan, dikirim ulang
//     otomatis (server menolak duplikat lewat `client_ref`);
//   - 402 langganan diblokir            → kembalikan apa adanya, TIDAK diantrekan
//     (layar "Langganan berakhir" dipicu klien HTTP);
//   - penolakan server lain (4xx)       → kembalikan apa adanya.
// Antrean gagal disimpan ke disk → hasil tetap tertunda (data di memori & terus dicoba),
// tetapi membawa `peringatan` agar kasir tahu jangan menutup aplikasi.

const { adalahGangguan } = require('../lib/klasifikasi-http')

const teks = (v) => (typeof v === 'string' && v ? v : null)

/**
 * @param {object} o
 * @param {object} o.offline      modul offline ({ koneksi, antrean, STATUS, buatClientRef, waktuKlien })
 * @param {(jalur: string, body: object) => Promise<object>} o.kirim  api.post terbungkus (withAuthWatch)
 * @param {() => string|null} o.tokoAktif
 * @param {() => string|null} [o.pemilikAktif]  kunci pemilik akun aktif (baris hanya dikirim akun pembuatnya)
 * @param {() => void} [o.setelahAntre]  kirim status offline ke renderer
 * @param {(pesan: string, err: Error) => void} [o.laporGalat]  galat penyiapan baris antre (bawaan console.error)
 */
function buatTulisAtauAntre({ offline, kirim, tokoAktif, pemilikAktif = () => null, setelahAntre = () => {}, laporGalat = null }) {
  const lapor = (pesan, err) => {
    try {
      if (typeof laporGalat === 'function') laporGalat(pesan, err)
      else console.error('[antrean-offline]', pesan)
    } catch { /* abaikan */ }
  }

  /**
   * @param {object} o
   * @param {boolean} [o.langsungAntre]  jangan coba kirim (rujukan transaksi lokal yang server belum kenal)
   * @param {(badan: object, clientRef: string) => ({body?: object, transaksi?: object}|void)} [o.siapkanAntre]
   *        tambahan HANYA untuk baris yang benar-benar diantrekan (checkout: offline:true, nomor & struk lokal)
   */
  return async function tulisAtauAntre({ jenis, jalur, body, transaksi = null, deltaStok = {}, langsungAntre = false, siapkanAntre = null }) {
    // client_ref pemanggil dipertahankan (refund: satu ref per lembar — tombol diulang setelah timeout =
    // refund yang sama); tanpa itu dibuat baru. waktu_klien pemanggil juga dipertahankan.
    const clientRef = teks(body && body.client_ref) || offline.buatClientRef()
    // Ref yang sama masih di antrean (tombol diulang selagi barisnya menunggu/ditinjau) → operasi yang SAMA:
    // jangan coba online (server bisa mencatatnya lalu baris antre dikirim lagi) dan jangan antrekan baris kedua.
    const ada = offline.antrean.cari(clientRef)
    if (ada && ada.status !== offline.STATUS.TERKIRIM) {
      return { ok: true, status: 202, data: null, meta: null, message: '', tertunda: true, clientRef }
    }
    const badan = { ...body, client_ref: clientRef, waktu_klien: teks(body && body.waktu_klien) || offline.waktuKlien() }
    if (!langsungAntre && offline.koneksi.online) {
      const r = await kirim(jalur, badan)
      if (r.ok) return { ...r, clientRef }
      if (!adalahGangguan(r)) return r // ditolak server / langganan: tampilkan apa adanya
    }
    let badanAntre = badan
    let transaksiAntre = transaksi
    if (typeof siapkanAntre === 'function') {
      // Galat penyiapan (nomor/struk lokal) tidak boleh menghilangkan operasi: antrekan dengan badan dasar.
      try {
        const s = siapkanAntre(badan, clientRef) || {}
        if (s.body) badanAntre = s.body
        if (s.transaksi) transaksiAntre = s.transaksi
      } catch (err) {
        badanAntre = badan
        transaksiAntre = transaksi
        lapor(`Penyiapan baris antrean ${jenis} gagal (${err && err.message ? err.message : String(err)}); diantrekan dengan badan dasar.`, err)
      }
    }
    let pemilik = null
    try { pemilik = pemilikAktif() || null } catch { pemilik = null }
    offline.antrean.antrekan({
      clientRef, jenis, tokoId: tokoAktif(), path: jalur, body: badanAntre,
      status: offline.STATUS.MENUNGGU, pemilik
    }, { transaksi: transaksiAntre, deltaStok })
    setelahAntre()
    const hasil = { ok: true, status: 202, data: null, meta: null, message: '', tertunda: true, clientRef }
    const masalah = offline.antrean.galatSimpan
    if (masalah) hasil.peringatan = masalah.pesan
    return hasil
  }
}

module.exports = { buatTulisAtauAntre }
