// Layar Riwayat Transaksi — daftar transaksi dengan filter tanggal/status,
// detail struk (cetak ulang), dan pembatalan transaksi.

import { api, firstError } from '../api.js'
import { esc, fmtIDR, fmtNumber, fmtDateTime, toISODate, daysAgo } from '../utils/format.js'
import { toast, showModal, confirmDialog, emptyStateHTML, loadingHTML, icons } from '../components/ui.js'
import { buildReceiptHTML, printReceipt } from '../components/receipt.js'

const DEFAULT_RANGE_DAYS = 6

const METHOD_BADGE = {
  TUNAI: 'badge--mint',
  TRANSFER: 'badge--info',
  QRIS: 'badge--neutral'
}

// Server bisa memakai "SELESAI" (spec OpenAPI) atau "LUNAS" (Docs-API.md §6.10)
// untuk transaksi sukses — dua-duanya diperlakukan sama.
const STATUS_BADGE = {
  SELESAI: 'badge--success',
  LUNAS: 'badge--success',
  DIBATALKAN: 'badge--danger'
}

const isVoided = (status) => String(status || '').toUpperCase() === 'DIBATALKAN'

export const HistoryScreen = {
  id: 'history',
  title: 'Riwayat',
  icon: icons.history,

  async render(container) {
    let alive = true
    let requestSeq = 0
    let loadedRows = []
    let closeDetailModal = null

    container.innerHTML = `
      <div class="screen-page">
        <div class="page-head">
          <div>
            <h1 class="page-head__title">Riwayat Transaksi</h1>
            <p class="page-head__desc">Telusuri transaksi yang tercatat, cetak ulang struk, atau batalkan bila diperlukan.</p>
          </div>
          <button class="icon-btn" id="hst-refresh" title="Muat ulang" aria-label="Muat ulang">${icons.refresh}</button>
        </div>

        <div class="card hst-filter">
          <div class="hst-filter__group">
            <label class="hst-filter__label" for="hst-dari">Dari</label>
            <input class="input" type="date" id="hst-dari" value="${toISODate(daysAgo(DEFAULT_RANGE_DAYS))}" />
          </div>
          <div class="hst-filter__group">
            <label class="hst-filter__label" for="hst-sampai">Sampai</label>
            <input class="input" type="date" id="hst-sampai" value="${toISODate(new Date())}" />
          </div>
          <div class="hst-filter__group">
            <label class="hst-filter__label" for="hst-status">Status</label>
            <select class="select" id="hst-status">
              <option value="">Semua status</option>
              <option value="OK">Selesai / Lunas</option>
              <option value="DIBATALKAN">Dibatalkan</option>
            </select>
          </div>
          <button class="btn btn--outline" id="hst-apply">Terapkan</button>
        </div>

        <div class="hst-kpis">
          <div class="stat-tile">
            <div class="stat-tile__label">Transaksi</div>
            <div class="stat-tile__value num" id="hst-kpi-count">—</div>
            <div class="stat-tile__sub">transaksi selesai pada rentang ini</div>
          </div>
          <div class="stat-tile stat-tile--accent">
            <div class="stat-tile__label">Total Penjualan</div>
            <div class="stat-tile__value num" id="hst-kpi-total">—</div>
            <div class="stat-tile__sub">akumulasi transaksi selesai</div>
          </div>
        </div>

        <div class="hst-table-area" id="hst-table-area"></div>
      </div>`

    const elDari = container.querySelector('#hst-dari')
    const elSampai = container.querySelector('#hst-sampai')
    const elStatus = container.querySelector('#hst-status')
    const tableArea = container.querySelector('#hst-table-area')
    const kpiCount = container.querySelector('#hst-kpi-count')
    const kpiTotal = container.querySelector('#hst-kpi-total')

    function updateKpis(rows) {
      const selesai = rows.filter((trx) => !isVoided(trx.status))
      const total = selesai.reduce((sum, trx) => sum + (Number(trx.grand_total) || 0), 0)
      kpiCount.textContent = fmtNumber(selesai.length)
      kpiTotal.textContent = fmtIDR(total)
    }

    function resetKpis() {
      kpiCount.textContent = '—'
      kpiTotal.textContent = '—'
    }

    function rowHTML(trx) {
      const method = String(trx.tipe_pembayaran || '').toUpperCase()
      const status = String(trx.status || '').toUpperCase()
      return `
        <tr class="is-clickable" data-id="${esc(trx.id)}" tabindex="0"
            aria-label="Lihat detail transaksi ${esc(trx.nomor)}">
          <td class="hst-col-no"><span class="mono">${esc(trx.nomor)}</span></td>
          <td class="hst-col-date">${fmtDateTime(trx.tanggal)}</td>
          <td><span class="badge ${METHOD_BADGE[method] || 'badge--neutral'}">${esc(method || '—')}</span></td>
          <td><span class="badge ${STATUS_BADGE[status] || 'badge--neutral'}">${esc(status || '—')}</span></td>
          <td class="u-right"><span class="num hst-total">${fmtIDR(trx.grand_total)}</span></td>
        </tr>`
    }

    function renderRows(rows) {
      if (rows.length === 0) {
        tableArea.innerHTML = `
          <div class="table-wrap">
            ${emptyStateHTML({
              icon: icons.history,
              title: 'Tidak ada transaksi',
              desc: 'Belum ada transaksi pada rentang ini. Coba perlebar rentang tanggal atau ubah filter status.'
            })}
          </div>`
        return
      }
      tableArea.innerHTML = `
        <div class="table-wrap">
          <table class="table">
            <thead>
              <tr>
                <th>No.</th>
                <th>Tanggal</th>
                <th>Metode</th>
                <th>Status</th>
                <th class="u-right">Total</th>
              </tr>
            </thead>
            <tbody>${rows.map(rowHTML).join('')}</tbody>
          </table>
        </div>`
    }

    async function loadData() {
      const tanggalDari = elDari.value
      const tanggalSampai = elSampai.value
      if (tanggalDari && tanggalSampai && tanggalDari > tanggalSampai) {
        toast('Tanggal "Dari" tidak boleh melebihi tanggal "Sampai".', 'error')
        return
      }

      const seq = ++requestSeq
      tableArea.innerHTML = `<div class="table-wrap">${loadingHTML('Memuat riwayat transaksi…')}</div>`

      // Filter "Selesai/Lunas" diterapkan di sisi klien karena penamaan status
      // sukses berbeda antar versi server (SELESAI vs LUNAS).
      const params = { tanggalDari, tanggalSampai }
      if (elStatus.value === 'DIBATALKAN') params.status = 'DIBATALKAN'

      const result = await api.trx.list(params)
      if (!alive || seq !== requestSeq) return

      if (!result.ok) {
        resetKpis()
        toast(firstError(result), 'error')
        tableArea.innerHTML = `
          <div class="table-wrap">
            ${emptyStateHTML({
              icon: icons.alert,
              title: 'Gagal memuat riwayat',
              desc: firstError(result)
            })}
          </div>`
        return
      }

      loadedRows = Array.isArray(result.data) ? result.data : []
      if (elStatus.value === 'OK') loadedRows = loadedRows.filter((trx) => !isVoided(trx.status))
      else if (elStatus.value === 'DIBATALKAN') loadedRows = loadedRows.filter((trx) => isVoided(trx.status))
      updateKpis(loadedRows)
      renderRows(loadedRows)
    }

    // ---------- Detail transaksi (modal struk) ----------

    async function openDetail(id) {
      // Cegah modal ganda (Enter berulang / klik cepat) — fokus tetap di baris
      // saat modal masih memuat, sehingga aktivasi kedua bisa lolos tanpa guard ini.
      if (closeDetailModal) return

      const body = document.createElement('div')
      body.innerHTML = loadingHTML('Memuat detail transaksi…')
      const footer = document.createElement('div')
      footer.className = 'hst-detail__foot'

      const { close } = showModal({
        title: 'Detail Transaksi',
        body,
        footer,
        size: 'md',
        onClose: () => { closeDetailModal = null }
      })
      closeDetailModal = close

      function renderStruk(struk) {
        body.innerHTML = `<div class="hst-detail__receipt">${buildReceiptHTML(struk)}</div>`
        footer.innerHTML = ''

        const btnPrint = document.createElement('button')
        btnPrint.className = 'btn btn--outline'
        btnPrint.innerHTML = `${icons.print} <span>Cetak</span>`
        btnPrint.addEventListener('click', () => printReceipt(struk))
        footer.appendChild(btnPrint)

        if (isVoided(struk.status)) return

        const btnCancel = document.createElement('button')
        btnCancel.className = 'btn btn--danger-outline'
        btnCancel.textContent = 'Batalkan Transaksi'
        btnCancel.addEventListener('click', async () => {
          const yes = await confirmDialog({
            title: 'Batalkan transaksi ini?',
            message: `Transaksi ${struk.nomor} akan dibatalkan — stok barang dikembalikan ke gudang dan jurnal penjualannya di-reverse. Tindakan ini tidak dapat diurungkan.`,
            confirmText: 'Ya, batalkan',
            cancelText: 'Kembali',
            danger: true
          })
          if (!yes) return

          btnCancel.disabled = true
          btnCancel.textContent = 'Membatalkan…'
          const result = await api.trx.batal({ id: struk.id })

          if (result.ok) {
            // Server bisa saja sukses tanpa mengembalikan struk — jangan anggap
            // gagal (tombol aktif lagi = risiko pembatalan ganda). Fallback:
            // salinan struk lama berstempel DIBATALKAN.
            const updated = result.data || { ...struk, status: 'DIBATALKAN' }
            toast(`Transaksi ${updated.nomor || struk.nomor} berhasil dibatalkan.`, 'success')
            renderStruk(updated)
            if (alive) loadData()
            return
          }
          btnCancel.disabled = false
          btnCancel.textContent = 'Batalkan Transaksi'
          toast(firstError(result), 'error')
        })
        footer.appendChild(btnCancel)
      }

      const result = await api.trx.detail({ id })
      if (!result.ok || !result.data) {
        // firstError() mengembalikan '' saat result.ok — beri pesan fallback
        // supaya toast tidak pernah kosong.
        const message = result.ok ? 'Transaksi tidak ditemukan.' : firstError(result)
        toast(message, 'error')
        body.innerHTML = emptyStateHTML({
          icon: icons.alert,
          title: 'Detail tidak dapat dimuat',
          desc: message
        })
        const btnClose = document.createElement('button')
        btnClose.className = 'btn btn--ghost'
        btnClose.textContent = 'Tutup'
        btnClose.addEventListener('click', () => close())
        footer.appendChild(btnClose)
        return
      }
      renderStruk(result.data)
    }

    function onRowActivate(event) {
      const tr = event.target.closest('tr[data-id]')
      if (!tr) return
      const trx = loadedRows.find((row) => String(row.id) === tr.dataset.id)
      openDetail(trx ? trx.id : tr.dataset.id)
    }

    // ---------- Event ----------

    container.querySelector('#hst-apply').addEventListener('click', loadData)
    container.querySelector('#hst-refresh').addEventListener('click', loadData)
    tableArea.addEventListener('click', onRowActivate)
    tableArea.addEventListener('keydown', (event) => {
      if (event.key === 'Enter') onRowActivate(event)
    })

    loadData()

    return () => {
      alive = false
      // Modal detail menempel di document.body — tanpa ini ia tetap terbuka
      // menutupi layar berikutnya (pindah layar via Ctrl+N / sesi berakhir).
      if (closeDetailModal) closeDetailModal()
    }
  }
}
