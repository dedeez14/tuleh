// Layar Pelanggan — cari, lihat detail, dan tambah pelanggan walk-in.

import { api, firstError } from '../api.js'
import { esc, debounce, fmtNumber } from '../utils/format.js'
import { toast, icons, showModal, emptyStateHTML, loadingHTML } from '../components/ui.js'

const SEARCH_DEBOUNCE_MS = 250

export const CustomersScreen = {
  id: 'customers',
  title: 'Pelanggan',
  icon: icons.user,

  async render(container) {
    let alive = true
    let rows = []
    let seq = 0
    let lastQuery = ''

    container.innerHTML = `
      <div class="screen-page">
        <div class="page-head">
          <div>
            <h1 class="page-head__title">Pelanggan</h1>
            <p class="page-head__desc">Daftar pelanggan toko — cari atau tambahkan yang baru.</p>
          </div>
          <button type="button" class="btn btn--primary" id="cst-add">
            ${icons.plus}<span>Tambah Pelanggan</span>
          </button>
        </div>

        <div class="card cst-filter">
          <div class="search-box u-grow">
            <span class="search-box__icon">${icons.search}</span>
            <input class="input" id="cst-q" type="text" placeholder="Cari nama atau telepon…" autocomplete="off" />
          </div>
          <span class="u-muted" id="cst-total"></span>
        </div>

        <div id="cst-body">${loadingHTML('Memuat pelanggan…')}</div>
      </div>`

    const body = container.querySelector('#cst-body')
    const totalEl = container.querySelector('#cst-total')

    function renderRows() {
      totalEl.textContent = `${fmtNumber(rows.length)} pelanggan`
      if (!rows.length) {
        // Bedakan kondisi kosong: belum ada data vs hasil pencarian nihil.
        body.innerHTML = lastQuery
          ? emptyStateHTML({
            icon: icons.user,
            title: 'Pelanggan tidak ditemukan',
            desc: 'Coba kata kunci lain, atau tambahkan pelanggan baru.'
          })
          : emptyStateHTML({
            icon: icons.user,
            title: 'Belum ada pelanggan',
            desc: 'Tambahkan pelanggan pertama lewat tombol "Tambah Pelanggan".'
          })
        return
      }
      body.innerHTML = `
        <div class="table-wrap">
          <table class="table">
            <thead>
              <tr><th>Kode</th><th>Nama</th><th>Telepon</th></tr>
            </thead>
            <tbody>
              ${rows.map((c) => `
                <tr class="is-clickable" data-id="${esc(c.id)}" tabindex="0">
                  <td class="mono">${esc(c.kode || '—')}</td>
                  <td class="cst-nama">${esc(c.nama)}</td>
                  <td>${c.telepon ? `<span class="mono">${esc(c.telepon)}</span>` : '<span class="u-faint">—</span>'}</td>
                </tr>`).join('')}
            </tbody>
          </table>
        </div>`
    }

    async function muat(q = '') {
      const s = ++seq
      lastQuery = q
      const result = await api.pelanggan.list({ q: q || undefined })
      if (!alive || s !== seq) return
      if (!result.ok) {
        body.innerHTML = emptyStateHTML({ icon: icons.alert, title: 'Gagal memuat pelanggan', desc: firstError(result) })
        return
      }
      rows = Array.isArray(result.data) ? result.data : []
      renderRows()
    }

    function bukaTambah() {
      const bodyEl = document.createElement('div')
      bodyEl.innerHTML = `
        <div class="field">
          <label class="field__label" for="cst-nama-in">Nama <span class="u-faint">*</span></label>
          <input class="input" id="cst-nama-in" type="text" maxlength="150" />
        </div>
        <div class="field">
          <label class="field__label" for="cst-telp-in">Telepon (opsional)</label>
          <input class="input" id="cst-telp-in" type="tel" maxlength="30" />
        </div>
        <div class="field">
          <label class="field__label" for="cst-alamat-in">Alamat (opsional)</label>
          <textarea class="textarea" id="cst-alamat-in" rows="2" maxlength="500"></textarea>
        </div>
        <div class="field__error u-hidden" id="cst-err"></div>`
      const footer = document.createElement('div')
      footer.innerHTML = `<button type="button" class="btn btn--primary" id="cst-save">Simpan</button>`

      const { close } = showModal({ title: 'Tambah Pelanggan', body: bodyEl, footer })
      footer.querySelector('#cst-save').addEventListener('click', async (e) => {
        const btn = e.currentTarget
        const nama = bodyEl.querySelector('#cst-nama-in').value.trim()
        const telepon = bodyEl.querySelector('#cst-telp-in').value.trim()
        const alamat = bodyEl.querySelector('#cst-alamat-in').value.trim()
        const errEl = bodyEl.querySelector('#cst-err')
        errEl.classList.add('u-hidden')
        if (!nama) {
          errEl.textContent = 'Nama pelanggan wajib diisi.'
          errEl.classList.remove('u-hidden')
          return
        }
        btn.disabled = true
        const result = await api.pelanggan.create({
          nama,
          telepon: telepon || undefined,
          alamat: alamat || undefined
        })
        if (!result.ok) {
          btn.disabled = false
          errEl.textContent = firstError(result)
          errEl.classList.remove('u-hidden')
          return
        }
        toast(`Pelanggan "${nama}" ditambahkan.`, 'success')
        close()
        muat(container.querySelector('#cst-q').value.trim())
      })
    }

    async function bukaDetail(id) {
      const bodyEl = document.createElement('div')
      bodyEl.innerHTML = loadingHTML('Memuat detail…')
      showModal({ title: 'Detail Pelanggan', body: bodyEl })
      const result = await api.pelanggan.detail({ id })
      if (!result.ok || !result.data) {
        bodyEl.innerHTML = emptyStateHTML({
          icon: icons.alert,
          title: 'Detail tidak dapat dimuat',
          desc: result.ok ? 'Pelanggan tidak ditemukan.' : firstError(result)
        })
        return
      }
      const c = result.data
      bodyEl.innerHTML = `
        <div class="cst-detail">
          <div><span>Kode</span><span class="mono">${esc(c.kode || '—')}</span></div>
          <div><span>Nama</span><span>${esc(c.nama)}</span></div>
          <div><span>Telepon</span><span class="mono">${esc(c.telepon || '—')}</span></div>
          ${c.alamat ? `<div><span>Alamat</span><span>${esc(c.alamat)}</span></div>` : ''}
        </div>`
    }

    container.querySelector('#cst-add').addEventListener('click', bukaTambah)

    container.querySelector('#cst-q').addEventListener('input', debounce((e) => {
      if (alive) muat(e.target.value.trim())
    }, SEARCH_DEBOUNCE_MS))

    body.addEventListener('click', (e) => {
      const tr = e.target.closest('tr[data-id]')
      if (tr) bukaDetail(tr.dataset.id)
    })

    body.addEventListener('keydown', (e) => {
      if (e.key !== 'Enter') return
      const tr = e.target.closest('tr[data-id]')
      if (tr) bukaDetail(tr.dataset.id)
    })

    await muat()

    return () => {
      alive = false
    }
  }
}
