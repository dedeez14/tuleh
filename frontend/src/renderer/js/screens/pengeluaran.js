// Layar Pengeluaran — catat biaya operasional (sewa, gaji, listrik, bahan, dll.)
// Disimpan lokal per toko (localStorage) sampai server MOVERA punya /pengeluaran.
// Menjadi fondasi Laba Rugi & Dashboard Keuangan.

import { getState } from '../state.js'
import { toast, icons, confirmDialog, emptyStateHTML } from '../components/ui.js'
import { esc, fmtIDR, fmtDate, toISODate, daysAgo, parseAmount } from '../utils/format.js'
import {
  KATEGORI_PENGELUARAN, labelKategori, ringkasPengeluaran,
  addPengeluaran, removePengeluaran, seedDemoKeuangan
} from '../lib/keuangan-store.js'

const RANGE_DAYS = 6 // 7 hari

export const PengeluaranScreen = {
  id: 'pengeluaran',
  title: 'Pengeluaran',
  icon: icons.wallet,

  async render(container) {
    const tokoId = getState().toko?.id || 'default'
    seedDemoKeuangan(tokoId) // contoh utk toko demo (idempoten)

    const ctx = {
      container, tokoId,
      dari: toISODate(daysAgo(RANGE_DAYS)),
      sampai: toISODate(new Date())
    }
    renderLayout(ctx)
    bind(ctx)
    refresh(ctx)
    return () => {}
  }
}

function renderLayout(ctx) {
  const hariIni = toISODate(new Date())
  ctx.container.innerHTML = `
    <div class="screen-page">
      <div class="page-head">
        <div>
          <h1 class="page-head__title">Pengeluaran</h1>
          <p class="page-head__desc">Catat biaya operasional agar laba bersih terhitung benar.</p>
        </div>
      </div>

      <div class="card keu-form">
        <div class="keu-form__grid">
          <div class="field">
            <label class="field__label" for="ex-tgl">Tanggal</label>
            <input type="date" class="input" id="ex-tgl" value="${hariIni}" max="${hariIni}" />
          </div>
          <div class="field">
            <label class="field__label" for="ex-kat">Kategori</label>
            <select class="select" id="ex-kat">
              ${KATEGORI_PENGELUARAN.map((k) => `<option value="${k.kode}">${esc(k.label)}</option>`).join('')}
            </select>
          </div>
          <div class="field">
            <label class="field__label" for="ex-nom">Nominal</label>
            <input type="text" inputmode="numeric" class="input" id="ex-nom" placeholder="mis. 50rb / 50000" autocomplete="off" />
          </div>
          <div class="field keu-form__note">
            <label class="field__label" for="ex-cat">Catatan (opsional)</label>
            <input type="text" class="input" id="ex-cat" placeholder="mis. beli daging & bumbu" maxlength="120" autocomplete="off" />
          </div>
          <button class="btn btn--primary keu-form__submit" id="ex-add" type="button">${icons.plus}<span>Catat</span></button>
        </div>
      </div>

      <div class="rpt-filters">
        <div class="rpt-filters__dates">
          <div class="rpt-filters__group">
            <label class="rpt-filters__label" for="ex-dari">Dari</label>
            <input type="date" class="input" id="ex-dari" value="${ctx.dari}" />
          </div>
          <div class="rpt-filters__group">
            <label class="rpt-filters__label" for="ex-sampai">Sampai</label>
            <input type="date" class="input" id="ex-sampai" value="${ctx.sampai}" />
          </div>
          <button class="btn btn--outline" id="ex-apply" type="button">Terapkan</button>
        </div>
      </div>

      <div id="ex-body"></div>
    </div>`
}

function bind(ctx) {
  const c = ctx.container
  c.querySelector('#ex-add').addEventListener('click', () => tambah(ctx))
  c.querySelector('#ex-nom').addEventListener('keydown', (e) => { if (e.key === 'Enter') tambah(ctx) })
  c.querySelector('#ex-apply').addEventListener('click', () => {
    const dari = c.querySelector('#ex-dari').value
    const sampai = c.querySelector('#ex-sampai').value
    if (!dari || !sampai) { toast('Lengkapi tanggal Dari dan Sampai.', 'error'); return }
    if (dari > sampai) { toast('Tanggal "Dari" tidak boleh melewati "Sampai".', 'error'); return }
    ctx.dari = dari; ctx.sampai = sampai; refresh(ctx)
  })
}

function tambah(ctx) {
  const c = ctx.container
  const tanggal = c.querySelector('#ex-tgl').value
  const kategori = c.querySelector('#ex-kat').value
  const nominal = parseAmount(c.querySelector('#ex-nom').value)
  const catatan = c.querySelector('#ex-cat').value.trim()
  if (!tanggal) { toast('Pilih tanggal.', 'error'); return }
  if (!(nominal > 0)) { toast('Isi nominal yang valid (mis. 50rb).', 'error'); return }
  addPengeluaran(ctx.tokoId, { tanggal, kategori, nominal, catatan })
  c.querySelector('#ex-nom').value = ''
  c.querySelector('#ex-cat').value = ''
  toast(`Pengeluaran ${fmtIDR(nominal)} dicatat.`, 'success')
  // Pastikan rentang mencakup tanggal baru agar langsung tampil
  if (tanggal < ctx.dari) { ctx.dari = tanggal; c.querySelector('#ex-dari').value = tanggal }
  if (tanggal > ctx.sampai) { ctx.sampai = tanggal; c.querySelector('#ex-sampai').value = tanggal }
  refresh(ctx)
}

function refresh(ctx) {
  const body = ctx.container.querySelector('#ex-body')
  const { total, perKategori, rows } = ringkasPengeluaran(ctx.tokoId, { dari: ctx.dari, sampai: ctx.sampai })

  const ringkas = `
    <div class="rpt-kpis">
      <div class="stat-tile stat-tile--accent">
        <div class="stat-tile__label">Total pengeluaran</div>
        <div class="stat-tile__value num">${fmtIDR(total)}</div>
        <div class="stat-tile__sub">${rows.length} catatan · ${esc(fmtDate(ctx.dari))} – ${esc(fmtDate(ctx.sampai))}</div>
      </div>
      ${perKategori.slice(0, 3).map((k) => `
        <div class="stat-tile">
          <div class="stat-tile__label">${esc(k.label)}</div>
          <div class="stat-tile__value num">${fmtIDR(k.total)}</div>
        </div>`).join('')}
    </div>`

  if (rows.length === 0) {
    body.innerHTML = ringkas + emptyStateHTML({
      icon: icons.wallet,
      title: 'Belum ada pengeluaran',
      desc: 'Catat biaya operasional (sewa, gaji, listrik, bahan) di atas untuk mulai menghitung laba bersih.'
    })
    return
  }

  const trs = rows.map((r) => `
    <tr>
      <td>${esc(fmtDate(r.tanggal))}</td>
      <td><span class="badge badge--neutral">${esc(labelKategori(r.kategori))}</span></td>
      <td>${esc(r.catatan || '—')}</td>
      <td class="num u-right">${fmtIDR(r.nominal)}</td>
      <td class="u-right">
        <button class="icon-btn keu-del" type="button" data-id="${esc(r.id)}" title="Hapus" aria-label="Hapus">${icons.trash}</button>
      </td>
    </tr>`).join('')

  body.innerHTML = ringkas + `
    <div class="table-wrap">
      <table class="table">
        <thead><tr><th>Tanggal</th><th>Kategori</th><th>Catatan</th><th class="u-right">Nominal</th><th></th></tr></thead>
        <tbody>${trs}</tbody>
      </table>
    </div>`

  body.querySelectorAll('.keu-del').forEach((btn) => {
    btn.addEventListener('click', async () => {
      const ok = await confirmDialog({ title: 'Hapus pengeluaran?', message: 'Catatan ini akan dihapus permanen.', confirmText: 'Hapus', danger: true })
      if (!ok) return
      removePengeluaran(ctx.tokoId, btn.dataset.id)
      toast('Pengeluaran dihapus.', 'info')
      refresh(ctx)
    })
  })
}
