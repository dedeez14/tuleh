// Layar "Langganan berakhir" (kontrak #2). Muncul saat endpoint TULIS mana pun menjawab
// HTTP 402 — sinyal dari main (desktop) / jembatan (Android lama) lewat
// api.langganan.onTerkunci. Pesan & URL perpanjang berasal dari server; tidak ada teks
// kontak/URL tertanam. Data tetap bisa dilihat (GET tidak diblokir server), jadi layar
// bisa ditutup untuk kembali melihat data — dan muncul lagi pada penulisan berikutnya.

import { api, firstError } from './api.js'
import { modelKunciLangganan } from './langganan.js'
import { LOGO_DATA_URI } from './assets/logo.js'

let overlayEl = null
let dipasang = false

function esc(s) {
  return String(s == null ? '' : s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]))
}

function tutup() {
  if (!overlayEl) return
  overlayEl.remove()
  overlayEl = null
}

/** Tampilkan layar kunci. `opsi.bisaBayar` → tombol bayar di aplikasi (hak langganan.kelola). */
export function tampilkanKunciLangganan(info, { bisaBayar = false, onBayar = null } = {}) {
  const m = modelKunciLangganan(info)
  if (overlayEl) {
    // Sudah tampil: segarkan pesan (server bisa mengirim teks berbeda per endpoint).
    const msg = overlayEl.querySelector('.upd__msg')
    if (msg) msg.textContent = m.pesan
    return
  }
  overlayEl = document.createElement('div')
  overlayEl.className = 'upd upd--block langganan-kunci'
  overlayEl.setAttribute('role', 'alertdialog')
  overlayEl.setAttribute('aria-modal', 'true')
  overlayEl.innerHTML = `
    <div class="upd__card">
      <img class="upd__logo" src="${LOGO_DATA_URI}" alt="" />
      <h1 class="upd__title">${esc(m.judul)}</h1>
      <p class="upd__msg">${esc(m.pesan)}</p>
      ${m.perpanjangUrl
        ? '<button type="button" class="upd__btn" data-kunci="perpanjang">Perpanjang langganan</button>'
        : '<p class="upd__hint">Tautan perpanjangan belum diatur penyedia layanan. Hubungi dukungan untuk memperpanjang.</p>'}
      ${bisaBayar && typeof onBayar === 'function' ? '<button type="button" class="upd__btn upd__btn--outline" data-kunci="bayar">Bayar di aplikasi</button>' : ''}
      <button type="button" class="upd__btn upd__btn--outline" data-kunci="cs">Hubungi dukungan</button>
      <div class="upd__hint" data-kunci-hint></div>
      <button type="button" class="upd__later" data-kunci="tutup">Tutup — lihat data saja</button>
    </div>`
  document.body.appendChild(overlayEl)
  const hint = (t) => { const el = overlayEl && overlayEl.querySelector('[data-kunci-hint]'); if (el) el.textContent = t || '' }

  overlayEl.addEventListener('click', async (e) => {
    const btn = e.target.closest('[data-kunci]')
    if (!btn) return
    const aksi = btn.dataset.kunci
    if (aksi === 'tutup') return tutup()
    if (aksi === 'perpanjang') {
      const r = await api.app.openExternal({ url: m.perpanjangUrl })
      hint(r && r.ok ? 'Halaman perpanjangan dibuka di peramban. Setelah dibayar, coba simpan lagi.' : firstError(r))
      return
    }
    if (aksi === 'bayar') {
      tutup()
      onBayar()
      return
    }
    if (aksi === 'cs') {
      const r = await api.cs.kontak()
      const link = r && r.ok && r.data && r.data.wa_link
      if (!link) { hint(firstError(r) || 'Kontak dukungan belum diatur penyedia layanan.'); return }
      const o = await api.app.openExternal({ url: link })
      if (!o || !o.ok) hint(firstError(o) || 'Gagal membuka kontak dukungan.')
    }
  })
}

/** Pasang pendengar sinyal 402 sekali (dipanggil saat boot). */
export function pasangKunciLangganan(opsi = () => ({})) {
  if (dipasang || !api.langganan || typeof api.langganan.onTerkunci !== 'function') return
  dipasang = true
  api.langganan.onTerkunci((info) => tampilkanKunciLangganan(info, opsi()))
}

export function kunciLanggananTampil() { return !!overlayEl }
