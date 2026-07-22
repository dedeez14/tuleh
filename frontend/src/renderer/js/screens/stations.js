// Layar Stasiun — atur titik kerja toko (kasir, dapur, waiter, mesin cuci…).
// Jenis stasiun dibaca dari manifest.station_types; jumlah bebas diatur user.
// Stasiun ISTIRAHAT/NONAKTIF tidak menerima pekerjaan baru (routing Fase 2b).

import { api, firstError } from '../api.js'
import { getState } from '../state.js'
import { esc, fmtNumber } from '../utils/format.js'
import { toast, icons, showModal, confirmDialog, emptyStateHTML, loadingHTML } from '../components/ui.js'

const STATUSES = [
  { id: 'AKTIF', label: 'Aktif' },
  { id: 'ISTIRAHAT', label: 'Istirahat' },
  { id: 'NONAKTIF', label: 'Nonaktif' }
]

// Fallback bila manifest tidak menyertakan station_types
function tipeStasiun(manifest) {
  if (manifest?.stationTypes?.length) return manifest.stationTypes
  const caps = manifest?.capabilities || []
  const jenis = [{ type: 'cashier', label: 'Kasir', min: 1 }]
  if (caps.includes('kitchen')) {
    jenis.push({ type: 'kitchen', label: 'Dapur', min: 1 }, { type: 'waiter', label: 'Waiter', min: 0 })
  }
  if (caps.includes('stages')) {
    jenis.push(
      { type: 'washer', label: 'Mesin Cuci', min: 0 },
      { type: 'dryer', label: 'Pengering', min: 0 },
      { type: 'folder', label: 'Meja Lipat', min: 0 }
    )
  }
  return jenis
}

export const StationsScreen = {
  id: 'stations',
  title: 'Stasiun',
  icon: icons.station,

  async render(container) {
    const { manifest } = getState()
    const jenis = tipeStasiun(manifest)
    let alive = true
    let rows = []

    container.innerHTML = `
      <div class="screen-page">
        <div class="page-head">
          <div>
            <h1 class="page-head__title">Stasiun</h1>
            <p class="page-head__desc">
              Titik kerja toko ini — tambah sesuai kebutuhan dan atur statusnya.
              Stasiun Istirahat/Nonaktif tidak menerima pekerjaan baru.
            </p>
          </div>
        </div>
        <div id="stn-body">${loadingHTML('Memuat stasiun…')}</div>
      </div>`

    const body = container.querySelector('#stn-body')

    function kartuHTML(st) {
      return `
        <div class="stn-item" data-id="${esc(st.id)}">
          <div class="stn-item__info">
            <span class="stn-item__nama">${esc(st.nama)}</span>
            <span class="stn-item__meta">
              ${st.kapasitas ? `<span class="u-faint">kapasitas ${fmtNumber(st.kapasitas)}</span>` : ''}
            </span>
          </div>
          <div class="stn-item__actions">
            <div class="segmented">
              ${STATUSES.map((s) => `
                <button type="button" class="segmented__item${st.status === s.id ? ' is-active' : ''}"
                        data-status="${s.id}">${s.label}</button>`).join('')}
            </div>
            <button type="button" class="icon-btn" data-del title="Hapus stasiun">${icons.trash}</button>
          </div>
        </div>`
    }

    function renderList() {
      body.innerHTML = jenis.map((j) => {
        const isi = rows.filter((s) => s.type === j.type)
        return `
          <section class="stn-group">
            <header class="stn-group__head">
              <span class="stn-group__label">${esc(j.label)}</span>
              <span class="stn-group__count num">${isi.length}</span>
              <button type="button" class="btn btn--outline btn--sm" data-add="${esc(j.type)}"
                      data-label="${esc(j.label)}">
                ${icons.plus}<span>Tambah</span>
              </button>
            </header>
            ${isi.length
              ? `<div class="stn-group__list">${isi.map(kartuHTML).join('')}</div>`
              : `<div class="stn-group__empty">Belum ada ${esc(j.label.toLowerCase())}.</div>`}
          </section>`
      }).join('')
    }

    async function muat() {
      const result = await api.station.list()
      if (!alive) return
      if (!result.ok) {
        body.innerHTML = emptyStateHTML({
          icon: icons.alert,
          title: 'Gagal memuat stasiun',
          desc: firstError(result) || 'Endpoint stasiun belum tersedia di server ini.'
        })
        return
      }
      rows = Array.isArray(result.data) ? result.data : []
      renderList()
    }

    function bukaTambah(type, label) {
      const bodyEl = document.createElement('div')
      bodyEl.innerHTML = `
        <div class="field">
          <label class="field__label" for="stn-nama">Nama stasiun</label>
          <input class="input" id="stn-nama" type="text" maxlength="100"
                 placeholder="mis. ${esc(label)} ${fmtNumber(rows.filter((s) => s.type === type).length + 1)}" />
        </div>
        <div class="field">
          <label class="field__label" for="stn-kap">Kapasitas (opsional)</label>
          <input class="input num" id="stn-kap" type="number" min="1" placeholder="maks pekerjaan bersamaan" />
        </div>
        <div class="field__error u-hidden" id="stn-err"></div>`
      const footer = document.createElement('div')
      footer.innerHTML = `<button type="button" class="btn btn--primary" id="stn-save">Simpan</button>`

      const { close } = showModal({ title: `Tambah ${label}`, body: bodyEl, footer })
      footer.querySelector('#stn-save').addEventListener('click', async (e) => {
        const btn = e.currentTarget
        const nama = bodyEl.querySelector('#stn-nama').value.trim()
        const kapasitas = bodyEl.querySelector('#stn-kap').value
        const errEl = bodyEl.querySelector('#stn-err')
        errEl.classList.add('u-hidden')
        if (!nama) {
          errEl.textContent = 'Nama stasiun wajib diisi.'
          errEl.classList.remove('u-hidden')
          return
        }
        btn.disabled = true
        const result = await api.station.create({ type, nama, kapasitas: kapasitas || undefined })
        if (!result.ok) {
          btn.disabled = false
          errEl.textContent = firstError(result)
          errEl.classList.remove('u-hidden')
          return
        }
        toast(`Stasiun "${nama}" ditambahkan.`, 'success')
        close()
        muat()
      })
    }

    body.addEventListener('click', async (e) => {
      const addBtn = e.target.closest('[data-add]')
      if (addBtn) {
        bukaTambah(addBtn.dataset.add, addBtn.dataset.label)
        return
      }

      const item = e.target.closest('.stn-item')
      if (!item) return
      const id = item.dataset.id
      const st = rows.find((s) => s.id === id)
      if (!st) return

      const statusBtn = e.target.closest('[data-status]')
      if (statusBtn && statusBtn.dataset.status !== st.status) {
        const result = await api.station.update({ id, status: statusBtn.dataset.status })
        if (!alive) return
        if (!result.ok) {
          toast(firstError(result), 'error')
          return
        }
        muat()
        return
      }

      if (e.target.closest('[data-del]')) {
        const yes = await confirmDialog({
          title: `Hapus "${st.nama}"?`,
          message: 'Stasiun akan dihapus dari toko ini.',
          confirmText: 'Hapus',
          danger: true
        })
        if (!yes || !alive) return
        const result = await api.station.remove({ id })
        if (!result.ok) {
          toast(firstError(result), 'error')
          return
        }
        toast(`Stasiun "${st.nama}" dihapus.`, 'success')
        muat()
      }
    })

    await muat()

    return () => {
      alive = false
    }
  }
}
