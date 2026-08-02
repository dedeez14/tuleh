// Layar Produk & Jasa (§4.1) — manajemen katalog utk OWNER/MANAGER (tabel Nama
// Item, Tipe, Harga Beli, Harga Jual, Stok, Aksi) + tambah/edit/nonaktif. KASIR
// melihat read-only (server menull-kan harga_beli & menolak aksi dgn 403).
// Selalu memuat ?tipe=SEMUA&include_habis=1 (jasa & item berstok-0 ikut tampil).

import { api, firstError } from '../api.js'
import { getState } from '../state.js'
import { esc, fmtIDR, fmtNumber, debounce, parseAmount } from '../utils/format.js'
import { toast, icons, showModal, emptyStateHTML, loadingHTML, confirmDialog } from '../components/ui.js'

const PER_PAGE = 50
const SEARCH_DEBOUNCE_MS = 250
const BATAS_MENIPIS = 5

function stokBadge(p) {
  if (p.tipe === 'JASA' || !p.kelola_stok) return '<span class="u-faint" title="Tidak dikelola stok">—</span>'
  const stok = Number(p.stok) || 0
  if (stok <= 0) return '<span class="badge badge--danger">Habis</span>'
  if (stok < BATAS_MENIPIS) return `<span class="badge badge--warn">${fmtNumber(stok)}</span>`
  return `<span class="num">${fmtNumber(stok)}</span>`
}

function tipeBadge(p) {
  return p.tipe === 'JASA'
    ? '<span class="badge badge--info">JASA</span>'
    : '<span class="badge badge--mint">PRODUK</span>'
}

export const ProductsScreen = {
  id: 'products',
  title: 'Produk & Jasa',
  icon: icons.box,

  async render(container) {
    const kategori = getState().kategori || []
    const posRole = getState().posRole
    const canManage = !posRole || posRole === 'OWNER' || posRole === 'MANAGER'
    const showBeli = canManage // harga_beli null utk KASIR → kolom disembunyikan

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
            <h1 class="page-head__title">Produk &amp; Jasa</h1>
            <p class="page-head__desc">${canManage ? 'Kelola katalog: tambah, ubah harga, atau nonaktifkan item.' : 'Katalog toko — harga & posisi stok.'}</p>
          </div>
          ${canManage ? `<button type="button" class="btn btn--primary" id="prd-add">${icons.plus}<span>Tambah Produk / Jasa</span></button>` : '<span class="prd-total u-muted" id="prd-total"></span>'}
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

        <div id="prd-body">${loadingHTML('Memuat katalog…')}</div>
      </div>`

    const body = container.querySelector('#prd-body')

    function barisHTML(p) {
      return `
        <tr data-id="${esc(p.id)}">
          <td>
            <div class="prd-nama">${esc(p.nama)}</div>
            <div class="prd-barcode mono">${esc(p.kode || '')}${p.barcode ? ` · ${esc(p.barcode)}` : ''}</div>
          </td>
          <td>${tipeBadge(p)}</td>
          ${showBeli ? `<td class="num u-right">${p.harga_beli != null ? fmtIDR(p.harga_beli) : '—'}</td>` : ''}
          <td class="num u-right">${fmtIDR(p.harga_jual)}</td>
          <td class="u-right">${stokBadge(p)}</td>
          ${canManage ? `<td class="u-right prd-aksi">
            <button class="btn btn--ghost btn--sm" data-edit="${esc(p.id)}">Edit</button>
            <button class="icon-btn" data-del="${esc(p.id)}" title="Nonaktifkan" aria-label="Nonaktifkan">${icons.trash}</button>
          </td>` : ''}
        </tr>`
    }

    function renderRows() {
      const totalEl = container.querySelector('#prd-total')
      if (totalEl) totalEl.textContent = meta ? `${fmtNumber(meta.total)} item` : ''
      if (!rows.length) {
        body.innerHTML = emptyStateHTML({
          icon: icons.box,
          title: 'Belum ada item',
          desc: query ? `Tidak ada yang cocok dengan "${query}".` : (canManage ? 'Tambahkan produk atau jasa pertama Anda.' : 'Katalog masih kosong.')
        })
        return
      }
      const hasMore = meta && Number(meta.current_page) < Number(meta.last_page)
      const cols = ['<th>Nama Item</th>', '<th>Tipe</th>', showBeli ? '<th class="u-right">Harga Beli</th>' : '', '<th class="u-right">Harga Jual</th>', '<th class="u-right">Stok</th>', canManage ? '<th class="u-right">Aksi</th>' : ''].join('')
      body.innerHTML = `
        <div class="table-wrap">
          <table class="table">
            <thead><tr>${cols}</tr></thead>
            <tbody>${rows.map(barisHTML).join('')}</tbody>
          </table>
        </div>
        ${hasMore ? `<div class="prd-more"><button type="button" class="btn btn--outline" id="prd-more">Muat lebih banyak</button><span class="u-faint">${fmtNumber(rows.length)} dari ${fmtNumber(meta.total)}</span></div>` : ''}`
    }

    async function muat({ append = false } = {}) {
      const s = ++seq
      const page = append && meta ? Number(meta.current_page) + 1 : 1
      if (!append) body.innerHTML = loadingHTML('Memuat katalog…')
      const result = await api.produk.list({
        q: query || undefined,
        kategoriId: kategoriId || undefined,
        tipe: 'SEMUA',        // §4.1: sertakan JASA
        includeHabis: true,   // §4.1: sertakan item berstok 0
        perPage: PER_PAGE,
        page
      })
      if (!alive || s !== seq) return
      if (!result.ok) {
        body.innerHTML = emptyStateHTML({ icon: icons.alert, title: 'Gagal memuat katalog', desc: firstError(result) })
        return
      }
      meta = result.meta || null
      rows = append ? [...rows, ...(result.data || [])] : (result.data || [])
      renderRows()
    }

    function bukaForm(existing) {
      const isEdit = !!existing
      const cur = existing || { tipe: 'PRODUK', kelola_stok: true }
      const formEl = document.createElement('div')
      formEl.className = 'prd-form'
      formEl.innerHTML = `
        <div class="field"><label class="field__label" for="pf-nama">Nama Item</label><input class="input" id="pf-nama" maxlength="120" value="${esc(cur.nama || '')}" placeholder="mis. Kopi Susu" /></div>
        <div class="field"><label class="field__label" for="pf-tipe">Tipe</label>
          <select class="select" id="pf-tipe" ${isEdit ? 'disabled' : ''}>
            <option value="PRODUK" ${cur.tipe !== 'JASA' ? 'selected' : ''}>Produk (barang berstok)</option>
            <option value="JASA" ${cur.tipe === 'JASA' ? 'selected' : ''}>Jasa (layanan, tanpa stok)</option>
          </select>
        </div>
        <div class="prd-form__row">
          <div class="field" id="pf-beli-wrap"><label class="field__label" for="pf-beli">Harga Beli</label><input class="input" inputmode="numeric" id="pf-beli" value="${cur.harga_beli != null ? cur.harga_beli : ''}" placeholder="mis. 8rb" /></div>
          <div class="field"><label class="field__label" for="pf-jual">Harga Jual</label><input class="input" inputmode="numeric" id="pf-jual" value="${cur.harga_jual != null ? cur.harga_jual : ''}" placeholder="mis. 12rb" /></div>
        </div>
        <div class="field" id="pf-barcode-wrap"><label class="field__label" for="pf-barcode">Barcode (opsional)</label><input class="input" id="pf-barcode" maxlength="60" value="${esc(cur.barcode || '')}" /></div>
        <label class="prd-form__check" id="pf-kelola-wrap"><input type="checkbox" id="pf-kelola" ${cur.kelola_stok !== false ? 'checked' : ''} /> <span>Kelola stok barang ini</span></label>`

      const footer = `<button class="btn btn--ghost" data-modal-close type="button">Batal</button><button class="btn btn--primary" id="pf-save" type="button">${isEdit ? 'Simpan' : 'Tambah'}</button>`
      const modal = showModal({ title: isEdit ? 'Edit Item' : 'Tambah Produk / Jasa', body: formEl, footer, size: 'md' })

      const tipeEl = formEl.querySelector('#pf-tipe')
      const syncTipe = () => {
        const jasa = tipeEl.value === 'JASA'
        formEl.querySelector('#pf-beli-wrap').style.display = jasa ? 'none' : ''
        formEl.querySelector('#pf-barcode-wrap').style.display = jasa ? 'none' : ''
        formEl.querySelector('#pf-kelola-wrap').style.display = jasa ? 'none' : ''
      }
      tipeEl.addEventListener('change', syncTipe); syncTipe()

      modal.el.querySelector('#pf-save').addEventListener('click', async () => {
        const nama = formEl.querySelector('#pf-nama').value.trim()
        const tipe = tipeEl.value
        const jual = parseAmount(formEl.querySelector('#pf-jual').value)
        const jasa = tipe === 'JASA'
        const beli = jasa ? null : parseAmount(formEl.querySelector('#pf-beli').value)
        const barcode = jasa ? '' : formEl.querySelector('#pf-barcode').value.trim()
        const kelola = jasa ? false : formEl.querySelector('#pf-kelola').checked
        if (!nama) { toast('Isi nama item.', 'error'); return }
        if (!(jual > 0)) { toast('Isi harga jual yang valid.', 'error'); return }

        let r
        if (isEdit) {
          const patch = { id: existing.id } // kirim HANYA yang berubah
          if (nama !== existing.nama) patch.nama = nama
          if (jual !== existing.harga_jual) patch.hargaJual = jual
          if (!jasa && beli !== existing.harga_beli) patch.hargaBeli = beli
          if (!jasa && barcode !== (existing.barcode || '')) patch.barcode = barcode
          if (!jasa && kelola !== existing.kelola_stok) patch.kelolaStok = kelola
          r = await api.produk.update(patch)
        } else {
          r = await api.produk.create({ nama, tipe, hargaBeli: beli, hargaJual: jual, barcode, kelolaStok: kelola })
        }
        if (!r.ok) { toast(firstError(r), 'error'); return }
        toast(isEdit ? 'Item diperbarui.' : `"${nama}" ditambahkan.`, 'success')
        modal.close()
        muat()
      })
    }

    async function hapus(p) {
      const yes = await confirmDialog({
        title: 'Nonaktifkan item?',
        message: `"${p.nama}" akan dinonaktifkan (bukan dihapus permanen) — riwayat penjualan tetap utuh.`,
        confirmText: 'Nonaktifkan', danger: true
      })
      if (!yes) return
      const r = await api.produk.remove({ id: p.id })
      if (!r.ok) { toast(firstError(r), 'error'); return }
      toast('Item dinonaktifkan.', 'info')
      muat()
    }

    container.querySelector('#prd-q').addEventListener('input', debounce((e) => {
      if (!alive) return
      const value = e.target.value.trim()
      if (value === query) return
      query = value
      muat()
    }, SEARCH_DEBOUNCE_MS))

    container.querySelector('#prd-kat').addEventListener('change', (e) => { kategoriId = e.target.value; muat() })
    const addBtn = container.querySelector('#prd-add')
    if (addBtn) addBtn.addEventListener('click', () => bukaForm(null))

    body.addEventListener('click', (e) => {
      if (e.target.closest('#prd-more')) { muat({ append: true }); return }
      const editBtn = e.target.closest('[data-edit]')
      if (editBtn) { const p = rows.find((x) => String(x.id) === editBtn.dataset.edit); if (p) bukaForm(p); return }
      const delBtn = e.target.closest('[data-del]')
      if (delBtn) { const p = rows.find((x) => String(x.id) === delBtn.dataset.del); if (p) hapus(p) }
    })

    await muat()
    return () => { alive = false }
  }
}
