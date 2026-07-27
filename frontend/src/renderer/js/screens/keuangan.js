// Layar Keuangan — dashboard analisis keuangan UMKM: KPI omzet/laba/margin,
// Laba Rugi (Omzet − HPP − Biaya), rincian metode bayar, pengeluaran per
// kategori, produk terlaris, tren omzet, editor modal (HPP), ekspor PDF & WA.
// Menggabungkan data server (/laporan/*) + Pengeluaran & HPP lokal (localStorage).

import { api, firstError } from '../api.js'
import { getState } from '../state.js'
import { toast, icons, loadingHTML } from '../components/ui.js'
import { esc, fmtIDR, fmtNumber, fmtDate, toISODate, daysAgo } from '../utils/format.js'
import {
  ringkasPengeluaran, getHppMap, setHpp, seedDemoKeuangan,
  hitungHPP, labaRugi, labelKategori
} from '../lib/keuangan-store.js'

const PRESETS = [
  { key: '1', label: 'Hari ini', days: 0 },
  { key: '7', label: '7 hari', days: 6 },
  { key: '30', label: '30 hari', days: 29 }
]

export const KeuanganScreen = {
  id: 'keuangan',
  title: 'Keuangan',
  icon: icons.report,

  async render(container) {
    const ctx = {
      container,
      tokoId: getState().toko?.id || 'default',
      preset: '7',
      dari: toISODate(daysAgo(6)),
      sampai: toISODate(new Date()),
      produk: [],
      vm: null,
      showHpp: false,
      disposed: false
    }
    renderShell(ctx)
    bindToolbar(ctx)
    await load(ctx)
    return () => { ctx.disposed = true }
  }
}

// ---------- Kerangka ----------

function renderShell(ctx) {
  ctx.container.innerHTML = `
    <div class="screen-page">
      <div class="page-head">
        <div>
          <h1 class="page-head__title">Keuangan</h1>
          <p class="page-head__desc">Omzet, laba, margin, metode bayar, dan tren — untung atau rugi terlihat jelas.</p>
        </div>
        <div class="keu-head__act">
          <button class="btn btn--outline btn--sm" id="keu-wa" type="button">${icons.store}<span>Bagikan</span></button>
          <button class="btn btn--outline btn--sm" id="keu-pdf" type="button">${icons.download}<span>PDF</span></button>
        </div>
      </div>
      <div class="keu-range">
        <div class="segmented" id="keu-preset">
          ${PRESETS.map((p) => `<button class="segmented__item${p.key === ctx.preset ? ' is-active' : ''}" type="button" data-preset="${p.key}">${p.label}</button>`).join('')}
          <button class="segmented__item${ctx.preset === 'custom' ? ' is-active' : ''}" type="button" data-preset="custom">Kustom</button>
        </div>
        <div class="keu-range__dates u-hidden" id="keu-dates">
          <input type="date" class="input" id="keu-dari" value="${ctx.dari}" />
          <span>–</span>
          <input type="date" class="input" id="keu-sampai" value="${ctx.sampai}" />
          <button class="btn btn--primary btn--sm" id="keu-apply" type="button">Terapkan</button>
        </div>
      </div>
      <div id="keu-body"></div>
    </div>`
}

function bindToolbar(ctx) {
  const c = ctx.container
  c.querySelector('#keu-preset').addEventListener('click', (e) => {
    const btn = e.target.closest('[data-preset]')
    if (!btn) return
    const key = btn.dataset.preset
    c.querySelectorAll('[data-preset]').forEach((b) => b.classList.toggle('is-active', b === btn))
    c.querySelector('#keu-dates').classList.toggle('u-hidden', key !== 'custom')
    ctx.preset = key
    if (key !== 'custom') {
      const p = PRESETS.find((x) => x.key === key)
      ctx.dari = toISODate(daysAgo(p.days))
      ctx.sampai = toISODate(new Date())
      load(ctx)
    }
  })
  c.querySelector('#keu-apply').addEventListener('click', () => {
    const dari = c.querySelector('#keu-dari').value
    const sampai = c.querySelector('#keu-sampai').value
    if (!dari || !sampai) { toast('Lengkapi tanggal Dari dan Sampai.', 'error'); return }
    if (dari > sampai) { toast('Tanggal "Dari" tidak boleh melewati "Sampai".', 'error'); return }
    ctx.dari = dari; ctx.sampai = sampai; load(ctx)
  })
  c.querySelector('#keu-pdf').addEventListener('click', () => exportPDF(ctx))
  c.querySelector('#keu-wa').addEventListener('click', () => bagikanWA(ctx))
}

// ---------- Rentang periode sebelumnya (untuk delta) ----------

function prevRange(dari, sampai) {
  const d0 = new Date(dari + 'T00:00:00')
  const d1 = new Date(sampai + 'T00:00:00')
  const len = Math.round((d1 - d0) / 86400000) + 1
  const bSampai = new Date(d0); bSampai.setDate(bSampai.getDate() - 1)
  const bDari = new Date(bSampai); bDari.setDate(bDari.getDate() - (len - 1))
  return { dari: toISODate(bDari), sampai: toISODate(bSampai) }
}

// ---------- Muat & hitung ----------

async function load(ctx) {
  const body = ctx.container.querySelector('#keu-body')
  body.innerHTML = loadingHTML('Menghitung keuangan…')
  const { dari, sampai } = ctx
  const b = prevRange(dari, sampai)

  if (ctx.produk.length === 0) {
    const pr = await api.produk.list({ perPage: 100 })
    if (pr.ok && Array.isArray(pr.data)) ctx.produk = pr.data
    seedDemoKeuangan(ctx.tokoId, ctx.produk)
  }

  const [harianA, produkA, rekapA, harianB] = await Promise.all([
    api.laporan.penjualanHarian({ tanggalDari: dari, tanggalSampai: sampai }),
    api.laporan.penjualanProduk({ tanggalDari: dari, tanggalSampai: sampai }),
    api.laporan.rekapKasir({ tanggalDari: dari, tanggalSampai: sampai }),
    api.laporan.penjualanHarian({ tanggalDari: b.dari, tanggalSampai: b.sampai })
  ])
  if (ctx.disposed) return
  if (!harianA.ok) { body.innerHTML = errHTML(firstError(harianA)); body.querySelector('#keu-retry')?.addEventListener('click', () => load(ctx)); return }

  const omzet = Number(harianA.data?.total?.total_omzet) || 0
  const jumlahTrx = Number(harianA.data?.total?.jumlah_transaksi) || 0
  const rataRata = Number(harianA.data?.total?.rata_rata) || 0
  const omzetB = Number(harianB.ok ? harianB.data?.total?.total_omzet : 0) || 0

  const penjualanProduk = produkA.ok && Array.isArray(produkA.data) ? produkA.data : []
  const hppMap = getHppMap(ctx.tokoId)
  const { hpp, lengkap: hppLengkap, tanpaModal } = hitungHPP(penjualanProduk, ctx.produk, hppMap)
  const biaya = ringkasPengeluaran(ctx.tokoId, { dari, sampai })
  const pnl = labaRugi({ omzet, hpp, biaya: biaya.total })

  const rekap = rekapA.ok && Array.isArray(rekapA.data) ? rekapA.data : []
  const metode = hitungMetode(rekap)
  const tren = Array.isArray(harianA.data?.rows) ? harianA.data.rows : []
  const deltaOmzet = omzetB > 0 ? Math.round(((omzet - omzetB) / omzetB) * 1000) / 10 : (omzet > 0 ? 100 : 0)

  ctx.vm = { dari, sampai, omzet, omzetB, deltaOmzet, jumlahTrx, rataRata, pnl, hppLengkap, tanpaModal, biaya, metode, tren, penjualanProduk }
  renderBody(ctx)
}

function hitungMetode(rekap) {
  let tunai = 0, transfer = 0, qris = 0
  for (const s of rekap) { tunai += Number(s.total_tunai) || 0; transfer += Number(s.total_transfer) || 0; qris += Number(s.total_qris) || 0 }
  const total = tunai + transfer + qris
  const pct = (v) => (total > 0 ? Math.round((v / total) * 1000) / 10 : 0)
  return { total, items: [
    { tipe: 'Tunai', total: tunai, persen: pct(tunai), cls: 'mint' },
    { tipe: 'Transfer', total: transfer, persen: pct(transfer), cls: 'info' },
    { tipe: 'QRIS', total: qris, persen: pct(qris), cls: 'accent' }
  ] }
}

// ---------- Render ----------

function deltaBadge(pct) {
  if (!Number.isFinite(pct) || pct === 0) return '<span class="keu-delta keu-delta--flat">0%</span>'
  const up = pct > 0
  return `<span class="keu-delta keu-delta--${up ? 'up' : 'down'}">${up ? '▲' : '▼'} ${fmtNumber(Math.abs(pct))}%</span>`
}

function renderBody(ctx) {
  const vm = ctx.vm
  const body = ctx.container.querySelector('#keu-body')
  body.innerHTML = `
    <div class="keu-kpis">
      <div class="stat-tile stat-tile--accent">
        <div class="stat-tile__label">Omzet</div>
        <div class="stat-tile__value num">${fmtIDR(vm.omzet)}</div>
        <div class="stat-tile__sub">${deltaBadge(vm.deltaOmzet)} vs periode sebelumnya</div>
      </div>
      <div class="stat-tile">
        <div class="stat-tile__label">Laba Bersih</div>
        <div class="stat-tile__value num ${vm.pnl.labaBersih < 0 ? 'keu-neg' : ''}">${fmtIDR(vm.pnl.labaBersih)}</div>
        <div class="stat-tile__sub">Margin ${fmtNumber(vm.pnl.marginBersih)}%</div>
      </div>
      <div class="stat-tile">
        <div class="stat-tile__label">Laba Kotor</div>
        <div class="stat-tile__value num">${fmtIDR(vm.pnl.labaKotor)}</div>
        <div class="stat-tile__sub">Margin ${fmtNumber(vm.pnl.marginKotor)}%</div>
      </div>
      <div class="stat-tile">
        <div class="stat-tile__label">Transaksi</div>
        <div class="stat-tile__value num">${fmtNumber(vm.jumlahTrx)}</div>
        <div class="stat-tile__sub">Rata-rata ${fmtIDR(vm.rataRata)}</div>
      </div>
    </div>

    ${pnlCardHTML(vm)}

    <div class="keu-grid2">
      ${metodeCardHTML(vm.metode)}
      ${biayaCardHTML(vm.biaya)}
    </div>

    ${trenCardHTML(vm.tren)}
    ${terlarisCardHTML(vm.penjualanProduk)}
    ${hppCardHTML(ctx)}`

  bindBody(ctx)
}

function pnlRow(label, value, opts = {}) {
  const { sub = false, total = false, minus = false } = opts
  const neg = value < 0
  const shown = (minus || neg) ? `−${fmtIDR(Math.abs(value))}` : fmtIDR(value)
  return `
    <div class="keu-pnl__row${total ? ' keu-pnl__row--total' : ''}${sub ? ' keu-pnl__row--sub' : ''}">
      <span>${esc(label)}</span>
      <span class="num${neg ? ' keu-neg' : ''}">${shown}</span>
    </div>`
}

function pnlCardHTML(vm) {
  const warn = !vm.hppLengkap
    ? `<div class="keu-warn">${icons.alert}<span>Sebagian produk belum diisi harga modal (HPP), jadi laba masih perkiraan. <button class="linklike" data-hpp-open type="button">Atur modal produk</button>.</span></div>`
    : ''
  return `
    <div class="card keu-pnl">
      <div class="card__header"><div class="card__title">Laba Rugi (${esc(fmtDate(vm.dari))} – ${esc(fmtDate(vm.sampai))})</div></div>
      <div class="card__body">
        ${pnlRow('Omzet penjualan', vm.pnl.omzet)}
        ${pnlRow('Harga pokok (HPP)', vm.pnl.hpp, { minus: true, sub: true })}
        ${pnlRow('Laba Kotor', vm.pnl.labaKotor, { total: true })}
        ${pnlRow('Biaya operasional', vm.pnl.biaya, { minus: true, sub: true })}
        ${pnlRow('Laba Bersih', vm.pnl.labaBersih, { total: true })}
        ${warn}
      </div>
    </div>`
}

function barRowHTML(label, value, pct, cls) {
  return `
    <div class="keu-bar">
      <div class="keu-bar__top"><span>${esc(label)}</span><span class="num">${fmtIDR(value)} · ${fmtNumber(pct)}%</span></div>
      <div class="keu-bar__track"><div class="keu-bar__fill keu-bar__fill--${cls}" style="width:${Math.max(pct, 0).toFixed(1)}%"></div></div>
    </div>`
}

function metodeCardHTML(m) {
  const isi = m.total > 0
    ? m.items.map((x) => barRowHTML(x.tipe, x.total, x.persen, x.cls)).join('')
    : '<p class="u-muted">Belum ada penjualan pada periode ini.</p>'
  return `
    <div class="card"><div class="card__header"><div class="card__title">Metode Pembayaran</div></div>
      <div class="card__body">${isi}</div></div>`
}

function biayaCardHTML(biaya) {
  const maxV = Math.max(1, ...biaya.perKategori.map((k) => k.total))
  const isi = biaya.total > 0
    ? biaya.perKategori.map((k) => barRowHTML(k.label, k.total, Math.round((k.total / maxV) * 100), 'warn')).join('')
    : `<p class="u-muted">Belum ada pengeluaran. Catat di menu <strong>Pengeluaran</strong>.</p>`
  return `
    <div class="card"><div class="card__header"><div class="card__title">Pengeluaran per Kategori</div>
      <span class="num">${fmtIDR(biaya.total)}</span></div>
      <div class="card__body">${isi}</div></div>`
}

function trenCardHTML(rows) {
  if (!rows || rows.length === 0) return ''
  const values = rows.map((r) => Number(r.total_omzet) || 0)
  const max = Math.max(...values, 1)
  const cells = rows.map((r, i) => {
    const pct = values[i] > 0 ? Math.max((values[i] / max) * 100, 2) : 0
    return `<div class="rpt-chart__cell" tabindex="0" aria-label="${esc(fmtDate(r.tanggal))}: ${fmtIDR(values[i])}"><div class="rpt-chart__bar" style="height:${pct.toFixed(1)}%"></div></div>`
  }).join('')
  const step = Math.ceil(rows.length / 8)
  const axis = rows.map((r, i) => `<span>${i % step === 0 ? esc(fmtDate(r.tanggal).split(' ').slice(0, 2).join(' ')) : ''}</span>`).join('')
  return `
    <div class="card rpt-chart"><div class="rpt-chart__caption">Tren omzet per hari</div>
      <div class="rpt-chart__plot"><div class="rpt-chart__gridlines" aria-hidden="true"><i></i><i></i><i></i></div>
        <div class="rpt-chart__cells">${cells}</div></div>
      <div class="rpt-chart__axis" aria-hidden="true">${axis}</div></div>`
}

function terlarisCardHTML(penjualanProduk) {
  const rows = [...(penjualanProduk || [])].sort((a, b) => (Number(b.total_nilai) || 0) - (Number(a.total_nilai) || 0)).slice(0, 5)
  if (rows.length === 0) return ''
  const trs = rows.map((r, i) => `
    <tr><td>${i + 1}. ${esc(r.produk)}</td><td class="num u-right">${fmtNumber(r.qty_terjual)}</td><td class="num u-right">${fmtIDR(r.total_nilai)}</td></tr>`).join('')
  return `
    <div class="card"><div class="card__header"><div class="card__title">Produk Terlaris</div></div>
      <div class="table-wrap"><table class="table"><thead><tr><th>Produk</th><th class="u-right">Qty</th><th class="u-right">Nilai</th></tr></thead><tbody>${trs}</tbody></table></div></div>`
}

function hppCardHTML(ctx) {
  const hppMap = getHppMap(ctx.tokoId)
  const rows = ctx.produk.map((p) => {
    const modal = hppMap[p.id]
    const margin = p.harga_jual > 0 && modal != null ? Math.round(((p.harga_jual - modal) / p.harga_jual) * 1000) / 10 : null
    return { id: p.id, nama: p.nama, harga: p.harga_jual, modal, margin }
  })
  const trs = rows.map((r) => `
    <tr>
      <td>${esc(r.nama)}</td>
      <td class="num u-right">${fmtIDR(r.harga)}</td>
      <td class="u-right"><input type="text" inputmode="numeric" class="input input--sm keu-hpp-in" data-id="${esc(r.id)}" value="${r.modal != null ? r.modal : ''}" placeholder="0" /></td>
      <td class="num u-right">${r.margin != null ? fmtNumber(r.margin) + '%' : '—'}</td>
    </tr>`).join('')
  return `
    <div class="card keu-hpp">
      <div class="card__header">
        <div class="card__title">Harga Modal Produk (HPP)</div>
        <button class="btn btn--ghost btn--sm" id="keu-hpp-toggle" type="button">${ctx.showHpp ? 'Sembunyikan' : 'Atur'}</button>
      </div>
      <div class="card__body${ctx.showHpp ? '' : ' u-hidden'}" id="keu-hpp-body">
        <p class="field__hint">Isi harga modal per produk agar laba & margin akurat. Tersimpan di perangkat ini.</p>
        <div class="table-wrap"><table class="table"><thead><tr><th>Produk</th><th class="u-right">Harga Jual</th><th class="u-right">Harga Modal</th><th class="u-right">Margin</th></tr></thead><tbody>${trs}</tbody></table></div>
      </div>
    </div>`
}

function errHTML(message) {
  return `<div class="empty-state"><div class="empty-state__icon">${icons.alert}</div>
    <div class="empty-state__title">Gagal memuat</div><div class="empty-state__desc">${esc(message)}</div>
    <button class="btn btn--outline btn--sm" id="keu-retry" type="button">Coba lagi</button></div>`
}

function bindBody(ctx) {
  const c = ctx.container
  c.querySelector('[data-hpp-open]')?.addEventListener('click', () => { ctx.showHpp = true; renderBody(ctx) })
  const toggle = c.querySelector('#keu-hpp-toggle')
  if (toggle) toggle.addEventListener('click', () => {
    ctx.showHpp = !ctx.showHpp
    c.querySelector('#keu-hpp-body').classList.toggle('u-hidden', !ctx.showHpp)
    toggle.textContent = ctx.showHpp ? 'Sembunyikan' : 'Atur'
  })
  c.querySelectorAll('.keu-hpp-in').forEach((input) => {
    input.addEventListener('change', () => {
      const val = Math.round(Number(String(input.value).replace(/[^\d]/g, '')) || 0)
      setHpp(ctx.tokoId, input.dataset.id, val)
      load(ctx) // hitung ulang P&L
    })
  })
}

// ---------- Ekspor ----------

function ringkasTeks(ctx) {
  const vm = ctx.vm; const nama = getState().toko?.nama || getState().company?.nama || 'Tuléh'
  return `*Laporan Keuangan ${nama}*\n${fmtDate(vm.dari)} – ${fmtDate(vm.sampai)}\n\n`
    + `Omzet: ${fmtIDR(vm.omzet)}\nHPP: ${fmtIDR(vm.pnl.hpp)}\nLaba Kotor: ${fmtIDR(vm.pnl.labaKotor)}\n`
    + `Biaya: ${fmtIDR(vm.pnl.biaya)}\nLaba Bersih: ${fmtIDR(vm.pnl.labaBersih)} (margin ${fmtNumber(vm.pnl.marginBersih)}%)\n`
    + `Transaksi: ${fmtNumber(vm.jumlahTrx)}\n\n_via aplikasi Tuléh_`
}

function bagikanWA(ctx) {
  if (!ctx.vm) return
  window.open(`https://wa.me/?text=${encodeURIComponent(ringkasTeks(ctx))}`, '_blank')
}

async function exportPDF(ctx) {
  if (!ctx.vm) return
  const vm = ctx.vm; const nama = getState().toko?.nama || getState().company?.nama || 'Tuléh'
  const root = document.getElementById('print-root')
  if (!root) return
  const rowsBiaya = vm.biaya.perKategori.map((k) => `<tr><td>${esc(k.label)}</td><td style="text-align:right">${fmtIDR(k.total)}</td></tr>`).join('')
  root.innerHTML = `
    <div class="keu-print">
      <h2>${esc(nama)}</h2>
      <div class="keu-print__sub">Laporan Keuangan · ${esc(fmtDate(vm.dari))} – ${esc(fmtDate(vm.sampai))}</div>
      <table class="keu-print__t">
        <tr><td>Omzet penjualan</td><td>${fmtIDR(vm.pnl.omzet)}</td></tr>
        <tr><td>Harga pokok (HPP)</td><td>−${fmtIDR(vm.pnl.hpp)}</td></tr>
        <tr class="keu-print__tot"><td>Laba Kotor</td><td>${fmtIDR(vm.pnl.labaKotor)} (${fmtNumber(vm.pnl.marginKotor)}%)</td></tr>
        <tr><td>Biaya operasional</td><td>−${fmtIDR(vm.pnl.biaya)}</td></tr>
        <tr class="keu-print__tot"><td>Laba Bersih</td><td>${fmtIDR(vm.pnl.labaBersih)} (${fmtNumber(vm.pnl.marginBersih)}%)</td></tr>
      </table>
      <div class="keu-print__sub">Rincian Biaya</div>
      <table class="keu-print__t">${rowsBiaya || '<tr><td>—</td><td></td></tr>'}</table>
      <div class="keu-print__foot">Transaksi: ${fmtNumber(vm.jumlahTrx)} · Rata-rata ${fmtIDR(vm.rataRata)} · Dicetak via Tuléh</div>
    </div>`
  const result = await api.app.print()
  root.innerHTML = ''
  if (!result.ok && result.message && !/dibatalkan|cancel/i.test(result.message)) toast(`Gagal cetak: ${result.message}`, 'error')
}
