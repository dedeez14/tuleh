// Layar Produk — jelajah katalog (read-only sesuai API MOVERA):
// pencarian, filter kategori, paginasi, dan detail produk bergambar.

import { api, firstError } from '../api.js'
import { getState } from '../state.js'
import { esc, fmtIDR, fmtNumber, debounce } from '../utils/format.js'
import { toast, icons, showModal, emptyStateHTML, loadingHTML } from '../components/ui.js'

const PER_PAGE = 50
const SEARCH_DEBOUNCE_MS = 250
const BATAS_MENIPIS = 5

function stokBadge(p) {
  if (!p.kelola_stok) return '<span class="u-faint" title="Stok produk ini tidak dikelola">—</span>'
  const stok = Number(p.stok) || 0
  if (stok <= 0) return '<span class="badge badge--danger">Habis</span>'
  if (stok < BATAS_MENIPIS) return `<span class="badge badge--warn">${fmtNumber(stok)}</span>`
  return `<span class="num">${fmtNumber(stok)}</span>`
}

export const ProductsScreen = {
  id: 'products',
  title: 'Produk',
  icon: icons.box,

  async render(container) {
    const kategori = getState().kategori || []
    let alive = true
    let query = ''
    let kategoriId = ''
    let rows = []
    let meta = null
    let seq = 0

    container.innerHTML = `
      <div class="screen-page">
        <div class="page-head">
          <div>
            <h1 class="page-head__title">Produk</h1>
            <p class="page-head__desc">Jelajahi katalog — harga, barcode, dan posisi stok.</p>
          </div>
          <span class="prd-total u-muted" id="prd-total"></span>
        </div>

        <div class="card prd-filter">
          <div class="search-box u-grow">
            <span class="search-box__icon">${icons.search}</span>
            <input class="input" id="prd-q" type="text" placeholder="Cari nama / kode / barcode…" autocomplete="off" />
          </div>
          <select class="select prd-filter__kat" id="prd-kat">
            <option value="">Semua kategori</option>
            ${kategori.map((k) => `<option value="${esc(k.id)}">${esc(k.nama)}</option>`).join('')}
          </select>
        </div>

        <div id="prd-body">${loadingHTML('Memuat produk…')}</div>
      </div>`

    const body = container.querySelector('#prd-body')
    const totalEl = container.querySelector('#prd-total')

    function barisHTML(p) {
      return `
        <tr class="is-clickable" data-id="${esc(p.id)}" tabindex="0">
          <td class="mono">${esc(p.kode)}</td>
          <td>
            <div class="prd-nama">${esc(p.nama)}</div>
            ${p.barcode ? `<div class="prd-barcode mono">${esc(p.barcode)}</div>` : ''}
          </td>
          <td>${esc(p.kategori || '—')}</td>
          <td>${esc(p.satuan || '—')}</td>
          <td class="num u-right">${fmtIDR(p.harga_jual)}</td>
          <td class="u-right">${stokBadge(p)}</td>
        </tr>`
    }

    function renderRows() {
      totalEl.textContent = meta ? `${fmtNumber(meta.total)} produk` : ''
      if (!rows.length) {
        body.innerHTML = emptyStateHTML({
          icon: icons.box,
          title: 'Produk tidak ditemukan',
          desc: query ? `Tidak ada yang cocok dengan "${query}".` : 'Belum ada produk pada kategori ini.'
        })
        return
      }
      const hasMore = meta && Number(meta.current_page) < Number(meta.last_page)
      body.innerHTML = `
        <div class="table-wrap">
          <table class="table">
            <thead>
              <tr>
                <th>Kode</th><th>Nama</th><th>Kategori</th><th>Satuan</th>
                <th class="u-right">Harga</th><th class="u-right">Stok</th>
              </tr>
            </thead>
            <tbody>${rows.map(barisHTML).join('')}</tbody>
          </table>
        </div>
        ${hasMore ? `
          <div class="prd-more">
            <button type="button" class="btn btn--outline" id="prd-more">Muat lebih banyak</button>
            <span class="u-faint">${fmtNumber(rows.length)} dari ${fmtNumber(meta.total)}</span>
          </div>` : ''}`
    }

    async function muat({ append = false } = {}) {
      const s = ++seq
      const page = append && meta ? Number(meta.current_page) + 1 : 1
      if (!append) body.innerHTML = loadingHTML('Memuat produk…')

      const result = await api.produk.list({
        q: query || undefined,
        kategoriId: kategoriId || undefined,
        gudangId: getState().session?.gudang_id,
        perPage: PER_PAGE,
        page
      })
      if (!alive || s !== seq) return
      if (!result.ok) {
        body.innerHTML = emptyStateHTML({ icon: icons.alert, title: 'Gagal memuat produk', desc: firstError(result) })
        return
      }
      meta = result.meta || null
      rows = append ? [...rows, ...(result.data || [])] : (result.data || [])
      renderRows()
    }

    function bukaDetail(p) {
      const inisial = (p.nama || '?').trim().split(/\s+/).slice(0, 2).map((w) => w[0]).join('').toUpperCase()
      const bodyEl = document.createElement('div')
      bodyEl.className = 'prd-detail'
      bodyEl.innerHTML = `
        <div class="prd-detail__media">
          ${p.gambar
            ? `<img src="${esc(p.gambar)}" alt="" loading="lazy" />`
            : `<div class="prd-detail__initial">${esc(inisial)}</div>`}
        </div>
        <div class="prd-detail__info">
          <div class="prd-detail__harga num">${fmtIDR(p.harga_jual)}</div>
          <div class="prd-detail__rows">
            <div><span>Kode</span><span class="mono">${esc(p.kode)}</span></div>
            <div><span>Barcode</span><span class="mono">${esc(p.barcode || '—')}</span></div>
            <div><span>Kategori</span><span>${esc(p.kategori || '—')}</span></div>
            <div><span>Satuan</span><span>${esc(p.satuan || '—')}</span></div>
            <div><span>Pajak</span><span class="num">${fmtNumber(p.pajak_persen || 0)}%</span></div>
            <div><span>Stok</span><span>${p.kelola_stok ? `${fmtNumber(p.stok)} (FIFO)` : 'Tidak dikelola'}</span></div>
          </div>
        </div>`
      showModal({ title: p.nama, body: bodyEl, size: 'md' })
    }

    container.querySelector('#prd-q').addEventListener('input', debounce((e) => {
      if (!alive) return
      const value = e.target.value.trim()
      if (value === query) return
      query = value
      muat()
    }, SEARCH_DEBOUNCE_MS))

    container.querySelector('#prd-kat').addEventListener('change', (e) => {
      kategoriId = e.target.value
      muat()
    })

    body.addEventListener('click', (e) => {
      if (e.target.closest('#prd-more')) {
        muat({ append: true })
        return
      }
      const tr = e.target.closest('tr[data-id]')
      if (!tr) return
      const p = rows.find((x) => String(x.id) === tr.dataset.id)
      if (p) bukaDetail(p)
    })

    body.addEventListener('keydown', (e) => {
      if (e.key !== 'Enter') return
      const tr = e.target.closest('tr[data-id]')
      if (!tr) return
      const p = rows.find((x) => String(x.id) === tr.dataset.id)
      if (p) bukaDetail(p)
    })

    await muat()

    return () => {
      alive = false
    }
  }
}
