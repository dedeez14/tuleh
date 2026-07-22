// Notifikasi ringan (tanpa backend). hitungNotifikasi() menurunkan daftar
// pemberitahuan dari state demo yang tersedia; renderPanelNotifikasi()
// menghasilkan markup dropdown. Semua string Bahasa Indonesia.

import { icons } from './components/ui.js'
import { esc } from './utils/format.js'
import { ringkasLangganan } from './langganan.js'

const BATAS_STOK_MENIPIS = 5
const MAKS_ITEM_STOK = 4

/**
 * hitungNotifikasi(state) → [{ id, ikon, warna, judul, detail, waktu }]
 * Sumber best-effort: produk ber-kelola-stok yang menipis, pesanan baru,
 * status sesi kasir, dan langganan (placeholder). Aman bila data kosong.
 */
export function hitungNotifikasi(state = {}) {
  const notifs = []

  // Stok menipis — dari produk ber-kelola-stok (bila daftar tersedia di state)
  const produk = Array.isArray(state.produk) ? state.produk : []
  const menipis = produk.filter((p) => p && p.kelola_stok && Number(p.stok) <= BATAS_STOK_MENIPIS)
  for (const p of menipis.slice(0, MAKS_ITEM_STOK)) {
    notifs.push({
      id: `stok-${p.id}`,
      ikon: 'box',
      warna: 'warn',
      judul: 'Stok menipis',
      detail: `${p.nama || 'Produk'} tersisa ${Number(p.stok) || 0}`,
      waktu: 'Hari ini'
    })
  }

  // Pesanan baru — dari papan pesanan pada tahap awal (bila tersedia)
  const orders = Array.isArray(state.orders) ? state.orders : []
  const baru = orders.filter((o) => o && (o.stage === 'ANTRIAN' || o.stage === 'MENUNGGU_BAYAR'))
  if (baru.length > 0) {
    notifs.push({
      id: 'order-baru',
      ikon: 'queue',
      warna: 'info',
      judul: 'Pesanan baru',
      detail: `${baru.length} pesanan menunggu diproses`,
      waktu: 'Baru saja'
    })
  }

  // Status sesi kasir
  if (state.session) {
    notifs.push({
      id: 'sesi-aktif',
      ikon: 'session',
      warna: 'success',
      judul: 'Sesi kasir aktif',
      detail: `Sesi ${state.session.nomor || 'kasir'} sedang berjalan`,
      waktu: 'Sekarang'
    })
  } else {
    notifs.push({
      id: 'sesi-tutup',
      ikon: 'session',
      warna: 'warn',
      judul: 'Sesi kasir belum dibuka',
      detail: 'Buka sesi untuk mulai mencatat transaksi',
      waktu: '—'
    })
  }

  // Langganan — hanya muncul bila perlu tindakan (segera berakhir / tenggang /
  // kedaluwarsa). Saat aktif & sehat, tidak ada notifikasi (hindari klaim palsu).
  const lang = ringkasLangganan(state.langganan)
  if (lang.perluAksi) {
    notifs.push({
      id: 'langganan',
      ikon: 'store',
      warna: lang.level === 'kedaluwarsa' ? 'danger' : 'warn',
      judul: lang.judul,
      detail: lang.detail,
      waktu: lang.sisaHari != null && lang.sisaHari > 0 ? `${lang.sisaHari} hari lagi` : 'Perlu perhatian'
    })
  }

  return notifs
}

function notifItemHTML(n) {
  const ikon = icons[n.ikon] || icons.alert
  const warna = ['warn', 'info', 'success', 'danger'].includes(n.warna) ? n.warna : 'info'
  return `
    <div class="notif-item">
      <span class="notif-item__icon notif-item__icon--${warna}">${ikon}</span>
      <div class="notif-item__body">
        <div class="notif-item__title">${esc(n.judul)}</div>
        <div class="notif-item__detail">${esc(n.detail)}</div>
      </div>
      <span class="notif-item__time">${esc(n.waktu)}</span>
    </div>`
}

/** Markup panel dropdown notifikasi (termasuk empty state & tombol tandai terbaca). */
export function renderPanelNotifikasi(notifs = []) {
  const isi = notifs.length > 0
    ? notifs.map(notifItemHTML).join('')
    : `<div class="notif-empty">
         <span class="notif-empty__icon">${icons.check}</span>
         <span>Tidak ada notifikasi baru</span>
       </div>`
  return `
    <div class="notif-panel" role="dialog" aria-label="Notifikasi">
      <div class="notif-panel__head">
        <span class="notif-panel__title">Notifikasi</span>
        <button type="button" class="notif-panel__mark" data-notif-read>Tandai terbaca</button>
      </div>
      <div class="notif-panel__list">${isi}</div>
      <div class="notif-panel__foot">
        <button type="button" class="notif-panel__cs" data-cs-contact>
          <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 11.5a8.38 8.38 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.38 8.38 0 0 1-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.38 8.38 0 0 1 3.8-.9h.5a8.48 8.48 0 0 1 8 8v.5z"/></svg>
          <span>Hubungi CS</span>
        </button>
      </div>
    </div>`
}
