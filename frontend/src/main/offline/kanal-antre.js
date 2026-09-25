'use strict'

// Aturan proses utama untuk kanal tulis yang boleh diantrekan (Fase 4) — murni agar bisa diuji tanpa Electron:
//  - daftar kanal antre DITURUNKAN dari field `antrean` kontrak bersama (bukan daftar tangan);
//  - refund/pembatalan atas transaksi LOKAL (id "lokal:<ref>") selalu langsung diantrekan, dengan penjaga
//    pemilik, induk ditinjau, dan satu tindakan tertunda per transaksi lokal; bila induknya sudah terkirim,
//    rujukan diganti id server dan dikirim seperti biasa;
//  - tutup sesi sendiri ditahan selama antrean akun ini untuk toko itu belum kosong (paritas Flutter);
//  - baris untuk panel Sinkronisasi tanpa token persetujuan.

const { STATUS, refIndukLokal, labelJenis } = require('./antrean')
const { gantiRujukanLokal, labelKode, labelPeringatan } = require('./operasi-batch')

const JENIS_BOLEH_LOKAL = new Set(['REFUND', 'BATAL'])

function daftarKanalAntre(KANAL) {
  return Object.keys(KANAL).filter((k) => KANAL[k] && KANAL[k].antrean && KANAL[k].antrean.jenis)
}

/**
 * Putusan satu permintaan kanal antre (`pemilik` undefined = akun belum diketahui → penjaga pemilik dilewati).
 * @returns {{tolak: string} | {jalur: string, body: object, langsungAntre: boolean}}
 */
function putuskanTulisAntre({ jenis, jalur, body, antrean, pemilik }) {
  const induk = refIndukLokal(jalur)
  if (!induk) {
    if (/\/lokal(:|%3A)/i.test(String(jalur))) return { tolak: 'Data ini belum tersinkron — tindakan ini baru bisa dilakukan setelah tersinkron.' }
    return { jalur, body, langsungAntre: false }
  }
  if (!JENIS_BOLEH_LOKAL.has(jenis)) return { tolak: 'Transaksi ini belum tersinkron — tindakan ini baru bisa dilakukan setelah tersinkron.' }
  const q = antrean.cari(induk)
  if (!q) return { tolak: 'Transaksi lokal tidak ditemukan (mungkin sudah terkirim). Muat ulang Riwayat lalu ulangi dari transaksi resminya.' }
  if (pemilik !== undefined && q.pemilik !== pemilik) {
    return { tolak: 'Transaksi ini dibuat akun lain dan belum terkirim — hanya akun itu yang bisa membatalkan atau merefundnya.' }
  }
  if (q.status === STATUS.TINJAU) return { tolak: 'Transaksi asal perlu ditinjau dulu (Pengaturan → Sinkronisasi).' }
  if (q.status === STATUS.TERKIRIM) {
    const ganti = gantiRujukanLokal({ path: jalur, body }, q)
    if (!ganti) return { tolak: 'Transaksi sudah tersinkron — muat ulang Riwayat lalu ulangi dari transaksi resminya.' }
    return { jalur: ganti.path, body: ganti.body, langsungAntre: false }
  }
  // Satu tindakan tertunda per transaksi lokal: refund kedua / batal setelah refund pasti bentrok di server.
  // Baris ber-client_ref SAMA = tombol yang sama diulang → bukan tindakan kedua (penulis antrean menjawab tertunda).
  const ref = body && typeof body.client_ref === 'string' && body.client_ref ? body.client_ref : null
  const tertunda = antrean.semua().find((x) => x.status !== STATUS.TERKIRIM && JENIS_BOLEH_LOKAL.has(x.jenis) && refIndukLokal(x.path) === induk && (ref === null || x.clientRef !== ref))
  if (tertunda) {
    return { tolak: tertunda.jenis === 'BATAL' ? 'Transaksi ini sudah menunggu dibatalkan.' : 'Transaksi ini masih punya refund yang menunggu dikirim.' }
  }
  return { jalur, body, langsungAntre: true }
}

/** Pesan penolakan tutup sesi sendiri, atau null bila antrean akun ini untuk toko itu sudah kosong. */
function pesanTahanTutupSesi(antrean, { tokoId = null, pemilik } = {}) {
  const n = antrean.ringkas(tokoId, pemilik).total
  if (n <= 0) return null
  return `${n} data belum terkirim ke server (transaksi, pembayaran, atau pembatalan). Sambungkan internet, buka Pengaturan → Sinkronisasi, dan tunggu sampai kosong sebelum menutup sesi.`
}

/** Baris antrean untuk renderer: label siap tampil, tanpa token persetujuan (berkas antrean tetap utuh). */
function barisUntukTampilan(p, pemilik) {
  const body = p.body && typeof p.body === 'object' ? { ...p.body } : p.body
  if (body && typeof body === 'object') delete body.otorisasi_token
  return {
    ...p,
    body,
    label: labelJenis(p.jenis),
    labelKode: p.kode ? labelKode(p.kode) : null,
    labelPeringatan: labelPeringatan(p.hasil && p.hasil.peringatan),
    milikLain: pemilik !== undefined && p.pemilik !== pemilik
  }
}

module.exports = { daftarKanalAntre, putuskanTulisAntre, pesanTahanTutupSesi, barisUntukTampilan }
