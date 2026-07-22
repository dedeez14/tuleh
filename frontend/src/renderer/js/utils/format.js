// Utilitas format & sanitasi — dipakai semua layar.

const idr = new Intl.NumberFormat('id-ID', {
  style: 'currency',
  currency: 'IDR',
  maximumFractionDigits: 0
})

const numberFmt = new Intl.NumberFormat('id-ID', { maximumFractionDigits: 2 })

const dateFmt = new Intl.DateTimeFormat('id-ID', { day: '2-digit', month: 'short', year: 'numeric' })

const dateTimeFmt = new Intl.DateTimeFormat('id-ID', {
  day: '2-digit',
  month: 'short',
  year: 'numeric',
  hour: '2-digit',
  minute: '2-digit'
})

const timeFmt = new Intl.DateTimeFormat('id-ID', { hour: '2-digit', minute: '2-digit' })

/** Escape HTML — WAJIB untuk semua data dari API sebelum masuk innerHTML. */
export function esc(value) {
  if (value === null || value === undefined) return ''
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;')
}

/** "Rp 18.000" */
export function fmtIDR(value) {
  const n = Number(value)
  return idr.format(Number.isFinite(n) ? n : 0)
}

/** Angka umum: 1.234,5 */
export function fmtNumber(value) {
  const n = Number(value)
  return numberFmt.format(Number.isFinite(n) ? n : 0)
}

function toDate(value) {
  if (!value) return null
  const d = new Date(value)
  return Number.isNaN(d.getTime()) ? null : d
}

export function fmtDate(value) {
  const d = toDate(value)
  return d ? dateFmt.format(d) : '—'
}

export function fmtDateTime(value) {
  const d = toDate(value)
  return d ? dateTimeFmt.format(d) : '—'
}

export function fmtTime(value) {
  const d = toDate(value)
  return d ? timeFmt.format(d) : '—'
}

/** "2026-07-02" untuk <input type="date"> dan query API. */
export function toISODate(date) {
  const d = date instanceof Date ? date : new Date(date)
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, '0')
  const day = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${day}`
}

export function daysAgo(n) {
  const d = new Date()
  d.setDate(d.getDate() - n)
  return d
}

/** Parse input uang bebas ("50.000", "50rb", "Rp 50,000") → angka. */
export function parseAmount(value) {
  if (typeof value === 'number') return Number.isFinite(value) ? value : 0
  if (!value) return 0
  const cleaned = String(value).toLowerCase().trim()
    .replace(/rp\s*/g, '')
    .replace(/[.\s]/g, '')
    .replace(',', '.')
  const withSuffix = cleaned.match(/^([\d.]+)(rb|k|jt|m)?$/)
  if (!withSuffix) return 0
  const base = Number(withSuffix[1])
  if (!Number.isFinite(base)) return 0
  const mult = { rb: 1000, k: 1000, jt: 1000000, m: 1000000 }[withSuffix[2]] || 1
  return base * mult
}

export function debounce(fn, waitMs) {
  let timer = null
  return (...args) => {
    clearTimeout(timer)
    timer = setTimeout(() => fn(...args), waitMs)
  }
}
