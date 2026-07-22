// Layar Laporan — 4 tab: Penjualan Harian, Per Produk, Stok, Rekap Kasir.
// Data dimuat malas (lazy) per tab dan di-cache per kombinasi filter;
// tombol Terapkan selalu mengambil ulang data terbaru dari server.

import { api, firstError } from '../api.js'
import { getState } from '../state.js'
import { toast, icons, emptyStateHTML, loadingHTML } from '../components/ui.js'
import { esc, fmtIDR, fmtNumber, fmtDate, toISODate, daysAgo, debounce } from '../utils/format.js'

const TABS = [
  { key: 'harian', label: 'Penjualan Harian' },
  { key: 'produk', label: 'Per Produk' },
  { key: 'stok', label: 'Stok' },
  { key: 'rekap', label: 'Rekap Kasir' }
]

const DEFAULT_RANGE_DAYS = 6 // 6 hari lalu s/d hari ini = 7 hari
const SEARCH_DEBOUNCE_MS = 200
const STOK_BATAS_MENIPIS = 5
const MAX_AXIS_LABELS = 14 // lebih dari ini, label sumbu-x ditampilkan sebagian
const TARGET_AXIS_LABELS = 10
const REVOKE_URL_DELAY_MS = 1000

export const ReportsScreen = {
  id: 'reports',
  title: 'Laporan',
  icon: icons.report,

  async render(container) {
    const ctx = {
      container,
      activeTab: 'harian',
      filters: {
        dari: toISODate(daysAgo(DEFAULT_RANGE_DAYS)),
        sampai: toISODate(new Date()),
        gudangId: ''
      },
      cache: new Map(),
      stokQuery: '',
      disposed: false
    }

    renderLayout(ctx)
    bindToolbar(ctx)
    await loadTab(ctx)

    return () => {
      ctx.disposed = true
    }
  }
}

// ---------- Kerangka layar ----------

function renderLayout(ctx) {
  ctx.container.innerHTML = `
    <div class="screen-page">
      <div class="page-head">
        <div>
          <h1 class="page-head__title">Laporan</h1>
          <p class="page-head__desc">Ringkasan penjualan, stok, dan rekap sesi kasir.</p>
        </div>
        <button class="btn btn--outline" id="rpt-export" type="button">
          ${icons.download}<span>Ekspor CSV</span>
        </button>
      </div>
      ${filterBarHTML(ctx)}
      <div class="tabs rpt-tabs" role="tablist" aria-label="Jenis laporan">
        ${TABS.map((t) => `
          <button class="tabs__item${t.key === ctx.activeTab ? ' is-active' : ''}" type="button"
                  role="tab" aria-selected="${t.key === ctx.activeTab}" data-tab="${t.key}">
            ${t.label}
          </button>`).join('')}
      </div>
      <div class="rpt-body" id="rpt-body" role="tabpanel"></div>
    </div>`
}

function filterBarHTML(ctx) {
  const { gudang } = getState()
  const isStok = ctx.activeTab === 'stok'
  return `
    <div class="rpt-filters">
      <div class="rpt-filters__dates${isStok ? ' u-hidden' : ''}" id="rpt-f-dates">
        <div class="rpt-filters__group">
          <label class="rpt-filters__label" for="rpt-dari">Dari</label>
          <input type="date" class="input" id="rpt-dari" value="${ctx.filters.dari}" />
        </div>
        <div class="rpt-filters__group">
          <label class="rpt-filters__label" for="rpt-sampai">Sampai</label>
          <input type="date" class="input" id="rpt-sampai" value="${ctx.filters.sampai}" />
        </div>
        <button class="btn btn--primary" id="rpt-apply" type="button">Terapkan</button>
      </div>
      <div class="rpt-filters__gudang${isStok ? '' : ' u-hidden'}" id="rpt-f-gudang">
        <div class="rpt-filters__group">
          <label class="rpt-filters__label" for="rpt-gudang">Gudang</label>
          <select class="select" id="rpt-gudang">
            <option value="">Semua gudang</option>
            ${(gudang || []).map((g) => `
              <option value="${esc(g.id)}"${String(g.id) === String(ctx.filters.gudangId) ? ' selected' : ''}>
                ${esc(g.nama)}
              </option>`).join('')}
          </select>
        </div>
      </div>
    </div>`
}

function bindToolbar(ctx) {
  const c = ctx.container
  c.querySelectorAll('[data-tab]').forEach((btn) => {
    btn.addEventListener('click', () => switchTab(ctx, btn.dataset.tab))
  })
  c.querySelector('#rpt-apply').addEventListener('click', () => applyDates(ctx))
  ;['#rpt-dari', '#rpt-sampai'].forEach((sel) => {
    c.querySelector(sel).addEventListener('keydown', (e) => {
      if (e.key === 'Enter') applyDates(ctx)
    })
  })
  c.querySelector('#rpt-gudang').addEventListener('change', (e) => {
    ctx.filters = { ...ctx.filters, gudangId: e.target.value }
    loadTab(ctx)
  })
  c.querySelector('#rpt-export').addEventListener('click', () => exportActiveTab(ctx))
}

function switchTab(ctx, tab) {
  if (tab === ctx.activeTab) return
  ctx.activeTab = tab
  ctx.container.querySelectorAll('[data-tab]').forEach((btn) => {
    const isActive = btn.dataset.tab === tab
    btn.classList.toggle('is-active', isActive)
    btn.setAttribute('aria-selected', String(isActive))
  })
  const isStok = tab === 'stok'
  ctx.container.querySelector('#rpt-f-dates').classList.toggle('u-hidden', isStok)
  ctx.container.querySelector('#rpt-f-gudang').classList.toggle('u-hidden', !isStok)
  loadTab(ctx)
}

function applyDates(ctx) {
  const dari = ctx.container.querySelector('#rpt-dari').value
  const sampai = ctx.container.querySelector('#rpt-sampai').value
  if (!dari || !sampai) {
    toast('Lengkapi tanggal Dari dan Sampai terlebih dahulu.', 'error')
    return
  }
  if (dari > sampai) {
    toast('Tanggal "Dari" tidak boleh melewati tanggal "Sampai".', 'error')
    return
  }
  ctx.filters = { ...ctx.filters, dari, sampai }
  ctx.cache.delete(cacheKey(ctx)) // Terapkan = ambil data terbaru
  loadTab(ctx)
}

// ---------- Pemuatan data per tab ----------

function cacheKey(ctx) {
  if (ctx.activeTab === 'stok') return `stok|${ctx.filters.gudangId}`
  return `${ctx.activeTab}|${ctx.filters.dari}|${ctx.filters.sampai}`
}

function fetchTab(ctx, tab) {
  const { dari, sampai, gudangId } = ctx.filters
  if (tab === 'harian') return api.laporan.penjualanHarian({ tanggalDari: dari, tanggalSampai: sampai })
  if (tab === 'produk') return api.laporan.penjualanProduk({ tanggalDari: dari, tanggalSampai: sampai })
  if (tab === 'stok') return api.laporan.stok({ gudangId: gudangId || undefined })
  return api.laporan.rekapKasir({ tanggalDari: dari, tanggalSampai: sampai })
}

async function loadTab(ctx) {
  const body = ctx.container.querySelector('#rpt-body')
  const tab = ctx.activeTab
  const key = cacheKey(ctx)

  if (ctx.cache.has(key)) {
    renderTab(ctx, tab, ctx.cache.get(key))
    return
  }

  body.innerHTML = loadingHTML('Memuat laporan…')
  const result = await fetchTab(ctx, tab)
  if (result.ok) ctx.cache.set(key, result.data)

  // Abaikan hasil bila layar sudah ditutup / tab atau filter sudah berganti
  if (ctx.disposed || tab !== ctx.activeTab || key !== cacheKey(ctx)) return

  if (!result.ok) {
    body.innerHTML = errorStateHTML(firstError(result))
    body.querySelector('#rpt-retry').addEventListener('click', () => loadTab(ctx))
    toast(firstError(result), 'error')
    return
  }
  renderTab(ctx, tab, result.data)
}

function errorStateHTML(message) {
  return `
    <div class="empty-state">
      <div class="empty-state__icon">${icons.alert}</div>
      <div class="empty-state__title">Gagal memuat laporan</div>
      <div class="empty-state__desc">${esc(message)}</div>
      <button class="btn btn--outline btn--sm rpt-retry" id="rpt-retry" type="button">Coba lagi</button>
    </div>`
}

function renderTab(ctx, tab, data) {
  const body = ctx.container.querySelector('#rpt-body')
  if (tab === 'harian') renderHarian(body, data)
  else if (tab === 'produk') renderProduk(body, data)
  else if (tab === 'stok') renderStok(ctx, body, data)
  else renderRekap(body, data)
}

// ---------- Tab 1: Penjualan Harian ----------

function renderHarian(body, data) {
  const rows = Array.isArray(data?.rows) ? data.rows : []
  if (rows.length === 0) {
    body.innerHTML = emptyStateHTML({
      title: 'Belum ada penjualan',
      desc: 'Tidak ada transaksi pada rentang tanggal ini. Coba ubah rentangnya.'
    })
    return
  }
  body.innerHTML = `
    ${kpiRowHTML(data.total || {})}
    ${columnChartHTML(rows)}
    ${harianTableHTML(rows)}`
  bindChartTooltip(body, rows)
}

function kpiRowHTML(total) {
  return `
    <div class="rpt-kpis">
      <div class="stat-tile stat-tile--accent">
        <div class="stat-tile__label">Total omzet</div>
        <div class="stat-tile__value num">${fmtIDR(total.total_omzet)}</div>
      </div>
      <div class="stat-tile">
        <div class="stat-tile__label">Jumlah transaksi</div>
        <div class="stat-tile__value num">${fmtNumber(total.jumlah_transaksi)}</div>
      </div>
      <div class="stat-tile">
        <div class="stat-tile__label">Rata-rata / transaksi</div>
        <div class="stat-tile__value num">${fmtIDR(total.rata_rata)}</div>
      </div>
    </div>`
}

/** "02 Jul 2026" → "02 Jul" untuk label sumbu-x. */
function shortDate(value) {
  const parts = fmtDate(value).split(' ')
  return parts.length >= 2 ? `${parts[0]} ${parts[1]}` : parts[0]
}

function columnChartHTML(rows) {
  const values = rows.map((r) => Number(r.total_omzet) || 0)
  const max = Math.max(...values)
  const peakIdx = values.indexOf(max)
  const step = rows.length > MAX_AXIS_LABELS ? Math.ceil(rows.length / TARGET_AXIS_LABELS) : 1

  const cells = rows.map((row, i) => {
    const raw = max > 0 ? (values[i] / max) * 100 : 0
    const pct = values[i] > 0 ? Math.max(raw, 1) : 0
    const peakLabel = i === peakIdx && max > 0
      ? `<div class="rpt-chart__peak num">${fmtIDR(values[i])}</div>`
      : ''
    return `
      <div class="rpt-chart__cell" data-idx="${i}" tabindex="0"
           aria-label="${esc(fmtDate(row.tanggal))}: ${fmtIDR(values[i])}">
        ${peakLabel}
        <div class="rpt-chart__bar" style="height:${pct.toFixed(2)}%"></div>
      </div>`
  }).join('')

  const axis = rows.map((row, i) =>
    `<span>${i % step === 0 ? esc(shortDate(row.tanggal)) : ''}</span>`).join('')

  // Label nilai pada gridline (75/50/25% dari puncak) agar bar terbaca tanpa hover
  const gridValues = max > 0
    ? `<div class="rpt-chart__gridvalues num" aria-hidden="true">
        <span>${fmtIDR(max * 0.75)}</span>
        <span>${fmtIDR(max * 0.5)}</span>
        <span>${fmtIDR(max * 0.25)}</span>
      </div>`
    : ''

  return `
    <div class="card rpt-chart">
      <div class="rpt-chart__caption">Omzet per hari</div>
      <div class="rpt-chart__plot">
        <div class="rpt-chart__gridlines" aria-hidden="true"><i></i><i></i><i></i></div>
        ${gridValues}
        <div class="rpt-chart__cells">${cells}</div>
        <div class="rpt-tooltip" hidden></div>
      </div>
      <div class="rpt-chart__axis" aria-hidden="true">${axis}</div>
    </div>`
}

function bindChartTooltip(body, rows) {
  const plot = body.querySelector('.rpt-chart__plot')
  const tip = body.querySelector('.rpt-tooltip')
  if (!plot || !tip) return

  function show(cell) {
    const row = rows[Number(cell.dataset.idx)]
    if (!row) return
    tip.innerHTML = `
      <div class="rpt-tooltip__date">${esc(fmtDate(row.tanggal))}</div>
      <div class="rpt-tooltip__value num">${fmtIDR(row.total_omzet)}</div>`
    tip.hidden = false
    const plotRect = plot.getBoundingClientRect()
    const cellRect = cell.getBoundingClientRect()
    const bar = cell.querySelector('.rpt-chart__bar')
    const barTop = bar ? bar.getBoundingClientRect().top : cellRect.bottom
    tip.style.left = `${cellRect.left - plotRect.left + cellRect.width / 2}px`
    tip.style.top = `${barTop - plotRect.top}px`
  }

  const hide = () => { tip.hidden = true }

  plot.querySelectorAll('.rpt-chart__cell').forEach((cell) => {
    cell.addEventListener('mouseenter', () => show(cell))
    cell.addEventListener('mouseleave', hide)
    cell.addEventListener('focus', () => show(cell))
    cell.addEventListener('blur', hide)
  })
}

function harianTableHTML(rows) {
  const trs = rows.map((r) => `
    <tr>
      <td>${esc(fmtDate(r.tanggal))}</td>
      <td class="num u-right">${fmtNumber(r.jumlah_transaksi)}</td>
      <td class="num u-right">${fmtIDR(r.total_omzet)}</td>
    </tr>`).join('')
  return `
    <div class="table-wrap">
      <table class="table">
        <thead>
          <tr><th>Tanggal</th><th class="u-right">Transaksi</th><th class="u-right">Omzet</th></tr>
        </thead>
        <tbody>${trs}</tbody>
      </table>
    </div>`
}

// ---------- Tab 2: Per Produk ----------

function sortByNilai(rows) {
  return [...rows].sort((a, b) => (Number(b.total_nilai) || 0) - (Number(a.total_nilai) || 0))
}

function renderProduk(body, data) {
  const rows = sortByNilai(Array.isArray(data) ? data : [])
  if (rows.length === 0) {
    body.innerHTML = emptyStateHTML({
      title: 'Belum ada produk terjual',
      desc: 'Tidak ada penjualan produk pada rentang tanggal ini.'
    })
    return
  }
  const max = Number(rows[0].total_nilai) || 0
  const trs = rows.map((r) => {
    const pct = max > 0 ? ((Number(r.total_nilai) || 0) / max) * 100 : 0
    return `
      <tr>
        <td>${esc(r.produk)}</td>
        <td class="num u-right">${fmtNumber(r.qty_terjual)}</td>
        <td class="num u-right">${fmtIDR(r.total_nilai)}</td>
        <td class="rpt-td-contrib">
          <div class="rpt-contrib"><div class="rpt-contrib__fill" style="width:${pct.toFixed(1)}%"></div></div>
        </td>
      </tr>`
  }).join('')
  body.innerHTML = `
    <div class="table-wrap">
      <table class="table">
        <thead>
          <tr>
            <th>Produk</th><th class="u-right">Qty Terjual</th>
            <th class="u-right">Total</th><th class="rpt-td-contrib">Kontribusi</th>
          </tr>
        </thead>
        <tbody>${trs}</tbody>
      </table>
    </div>`
}

// ---------- Tab 3: Stok ----------

function filterStok(rows, query) {
  const q = String(query || '').toLowerCase()
  if (!q) return rows
  return rows.filter((r) =>
    String(r.produk || '').toLowerCase().includes(q) ||
    String(r.kode || '').toLowerCase().includes(q))
}

function stokBadgeHTML(stok) {
  const n = Number(stok) || 0
  if (n <= 0) return '<span class="badge badge--danger">Habis</span>'
  if (n < STOK_BATAS_MENIPIS) return '<span class="badge badge--warn">Menipis</span>'
  return '<span class="badge badge--mint">Aman</span>'
}

function stokTableHTML(rows) {
  if (rows.length === 0) {
    return emptyStateHTML({
      icon: icons.search,
      title: 'Tidak ada produk yang cocok',
      desc: 'Coba kata kunci lain untuk nama atau kode produk.'
    })
  }
  const trs = rows.map((r) => `
    <tr>
      <td class="mono">${esc(r.kode)}</td>
      <td>${esc(r.produk)}</td>
      <td class="num u-right">${fmtNumber(r.stok)}</td>
      <td>${stokBadgeHTML(r.stok)}</td>
    </tr>`).join('')
  return `
    <div class="table-wrap">
      <table class="table">
        <thead>
          <tr><th>Kode</th><th>Produk</th><th class="u-right">Stok</th><th>Status</th></tr>
        </thead>
        <tbody>${trs}</tbody>
      </table>
    </div>`
}

function renderStok(ctx, body, data) {
  const rows = Array.isArray(data) ? data : []
  if (rows.length === 0) {
    body.innerHTML = emptyStateHTML({
      title: 'Tidak ada data stok',
      desc: 'Belum ada produk dengan stok pada gudang yang dipilih.'
    })
    return
  }
  body.innerHTML = `
    <div class="search-box rpt-stok-search">
      <span class="search-box__icon">${icons.search}</span>
      <input class="input" id="rpt-stok-q" type="text" autocomplete="off"
             placeholder="Cari nama atau kode produk…" value="${esc(ctx.stokQuery)}" />
    </div>
    <div id="rpt-stok-table"></div>`

  const tableEl = body.querySelector('#rpt-stok-table')
  const renderTable = () => {
    tableEl.innerHTML = stokTableHTML(filterStok(rows, ctx.stokQuery))
  }
  renderTable()

  const input = body.querySelector('#rpt-stok-q')
  input.addEventListener('input', debounce(() => {
    ctx.stokQuery = input.value.trim()
    renderTable()
  }, SEARCH_DEBOUNCE_MS))
}

// ---------- Tab 4: Rekap Kasir ----------

function sesiBadgeHTML(status) {
  if (status === 'BUKA') return '<span class="badge badge--mint"><span class="badge__dot"></span>Buka</span>'
  if (status === 'TUTUP') return '<span class="badge badge--neutral">Tutup</span>'
  return `<span class="badge badge--neutral">${esc(status || '—')}</span>`
}

function selisihHTML(selisih) {
  if (selisih === null || selisih === undefined) return '<span class="u-muted">—</span>'
  const n = Number(selisih) || 0
  const cls = n < 0 ? ' rpt-neg' : n > 0 ? ' rpt-pos' : ''
  return `<span class="num${cls}">${fmtIDR(n)}</span>`
}

function renderRekap(body, data) {
  const rows = Array.isArray(data) ? data : []
  if (rows.length === 0) {
    body.innerHTML = emptyStateHTML({
      title: 'Belum ada sesi kasir',
      desc: 'Tidak ada sesi kasir pada rentang tanggal ini.'
    })
    return
  }
  const trs = rows.map((r) => `
    <tr>
      <td class="mono">${esc(r.nomor)}</td>
      <td>${sesiBadgeHTML(r.status)}</td>
      <td>${esc(r.kasir || '—')}</td>
      <td class="num u-right">${fmtIDR(r.total_penjualan)}</td>
      <td class="num u-right">${fmtIDR(r.total_tunai)}</td>
      <td class="num u-right">${fmtIDR(r.total_transfer)}</td>
      <td class="num u-right">${fmtIDR(r.total_qris)}</td>
      <td class="u-right">${selisihHTML(r.selisih)}</td>
    </tr>`).join('')
  body.innerHTML = `
    <div class="table-wrap">
      <table class="table">
        <thead>
          <tr>
            <th>Nomor</th><th>Status</th><th>Kasir</th>
            <th class="u-right">Total Penjualan</th><th class="u-right">Tunai</th>
            <th class="u-right">Transfer</th><th class="u-right">QRIS</th>
            <th class="u-right">Selisih</th>
          </tr>
        </thead>
        <tbody>${trs}</tbody>
      </table>
    </div>`
}

// ---------- Ekspor CSV ----------

function csvCell(value) {
  const s = value === null || value === undefined ? '' : String(value)
  return /[",\n\r]/.test(s) ? `"${s.replaceAll('"', '""')}"` : s
}

function downloadCSV(filename, rows) {
  const csv = rows.map((row) => row.map(csvCell).join(',')).join('\r\n')
  // BOM agar Excel membaca UTF-8 dengan benar
  const UTF8_BOM = String.fromCharCode(0xfeff)
  const blob = new Blob([UTF8_BOM + csv], { type: 'text/csv;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const link = document.createElement('a')
  link.href = url
  link.download = filename
  document.body.appendChild(link)
  link.click()
  link.remove()
  setTimeout(() => URL.revokeObjectURL(url), REVOKE_URL_DELAY_MS)
}

function slugify(text) {
  return String(text || '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '') || 'gudang'
}

const CSV_BUILDERS = {
  harian(ctx, data) {
    const rows = Array.isArray(data?.rows) ? data.rows : []
    if (rows.length === 0) return null
    return {
      filename: `penjualan-harian_${ctx.filters.dari}_${ctx.filters.sampai}.csv`,
      rows: [
        ['Tanggal', 'Jumlah Transaksi', 'Total Omzet'],
        ...rows.map((r) => [r.tanggal, r.jumlah_transaksi, r.total_omzet])
      ]
    }
  },
  produk(ctx, data) {
    const rows = sortByNilai(Array.isArray(data) ? data : [])
    if (rows.length === 0) return null
    return {
      filename: `penjualan-produk_${ctx.filters.dari}_${ctx.filters.sampai}.csv`,
      rows: [
        ['Produk', 'Qty Terjual', 'Total Nilai'],
        ...rows.map((r) => [r.produk, r.qty_terjual, r.total_nilai])
      ]
    }
  },
  stok(ctx, data) {
    const rows = filterStok(Array.isArray(data) ? data : [], ctx.stokQuery)
    if (rows.length === 0) return null
    const g = (getState().gudang || []).find((x) => String(x.id) === String(ctx.filters.gudangId))
    const label = ctx.filters.gudangId && g ? slugify(g.nama || g.kode) : 'semua-gudang'
    return {
      filename: `stok_${label}.csv`,
      rows: [['Kode', 'Produk', 'Stok'], ...rows.map((r) => [r.kode, r.produk, r.stok])]
    }
  },
  rekap(ctx, data) {
    const rows = Array.isArray(data) ? data : []
    if (rows.length === 0) return null
    return {
      filename: `rekap-kasir_${ctx.filters.dari}_${ctx.filters.sampai}.csv`,
      rows: [
        ['Nomor', 'Status', 'Kasir', 'Total Penjualan', 'Tunai', 'Transfer', 'QRIS', 'Selisih'],
        ...rows.map((r) => [
          r.nomor, r.status, r.kasir ?? '',
          r.total_penjualan, r.total_tunai, r.total_transfer, r.total_qris,
          r.selisih ?? ''
        ])
      ]
    }
  }
}

function exportActiveTab(ctx) {
  const data = ctx.cache.get(cacheKey(ctx))
  const spec = CSV_BUILDERS[ctx.activeTab](ctx, data)
  if (!spec) {
    toast('Belum ada data untuk diekspor pada tab ini.', 'info')
    return
  }
  downloadCSV(spec.filename, spec.rows)
  toast('File CSV berhasil diunduh.', 'success')
}
