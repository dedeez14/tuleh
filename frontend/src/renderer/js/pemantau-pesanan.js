// Pemantau pesanan meja (desktop) — padanan layanan latar depan di Android.
//
// Selama pengguna masuk, memeriksa /orders dan /bills tiap JEDA_MS. Kejadian
// (pesanan baru, tambah pesanan, minta bayar) → notifikasi sistem Windows +
// bunyi ting, kecuali layar tujuannya sedang terbuka (layar itu punya
// pembaruannya sendiri). Klik notifikasi → buka layar tujuan.
//
// Server MOVERA tidak punya push, jadi ini polling; jedanya sama dengan
// Android (15 dtk) supaya kedua perangkat "mendengar" pada saat yang sama.

import { api } from './api.js'
import { getState } from './state.js'
import { bandingkan } from './utils/deteksi-pesanan.js'
import { ting } from './utils/suara.js'

export const JEDA_MS = 15000

let timer = null
let potret = null
let sibuk = false
let bukaLayar = null // (id) => Promise — disuntik dari app.js agar tidak impor melingkar

/** Endpoint mana yang relevan untuk toko ini (dari manifest). */
function cakupan() {
  const { manifest } = getState()
  const caps = Array.isArray(manifest && manifest.capabilities) ? manifest.capabilities : []
  const states = manifest && manifest.lifecycle && Array.isArray(manifest.lifecycle.states) ? manifest.lifecycle.states : []
  return {
    meja: caps.includes('tables_qr') || caps.includes('tables'),
    pesanan: states.length >= 2 || caps.includes('orders')
  }
}

async function periksa() {
  if (sibuk) return
  sibuk = true
  try {
    const { meja, pesanan } = cakupan()
    if (!meja && !pesanan) return
    let orders = []
    let tables = []
    let adaData = false
    if (pesanan) {
      const r = await api.order.list({})
      if (r && r.ok) { adaData = true; orders = Array.isArray(r.data) ? r.data : [] }
    }
    if (meja) {
      const r = await api.bill.peta()
      if (r && r.ok) { adaData = true; tables = r.data && Array.isArray(r.data.tables) ? r.data.tables : [] }
    }
    if (!adaData) return // jaringan gagal — jangan rusak potret
    const hasil = bandingkan({ sebelum: potret, orders, tables })
    potret = hasil.potret
    for (const k of hasil.kejadian) umumkan(k)
  } catch {
    // gagal satu putaran — coba lagi putaran berikutnya
  } finally {
    sibuk = false
  }
}

function umumkan(k) {
  const layarAktif = getState().screen
  if (layarAktif === k.tujuan) return // layar itu memperbarui dirinya sendiri (dan ting sendiri)
  ting()
  try {
    if (typeof Notification === 'undefined') return
    const n = new Notification(k.judul, { body: k.isi, tag: `tuleh-${k.tujuan}`, silent: true })
    n.onclick = () => {
      try { window.focus() } catch { /* abaikan */ }
      if (typeof bukaLayar === 'function') bukaLayar(k.tujuan)
    }
  } catch {
    // Notifikasi sistem tidak tersedia — bunyi sudah cukup
  }
}

/** Mulai memantau. `onBuka(idLayar)` dipanggil saat notifikasi diklik. */
export function mulaiPemantau({ onBuka } = {}) {
  hentikanPemantau()
  bukaLayar = typeof onBuka === 'function' ? onBuka : null
  potret = null
  timer = setInterval(periksa, JEDA_MS)
  periksa() // potret awal segera (tanpa notifikasi)
}

export function hentikanPemantau() {
  if (timer) clearInterval(timer)
  timer = null
  potret = null
  sibuk = false
}
