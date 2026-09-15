'use strict'

// Klien POS API proses utama: merakit inti lib/klien-http.js dengan transport
// Electron (net.fetch) dan versi aplikasi. Logika klasifikasi jawaban (gangguan
// jaringan vs penolakan, 401/402/426) & salinan offline tinggal di inti agar teruji.

const { net, app } = require('electron')
const offline = require('./offline')
const { buatKlienHttp } = require('./lib/klien-http')

// Nilai X-Tuleh-Platform & `platform` laporan diagnostik untuk aplikasi desktop.
const PLATFORM = 'desktop'

// Versi app (satu sumber: package.json via Electron) — header X-Tuleh-Version.
function appVersion() {
  try { return app.getVersion() } catch { return '0.0.0' }
}

const klien = buatKlienHttp({
  fetch: (url, init) => net.fetch(url, init),
  versiApp: appVersion,
  platform: PLATFORM,
  offline,
  // Jalur uji: pura-pura jaringan putus (IPOS_SMOKE_OFFLINE=1).
  pura2Offline: () => process.env.IPOS_SMOKE_OFFLINE === '1'
})

// ---- Masa coba Mode Demo: pendaftaran perangkat & OTP (publik, tanpa Bearer).
// 404 = server belum memasang endpoint → pemanggil jatuh ke lapis lokal.
const demoPerangkatDaftar = (body) => klien.request('POST', '/demo/perangkat', { body, auth: false })
const demoPerangkatStatus = (perangkatId) => klien.request('GET', `/demo/perangkat/${encodeURIComponent(perangkatId)}`, { auth: false })
const demoOtpKirim = (body) => klien.request('POST', '/demo/otp/kirim', { body, auth: false })
const demoOtpVerifikasi = (body) => klien.request('POST', '/demo/otp/verifikasi', { body, auth: false })

module.exports = {
  ...klien,
  PLATFORM,
  appVersion,
  demoPerangkatDaftar,
  demoPerangkatStatus,
  demoOtpKirim,
  demoOtpVerifikasi
}
