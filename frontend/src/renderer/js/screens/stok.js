// Layar Stok — peringatan stok menipis/habis, ambang minimum per produk, dan
// saran restok. Ambang tersimpan lokal per toko; peringatan juga muncul di lonceng.

import { api, firstError } from '../api.js'
import { getState, setState } from '../state.js'
import { toast, icons, loadingHTML, emptyStateHTML } from '../components/ui.js'
import { esc, fmtNumber, debounce } from '../utils/format.js'
import { analisisStok, setMin } from '../lib/stok-store.js'

const FILTERS = [
  { key: 'menipis', label: 'Perlu restok' },
  { key: 'semua', label: 'Semua' },
  { key: 'habis', label: 'Habis' },
  { key: 'aman', label: 'Aman' }
]

export const StokScreen = {
  id: 'stok',
  title: 'Stok',
  icon: icons.box,

  async render(container) {
    const ctx = {
      container,
      tokoId: getState().toko?.id || 'default',
      rows: [], analisis: null, filter: 'menipis', q: '', disposed: false
    }
    renderShell(ctx)
    bind(ctx)
    await load(ctx)
    return () => { ctx.disposed = true }
  }
}

function renderShell(ctx) {
  ctx.container.innerHTML = `
    <div class="screen-page">
      <div class="page-head">
        <div>
          <h1 class="page-head__title">Stok</h1>
          <p class="page-head__desc">Pantau stok menipis, atur batas minimum, dan lihat saran restok.</p>
        </div>
        <button class="btn btn--outline btn--sm" id="stk-refresh" type="button">${icons.refresh}<span>Muat ulang</span></button>
      </div>
      <div id="stk-body"></div>
    </div>`
}

function bind(ctx) {
  ctx.container.querySelector('#stk-refresh').addEventListener('click', () => load(ctx, true))
}

async function load(ctx, force) {
  const body = ctx.container.querySelector('#stk-body')
  if (!ctx.analisis || force) body.innerHTML = loadingHTML('Memuat stok…')
  const result = await api.laporan.stok({})
  if (ctx.disposed) return
  if (!result.ok) {
    body.innerHTML = `<div class="empty-state"><div class="empty-state__icon">${icons.alert}</div>
      <div class="empty-state__title">Gagal memuat stok</div><div class="empty-state__desc">${esc(firstError(result))}</div>
      <button class="btn btn--outline btn--sm" id="stk-retry" type="button">Coba lagi</button></div>`
    body.querySelector('#stk-retry')?.addEventListener('click', () => load(ctx, true))
    return
  }
  ctx.rows = Array.isArray(result.data) ? result.data : []
  ctx.analisis = analisisStok(ctx.rows, ctx.tokoId)
  // Segarkan peringatan lonceng
  setState({ stokAlerts: ctx.analisis.alerts })
  renderBody(ctx)
}

function statusBadge(status) {
  if (status === 'habis') return '<span class="badge badge--danger">Habis</span>'
  if (status === 'menipis') return '<span class="badge badge--warn">Menipis</span>'
  return '<span class="badge badge--mint">Aman</span>'
}

function currentRows(ctx) {
  const a = ctx.analisis
  let rows = ctx.filter === 'menipis' ? a.alerts
    : ctx.filter === 'habis' ? a.habis
      : ctx.filter === 'aman' ? a.aman
        : [...a.habis, ...a.menipis, ...a.aman]
  const q = ctx.q.toLowerCase()
  if (q) rows = rows.filter((r) => String(r.produk).toLowerCase().includes(q) || String(r.kode).toLowerCase().includes(q))
  return rows
}

function renderBody(ctx) {
  const body = ctx.container.querySelector('#stk-body')
  const a = ctx.analisis
  body.innerHTML = `
    <div class="rpt-kpis">
      <div class="stat-tile${a.habis.length ? ' stat-tile--accent' : ''}">
        <div class="stat-tile__label">Perlu restok</div>
        <div class="stat-tile__value num">${fmtNumber(a.alerts.length)}</div>
        <div class="stat-tile__sub">${a.habis.length} habis · ${a.menipis.length} menipis</div>
      </div>
      <div class="stat-tile"><div class="stat-tile__label">Stok aman</div><div class="stat-tile__value num">${fmtNumber(a.aman.length)}</div></div>
      <div class="stat-tile"><div class="stat-tile__label">Total produk</div><div class="stat-tile__value num">${fmtNumber(ctx.rows.length)}</div></div>
    </div>

    <div class="stk-toolbar">
      <div class="segmented" id="stk-filter">
        ${FILTERS.map((f) => `<button class="segmented__item${f.key === ctx.filter ? ' is-active' : ''}" type="button" data-f="${f.key}">${f.label}${f.key === 'menipis' && a.alerts.length ? ` (${a.alerts.length})` : ''}</button>`).join('')}
      </div>
      <div class="search-box stk-search">
        <span class="search-box__icon">${icons.search}</span>
        <input class="input" id="stk-q" type="text" autocomplete="off" placeholder="Cari nama / kode…" value="${esc(ctx.q)}" />
      </div>
    </div>
    <div id="stk-table"></div>`

  body.querySelectorAll('[data-f]').forEach((btn) => btn.addEventListener('click', () => {
    ctx.filter = btn.dataset.f
    body.querySelectorAll('[data-f]').forEach((b) => b.classList.toggle('is-active', b === btn))
    renderTable(ctx)
  }))
  const input = body.querySelector('#stk-q')
  input.addEventListener('input', debounce(() => { ctx.q = input.value.trim(); renderTable(ctx) }, 200))
  renderTable(ctx)
}

function renderTable(ctx) {
  const el = ctx.container.querySelector('#stk-table')
  const rows = currentRows(ctx)
  if (rows.length === 0) {
    el.innerHTML = emptyStateHTML({
      icon: ctx.filter === 'menipis' ? icons.check : icons.search,
      title: ctx.filter === 'menipis' ? 'Semua stok aman 👍' : 'Tidak ada produk',
      desc: ctx.filter === 'menipis' ? 'Tidak ada produk yang perlu di-restok saat ini.' : 'Coba ubah filter atau kata kunci.'
    })
    return
  }
  const trs = rows.map((r) => `
    <tr>
      <td class="mono">${esc(r.kode)}</td>
      <td>${esc(r.produk)}</td>
      <td class="num u-right">${fmtNumber(r.stok)}</td>
      <td class="u-right"><input type="number" min="0" class="input input--sm stk-min" data-id="${esc(r.id)}" value="${r.min}" /></td>
      <td>${statusBadge(r.status)}</td>
      <td class="num u-right">${r.status === 'aman' ? '—' : `+${fmtNumber(r.saran)}`}</td>
    </tr>`).join('')
  el.innerHTML = `
    <div class="table-wrap"><table class="table"><thead>
      <tr><th>Kode</th><th>Produk</th><th class="u-right">Stok</th><th class="u-right">Min</th><th>Status</th><th class="u-right">Saran restok</th></tr>
    </thead><tbody>${trs}</tbody></table></div>`

  el.querySelectorAll('.stk-min').forEach((inp) => inp.addEventListener('change', () => {
    setMin(ctx.tokoId, inp.dataset.id, inp.value)
    ctx.analisis = analisisStok(ctx.rows, ctx.tokoId)
    setState({ stokAlerts: ctx.analisis.alerts })
    renderBody(ctx)
  }))
}
