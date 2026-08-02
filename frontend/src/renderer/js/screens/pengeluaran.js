// Layar Pengeluaran (§4.3) — Laporan Keuangan bulan ini (Omset / Pengeluaran /
// Laba dari GET /laporan/keuangan) + input & daftar pengeluaran (server-backed,
// O/M). Uang integer rupiah. Menggantikan versi localStorage sebelumnya.

import { api, firstError } from '../api.js'
import { toast, icons, confirmDialog, emptyStateHTML } from '../components/ui.js'
import { esc, fmtIDR, fmtDate, toISODate, parseAmount } from '../utils/format.js'

const bulanIni = () => toISODate(new Date()).slice(0, 7)

export const PengeluaranScreen = {
  id: 'pengeluaran',
  title: 'Pengeluaran',
  icon: icons.wallet,

  async render(container) {
    const ctx = { container, bulan: bulanIni() }
    renderLayout(ctx)
    bind(ctx)
    await refresh(ctx)
    return () => {}
  }
}

function renderLayout(ctx) {
  ctx.container.innerHTML = `
    <div class="screen-page">
      <div class="page-head">
        <div>
          <h1 class="page-head__title">Laporan Keuangan &amp; Pengeluaran</h1>
          <p class="page-head__desc">Ringkasan omzet, pengeluaran, dan laba bulan berjalan — plus catat pengeluaran.</p>
        </div>
        <div class="field field--inline">
          <label class="field__label" for="ex-bulan">Bulan</label>
          <input type="month" class="input" id="ex-bulan" value="${ctx.bulan}" max="${bulanIni()}" />
        </div>
      </div>

      <div class="rpt-kpis" id="ex-kpis"></div>

      <div class="card keu-form">
        <h2 class="inv-card__title">Catat Pengeluaran Baru</h2>
        <div class="keu-form__grid">
          <div class="field keu-form__note">
            <label class="field__label" for="ex-ket">Keterangan</label>
            <input type="text" class="input" id="ex-ket" placeholder="mis. LISTRIK / GAJI / BELANJA BAHAN" maxlength="120" autocomplete="off" />
          </div>
          <div class="field">
            <label class="field__label" for="ex-nom">Nominal</label>
            <input type="text" inputmode="numeric" class="input" id="ex-nom" placeholder="mis. 350rb / 350000" autocomplete="off" />
          </div>
          <button class="btn btn--primary keu-form__submit" id="ex-add" type="button">${icons.plus}<span>Catat</span></button>
        </div>
      </div>

      <div id="ex-body"></div>
    </div>`
}

function bind(ctx) {
  const c = ctx.container
  c.querySelector('#ex-add').addEventListener('click', () => tambah(ctx))
  c.querySelector('#ex-nom').addEventListener('keydown', (e) => { if (e.key === 'Enter') tambah(ctx) })
  c.querySelector('#ex-bulan').addEventListener('change', (e) => { ctx.bulan = e.target.value || bulanIni(); refresh(ctx) })
}

function kpiCard(label, value, opts = {}) {
  const cls = opts.accent ? ' stat-tile--accent' : ''
  const valCls = opts.danger ? ' inv-jml--out' : (opts.good ? ' inv-jml--in' : '')
  return `
    <div class="stat-tile${cls}">
      <div class="stat-tile__label">${esc(label)}</div>
      <div class="stat-tile__value num${valCls}">${fmtIDR(value)}</div>
      ${opts.sub ? `<div class="stat-tile__sub">${esc(opts.sub)}</div>` : ''}
    </div>`
}

async function refresh(ctx) {
  const c = ctx.container
  const kpis = c.querySelector('#ex-kpis')
  const body = c.querySelector('#ex-body')
  kpis.innerHTML = '<div class="stat-tile"><div class="stat-tile__label">Memuat…</div></div>'

  const [keu, list] = await Promise.all([
    api.laporan.keuangan({ bulan: ctx.bulan }),
    api.pengeluaran.list({ bulan: ctx.bulan })
  ])

  if (keu.ok && keu.data) {
    const d = keu.data
    kpis.innerHTML =
      kpiCard('Total Omzet Bulan Ini', d.omset, { sub: `${d.jumlah_transaksi || 0} transaksi` }) +
      kpiCard('Total Pengeluaran', d.pengeluaran, { danger: (d.pengeluaran || 0) > 0 }) +
      kpiCard('Laba Bersih', d.laba, { accent: true, good: (d.laba || 0) >= 0, danger: (d.laba || 0) < 0 })
  } else {
    kpis.innerHTML = ''
    toast(firstError(keu), 'error')
  }

  if (!list.ok) {
    body.innerHTML = emptyStateHTML({ icon: icons.wallet, title: 'Gagal memuat pengeluaran', desc: firstError(list) })
    return
  }
  const rows = Array.isArray(list.data) ? list.data : []
  const total = list.meta && list.meta.total != null ? list.meta.total : rows.reduce((s, r) => s + (Number(r.nominal) || 0), 0)

  if (rows.length === 0) {
    body.innerHTML = emptyStateHTML({
      icon: icons.wallet,
      title: 'Belum ada pengeluaran bulan ini',
      desc: 'Catat biaya operasional (listrik, gaji, sewa, bahan) di atas untuk menghitung laba bersih.'
    })
    return
  }

  const trs = rows.map((r) => `
    <tr>
      <td>${esc(fmtDate(r.tanggal))}</td>
      <td>${esc(r.keterangan || '—')}</td>
      <td class="num u-right">${fmtIDR(r.nominal)}</td>
      <td class="u-right"><button class="icon-btn keu-del" type="button" data-id="${esc(r.id)}" title="Hapus" aria-label="Hapus">${icons.trash}</button></td>
    </tr>`).join('')

  body.innerHTML = `
    <div class="table-wrap">
      <table class="table">
        <thead><tr><th>Tanggal</th><th>Keterangan</th><th class="u-right">Nominal</th><th></th></tr></thead>
        <tbody>${trs}</tbody>
        <tfoot><tr><td colspan="2" class="u-right"><strong>Total</strong></td><td class="num u-right"><strong>${fmtIDR(total)}</strong></td><td></td></tr></tfoot>
      </table>
    </div>`

  body.querySelectorAll('.keu-del').forEach((btn) => {
    btn.addEventListener('click', async () => {
      const yes = await confirmDialog({ title: 'Hapus pengeluaran?', message: 'Catatan ini akan dihapus permanen.', confirmText: 'Hapus', danger: true })
      if (!yes) return
      const r = await api.pengeluaran.remove({ id: btn.dataset.id })
      if (!r.ok) { toast(firstError(r), 'error'); return }
      toast('Pengeluaran dihapus.', 'info')
      refresh(ctx)
    })
  })
}

async function tambah(ctx) {
  const c = ctx.container
  const keterangan = c.querySelector('#ex-ket').value.trim()
  const nominal = parseAmount(c.querySelector('#ex-nom').value)
  const btn = c.querySelector('#ex-add')
  if (!keterangan) { toast('Isi keterangan pengeluaran.', 'error'); return }
  if (!(nominal > 0)) { toast('Isi nominal yang valid (mis. 350rb).', 'error'); return }

  // Bila bulan tampil bukan bulan berjalan, catat di tanggal 1 bulan itu agar konsisten.
  const tanggal = ctx.bulan === bulanIni() ? toISODate(new Date()) : `${ctx.bulan}-01`
  btn.disabled = true
  const r = await api.pengeluaran.create({ keterangan, nominal, tanggal })
  btn.disabled = false
  if (!r.ok) { toast(firstError(r), 'error'); return }

  c.querySelector('#ex-ket').value = ''
  c.querySelector('#ex-nom').value = ''
  toast(`Pengeluaran ${fmtIDR(nominal)} dicatat.`, 'success')
  refresh(ctx)
}
