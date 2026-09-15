'use strict'

// Penyamaran rahasia sebelum teks menyentuh log berkas atau laporan diagnostik.
// Kontrak #1: klien TIDAK boleh mengirim token, PIN, atau kata sandi. Lebih baik
// menyamarkan terlalu banyak daripada membocorkan satu token.

const TANDA = '[DISAMARKAN]'

// Nama kunci yang nilainya selalu rahasia (JSON, objek JS, query string, form).
const KUNCI_RAHASIA = [
  'token', 'access_token', 'refresh_token', 'identitas_token', 'bearer',
  'password', 'kata_sandi', 'sandi', 'pass',
  'pin', 'pin_baru', 'pin_lama', 'pin_konfirmasi',
  'server_key', 'client_key', 'serverkey', 'clientkey', 'api_key', 'apikey', 'secret', 'otp', 'kode_otp'
]
const POLA_KUNCI = KUNCI_RAHASIA.join('|')

const ATURAN = [
  // Header Authorization utuh (baris log permintaan)
  [/(authorization)\s*[:=]\s*[^\r\n,}]+/gi, `$1: ${TANDA}`],
  // Bearer <token>
  [/\bBearer\s+[A-Za-z0-9\-._~+/|]+=*/gi, `Bearer ${TANDA}`],
  // Token Sanctum "<id>|<40+ karakter>"
  [/\b\d+\|[A-Za-z0-9]{20,}\b/g, TANDA],
  // JWT
  [/\beyJ[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}\b/g, TANDA],
  // Kunci Midtrans
  [/\b(?:SB-)?Mid-(?:server|client)-[A-Za-z0-9_-]+/g, TANDA],
  // "kunci": "nilai" (JSON) — termasuk nilai angka
  [new RegExp(`("(?:${POLA_KUNCI})"\\s*:\\s*)("(?:[^"\\\\]|\\\\.)*"|-?\\d+)`, 'gi'), `$1"${TANDA}"`],
  // kunci: 'nilai' / kunci = "nilai" (objek JS / log bebas)
  [new RegExp(`\\b((?:${POLA_KUNCI})\\s*[:=]\\s*)(['"])[^'"]*\\2`, 'gi'), `$1$2${TANDA}$2`],
  // ?kunci=nilai&… (query string / form)
  [new RegExp(`([?&\\s](?:${POLA_KUNCI})=)[^&\\s"']+`, 'gi'), `$1${TANDA}`]
]

function samarkan(teks) {
  if (teks === null || teks === undefined) return ''
  let s = String(teks)
  for (const [pola, ganti] of ATURAN) s = s.replace(pola, ganti)
  return s
}

/** Samarkan rekursif objek (untuk `konteks` laporan): nilai berkunci rahasia dibuang. */
function samarkanObjek(nilai, kedalaman = 0) {
  if (kedalaman > 6) return TANDA
  if (typeof nilai === 'string') return samarkan(nilai)
  if (Array.isArray(nilai)) return nilai.map((v) => samarkanObjek(v, kedalaman + 1))
  if (nilai && typeof nilai === 'object') {
    const out = {}
    const rahasia = new RegExp(`^(?:${POLA_KUNCI}|authorization)$`, 'i')
    for (const [k, v] of Object.entries(nilai)) out[k] = rahasia.test(k) ? TANDA : samarkanObjek(v, kedalaman + 1)
    return out
  }
  return nilai
}

module.exports = { samarkan, samarkanObjek, TANDA }
