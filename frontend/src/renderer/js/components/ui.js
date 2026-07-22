// Komponen UI bersama: toast, modal, konfirmasi, empty state, ikon.
// Semua menerima/menghasilkan string HTML yang SUDAH di-escape oleh pemanggil
// (pakai esc() dari utils/format.js untuk data API).

import { esc } from '../utils/format.js'

// ---------- Ikon (inline SVG, stroke mengikuti currentColor) ----------

const strokeAttrs = 'fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"'

export const icons = {
  pos: `<svg width="18" height="18" viewBox="0 0 24 24" ${strokeAttrs}><path d="M2 7h20v5a10 10 0 0 1-20 0z"/><path d="M6 7V4a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v3"/><path d="M9 22h6"/><path d="M12 17v5"/></svg>`,
  history: `<svg width="18" height="18" viewBox="0 0 24 24" ${strokeAttrs}><path d="M3 12a9 9 0 1 0 3-6.7L3 8"/><path d="M3 3v5h5"/><path d="M12 7v5l3 3"/></svg>`,
  session: `<svg width="18" height="18" viewBox="0 0 24 24" ${strokeAttrs}><rect x="2" y="6" width="20" height="12" rx="2"/><circle cx="12" cy="12" r="3"/><path d="M6 12h.01M18 12h.01"/></svg>`,
  report: `<svg width="18" height="18" viewBox="0 0 24 24" ${strokeAttrs}><path d="M3 3v18h18"/><path d="M7 15v3"/><path d="M11 11v7"/><path d="M15 13v5"/><path d="M19 8v10"/></svg>`,
  settings: `<svg width="18" height="18" viewBox="0 0 24 24" ${strokeAttrs}><circle cx="12" cy="12" r="3"/><path d="M12 2v2m0 16v2M4.9 4.9l1.4 1.4m11.4 11.4 1.4 1.4M2 12h2m16 0h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg>`,
  search: `<svg width="16" height="16" viewBox="0 0 24 24" ${strokeAttrs}><circle cx="11" cy="11" r="7"/><path d="m21 21-4.3-4.3"/></svg>`,
  plus: `<svg width="16" height="16" viewBox="0 0 24 24" ${strokeAttrs}><path d="M12 5v14M5 12h14"/></svg>`,
  minus: `<svg width="16" height="16" viewBox="0 0 24 24" ${strokeAttrs}><path d="M5 12h14"/></svg>`,
  x: `<svg width="16" height="16" viewBox="0 0 24 24" ${strokeAttrs}><path d="M18 6 6 18M6 6l12 12"/></svg>`,
  trash: `<svg width="16" height="16" viewBox="0 0 24 24" ${strokeAttrs}><path d="M3 6h18"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6"/><path d="M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/></svg>`,
  print: `<svg width="16" height="16" viewBox="0 0 24 24" ${strokeAttrs}><path d="M6 9V2h12v7"/><path d="M6 18H4a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2h-2"/><rect x="6" y="14" width="12" height="8"/></svg>`,
  user: `<svg width="16" height="16" viewBox="0 0 24 24" ${strokeAttrs}><path d="M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>`,
  logout: `<svg width="16" height="16" viewBox="0 0 24 24" ${strokeAttrs}><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><path d="m16 17 5-5-5-5"/><path d="M21 12H9"/></svg>`,
  barcode: `<svg width="16" height="16" viewBox="0 0 24 24" ${strokeAttrs}><path d="M3 5v14M8 5v14M12 5v14M17 5v14M21 5v14"/></svg>`,
  cash: `<svg width="16" height="16" viewBox="0 0 24 24" ${strokeAttrs}><rect x="2" y="6" width="20" height="12" rx="2"/><circle cx="12" cy="12" r="3"/></svg>`,
  wallet: `<svg width="16" height="16" viewBox="0 0 24 24" ${strokeAttrs}><path d="M21 12V7H5a2 2 0 0 1 0-4h14v4"/><path d="M3 5v14a2 2 0 0 0 2 2h16v-5"/><path d="M18 12a2 2 0 0 0 0 4h4v-4Z"/></svg>`,
  qris: `<svg width="16" height="16" viewBox="0 0 24 24" ${strokeAttrs}><rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><path d="M14 14h3v3h-3zM20 14h1v1h-1zM14 20h1v1h-1zM19 19h2v2h-2z"/></svg>`,
  box: `<svg width="20" height="20" viewBox="0 0 24 24" ${strokeAttrs}><path d="M21 8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16Z"/><path d="m3.3 7 8.7 5 8.7-5"/><path d="M12 22V12"/></svg>`,
  alert: `<svg width="18" height="18" viewBox="0 0 24 24" ${strokeAttrs}><path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3Z"/><path d="M12 9v4M12 17h.01"/></svg>`,
  check: `<svg width="18" height="18" viewBox="0 0 24 24" ${strokeAttrs}><path d="M20 6 9 17l-5-5"/></svg>`,
  refresh: `<svg width="16" height="16" viewBox="0 0 24 24" ${strokeAttrs}><path d="M21 12a9 9 0 1 1-2.64-6.36L21 8"/><path d="M21 3v5h-5"/></svg>`,
  download: `<svg width="16" height="16" viewBox="0 0 24 24" ${strokeAttrs}><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><path d="m7 10 5 5 5-5"/><path d="M12 15V3"/></svg>`,
  store: `<svg width="18" height="18" viewBox="0 0 24 24" ${strokeAttrs}><path d="m2 7 2-4h16l2 4"/><path d="M2 7v3a3 3 0 0 0 6 0V7a3 3 0 0 0 6 0v3a3 3 0 0 0 6 0V7"/><path d="M4 12v9h16v-9"/><path d="M9 21v-6h6v6"/></svg>`,
  kitchen: `<svg width="18" height="18" viewBox="0 0 24 24" ${strokeAttrs}><path d="M12 3c1.5 2 4 3.5 4 6.5A4 4 0 0 1 8 9.5C8 6.5 10.5 5 12 3Z"/><path d="M5 14h14"/><path d="M6 14v5a2 2 0 0 0 2 2h8a2 2 0 0 0 2-2v-5"/></svg>`,
  queue: `<svg width="18" height="18" viewBox="0 0 24 24" ${strokeAttrs}><path d="M10 6h11"/><path d="M10 12h11"/><path d="M10 18h11"/><path d="M4 6h.5"/><path d="M4 12h.5"/><path d="M4 18h.5"/></svg>`,
  kanban: `<svg width="18" height="18" viewBox="0 0 24 24" ${strokeAttrs}><rect x="3" y="3" width="5" height="18" rx="1"/><rect x="10" y="3" width="5" height="12" rx="1"/><rect x="17" y="3" width="5" height="8" rx="1"/></svg>`,
  station: `<svg width="18" height="18" viewBox="0 0 24 24" ${strokeAttrs}><path d="M4 21v-7"/><path d="M4 10V3"/><path d="M12 21v-9"/><path d="M12 8V3"/><path d="M20 21v-5"/><path d="M20 12V3"/><path d="M2 14h4"/><path d="M10 8h4"/><path d="M18 16h4"/></svg>`,
  bell: `<svg width="18" height="18" viewBox="0 0 24 24" ${strokeAttrs}><path d="M10.3 21a1.94 1.94 0 0 0 3.4 0"/><path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9"/></svg>`,
  moon: `<svg width="18" height="18" viewBox="0 0 24 24" ${strokeAttrs}><path d="M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z"/></svg>`,
  sun: `<svg width="18" height="18" viewBox="0 0 24 24" ${strokeAttrs}><circle cx="12" cy="12" r="4"/><path d="M12 2v2m0 16v2M4.9 4.9l1.4 1.4m11.4 11.4 1.4 1.4M2 12h2m16 0h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg>`
}

// ---------- Toast ----------

function toastStack() {
  let stack = document.querySelector('.toast-stack')
  if (!stack) {
    stack = document.createElement('div')
    stack.className = 'toast-stack'
    document.body.appendChild(stack)
  }
  return stack
}

/** toast('Tersimpan', 'success' | 'error' | 'info') */
export function toast(message, type = 'info', durationMs = 3200) {
  const el = document.createElement('div')
  el.className = `toast toast--${type}`
  el.setAttribute('role', 'status')
  el.textContent = message
  toastStack().appendChild(el)
  setTimeout(() => {
    el.classList.add('is-leaving')
    setTimeout(() => el.remove(), 260)
  }, durationMs)
}

// ---------- Modal ----------

let openModals = []

/**
 * showModal({ title, body, footer, size, onClose }) → { el, close }
 * body/footer: string HTML (data API harus sudah di-esc) atau Node.
 */
export function showModal({ title = '', body = '', footer = '', size = '', onClose = null }) {
  const overlay = document.createElement('div')
  overlay.className = 'modal-overlay'
  const sizeClass = size ? ` modal--${size}` : ''
  overlay.innerHTML = `
    <div class="modal${sizeClass}" role="dialog" aria-modal="true" aria-label="${esc(title)}">
      <div class="modal__header">
        <h2 class="modal__title">${esc(title)}</h2>
        <button class="icon-btn" data-modal-close aria-label="Tutup">${icons.x}</button>
      </div>
      <div class="modal__body"></div>
      <div class="modal__footer"></div>
    </div>`

  const bodyEl = overlay.querySelector('.modal__body')
  const footerEl = overlay.querySelector('.modal__footer')
  if (body instanceof Node) bodyEl.appendChild(body)
  else bodyEl.innerHTML = body
  if (footer instanceof Node) footerEl.appendChild(footer)
  else if (footer) footerEl.innerHTML = footer
  else footerEl.remove()

  function close() {
    overlay.remove()
    openModals = openModals.filter((m) => m !== close)
    if (typeof onClose === 'function') onClose()
  }

  overlay.addEventListener('click', (e) => {
    if (e.target === overlay || e.target.closest('[data-modal-close]')) close()
  })

  openModals.push(close)
  document.body.appendChild(overlay)

  const firstInput = overlay.querySelector('input, select, textarea, button:not([data-modal-close])')
  if (firstInput) firstInput.focus()

  return { el: overlay, close }
}

export function closeTopModal() {
  const close = openModals[openModals.length - 1]
  if (close) {
    close()
    return true
  }
  return false
}

/** Dialog konfirmasi — resolve true bila dikonfirmasi. */
export function confirmDialog({ title, message, confirmText = 'Ya, lanjutkan', cancelText = 'Batal', danger = false }) {
  return new Promise((resolve) => {
    const footer = document.createElement('div')
    footer.className = 'u-flex'
    footer.style.justifyContent = 'flex-end'
    footer.style.gap = 'var(--sp-3)'
    footer.innerHTML = `
      <button class="btn btn--ghost" data-cancel>${esc(cancelText)}</button>
      <button class="btn ${danger ? 'btn--danger' : 'btn--primary'}" data-confirm>${esc(confirmText)}</button>`

    const { close } = showModal({
      title,
      body: `<p class="u-muted">${esc(message)}</p>`,
      footer,
      onClose: () => resolve(false)
    })

    footer.querySelector('[data-cancel]').addEventListener('click', () => close())
    footer.querySelector('[data-confirm]').addEventListener('click', () => {
      resolve(true)
      // Cegah onClose me-resolve(false) setelah resolve(true) — resolve kedua no-op
      close()
    })
  })
}

// ---------- Status kosong / loading ----------

export function emptyStateHTML({ icon = icons.box, title, desc = '' }) {
  return `
    <div class="empty-state">
      <div class="empty-state__icon">${icon}</div>
      <div class="empty-state__title">${esc(title)}</div>
      ${desc ? `<div class="empty-state__desc">${esc(desc)}</div>` : ''}
    </div>`
}

export function loadingHTML(label = 'Memuat…') {
  return `
    <div class="empty-state" role="status">
      <div class="spinner spinner--lg"></div>
      <div class="empty-state__desc">${esc(label)}</div>
    </div>`
}

// ESC menutup modal teratas
document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') closeTopModal()
})
