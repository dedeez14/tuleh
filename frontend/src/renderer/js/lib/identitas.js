// Identitas sesi (hak akses, peran, perusahaan, sesi kasir, versi manifest) ikut berubah saat app
// terbuka: pemilik mencabut hak dari ERP, manajer menutup sesi kasir dari perangkat lain, menu toko
// diubah. /auth/me tidak ber-ETag, jadi app memanggilnya ulang saat kembali ke depan dengan throttle
// agar berpindah jendela bolak-balik tidak membanjiri server. Fungsi di sini murni (diuji), efeknya
// dijalankan app.js.

import { cocokkanToko } from './toko-cocok.js'

export const JEDA_IDENTITAS_MS = 60000
// Jalur `paksa` (sesudah 403) punya jeda sendiri: layar yang polling — papan pesanan 4 dtk,
// Inventory 10 dtk — akan kena 403 setiap kali bila haknya dicabut, dan tanpa jeda ini setiap
// penolakan memanggil /auth/me lagi. Harus lebih panjang dari polling tercepat.
export const JEDA_PAKSA_MS = 30000

export function perluMuatUlang(terakhirMs, sekarangMs, {
  jeda = JEDA_IDENTITAS_MS, paksa = false, terakhirPaksaMs = 0, jedaPaksa = JEDA_PAKSA_MS
} = {}) {
  const now = Number(sekarangMs) || 0
  if (paksa) {
    const paksaTerakhir = Number(terakhirPaksaMs) || 0
    return paksaTerakhir <= 0 || now - paksaTerakhir >= jedaPaksa
  }
  const terakhir = Number(terakhirMs) || 0
  if (terakhir <= 0) return true // belum pernah dimuat (mis. sesudah keluar akun)
  return now - terakhir >= jeda
}

/** Patch state dari jawaban /auth/me. `akses` bukan array = tanpa hak (gagal-tertutup). */
export function patchIdentitas(me) {
  const sesi = (me && me.sesi_aktif) || null
  return {
    user: (me && me.user) || null,
    akses: Array.isArray(me && me.akses) ? me.akses : null,
    peran: (me && me.peran) || null,
    company: (me && me.company) || null,
    branch: (me && me.branch) || null,
    session: sesi,
    sessionId: sesi && sesi.id ? sesi.id : null
  }
}

/** Sidik jari daftar hak: urutan dari server tidak dijamin, jadi diurutkan dulu.
 *  `null` (belum dimuat / respons rusak) sengaja berbeda dari `[]` (tanpa hak sama sekali). */
export function kunciAkses(akses) {
  return Array.isArray(akses) ? [...akses].map(String).sort().join('|') : '\u0000belum'
}

/** Versi manifest toko aktif berbeda dari yang sedang dipakai → manifest perlu dimuat ulang.
 *  Toko dicocokkan lewat kode/nama: id-nya ciphertext non-deterministik (lihat toko-cocok.js). */
export function manifestBerubah(tokoAktif, tokos) {
  const baru = cocokkanToko(tokos, tokoAktif)
  if (!baru) return false
  return Number(baru.manifest_version || 0) !== Number(tokoAktif.manifest_version || 0)
}

/**
 * Layar aktif harus ditinggalkan bila TADINYA boleh dibuka dan sekarang tidak lagi.
 * @param {string|null} screen layar yang sedang terbuka
 * @param {string[]|null} layarTersedia layar yang punya pintu SESUDAH hak/menu disegarkan
 * @param {string[]|null} [layarSebelumnya] layar yang punya pintu sebelumnya; bila diberikan, layar
 *   yang memang tak pernah punya pintu (dibuka dari dalam layar lain / pintasan papan tik) dibiarkan
 * Daftar kosong/tak diketahui = jangan usir siapa pun (gagal-terbuka).
 */
export function layarTujuan(screen, layarTersedia, layarSebelumnya = null) {
  if (!screen || screen === 'home') return null
  if (!Array.isArray(layarTersedia) || layarTersedia.length === 0) return null
  if (Array.isArray(layarSebelumnya) && !layarSebelumnya.includes(screen)) return null
  return layarTersedia.includes(screen) ? null : 'home'
}

/**
 * Seluruh keputusan muat ulang identitas dalam satu fungsi murni.
 *
 * @param {{ok?: boolean, data?: object}} me amplop /auth/me apa adanya
 * @param {{akses?, toko?, screen?, layarTersedia?, layarSebelumnya?}} state layarTersedia = daftar
 *   layar berpintu yang BERLAKU untuk identitas baru; pemanggil yang memuat ulang manifest lebih
 *   dulu menilai ulang sendiri dengan layarTujuan().
 * @returns {{patch: object|null, perluRender: boolean, perluManifest: boolean, keLayar: string|null}}
 *
 * Jawaban gagal/offline TIDAK menghasilkan patch: amplop kosong bukan bukti hak dicabut, dan
 * menghapus `akses` di situ justru mengunci kasir yang sedang bekerja tanpa sinyal dari server.
 */
export function putusanIdentitas(me, state = {}) {
  const kosong = { patch: null, perluRender: false, perluManifest: false, keLayar: null }
  if (!me || me.ok !== true || !me.data || !me.data.user) return kosong

  const data = me.data
  const patch = patchIdentitas(data)
  // Hak berubah → manifest ikut dimuat ulang: server menyaring menu per hak akses, sedangkan
  // manifest_version (pos_toko.manifest_revision) tidak bergerak saat peran diubah.
  const perluRender = kunciAkses(state.akses) !== kunciAkses(patch.akses)
  return {
    patch,
    perluRender,
    perluManifest: perluRender || manifestBerubah(state.toko, data.tokos),
    keLayar: layarTujuan(state.screen, state.layarTersedia, state.layarSebelumnya)
  }
}
