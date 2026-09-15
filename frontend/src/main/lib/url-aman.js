'use strict'

// Validasi URL yang boleh dibuka di peramban sistem / jendela bayar. URL datang dari
// server (perpanjang_url, migrasi.url, wa_link) atau renderer — tetap diperiksa di
// proses utama: hanya https, tanpa kredensial tertanam, host wajib ada.

function urlHttpsAman(nilai) {
  if (typeof nilai !== 'string' || nilai.length === 0 || nilai.length > 2000) return null
  let u
  try {
    u = new URL(nilai)
  } catch {
    return null
  }
  if (u.protocol !== 'https:' || !u.hostname || u.username || u.password) return null
  return u.toString()
}

/**
 * Domain yang dianggap "halaman selesai bayar milik server" — diturunkan dari server
 * yang dipakai aplikasi (bukan domain tertanam). tokosaya.contoh.com → contoh.com.
 */
function domainServer(baseUrl) {
  try {
    const host = new URL(baseUrl).hostname.toLowerCase()
    if (!host || /^[\d.]+$/.test(host) || host === 'localhost') return host || null
    const bagian = host.split('.')
    return bagian.length > 2 ? bagian.slice(1).join('.') : host
  } catch {
    return null
  }
}

/** Host `navUrl` sama dengan / subdomain dari salah satu domain. */
function hostMilik(navUrl, domains) {
  let host
  try { host = new URL(navUrl).hostname.toLowerCase() } catch { return false }
  return domains.filter(Boolean).some((d) => host === d || host.endsWith(`.${d}`))
}

module.exports = { urlHttpsAman, domainServer, hostMilik }
