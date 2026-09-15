// Layar Sesi Kasir — buka/tutup sesi sendiri, rekap X/Z, dan daftar sesi per shift.
//
// Satu toko punya banyak kasir, masing-masing bersesi sendiri. Owner/Manager
// (`sesi.lihat_semua`) memantau sesi SEMUA kasir di toko aktif — ringkasan sesi
// berjalan, detail transaksi per sesi, dan menutup sesi kasir lain (`sesi.tutup_lain`).
// Kasir hanya melihat sesinya sendiri (server menyaring).

import { api, firstError } from '../api.js'
import { pasangFormatRupiah } from '../utils/rupiah-input.js'
import { getState } from '../state.js'
import { bisa } from '../akses.js'
import { sesiAktifSaya, ringkasSesi, saringStatusSesi, bolehTutupDariDaftar } from '../lib/sesi-pantau.js'
import { icons, toast, showModal, emptyStateHTML, loadingHTML } from '../components/ui.js'
import {
  esc,
  fmtIDR,
  fmtNumber,
  fmtDateTime,
  fmtTime,
  toISODate,
  daysAgo,
  parseAmount
} from '../utils/format.js'

const DASH = '<span class="u-faint">—</span>'
const HINT_KAS_AWAL = 'Uang modal di laci saat sesi dimulai.'
const HINT_KAS_FISIK = 'Masukkan jumlah uang hasil hitung fisik di laci.'

// ---------- Potongan markup ----------

function statusBadge(status) {
  if (status === 'BUKA') {
    return '<span class="badge badge--success"><span class="badge__dot"></span>BUKA</span>'
  }
  if (status === 'TUTUP') {
    return '<span class="badge badge--neutral">TUTUP</span>'
  }
  return `<span class="badge badge--neutral">${esc(status || '—')}</span>`
}

function selisihHTML(value) {
  if (value === null || value === undefined || value === '') return DASH
  const n = Number(value) || 0
  if (n < 0) return `<span class="num ses-neg">Kurang ${fmtIDR(Math.abs(n))}</span>`
  return `<span class="num ses-pos">Lebih ${fmtIDR(n)}</span>`
}

function defRow(label, valueHTML, extraClass = '') {
  return `
    <div class="ses-def__row${extraClass ? ` ${extraClass}` : ''}">
      <span class="ses-def__label">${label}</span>
      <span class="ses-def__value">${valueHTML}</span>
    </div>`
}

function rekapBodyHTML(r) {
  const money = (v) => `<span class="num">${fmtIDR(v)}</span>`
  return `
    <div class="ses-def">
      ${defRow('Nomor', `<span class="mono">${esc(r.nomor)}</span>`)}
      ${defRow('Status', statusBadge(r.status))}
      ${defRow('Kasir', r.kasir ? esc(r.kasir) : DASH)}
      ${defRow('Waktu buka', r.waktu_buka ? fmtDateTime(r.waktu_buka) : DASH)}
      ${defRow('Waktu tutup', r.waktu_tutup ? fmtDateTime(r.waktu_tutup) : DASH)}
      <div class="ses-def__sep"></div>
      ${defRow('Kas Awal', money(r.kas_awal))}
      ${defRow('Tunai', money(r.total_tunai))}
      ${defRow('Transfer', money(r.total_transfer))}
      ${defRow('QRIS', money(r.total_qris))}
      ${defRow('Total Penjualan', money(r.total_penjualan), 'ses-def__row--strong')}
      ${defRow('Jumlah Transaksi', `<span class="num">${fmtNumber(r.jumlah_transaksi)}</span>`)}
      <div class="ses-def__sep"></div>
      ${defRow('Kas Akhir Sistem', money(r.kas_akhir_sistem))}
      ${defRow(
        'Kas Akhir Fisik',
        r.kas_akhir_fisik === null || r.kas_akhir_fisik === undefined ? DASH : money(r.kas_akhir_fisik)
      )}
      ${defRow('Selisih', selisihHTML(r.selisih))}
    </div>`
}

function showRekapModal(rekap) {
  if (!rekap) return
  const isClosed = rekap.status === 'TUTUP'
  showModal({
    title: `Rekap ${isClosed ? 'Z' : 'X'} — ${rekap.nomor || ''}`,
    body: `
      <p class="u-muted">Rekap X = rekap berjalan saat sesi masih buka; Rekap Z = rekap penutupan sesi.</p>
      ${rekapBodyHTML(rekap)}`,
    footer: '<button class="btn btn--primary" data-modal-close>Tutup</button>'
  })
}

function trxSesiHTML(rows) {
  if (rows.length === 0) {
    return '<p class="u-muted ses-detail__empty">Belum ada transaksi pada sesi ini.</p>'
  }
  return `
    <div class="table-wrap ses-detail__trx">
      <table class="table">
        <thead><tr><th>No.</th><th>Jam</th><th>Bayar</th><th class="u-right">Total</th></tr></thead>
        <tbody>
          ${rows.map((t) => `
            <tr>
              <td class="mono">${esc(t.nomor)}</td>
              <td>${fmtTime(t.waktu || t.tanggal)}</td>
              <td>${esc(t.tipe_pembayaran || '—')}<div class="ses-detail__status${String(t.status).toUpperCase() === 'DIBATALKAN' ? ' ses-neg' : ''}">${esc(t.status || '—')}</div></td>
              <td class="u-right num">${fmtIDR(t.grand_total)}</td>
            </tr>`).join('')}
        </tbody>
      </table>
    </div>`
}

function ringkasanHTML(rows) {
  const r = ringkasSesi(rows)
  return `
    <div class="ses-ringkas">
      <div class="stat-tile">
        <div class="stat-tile__label">Kasir Bertugas</div>
        <div class="stat-tile__value num">${fmtNumber(r.berjalan)}</div>
        <div class="stat-tile__sub">sesi sedang berjalan</div>
      </div>
      <div class="stat-tile">
        <div class="stat-tile__label">Transaksi Berjalan</div>
        <div class="stat-tile__value num">${fmtNumber(r.transaksiBerjalan)}</div>
        <div class="stat-tile__sub">dari semua sesi yang buka</div>
      </div>
      <div class="stat-tile stat-tile--accent">
        <div class="stat-tile__label">Penjualan Berjalan</div>
        <div class="stat-tile__value num">${fmtIDR(r.penjualanBerjalan)}</div>
        <div class="stat-tile__sub">akumulasi sesi yang buka</div>
      </div>
    </div>`
}

function heroStatsHTML(s) {
  const stats = [
    { label: 'Kas Awal', value: fmtIDR(s.kas_awal) },
    { label: 'Total Penjualan', value: fmtIDR(s.total_penjualan), accent: true },
    { label: 'Jumlah Transaksi', value: fmtNumber(s.jumlah_transaksi) },
    { label: 'Tunai', value: fmtIDR(s.total_tunai) },
    { label: 'Transfer', value: fmtIDR(s.total_transfer) },
    { label: 'QRIS', value: fmtIDR(s.total_qris) },
    { label: 'Kas Akhir (Sistem)', value: fmtIDR(s.kas_akhir_sistem) }
  ]
  return stats
    .map(
      (st) => `
        <div class="stat-tile${st.accent ? ' stat-tile--accent' : ''}">
          <div class="stat-tile__label">${st.label}</div>
          <div class="stat-tile__value num${st.accent ? '' : ' ses-stat--sm'}">${st.value}</div>
        </div>`
    )
    .join('')
}

function heroHTML(s) {
  return `
    <div class="card ses-hero">
      <div class="ses-hero__top">
        <div>
          <span class="badge badge--success"><span class="badge__dot"></span>BUKA</span>
          <div class="ses-hero__nomor mono">${esc(s.nomor)}</div>
          <div class="ses-hero__meta">
            Dibuka ${fmtDateTime(s.waktu_buka)}${s.kasir ? ` · Kasir: ${esc(s.kasir)}` : ''}
          </div>
        </div>
        <div class="ses-hero__actions">
          <button class="btn btn--outline" id="ses-rekap-x"
                  title="Lihat rekap sementara tanpa menutup sesi">Rekap X</button>
          <button class="btn btn--dark" id="ses-close">Tutup Sesi</button>
        </div>
      </div>
      <div class="ses-hero__stats">${heroStatsHTML(s)}</div>
    </div>`
}

function openFormHTML(gudang, gudangError) {
  const warnEmpty = gudangError
    ? `<div class="ses-open__warn">
         Daftar gudang gagal dimuat dari server (${esc(gudangError)}).
         Ini masalah yang dikenal di sisi server — hubungi admin server,
         lalu keluar dan masuk kembali setelah diperbaiki.
       </div>`
    : `<div class="ses-open__warn">
         Akun Anda belum memiliki akses ke gudang mana pun, sehingga sesi belum bisa dibuka.
         Hubungi admin untuk mengatur akses gudang.
       </div>`
  const inner =
    gudang.length === 0
      ? warnEmpty
      : `<form id="ses-open-form" novalidate>
           <div class="field">
             <label class="field__label" for="ses-gudang">Gudang</label>
             <select class="select" id="ses-gudang">
               ${gudang
                 .map(
                   (g) =>
                     `<option value="${esc(g.id)}">${esc(g.nama)}${g.kode ? ` (${esc(g.kode)})` : ''}</option>`
                 )
                 .join('')}
             </select>
           </div>
           <div class="field">
             <label class="field__label" for="ses-kas-awal">Kas awal <span class="ses-req">*</span></label>
             <input class="input num" id="ses-kas-awal" type="text" inputmode="numeric"
                    placeholder="mis. 500.000 atau 500rb" autocomplete="off" required />
             <div class="field__hint" id="ses-kas-awal-view">${HINT_KAS_AWAL}</div>
           </div>
           <div class="field">
             <label class="field__label" for="ses-open-note">Catatan (opsional)</label>
             <textarea class="textarea" id="ses-open-note" rows="2" placeholder="mis. shift pagi"></textarea>
           </div>
           <button class="btn btn--primary btn--lg btn--block ses-open__submit" id="ses-open-submit" type="submit">
             Buka Sesi
           </button>
         </form>`
  return `
    <div class="card ses-open">
      <div class="card__body">
        <div class="ses-open__icon">${icons.session}</div>
        <h2 class="ses-open__title">Buka Sesi Kasir</h2>
        <p class="ses-open__desc">
          Belum ada sesi berjalan. Buka sesi terlebih dahulu agar transaksi bisa dilayani.
        </p>
        ${inner}
      </div>
    </div>`
}

// ---------- Resolusi id sesi aktif ----------
// SesiRekap dari /sesi/aktif tidak selalu menyertakan id — cari padanannya di daftar sesi.

async function resolveActiveSessionId() {
  const { session, sessionId } = getState()
  // Id dari API bisa berupa angka — jembatan IPC (str) hanya menerima string.
  if (sessionId !== null && sessionId !== undefined) return String(sessionId)
  const res = await api.sesi.list({
    tanggalDari: toISODate(daysAgo(30)),
    tanggalSampai: toISODate(new Date())
  })
  if (!res.ok) {
    toast(firstError(res), 'error')
    return null
  }
  // Daftar Owner/Manager memuat sesi kasir lain — hanya sesi milik sendiri yang boleh terpilih.
  const match = sesiAktifSaya(res.data || [], session)
  if (!match || match.id === undefined || match.id === null) {
    toast('Sesi aktif tidak ditemukan di daftar sesi server. Muat ulang aplikasi lalu coba lagi.', 'error')
    return null
  }
  return String(match.id)
}

// ---------- Layar ----------

export const SessionsScreen = {
  id: 'sessions',
  title: 'Sesi Kasir',
  icon: icons.session,
  async render(container) {
    const pantauSemua = bisa('sesi.lihat_semua')
    container.innerHTML = `
      <div class="screen-page">
        <div class="page-head">
          <div>
            <h1 class="page-head__title">Sesi Kasir</h1>
            <p class="page-head__desc">${pantauSemua
              ? 'Buka dan tutup sesi Anda, lalu pantau sesi, transaksi, dan kas semua kasir di toko ini.'
              : 'Buka dan tutup sesi kasir, lalu pantau rekap kas per shift.'}</p>
          </div>
        </div>
        <section id="ses-active" aria-label="Sesi aktif"></section>
        <section class="ses-history" aria-label="Riwayat sesi">
          <div class="ses-history__head">
            <h2 class="ses-history__title">${pantauSemua ? 'Sesi Kasir di Toko Ini' : 'Riwayat Sesi'}</h2>
            <div class="ses-history__filter">
              <select class="select ses-status" id="ses-status" aria-label="Status sesi">
                <option value="">Semua status</option>
                <option value="BUKA">Sedang berjalan</option>
                <option value="TUTUP">Sudah ditutup</option>
              </select>
              <input class="input ses-date" id="ses-from" type="date"
                     value="${toISODate(daysAgo(30))}" aria-label="Dari tanggal" />
              <span class="u-faint">s.d.</span>
              <input class="input ses-date" id="ses-to" type="date"
                     value="${toISODate(new Date())}" aria-label="Sampai tanggal" />
              <button class="btn btn--ghost btn--sm" id="ses-refresh">${icons.refresh} Segarkan</button>
            </div>
          </div>
          ${pantauSemua ? '<div id="ses-ringkas-host"></div>' : ''}
          <div id="ses-history-body"></div>
        </section>
      </div>`

    const activeHost = container.querySelector('#ses-active')
    const historyBody = container.querySelector('#ses-history-body')
    const ringkasHost = container.querySelector('#ses-ringkas-host')
    const elStatus = container.querySelector('#ses-status')
    let historyToken = 0
    let semuaSesi = []

    // ----- Riwayat sesi -----

    async function loadHistory() {
      const token = ++historyToken
      historyBody.innerHTML = loadingHTML('Memuat riwayat sesi…')
      const res = await api.sesi.list({
        tanggalDari: container.querySelector('#ses-from').value,
        tanggalSampai: container.querySelector('#ses-to').value
      })
      if (token !== historyToken) return
      if (!res.ok) {
        if (ringkasHost) ringkasHost.innerHTML = ''
        historyBody.innerHTML = emptyStateHTML({
          icon: icons.alert,
          title: 'Gagal memuat riwayat',
          desc: firstError(res)
        })
        return
      }
      semuaSesi = res.data || []
      renderHistory()
    }

    function renderHistory() {
      if (ringkasHost) ringkasHost.innerHTML = ringkasanHTML(semuaSesi)
      const rows = saringStatusSesi(semuaSesi, elStatus.value)
      if (rows.length === 0) {
        historyBody.innerHTML = emptyStateHTML({
          title: 'Belum ada sesi',
          desc: elStatus.value ? 'Tidak ada sesi dengan status ini pada rentang tanggal ini.' : 'Tidak ada sesi kasir pada rentang tanggal ini.'
        })
        return
      }
      const kasirHTML = (row) => `${row.kasir ? esc(row.kasir) : DASH}${row.milik_saya ? ' <span class="badge badge--info">Anda</span>' : ''}`
      historyBody.innerHTML = `
        <div class="table-wrap">
          <table class="table">
            <thead>
              <tr>
                <th>Nomor</th><th>Status</th>${pantauSemua ? '<th>Kasir</th>' : ''}<th>Buka</th><th>Tutup</th>
                <th class="u-right">Transaksi</th><th class="u-right">Penjualan</th><th class="u-right">Selisih</th>
              </tr>
            </thead>
            <tbody>
              ${rows
                .map(
                  (row, i) => `
                    <tr class="is-clickable" data-i="${i}" tabindex="0" title="Lihat detail sesi">
                      <td class="mono">${esc(row.nomor)}</td>
                      <td>${statusBadge(row.status)}</td>
                      ${pantauSemua ? `<td>${kasirHTML(row)}</td>` : ''}
                      <td>${fmtDateTime(row.waktu_buka)}</td>
                      <td>${row.waktu_tutup ? fmtDateTime(row.waktu_tutup) : DASH}</td>
                      <td class="u-right num">${row.jumlah_transaksi === undefined ? DASH : fmtNumber(row.jumlah_transaksi)}</td>
                      <td class="u-right num">${row.total_penjualan === undefined ? DASH : fmtIDR(row.total_penjualan)}</td>
                      <td class="u-right">${selisihHTML(row.selisih)}</td>
                    </tr>`
                )
                .join('')}
            </tbody>
          </table>
        </div>`
      historyBody.querySelectorAll('tr.is-clickable').forEach((tr) => {
        const openRow = () => openDetailSesi(rows[Number(tr.dataset.i)])
        tr.addEventListener('click', openRow)
        tr.addEventListener('keydown', (e) => {
          if (e.key === 'Enter') openRow()
        })
      })
    }

    // Detail sesi: rekap kas + transaksi sesi itu; Owner/Manager dapat menutup sesi kasir lain.
    async function openDetailSesi(row) {
      if (!row || row.id === undefined || row.id === null) {
        toast('Sesi ini tidak memiliki ID sehingga rekapnya tidak bisa diambil.', 'error')
        return
      }
      // Id dari API bisa berupa angka — jembatan IPC (str) hanya menerima string.
      const id = String(row.id)
      const body = document.createElement('div')
      body.innerHTML = loadingHTML('Memuat detail sesi…')
      const footer = document.createElement('div')
      footer.className = 'ses-detail__foot'
      const modal = showModal({
        title: `Sesi ${row.nomor || ''}${row.kasir ? ` — ${row.kasir}` : ''}`,
        body,
        footer,
        size: 'md'
      })

      const [rekap, trx] = await Promise.all([api.sesi.rekap({ id }), api.trx.list({ sesiId: id })])
      if (!rekap.ok || !rekap.data) {
        body.innerHTML = emptyStateHTML({ icon: icons.alert, title: 'Detail sesi tidak dapat dimuat', desc: firstError(rekap) || 'Sesi tidak ditemukan.' })
        footer.innerHTML = '<button class="btn btn--ghost" data-modal-close>Tutup</button>'
        return
      }
      const daftarTrx = trx.ok && Array.isArray(trx.data) ? trx.data : []
      body.innerHTML = `
        ${rekapBodyHTML(rekap.data)}
        <h3 class="ses-detail__subtitle">Transaksi Sesi Ini${trx.ok ? ` (${fmtNumber(daftarTrx.length)})` : ''}</h3>
        ${trx.ok ? trxSesiHTML(daftarTrx) : `<p class="u-muted">${esc(firstError(trx))}</p>`}`

      footer.innerHTML = '<button class="btn btn--ghost" data-modal-close>Tutup</button>'
      if (bolehTutupDariDaftar({ ...row, status: rekap.data.status }, bisa('sesi.tutup_lain'))) {
        const btn = document.createElement('button')
        btn.className = 'btn btn--danger'
        btn.textContent = 'Tutup Sesi Kasir Ini'
        btn.addEventListener('click', () => {
          modal.close()
          openCloseModal({ sesi: rekap.data, id, milikSendiri: false })
        })
        footer.appendChild(btn)
      }
    }

    // ----- Sesi aktif -----

    // Owner/Manager datang ke layar ini terutama untuk memantau: formulir buka sesi
    // sendiri diringkas jadi satu baris sampai diminta.
    let formSesiDibuka = !pantauSemua

    function renderActive() {
      const { session, gudang, gudangError } = getState()
      if (session) {
        activeHost.innerHTML = heroHTML(session)
        bindHero()
      } else if (!formSesiDibuka) {
        activeHost.innerHTML = `
          <div class="card ses-ringkas-buka">
            <span class="u-grow">Anda belum membuka sesi kasir sendiri.</span>
            <button type="button" class="btn btn--outline btn--sm" id="ses-buka-saya">${icons.session} Buka Sesi Saya</button>
          </div>`
        activeHost.querySelector('#ses-buka-saya').addEventListener('click', () => {
          formSesiDibuka = true
          renderActive()
        })
      } else {
        activeHost.innerHTML = openFormHTML(gudang || [], gudangError)
        bindOpenForm()
      }
    }

    function bindHero() {
      activeHost.querySelector('#ses-rekap-x').addEventListener('click', async (e) => {
        const btn = e.currentTarget
        btn.disabled = true
        const { refreshActiveSession } = await import('../app.js')
        const res = await refreshActiveSession()
        btn.disabled = false
        if (!res.ok) {
          toast(firstError(res), 'error')
          return
        }
        if (!res.data) {
          toast('Sesi ternyata sudah ditutup dari tempat lain.', 'info')
          renderActive()
          loadHistory()
          return
        }
        renderActive() // segarkan angka hero dengan data terbaru
        showRekapModal(res.data)
      })
      activeHost.querySelector('#ses-close').addEventListener('click', () => openCloseModal())
    }

    function bindOpenForm() {
      const form = activeHost.querySelector('#ses-open-form')
      if (!form) return
      const kasInput = activeHost.querySelector('#ses-kas-awal')
      const kasView = activeHost.querySelector('#ses-kas-awal-view')
      pasangFormatRupiah(kasInput) // 100000 → 100.000 saat diketik

      kasInput.addEventListener('input', () => {
        const raw = kasInput.value.trim()
        kasView.textContent = raw ? `Terbaca: ${fmtIDR(parseAmount(raw))}` : HINT_KAS_AWAL
      })

      form.addEventListener('submit', async (e) => {
        e.preventDefault()
        const raw = kasInput.value.trim()
        if (!raw) {
          toast('Isi kas awal terlebih dahulu.', 'error')
          kasInput.focus()
          return
        }
        // Nilai <select> selalu string; validator IPC (str) menolak tipe non-string,
        // jadi JANGAN dikonversi ke Number.
        const gudangId = activeHost.querySelector('#ses-gudang').value
        const btn = activeHost.querySelector('#ses-open-submit')
        btn.disabled = true
        btn.textContent = 'Membuka sesi…'
        const result = await api.sesi.buka({
          gudangId,
          kasAwal: parseAmount(raw),
          catatan: activeHost.querySelector('#ses-open-note').value.trim()
        })
        if (!result.ok) {
          btn.disabled = false
          btn.textContent = 'Buka Sesi'
          toast(firstError(result), 'error')
          return
        }
        toast('Sesi kasir berhasil dibuka. Selamat bekerja!', 'success')
        const { refreshActiveSession } = await import('../app.js')
        await refreshActiveSession()
        renderActive()
        loadHistory()
      })
    }

    // Tanpa argumen = sesi aktif sendiri. `target` = sesi kasir lain dari detail daftar (Owner/Manager).
    function openCloseModal(target = null) {
      const milikSendiri = !target || target.milikSendiri !== false
      const session = target ? target.sesi : getState().session
      if (!session) return
      const kasSistem = Number(session.kas_akhir_sistem) || 0

      const modal = showModal({
        title: `Tutup Sesi — ${session.nomor || ''}`,
        body: `
          ${milikSendiri ? '' : `<div class="ses-open__warn ses-close__lain">
            Sesi ini milik kasir <strong>${esc(session.kasir || 'lain')}</strong>. Hitung uang laci bersama kasir
            sebelum menutupnya — kasir perlu membuka sesi baru untuk melayani lagi.
          </div>`}
          <div class="ses-close__system">
            <span class="u-muted">Kas akhir sistem</span>
            <span class="mono num">${fmtIDR(kasSistem)}</span>
          </div>
          <div class="field">
            <label class="field__label" for="ses-kas-fisik">Kas akhir fisik (hitung laci)</label>
            <input class="input input--lg num" id="ses-kas-fisik" type="text" inputmode="numeric"
                   placeholder="mis. 1.250.000" autocomplete="off" />
            <div class="field__hint" id="ses-fisik-view">${HINT_KAS_FISIK}</div>
          </div>
          <div class="ses-close__diff" id="ses-diff">
            <span>Selisih (fisik − sistem)</span>
            <span class="num" id="ses-diff-value">—</span>
          </div>
          <div class="field">
            <label class="field__label" for="ses-close-note">Catatan (opsional)</label>
            <textarea class="textarea" id="ses-close-note" rows="2"
                      placeholder="mis. selisih dari uang kembalian"></textarea>
          </div>`,
        footer: `
          <button class="btn btn--ghost" data-modal-close>Batal</button>
          <button class="btn btn--danger" data-close-submit>Tutup Sesi</button>`
      })

      const root = modal.el
      const inputFisik = root.querySelector('#ses-kas-fisik')
      const fisikView = root.querySelector('#ses-fisik-view')
      pasangFormatRupiah(inputFisik)
      const diffBox = root.querySelector('#ses-diff')
      const diffValue = root.querySelector('#ses-diff-value')
      const btnSubmit = root.querySelector('[data-close-submit]')

      function syncDiff() {
        const raw = inputFisik.value.trim()
        diffBox.classList.remove('is-pos', 'is-neg')
        if (!raw) {
          fisikView.textContent = HINT_KAS_FISIK
          diffValue.textContent = '—'
          return
        }
        const fisik = parseAmount(raw)
        fisikView.textContent = `Terbaca: ${fmtIDR(fisik)}`
        const diff = fisik - kasSistem
        if (diff >= 0) {
          diffBox.classList.add('is-pos')
          diffValue.textContent = `Lebih ${fmtIDR(diff)}`
        } else {
          diffBox.classList.add('is-neg')
          diffValue.textContent = `Kurang ${fmtIDR(Math.abs(diff))}`
        }
      }
      inputFisik.addEventListener('input', syncDiff)
      inputFisik.addEventListener('keydown', (e) => {
        if (e.key === 'Enter') btnSubmit.click()
      })

      btnSubmit.addEventListener('click', async () => {
        const raw = inputFisik.value.trim()
        if (!raw) {
          toast('Isi kas akhir fisik hasil hitung laci.', 'error')
          inputFisik.focus()
          return
        }
        btnSubmit.disabled = true
        btnSubmit.textContent = 'Menutup…'
        const restore = () => {
          btnSubmit.disabled = false
          btnSubmit.textContent = 'Tutup Sesi'
        }
        const id = target && target.id ? target.id : await resolveActiveSessionId()
        if (id === null || id === undefined) {
          restore()
          return
        }
        const result = await api.sesi.tutup({
          id,
          kasAkhirFisik: parseAmount(raw),
          catatan: root.querySelector('#ses-close-note').value.trim()
        })
        if (!result.ok) {
          restore()
          toast(firstError(result), 'error')
          return
        }
        modal.close()
        toast(milikSendiri ? 'Sesi berhasil ditutup.' : `Sesi ${session.nomor || ''} milik ${session.kasir || 'kasir'} berhasil ditutup.`, 'success')
        if (milikSendiri) {
          const { refreshActiveSession } = await import('../app.js')
          await refreshActiveSession()
          renderActive()
        }
        loadHistory()
        showRekapModal(result.data)
      })
    }

    container.querySelector('#ses-from').addEventListener('change', loadHistory)
    container.querySelector('#ses-to').addEventListener('change', loadHistory)
    container.querySelector('#ses-refresh').addEventListener('click', loadHistory)
    elStatus.addEventListener('change', renderHistory)

    renderActive()
    loadHistory()
  }
}
