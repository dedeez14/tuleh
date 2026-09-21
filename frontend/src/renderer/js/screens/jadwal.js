// Layar Jadwal (gym, klinik) — slot kelas/janji temu satu hari beserta pesertanya.
// Menata slot & peserta butuh hak `jadwal.kelola` dari server; pemegang `jadwal.lihat`
// saja (mis. kasir bawaan) tetap bisa membuka dan membaca daftarnya.

import { api, firstError } from '../api.js'
import { esc, debounce } from '../utils/format.js'
import { toast, icons, showModal, confirmDialog, emptyStateHTML, loadingHTML } from '../components/ui.js'
import { hariIni, geserTanggal, labelTanggal, labelKuota, slotPenuh, urutSlot, susunSlot } from '../lib/jadwal-model.js'
import { bisa } from '../akses.js'

const STATUS_PESERTA = [
  { id: 'TERDAFTAR', label: 'Terdaftar' },
  { id: 'HADIR', label: 'Hadir' },
  { id: 'BATAL', label: 'Batal' }
]

export const JadwalScreen = {
  id: 'jadwal',
  title: 'Jadwal',
  icon: icons.session,

  async render(container) {
    let alive = true
    let tanggal = hariIni()
    let rows = []
    const kelola = bisa('jadwal.kelola')
    const openModalCloses = new Set()

    container.innerHTML = `
      <div class="screen-page">
        <div class="page-head">
          <div>
            <h1 class="page-head__title">Jadwal</h1>
            <p class="page-head__desc">Kelas &amp; janji temu toko ini — kuota, peserta, dan kehadiran.</p>
          </div>
          ${kelola ? `<button type="button" class="btn btn--primary" id="jdw-add">${icons.plus}<span>Tambah Jadwal</span></button>` : ''}
        </div>

        <div class="card jdw-hari">
          <button type="button" class="icon-btn" id="jdw-prev" title="Hari sebelumnya">‹</button>
          <span class="jdw-hari__label" id="jdw-label"></span>
          <button type="button" class="icon-btn" id="jdw-next" title="Hari berikutnya">›</button>
          <input class="input jdw-hari__input" type="date" id="jdw-date" />
          <button type="button" class="btn btn--ghost btn--sm" id="jdw-today">Hari ini</button>
        </div>

        <div id="jdw-body">${loadingHTML('Memuat jadwal…')}</div>
      </div>`

    const body = container.querySelector('#jdw-body')
    const label = container.querySelector('#jdw-label')
    const input = container.querySelector('#jdw-date')

    function kartuHTML(s) {
      const batal = String(s.status || '').toUpperCase() === 'BATAL'
      return `
        <div class="jdw-item${batal ? ' is-batal' : ''}${slotPenuh(s) ? ' is-penuh' : ''}" data-id="${esc(s.id)}" tabindex="0">
          <span class="jdw-item__jam mono">${esc(s.jam_mulai)}${s.jam_selesai ? `–${esc(s.jam_selesai)}` : ''}</span>
          <span class="jdw-item__info">
            <span class="jdw-item__nama">${esc(s.nama)}</span>
            <span class="jdw-item__meta">${esc(labelKuota(s))}${s.pengajar ? ` · ${esc(s.pengajar)}` : ''}${batal ? ' · dibatalkan' : ''}</span>
          </span>
          <span class="jdw-item__aksi">${icons.search}</span>
        </div>`
    }

    function renderList() {
      if (!rows.length) {
        body.innerHTML = emptyStateHTML({
          icon: icons.session,
          title: 'Belum ada jadwal hari ini',
          desc: kelola ? 'Tambahkan slot lewat tombol "Tambah Jadwal".' : 'Minta pemilik atau manajer menambahkan slotnya.'
        })
        return
      }
      body.innerHTML = `<div class="jdw-list">${urutSlot(rows).map(kartuHTML).join('')}</div>`
    }

    async function muat() {
      label.textContent = labelTanggal(tanggal)
      input.value = tanggal
      body.innerHTML = loadingHTML('Memuat jadwal…')
      const result = await api.jadwal.list({ tanggal, semua: kelola })
      if (!alive) return
      if (!result.ok) {
        body.innerHTML = emptyStateHTML({ icon: icons.alert, title: 'Gagal memuat jadwal', desc: firstError(result) })
        return
      }
      rows = Array.isArray(result.data) ? result.data : []
      renderList()
    }

    // Modal menempel ke document.body — tanpa mencatat & menutupnya di cleanup,
    // modal tetap terbuka menutupi layar berikutnya saat pindah layar (Ctrl+N dst.).
    function bukaModal(opsi) {
      let ref
      const hasil = showModal({
        ...opsi,
        onClose: () => {
          openModalCloses.delete(ref)
          if (typeof opsi.onClose === 'function') opsi.onClose()
        }
      })
      ref = hasil.close
      openModalCloses.add(ref)
      return hasil
    }

    function bukaForm(slot) {
      const el = document.createElement('div')
      el.innerHTML = `
        <div class="field"><label class="field__label" for="jf-nama">Nama jadwal</label>
          <input class="input" id="jf-nama" maxlength="150" value="${esc(slot?.nama || '')}" placeholder="mis. Yoga Pagi, Poli Gigi" /></div>
        <div class="jdw-form__baris">
          <div class="field"><label class="field__label" for="jf-tgl">Tanggal</label>
            <input class="input" id="jf-tgl" type="date" value="${esc(slot?.tanggal || tanggal)}" /></div>
          <div class="field"><label class="field__label" for="jf-mulai">Jam mulai</label>
            <input class="input" id="jf-mulai" type="time" value="${esc(slot?.jam_mulai || '')}" /></div>
          <div class="field"><label class="field__label" for="jf-selesai">Jam selesai</label>
            <input class="input" id="jf-selesai" type="time" value="${esc(slot?.jam_selesai || '')}" /></div>
        </div>
        <div class="jdw-form__baris">
          <div class="field"><label class="field__label" for="jf-kuota">Kuota (kosong = tanpa batas)</label>
            <input class="input num" id="jf-kuota" type="number" min="1" step="1" value="${slot?.kuota ?? ''}" /></div>
          <div class="field"><label class="field__label" for="jf-pengajar">Pengajar / petugas</label>
            <input class="input" id="jf-pengajar" maxlength="100" value="${esc(slot?.pengajar || '')}" /></div>
        </div>
        <div class="field"><label class="field__label" for="jf-catatan">Catatan</label>
          <input class="input" id="jf-catatan" maxlength="255" value="${esc(slot?.catatan || '')}" /></div>
        <div class="field__error u-hidden" id="jf-err"></div>`
      const footer = document.createElement('div')
      footer.innerHTML = `<button type="button" class="btn btn--primary" id="jf-save">Simpan</button>`
      const { close } = bukaModal({ title: slot ? 'Ubah jadwal' : 'Tambah jadwal', body: el, footer, size: 'md' })

      footer.querySelector('#jf-save').addEventListener('click', async (e) => {
        const btn = e.currentTarget
        const err = el.querySelector('#jf-err')
        err.classList.add('u-hidden')
        let isi
        try {
          isi = susunSlot({
            nama: el.querySelector('#jf-nama').value,
            tanggal: el.querySelector('#jf-tgl').value,
            jamMulai: el.querySelector('#jf-mulai').value,
            jamSelesai: el.querySelector('#jf-selesai').value,
            kuota: el.querySelector('#jf-kuota').value,
            pengajar: el.querySelector('#jf-pengajar').value,
            catatan: el.querySelector('#jf-catatan').value
          })
        } catch (ex) {
          err.textContent = ex.message
          err.classList.remove('u-hidden')
          return
        }
        btn.disabled = true
        const result = slot ? await api.jadwal.ubah({ id: slot.id, ...isi }) : await api.jadwal.simpan(isi)
        if (!result.ok) {
          btn.disabled = false
          err.textContent = firstError(result)
          err.classList.remove('u-hidden')
          return
        }
        toast(slot ? 'Jadwal diperbarui.' : `Jadwal "${isi.nama}" ditambahkan.`, 'success')
        close()
        tanggal = isi.tanggal
        muat()
      })
    }

    async function bukaDetail(id) {
      const result = await api.jadwal.detail({ id })
      if (!alive) return
      if (!result.ok) {
        toast(firstError(result), 'error')
        return
      }
      const slot = result.data
      const el = document.createElement('div')
      const footer = document.createElement('div')
      footer.className = 'u-flex'
      footer.style.gap = 'var(--sp-3)'
      const { close } = bukaModal({ title: slot.nama, body: el, footer, size: 'md' })

      function gambar(s) {
        el.innerHTML = `
          <p class="jdw-detail__meta">
            <span class="mono">${esc(s.jam_mulai)}${s.jam_selesai ? `–${esc(s.jam_selesai)}` : ''}</span> ·
            ${esc(labelTanggal(s.tanggal))} · ${esc(labelKuota(s))}${s.pengajar ? ` · ${esc(s.pengajar)}` : ''}
          </p>
          ${s.catatan ? `<p class="u-muted">${esc(s.catatan)}</p>` : ''}
          ${(s.peserta || []).length
            ? `<table class="table jdw-peserta"><thead><tr><th>Peserta</th><th>Status</th><th></th></tr></thead><tbody>
                ${s.peserta.map((p) => `
                  <tr data-peserta="${esc(p.id)}">
                    <td>${esc(p.nama)}${p.telepon ? `<div class="u-faint mono">${esc(p.telepon)}</div>` : ''}</td>
                    <td>${kelola
                      ? `<select class="select" data-status>${STATUS_PESERTA.map((x) => `<option value="${x.id}"${x.id === p.status ? ' selected' : ''}>${x.label}</option>`).join('')}</select>`
                      : `<span class="badge">${esc(p.status)}</span>`}</td>
                    <td>${kelola ? `<button type="button" class="icon-btn" data-lepas title="Lepas peserta">${icons.trash}</button>` : ''}</td>
                  </tr>`).join('')}
              </tbody></table>`
            : '<p class="u-muted">Belum ada peserta terdaftar.</p>'}`
      }

      gambar(slot)

      async function segarkan() {
        const ulang = await api.jadwal.detail({ id })
        if (ulang.ok) gambar(ulang.data)
        muat()
      }

      el.addEventListener('change', async (e) => {
        const sel = e.target.closest('[data-status]')
        if (!sel) return
        const baris = sel.closest('[data-peserta]')
        const r = await api.jadwal.pesertaStatus({ id, pesertaId: baris.dataset.peserta, status: sel.value })
        if (!r.ok) {
          toast(firstError(r), 'error')
          return
        }
        toast('Status peserta diperbarui.', 'success')
        segarkan()
      })

      el.addEventListener('click', async (e) => {
        if (!e.target.closest('[data-lepas]')) return
        const baris = e.target.closest('[data-peserta]')
        const yes = await confirmDialog({ title: 'Lepas peserta?', message: 'Kursinya kembali tersedia untuk pelanggan lain.', confirmText: 'Lepas', danger: true })
        if (!yes) return
        const r = await api.jadwal.pesertaHapus({ id, pesertaId: baris.dataset.peserta })
        if (!r.ok) {
          toast(firstError(r), 'error')
          return
        }
        toast('Peserta dilepas.', 'success')
        segarkan()
      })

      if (kelola) {
        const btnDaftar = document.createElement('button')
        btnDaftar.className = 'btn btn--primary'
        btnDaftar.textContent = 'Daftarkan peserta'
        btnDaftar.addEventListener('click', () => pilihPelanggan(id, segarkan))
        const btnUbah = document.createElement('button')
        btnUbah.className = 'btn btn--outline'
        btnUbah.textContent = 'Ubah jadwal'
        btnUbah.addEventListener('click', () => { close(); bukaForm(slot) })
        const btnBatal = document.createElement('button')
        btnBatal.className = 'btn btn--ghost'
        btnBatal.textContent = 'Batalkan jadwal'
        btnBatal.addEventListener('click', async () => {
          const yes = await confirmDialog({
            title: `Batalkan "${slot.nama}"?`,
            message: 'Slot disembunyikan dari daftar harian. Pendaftaran yang sudah tercatat tetap tersimpan.',
            confirmText: 'Ya, batalkan',
            danger: true
          })
          if (!yes) return
          const r = await api.jadwal.batal({ id })
          if (!r.ok) {
            toast(firstError(r), 'error')
            return
          }
          toast('Jadwal dibatalkan.', 'success')
          close()
          muat()
        })
        footer.append(btnBatal, btnUbah, btnDaftar)
      }
    }

    function pilihPelanggan(idJadwal, sesudah) {
      const el = document.createElement('div')
      el.innerHTML = `
        <div class="search-box"><span class="search-box__icon">${icons.search}</span>
          <input class="input" id="jp-q" type="text" placeholder="Cari nama atau telepon…" autocomplete="off" /></div>
        <div id="jp-hasil" class="jdw-cari">${loadingHTML('Memuat pelanggan…')}</div>`
      const { close } = bukaModal({ title: 'Daftarkan peserta', body: el, size: 'md' })
      const hasil = el.querySelector('#jp-hasil')

      async function cari(q) {
        const r = await api.pelanggan.list({ q })
        const list = r.ok && Array.isArray(r.data) ? r.data : []
        hasil.innerHTML = list.length
          ? list.map((c) => `<button type="button" class="jdw-cari__item" data-pelanggan="${esc(c.id)}">
              <span>${esc(c.nama)}</span><span class="u-faint mono">${esc(c.telepon || '—')}</span></button>`).join('')
          : emptyStateHTML({ icon: icons.user, title: 'Pelanggan tidak ditemukan', desc: 'Tambahkan lewat layar Pelanggan lebih dulu.' })
      }

      el.querySelector('#jp-q').addEventListener('input', debounce((e) => cari(e.target.value.trim()), 250))
      hasil.addEventListener('click', async (e) => {
        const btn = e.target.closest('[data-pelanggan]')
        if (!btn) return
        btn.disabled = true
        const r = await api.jadwal.pesertaTambah({ id: idJadwal, idPelanggan: btn.dataset.pelanggan })
        if (!r.ok) {
          btn.disabled = false
          // Server mengirim kode mesin (KUOTA_PENUH / SUDAH_TERDAFTAR); pesannya sudah siap tampil.
          toast(firstError(r), 'error')
          return
        }
        toast(`${r.data.nama} didaftarkan.`, 'success')
        close()
        sesudah()
      })
      cari('')
    }

    container.querySelector('#jdw-prev').addEventListener('click', () => { tanggal = geserTanggal(tanggal, -1); muat() })
    container.querySelector('#jdw-next').addEventListener('click', () => { tanggal = geserTanggal(tanggal, 1); muat() })
    container.querySelector('#jdw-today').addEventListener('click', () => { tanggal = hariIni(); muat() })
    input.addEventListener('change', () => { if (input.value) { tanggal = input.value; muat() } })
    const add = container.querySelector('#jdw-add')
    if (add) add.addEventListener('click', () => bukaForm(null))
    body.addEventListener('click', (e) => {
      const item = e.target.closest('.jdw-item')
      if (item) bukaDetail(item.dataset.id)
    })

    await muat()

    return () => {
      // Tutup modal yang masih terbuka (form/detail/cari peserta bersarang) —
      // ia menempel di document.body, bukan di `container`, jadi tak ikut hilang
      // saat showScreen() mengganti isi #screen-root.
      for (const tutup of [...openModalCloses]) tutup()
      alive = false
    }
  }
}
