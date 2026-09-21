'use strict'

// Klasifikasi jawaban HTTP untuk aplikasi (kontrak "Klien — perilaku wajib",
// spesifikasi kesiapan produksi 2026-09-15). SATU tempat yang memutuskan apakah
// sebuah jawaban adalah penolakan server atau gangguan jaringan — dipakai klien
// HTTP (salinan baca + penanda offline), penulis antrean, dan pengurai.
//
//   GANGGUAN  : 5xx / 408 / 429 dari server, atau galat yang dibuat gateway lokal
//               (502/503/504 ber-header X-Tuleh-Gateway) → perlakukan seperti
//               jaringan putus: tandai offline, GET dari salinan, tulis diantrekan,
//               antrean dicoba ulang dengan mundur (bukan "perlu ditinjau").
//               KECUALI 429 yang membawa `errors` — lihat penolakanDomain() di bawah.
//   LANGGANAN : 402 → layar "Langganan berakhir"; TIDAK diantrekan.
//   SESI      : 401 → alur sesi berakhir (kembali ke login).
//   UPDATE    : 426 → layar update wajib.
//   TOLAK     : 4xx lain → penolakan server, ditampilkan apa adanya.

const JENIS = Object.freeze({
  SUKSES: 'SUKSES',
  GANGGUAN: 'GANGGUAN',
  LANGGANAN: 'LANGGANAN',
  SESI: 'SESI',
  UPDATE: 'UPDATE',
  TOLAK: 'TOLAK'
})

const HEADER_GATEWAY = 'x-tuleh-gateway'

// Penanda galat buatan gateway yang berarti "server tidak terjangkau" (lihat backend/proxy.go).
const PENANDA_GATEWAY_GANGGUAN = new Set(['upstream-unreachable', 'rate-limited', 'internal'])

function ambilHeader(headers, nama) {
  if (!headers) return null
  if (typeof headers.get === 'function') return headers.get(nama)
  const kunci = Object.keys(headers).find((k) => k.toLowerCase() === nama)
  return kunci ? headers[kunci] : null
}

/** Penanda galat buatan gateway lokal (null bila jawaban berasal dari server). */
function penandaGateway(headers) {
  const v = ambilHeader(headers, HEADER_GATEWAY)
  return v ? String(v).trim().toLowerCase() : null
}

/**
 * 429 yang dijawab server dengan `errors` terisi adalah penolakan DOMAIN, bukan rem lalu lintas:
 * kunci PIN persetujuan (`errors.kode = ['PIN_TERKUNCI']`, `data.terkunci_detik` untuk hitung
 * mundur) memakai 429 karena itu memang "terlalu banyak percobaan". Diperlakukan sebagai
 * gangguan, satu PIN salah akan menandai SELURUH aplikasi offline, mengantrekan ulang permintaan
 * yang server sudah tolak dengan sadar, dan membuang `data` dari amplopnya. 429 polos (rem gateway
 * atau throttle Laravel tanpa badan) tetap gangguan.
 */
function penolakanDomain(status, payload) {
  if (status !== 429) return false
  const e = payload && payload.errors
  return !!e && typeof e === 'object' && Object.keys(e).length > 0
}

/**
 * @param {number} status  kode HTTP (0 = tidak ada jawaban sama sekali)
 * @param {object} [headers]  Headers fetch atau objek biasa
 * @param {object|null} [payload]  badan JSON ter-parse (amplop {success,...})
 */
function klasifikasi(status, headers = null, payload = null) {
  const s = Number(status) || 0
  if (s === 0) return JENIS.GANGGUAN
  const gw = penandaGateway(headers)
  if (gw && PENANDA_GATEWAY_GANGGUAN.has(gw)) return JENIS.GANGGUAN
  if (penolakanDomain(s, payload)) return JENIS.TOLAK
  if (s >= 500 || s === 408 || s === 429) return JENIS.GANGGUAN
  if (s === 402) return JENIS.LANGGANAN
  if (s === 401) return JENIS.SESI
  if (s === 426) return JENIS.UPDATE
  if (s >= 200 && s < 300 && !(payload && payload.success === false)) return JENIS.SUKSES
  return JENIS.TOLAK
}

/** Amplop gagal dianggap gangguan jaringan (boleh diantrekan & dicoba ulang). */
function adalahGangguan(res) {
  if (!res || res.ok) return false
  if (res.gangguan === true) return true
  return res.status === 0 || res.status === -1
}

/**
 * Sifat gangguan untuk pengurai antrean (null bila bukan gangguan):
 *   'JARINGAN' — server tak terjangkau / dibatasi (status 0, gateway upstream-unreachable
 *                atau rate-limited, 429): semua kiriman akan gagal sama → hentikan putaran.
 *   'SERVER'   — server menjawab 5xx/408 untuk permintaan INI (mis. bug pada satu muatan):
 *                mundur per baris & lanjut ke baris lain; dihitung menuju batas tinjau.
 *   'TIMEOUT'  — tak ada jawaban dalam batas waktu (-1): mundur per baris, tidak dihitung
 *                sebagai galat server (tak ada pesan server).
 */
function jenisGangguan(res) {
  if (!adalahGangguan(res)) return null
  const s = Number(res.status) || 0
  if (s === -1 || res.timeout === true) return 'TIMEOUT'
  if (s === 0 || s === 429 || res.gateway === 'upstream-unreachable' || res.gateway === 'rate-limited') return 'JARINGAN'
  return 'SERVER'
}

/** Info langganan dari amplop 402 (kontrak #2): { pesan, status, perpanjangUrl }. */
function infoLangganan(payload) {
  const meta = payload && payload.meta && typeof payload.meta === 'object' ? payload.meta : {}
  const l = meta.langganan && typeof meta.langganan === 'object' ? meta.langganan : {}
  return {
    pesan: payload && typeof payload.message === 'string' ? payload.message : '',
    status: typeof l.status === 'string' ? l.status : null,
    perpanjangUrl: typeof l.perpanjang_url === 'string' && l.perpanjang_url ? l.perpanjang_url : null
  }
}

module.exports = { JENIS, klasifikasi, adalahGangguan, jenisGangguan, penandaGateway, penolakanDomain, infoLangganan, HEADER_GATEWAY }
