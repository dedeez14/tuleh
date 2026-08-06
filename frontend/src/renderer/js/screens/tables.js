// Layar Meja & QR — daftar meja toko + QR pemesanan mandiri per meja.
// Pelanggan memindai QR di meja → menu tampil di HP → pesanan masuk sebagai
// "Menunggu Bayar" di Papan Pesanan.

import { api, firstError } from '../api.js'
import { getState } from '../state.js'
import { esc } from '../utils/format.js'
import { icons, showModal, emptyStateHTML, loadingHTML } from '../components/ui.js'
import { printQR } from '../components/receipt.js'

export const TablesScreen = {
  id: 'tables',
  title: 'Meja & QR',
  icon: icons.qris,

  async render(container) {
    let alive = true

    container.innerHTML = `
      <div class="screen-page">
        <div class="page-head">
          <div>
            <h1 class="page-head__title">Meja & QR</h1>
            <p class="page-head__desc">
              Tempel QR di tiap meja — pelanggan memesan sendiri dari HP,
              pesanan masuk ke Papan Pesanan sebagai "Menunggu Bayar".
            </p>
          </div>
        </div>
        <div id="tbl-info" class="tbl-info u-hidden"></div>
        <div id="tbl-body">${loadingHTML('Memuat meja…')}</div>
      </div>`

    const body = container.querySelector('#tbl-body')
    const infoEl = container.querySelector('#tbl-info')

    const [tables, appInfo] = await Promise.all([api.table.list(), api.app.info()])
    if (!alive) return

    const tracking = appInfo.ok && appInfo.data ? appInfo.data.tracking : null
    const contohKode = tables.ok && Array.isArray(tables.data) && tables.data[0] ? tables.data[0].kode : null
    if (!tracking || !tracking.running) {
      infoEl.classList.remove('u-hidden')
      infoEl.textContent = 'Server pemesanan LAN tidak aktif — QR meja tidak dapat diakses pelanggan saat ini.'
    } else {
      infoEl.classList.remove('u-hidden')
      // Tampilkan contoh URL NYATA (bukan pola) — pola mengundang salah ketik
      infoEl.textContent = contohKode
        ? `Contoh (Meja ${tables.data[0].nomor}): ${tracking.baseUrl}/o/${contohKode} — gunakan QR di tiap kartu meja; HP pelanggan harus satu WiFi.`
        : `Server pemesanan aktif di ${tracking.baseUrl} — gunakan QR di tiap kartu meja.`
    }

    if (!tables.ok) {
      body.innerHTML = emptyStateHTML({
        icon: icons.alert,
        title: 'Gagal memuat meja',
        desc: firstError(tables) || 'Endpoint meja belum tersedia di server ini.'
      })
      return
    }

    const rows = Array.isArray(tables.data) ? tables.data : []
    if (!rows.length) {
      body.innerHTML = emptyStateHTML({
        icon: icons.qris,
        title: 'Belum ada meja',
        desc: 'Toko ini belum memiliki meja terdaftar.'
      })
      return
    }

    body.innerHTML = `
      <div class="tbl-grid">
        ${rows.map((t) => `
          <button type="button" class="tbl-card" data-kode="${esc(t.kode)}" data-nomor="${esc(t.nomor)}">
            <span class="tbl-card__icon">${icons.qris}</span>
            <span class="tbl-card__nomor">Meja ${esc(t.nomor)}</span>
            <span class="tbl-card__kode mono">${esc(t.kode)}</span>
            <span class="tbl-card__hint">Klik untuk lihat QR</span>
          </button>`).join('')}
      </div>`

    body.addEventListener('click', async (e) => {
      const card = e.target.closest('.tbl-card')
      if (!card) return
      if (!tracking || !tracking.running) return

      const url = `${tracking.baseUrl}/o/${card.dataset.kode}`
      const qrResult = await api.qr.make({ text: url })
      if (!alive) return
      if (!qrResult.ok) return

      const bodyEl = document.createElement('div')
      bodyEl.className = 'tbl-qr'
      bodyEl.innerHTML = `
        <img class="tbl-qr__img" src="${esc(qrResult.data.uri)}" alt="QR Meja ${esc(card.dataset.nomor)}" />
        <div class="tbl-qr__url mono">${esc(url)}</div>
        <p class="tbl-qr__hint">
          Cetak dan tempel di Meja ${esc(card.dataset.nomor)}. Pelanggan memindai
          dengan kamera HP (WiFi yang sama) untuk membuka menu dan memesan.
        </p>`
      const footer = document.createElement('div')
      footer.innerHTML = `<button type="button" class="btn btn--primary btn--block" id="tqr-print">${icons.print} Cetak QR Meja</button>`
      const tokoNama = getState().company?.nama || getState().company?.name || 'Tuléh'
      showModal({ title: `QR Meja ${card.dataset.nomor}`, body: bodyEl, footer })
      footer.querySelector('#tqr-print').addEventListener('click', () =>
        printQR({ nomor: card.dataset.nomor, tokoNama, url, qrUri: qrResult.data.uri }))
    })

    return () => {
      alive = false
    }
  }
}
