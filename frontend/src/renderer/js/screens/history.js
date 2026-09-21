// Layar Riwayat Transaksi — daftar transaksi dengan filter tanggal/status/kasir,
// detail struk (cetak ulang), dan pembatalan transaksi.
//
// Server menyaring per toko aktif: Owner/Manager menerima transaksi SEMUA kasir
// (kolom & saring Kasir tampil), Kasir hanya transaksinya sendiri.

import { api, firstError } from '../api.js'
import { esc, fmtIDR, fmtNumber, fmtDateTime, toISODate, daysAgo } from '../utils/format.js'
import { toast, showModal, confirmDialog, emptyStateHTML, loadingHTML, icons } from '../components/ui.js'
import { buildReceiptHTML, printReceipt, tombolBagikanStruk } from '../components/receipt.js'
import { cariRiwayat, daftarKasir, saringKasir } from '../lib/cari-riwayat.js'
import { strukRefund } from '../lib/struk-teks.js'
import { barisRefund, bisaDirefund, perkiraanRefund, susunPermintaanRefund } from '../lib/refund-form.js'
import { labelKuantitas } from '../lib/satuan-terukur.js'
import { getState } from '../state.js'
import { bisa } from '../akses.js'
import { mintaOtorisasi } from '../components/dialog-otorisasi.js'
import { labelAksi, perluPersetujuan } from '../lib/otorisasi.js'

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
  DIBATALKAN: 'badge--danger',
  'BELUM SINKRON': 'badge--warn'
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
    const pantauSemua = bisa('transaksi.riwayat_semua')

    container.innerHTML = `
      <div class="screen-page">
        <div class="page-head">
          <div>
            <h1 class="page-head__title">Riwayat Transaksi</h1>
            <p class="page-head__desc">${pantauSemua
              ? 'Transaksi semua kasir di toko ini — saring per kasir, cetak ulang struk, atau batalkan bila diperlukan.'
              : 'Transaksi yang Anda catat di toko ini — cetak ulang struk dari sini.'}</p>
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
          <div class="hst-filter__group hst-filter__group--cari">
            <label class="hst-filter__label" for="hst-cari">Cari</label>
            <input class="input" type="search" id="hst-cari" placeholder="${pantauSemua ? 'Nomor, kasir, sesi, atau nominal…' : 'Nomor, nominal, atau metode…'}" autocomplete="off" />
          </div>
          <div class="hst-filter__group">
            <label class="hst-filter__label" for="hst-status">Status</label>
            <select class="select" id="hst-status">
              <option value="">Semua status</option>
              <option value="OK">Selesai / Lunas</option>
              <option value="DIBATALKAN">Dibatalkan</option>
            </select>
          </div>
          ${pantauSemua ? `
          <div class="hst-filter__group">
            <label class="hst-filter__label" for="hst-kasir">Kasir</label>
            <select class="select" id="hst-kasir"><option value="">Semua kasir</option></select>
          </div>` : ''}
          <button class="btn btn--outline" id="hst-apply">Terapkan</button>
        </div>

        <div class="hst-kpis">
          <div class="stat-tile">
            <div class="stat-tile__label">Transaksi</div>
            <div class="stat-tile__value num" id="hst-kpi-count">—</div>
            <div class="stat-tile__sub" id="hst-kpi-count-sub">transaksi selesai pada rentang ini</div>
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
    const elCari = container.querySelector('#hst-cari')
    const elKasir = container.querySelector('#hst-kasir') // null bila tak berhak melihat kasir lain
    const kpiCountSub = container.querySelector('#hst-kpi-count-sub')
    const tableArea = container.querySelector('#hst-table-area')
    const kpiCount = container.querySelector('#hst-kpi-count')
    const kpiTotal = container.querySelector('#hst-kpi-total')

    function updateKpis(rows) {
      const selesai = rows.filter((trx) => !isVoided(trx.status))
      const total = selesai.reduce((sum, trx) => sum + (Number(trx.grand_total) || 0), 0)
      kpiCount.textContent = fmtNumber(selesai.length)
      kpiTotal.textContent = fmtIDR(total)
      kpiCountSub.textContent = elKasir && elKasir.value
        ? `transaksi selesai oleh ${elKasir.value}`
        : 'transaksi selesai pada rentang ini'
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
          <td class="hst-col-date">${fmtDateTime(trx.waktu || trx.tanggal)}</td>
          ${pantauSemua ? `<td class="hst-col-kasir">${esc(trx.kasir?.nama || '—')}</td>` : ''}
          <td class="hst-col-no"><span class="mono">${esc(trx.sesi?.nomor || '—')}</span></td>
          <td><span class="badge ${METHOD_BADGE[method] || 'badge--neutral'}">${esc(method || '—')}</span></td>
          <td><span class="badge ${STATUS_BADGE[status] || 'badge--neutral'}">${esc(status || '—')}</span>${Number(trx.total_refund) > 0 ? ` <span class="badge badge--warn" title="Sebagian/seluruh dana sudah dikembalikan">Refund ${fmtIDR(trx.total_refund)}</span>` : ''}</td>
          <td class="u-right"><span class="num hst-total">${fmtIDR(trx.grand_total)}</span></td>
        </tr>`
    }

    function renderRows(rows) {
      if (rows.length === 0) {
        const mencari = elCari.value.trim().length > 0
        tableArea.innerHTML = `
          <div class="table-wrap">
            ${emptyStateHTML({
              icon: mencari ? icons.search : icons.history,
              title: mencari ? 'Tidak ada yang cocok' : 'Tidak ada transaksi',
              desc: mencari
                // emptyStateHTML() sudah meng-escape; jangan di-escape dua kali
                // atau "Nasi & Es Teh" tampil sebagai "Nasi &amp; Es Teh".
                ? `Tidak ada transaksi yang cocok dengan "${elCari.value.trim()}" pada rentang ini.`
                : 'Belum ada transaksi pada rentang ini. Coba perlebar rentang tanggal atau ubah filter status.'
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
                <th>Waktu</th>
                ${pantauSemua ? '<th>Kasir</th>' : ''}
                <th>Sesi</th>
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
      isiPilihanKasir()
      terapkanPencarian()
    }

    // Pilihan kasir diturunkan dari baris yang dimuat (disaring per nama — id kasir
    // terenkripsi berbeda tiap baris). Pilihan yang masih ada dipertahankan.
    function isiPilihanKasir() {
      if (!elKasir) return
      const pilih = elKasir.value
      const nama = daftarKasir(loadedRows)
      elKasir.innerHTML = '<option value="">Semua kasir</option>' +
        nama.map((n) => `<option value="${esc(n)}">${esc(n)}</option>`).join('')
      elKasir.value = nama.includes(pilih) ? pilih : ''
    }

    // Saring kasir & pencarian berjalan atas baris yang sudah dimuat: tidak memanggil
    // server lagi, jadi tetap bekerja saat offline. KPI mengikuti kasir terpilih tetapi
    // tidak berubah saat mengetik pencarian.
    function terapkanPencarian() {
      const milikKasir = saringKasir(loadedRows, elKasir ? elKasir.value : '')
      updateKpis(milikKasir)
      renderRows(cariRiwayat(milikKasir, elCari.value))
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
        // Pembatalan lewat PIN atasan: server mengirim nama penyetujunya — tampilkan supaya
        // struk yang dicetak ulang & layar bercerita sama dengan catatan di server.
        if (struk.disetujui_oleh) {
          const ket = document.createElement('div')
          ket.className = 'hst-refund__judul'
          ket.textContent = `Disetujui: ${struk.disetujui_oleh}`
          body.appendChild(ket)
        }
        if ((struk.refunds || []).length) {
          const judul = document.createElement('div')
          judul.className = 'hst-refund__judul'
          judul.textContent = `Refund tercatat (${struk.refunds.length})`
          body.appendChild(judul)
        }
        for (const r of struk.refunds || []) {
          const baris = document.createElement('div')
          baris.className = 'hst-refund'
          baris.innerHTML = `<span class="mono">${esc(r.nomor || '')}</span><span>${fmtDateTime(r.tanggal)}</span>${r.disetujui_oleh ? `<span>Disetujui: ${esc(r.disetujui_oleh)}</span>` : ''}<span class="num">−${fmtIDR(r.total)}</span>`
          const btn = document.createElement('button')
          btn.type = 'button'
          btn.className = 'btn btn--ghost'
          btn.textContent = 'Cetak nota'
          btn.addEventListener('click', () => printReceipt(strukRefund(struk, r)))
          baris.appendChild(btn)
          body.appendChild(baris)
        }
        footer.innerHTML = ''

        const btnPrint = document.createElement('button')
        btnPrint.className = 'btn btn--outline'
        btnPrint.innerHTML = `${icons.print} <span>Cetak</span>`
        btnPrint.addEventListener('click', () => printReceipt(struk))
        footer.appendChild(btnPrint)

        if (isVoided(struk.status)) return
        footer.appendChild(tombolBagikanStruk(struk))
        if (struk.belum_sinkron || String(struk.id || '').startsWith('lokal:')) return // batalkan/refund lewat Pengaturan → Sinkronisasi
        // Tanpa hak sendiri, tombol TETAP tampil: kasir meminta PIN atasannya di dialog
        // (labelnya mengatakan itu sebelum ditekan). Server tetap yang memutuskan.
        if (bisaDirefund(struk)) {
          const btnRefund = document.createElement('button')
          btnRefund.className = 'btn btn--outline'
          btnRefund.textContent = labelAksi('transaksi.refund', bisa('transaksi.refund'))
          btnRefund.title = 'Kembalikan dana sebagian/penuh — dicatat sebagai dokumen refund bernomor'
          btnRefund.addEventListener('click', () => {
            // Diperiksa DI SINI, bukan saat modal dibuat: kasir bisa kehilangan
            // koneksi setelah detail terbuka, dan refund tidak diantrekan.
            if (getState().online === false) {
              toast('Refund hanya bisa dilakukan saat terhubung ke server.', 'error')
              return
            }
            bukaLembarRefund(struk)
          })
          footer.appendChild(btnRefund)
        }
        const labelBatal = labelAksi('transaksi.batal', bisa('transaksi.batal'))
        const btnCancel = document.createElement('button')
        btnCancel.className = 'btn btn--danger-outline'
        btnCancel.textContent = labelBatal
        btnCancel.addEventListener('click', async () => {
          const yes = await confirmDialog({
            title: 'Batalkan transaksi ini?',
            message: `Transaksi ${struk.nomor} akan dibatalkan — stok barang dikembalikan ke gudang dan jurnal penjualannya di-reverse. Tindakan ini tidak dapat diurungkan.`,
            confirmText: 'Ya, batalkan',
            cancelText: 'Kembali',
            danger: true
          })
          if (!yes) return

          // Token persetujuan sekali pakai (5 menit, satu aksi & satu transaksi). Server
          // membakarnya walau layanan lalu menolak — pesannya tampil apa adanya dan kasir
          // meminta persetujuan lagi.
          let token
          if (perluPersetujuan('transaksi.batal', { punyaHak: bisa('transaksi.batal') })) {
            token = await mintaOtorisasi({ aksi: 'transaksi.batal', transaksiId: struk.id })
            if (!token) return // dibatalkan / PIN salah — pesannya sudah tampil di dialog
          }

          btnCancel.disabled = true
          btnCancel.textContent = 'Membatalkan…'
          const result = await api.trx.batal({ id: struk.id, otorisasiToken: token })

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
          btnCancel.textContent = labelBatal
          toast(firstError(result), 'error')
        })
        footer.appendChild(btnCancel)
      }

      function bukaLembarRefund(struk) {
        const baris = barisRefund(struk)
        const aktif = Array.isArray(getState().paymentMethods) && getState().paymentMethods.length ? getState().paymentMethods : ['TUNAI']
        const asal = String(struk.tipe_pembayaran || '').toUpperCase()
        const bawaan = aktif.includes(asal) ? asal : aktif[0]
        const body = document.createElement('div')
        body.className = 'refund-form'
        body.innerHTML = `
          <p class="refund-form__intro">Transaksi <span class="mono">${esc(struk.nomor)}</span>. Isi jumlah yang dikembalikan per item (kosong = tidak direfund).</p>
          <table class="table refund-form__tabel">
            <thead><tr><th>Item</th><th class="u-right">Sisa</th><th class="u-right">Refund</th></tr></thead>
            <tbody>${baris.map((b) => `
              <tr>
                <td>${esc(b.nama)}<div class="refund-form__sub">${fmtIDR(b.nilaiPerUnit)} / ${esc(b.satuan || 'item')}</div></td>
                <td class="u-right">${esc(labelKuantitas(b.sisa, b.satuan))}</td>
                <td class="u-right"><input class="input refund-form__qty" type="text" inputmode="decimal" data-refund-id="${esc(b.id)}" placeholder="0" /></td>
              </tr>`).join('')}
            </tbody>
          </table>
          <div class="field">
            <label for="rf-metode">Metode pengembalian dana</label>
            <select class="select" id="rf-metode">${aktif.map((m) => `<option value="${esc(m)}"${m === bawaan ? ' selected' : ''}>${esc(m)}</option>`).join('')}</select>
          </div>
          <div class="field">
            <label for="rf-alasan">Alasan (wajib)</label>
            <textarea class="textarea" id="rf-alasan" rows="2" maxlength="255" placeholder="Contoh: rasa tidak sesuai, barang rusak"></textarea>
          </div>
          <label class="field refund-form__cek"><input type="checkbox" id="rf-stok" checked /> Barang kembali ke stok</label>
          <div class="refund-form__ringkas">Perkiraan dana kembali <strong class="num" id="rf-perkiraan">${fmtIDR(0)}</strong><span class="refund-form__sub">nilai pasti dihitung server (diskon &amp; pajak ikut dihitung)</span></div>`
        const footer = document.createElement('div')
        footer.className = 'hst-detail__foot'
        const btnKembali = document.createElement('button')
        btnKembali.className = 'btn btn--ghost'
        btnKembali.textContent = 'Kembali'
        const btnKirim = document.createElement('button')
        btnKirim.className = 'btn btn--primary'
        btnKirim.textContent = 'Catat refund'
        footer.append(btnKembali, btnKirim)
        const { close } = showModal({ title: 'Refund transaksi', body, footer, size: 'md' })
        btnKembali.addEventListener('click', () => close())

        // Terima desimal gaya Indonesia (koma) maupun titik: "0,5" → 0.5 (pola sama dengan inventory.js/dialog-ukuran.js).
        const qty = () => Object.fromEntries([...body.querySelectorAll('[data-refund-id]')].map((el) => [el.dataset.refundId, Number(String(el.value).trim().replace(',', '.')) || 0]))
        body.addEventListener('input', () => { body.querySelector('#rf-perkiraan').textContent = fmtIDR(perkiraanRefund(struk, qty())) })
        // Satu client_ref per lembar: pengulangan tombol setelah timeout mengembalikan refund yang sama (pos.idempoten).
        const clientRef = globalThis.crypto?.randomUUID ? crypto.randomUUID() : `rf-${Date.now()}-${Math.random().toString(16).slice(2)}`

        btnKirim.addEventListener('click', async () => {
          let payload
          try {
            payload = susunPermintaanRefund(struk, {
              qty: qty(),
              metode: body.querySelector('#rf-metode').value,
              alasan: body.querySelector('#rf-alasan').value,
              kembaliStok: body.querySelector('#rf-stok').checked
            })
          } catch (e) {
            toast(e.message, 'error')
            return
          }
          const yes = await confirmDialog({
            title: 'Catat refund?',
            message: `Sekitar ${fmtIDR(perkiraanRefund(struk, qty()))} dikembalikan ke pelanggan via ${payload.metode}. Dokumen refund bernomor akan dibuat dan tidak dapat diurungkan.`,
            confirmText: 'Ya, catat',
            cancelText: 'Kembali'
          })
          if (!yes) return

          let token
          if (perluPersetujuan('transaksi.refund', { punyaHak: bisa('transaksi.refund') })) {
            token = await mintaOtorisasi({ aksi: 'transaksi.refund', transaksiId: struk.id })
            if (!token) return
          }

          btnKirim.disabled = true
          btnKirim.textContent = 'Mencatat…'
          const result = await api.trx.refund({ ...payload, clientRef, waktuKlien: new Date().toISOString(), otorisasiToken: token })
          if (!result.ok) {
            btnKirim.disabled = false
            btnKirim.textContent = 'Catat refund'
            toast(firstError(result), 'error')
            return
          }
          const refund = result.data || {}
          toast(`Refund ${refund.nomor || ''} tercatat — ${fmtIDR(refund.total)} dikembalikan.`, 'success')
          close()
          const segar = await api.trx.struk({ id: struk.id })
          renderStruk(segar.ok && segar.data ? segar.data : struk)
          if (alive) loadData()
        })
      }

      // Struk lokal (belum tersinkron, id "lokal:<ref>") masih dilayani lewat antrean offline via trx:detail;
      // trx:struk hanya mengenal transaksi yang sudah tersinkron ke server.
      const result = await (String(id).startsWith('lokal:') ? api.trx.detail({ id }) : api.trx.struk({ id }))
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
    // Ketik = saring langsung (tanpa tombol Terapkan); Esc mengosongkan.
    elCari.addEventListener('input', terapkanPencarian)
    if (elKasir) elKasir.addEventListener('change', terapkanPencarian)
    elCari.addEventListener('keydown', (event) => {
      if (event.key !== 'Escape' || !elCari.value) return
      elCari.value = ''
      terapkanPencarian()
    })
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
