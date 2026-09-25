'use strict'

// Permintaan tulis dengan jalur offline (dipakai ipc.js untuk semua kanal kontrak ber-`antrean`
// dan checkout). Keputusan per jawaban mengikuti kontrak "Klien — perilaku wajib":
//   - client_ref masih di antrean (belum terkirim) → tertunda lagi, tanpa kirim & tanpa baris kedua
//     (baris ditinjau → `perluTinjau`);
//   - client_ref sudah TERKIRIM lewat antrean + offline/gangguan → hasil tersimpan (`dariAntrean`), tanpa baris baru;
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
 * `data` dari hasil baris TERKIRIM: hasil batch ({id, nomor, kode, tipe, idempoten, data, …}) → `data` item
 * + id/nomor item (bentuk sama dengan respons online, mis. refund {id, nomor, total, transaksi_id,
 * transaksi_nomor}; id/nomor item kosong → milik `data` bila ada); hasil pemulih ({id, nomor, dipulihkan})
 * → {id, nomor}; hasil per baris = data server mentah (tanpa penanda internal `_idempoten`).
 */
function dataHasilTersimpan(h) {
  if (!h || typeof h !== 'object') return null
  const bentukBatch = 'kode' in h && 'tipe' in h && 'idempoten' in h
  if (bentukBatch) {
    const d = h.data && typeof h.data === 'object' && !Array.isArray(h.data) ? h.data : {}
    return { ...d, id: h.id ?? d.id ?? null, nomor: h.nomor ?? d.nomor ?? null }
  }
  if (h.dipulihkan === true) return { id: h.id ?? null, nomor: h.nomor ?? null }
  const { _idempoten, ...data } = h
  return data
}

/**
 * @param {object} o
 * @param {object} o.offline      modul offline ({ koneksi, antrean, STATUS, buatClientRef, waktuKlien })
 * @param {(jalur: string, body: object, pesan: {tokoId: string|null}) => Promise<object>} o.kirim  api.post
 *        terbungkus (withAuthWatch); kirim atas nama `pesan.tokoId` (toko saat operasi dimulai), bukan toko aktif
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
   * @param {(badan: object, clientRef: string, ctx: {tokoId: string|null}) => ({body?: object, transaksi?: object}|void)} [o.siapkanAntre]
   *        tambahan HANYA untuk baris yang benar-benar diantrekan (checkout: offline:true, nomor & struk lokal);
   *        `ctx.tokoId` = toko baris ini (pakai untuk transaksi lokal, bukan toko aktif saat itu)
   */
  return async function tulisAtauAntre({ jenis, jalur, body, transaksi = null, deltaStok = {}, langsungAntre = false, siapkanAntre = null }) {
    // client_ref pemanggil dipertahankan (refund: satu ref per lembar — tombol diulang setelah timeout =
    // refund yang sama); tanpa itu dibuat baru. waktu_klien pemanggil juga dipertahankan.
    const clientRef = teks(body && body.client_ref) || offline.buatClientRef()
    // Ref yang sama masih di antrean (tombol diulang selagi barisnya menunggu/ditinjau) → operasi yang SAMA:
    // jangan coba online (server bisa mencatatnya lalu baris antre dikirim lagi) dan jangan antrekan baris kedua.
    const ada = offline.antrean.cari(clientRef)
    if (ada && ada.status !== offline.STATUS.TERKIRIM) {
      const r = { ok: true, status: 202, data: null, meta: null, message: '', tertunda: true, clientRef }
      if (ada.status === offline.STATUS.TINJAU) r.perluTinjau = true
      return r
    }
    const badan = { ...body, client_ref: clientRef, waktu_klien: teks(body && body.waktu_klien) || offline.waktuKlien() }
    // Pemilik & toko dibaca SEKALI, sebelum mencoba online: kasir bisa keluar (auth:logout → akun dilupakan),
    // akun lain masuk, atau pindah toko selagi permintaan menggantung lalu timeout — baris tetap milik akun &
    // toko saat operasi dimulai (sama dengan kiriman online-nya), tidak dikirim dengan token akun berikutnya
    // dan penjualan/refund tidak jatuh ke toko lain.
    let pemilik = null
    try { pemilik = pemilikAktif() || null } catch { pemilik = null }
    const toko = tokoAktif() || null
    if (!langsungAntre && offline.koneksi.online) {
      const r = await kirim(jalur, badan, { tokoId: toko })
      if (r.ok) return { ...r, clientRef }
      if (!adalahGangguan(r)) return r // ditolak server / langganan: tampilkan apa adanya
    }
    // Operasi ini SUDAH tercatat server lewat antrean (ref sama TERKIRIM) dan server kini tak terjangkau:
    // kembalikan hasil tersimpan — mengantrekan lagi = baris kembar berkunci sama.
    if (ada && ada.status === offline.STATUS.TERKIRIM) {
      return { ok: true, status: 200, data: dataHasilTersimpan(ada.hasil), meta: null, message: '', clientRef, dariAntrean: true }
    }
    let badanAntre = badan
    let transaksiAntre = transaksi
    if (typeof siapkanAntre === 'function') {
      // Galat penyiapan (nomor/struk lokal) tidak boleh menghilangkan operasi: antrekan dengan badan dasar.
      try {
        const s = siapkanAntre(badan, clientRef, { tokoId: toko }) || {}
        if (s.body) badanAntre = s.body
        if (s.transaksi) transaksiAntre = s.transaksi
      } catch (err) {
        badanAntre = badan
        transaksiAntre = transaksi
        lapor(`Penyiapan baris antrean ${jenis} gagal (${err && err.message ? err.message : String(err)}); diantrekan dengan badan dasar.`, err)
      }
    }
    offline.antrean.antrekan({
      clientRef, jenis, tokoId: toko, path: jalur, body: badanAntre,
      status: offline.STATUS.MENUNGGU, pemilik
    }, { transaksi: transaksiAntre, deltaStok })
    setelahAntre()
    const hasil = { ok: true, status: 202, data: null, meta: null, message: '', tertunda: true, clientRef }
    const masalah = offline.antrean.galatSimpan
    if (masalah) hasil.peringatan = masalah.pesan
    return hasil
  }
}

module.exports = { buatTulisAtauAntre, dataHasilTersimpan }
