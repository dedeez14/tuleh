// Kelola Meja — tambah, ubah nomor, dan nonaktifkan meja langsung dari kasir.
// Daftar meja dimiliki server (ERP); layar ini hanya jendela ke sana.
//
// Dua aturan server yang tampak di UI:
// - `kode` QR TIDAK ikut berubah saat meja diberi nomor baru, sehingga QR yang
//   sudah tercetak dan tertempel tetap berlaku;
// - meja yang masih punya bon terbuka tidak bisa dinonaktifkan (server balas
//   409 dengan menyebut nomor bonnya) — pesannya ditampilkan apa adanya.

import { api, firstError } from '../api.js'
import { esc } from '../utils/format.js'
import { icons, showModal, toast, confirmDialog, loadingHTML } from '../components/ui.js'
import { getState } from '../state.js'

/** Peran yang boleh mengubah daftar meja (server menolak selain ini dgn 403). */
export function bolehKelolaMeja(posRole) {
  const r = String(posRole || '').toUpperCase()
  return r === 'OWNER' || r === 'MANAGER'
}

/** Buka dialog kelola meja. `onUbah` dipanggil bila daftar berubah. */
export function bukaKelolaMeja({ onUbah } = {}) {
  const body = document.createElement('div')
  body.className = 'meja-kelola'
  body.innerHTML = loadingHTML('Memuat daftar meja…')

  const footer = document.createElement('div')
  footer.className = 'meja-kelola__foot'
  footer.innerHTML = `
    <input class="input" id="mk-nomor" type="text" maxlength="30" placeholder="Nomor meja baru (mis. 7 atau A3)" />
    <button type="button" class="btn btn--primary" id="mk-tambah">${icons.plus} Tambah</button>`

  let berubah = false
  const { close } = showModal({
    title: 'Kelola Meja',
    body,
    footer,
    size: 'md',
    onClose: () => { if (berubah && onUbah) onUbah() }
  })

  async function muat() {
    body.innerHTML = loadingHTML('Memuat daftar meja…')
    const r = await api.table.list({ semua: true })
    if (!r.ok) {
      body.innerHTML = `<p class="meja-kelola__galat">${esc(firstError(r) || 'Gagal memuat meja.')}</p>`
      return
    }
    const rows = Array.isArray(r.data) ? r.data : []
    if (!rows.length) {
      body.innerHTML = `<p class="meja-kelola__kosong">Belum ada meja. Tambahkan lewat kolom di bawah.</p>`
      return
    }
    body.innerHTML = `
      <table class="table meja-kelola__tabel">
        <thead><tr><th>Meja</th><th>Kode QR</th><th class="u-right">Aksi</th></tr></thead>
        <tbody>
          ${rows.map((t) => `
            <tr data-id="${esc(t.id)}" data-nomor="${esc(t.nomor)}" class="${t.aktif === false ? 'is-nonaktif' : ''}">
              <td>
                <span class="meja-kelola__nomor">Meja ${esc(t.nomor)}</span>
                ${t.aktif === false ? '<span class="badge badge--neutral">nonaktif</span>' : ''}
              </td>
              <td class="mono">${esc(t.kode || '—')}</td>
              <td class="u-right">
                <button type="button" class="btn btn--ghost btn--sm" data-aksi="ubah">Ubah nomor</button>
                ${t.aktif === false ? '' : '<button type="button" class="btn btn--ghost btn--sm" data-aksi="nonaktif">Nonaktifkan</button>'}
              </td>
            </tr>`).join('')}
        </tbody>
      </table>`
  }

  body.addEventListener('click', async (e) => {
    const tombol = e.target.closest('button[data-aksi]')
    if (!tombol) return
    const baris = tombol.closest('tr')
    const id = baris.dataset.id
    const nomorLama = baris.dataset.nomor

    if (tombol.dataset.aksi === 'ubah') {
      const nomor = await mintaNomor(nomorLama)
      if (!nomor || nomor === nomorLama) return
      tombol.disabled = true
      // `kode` tidak dikirim: QR yang sudah tertempel di meja tetap berlaku.
      const r = await api.table.ubah({ id, nomor })
      tombol.disabled = false
      if (!r.ok) { toast(firstError(r) || 'Gagal mengubah nomor meja.', 'error', 6000); return }
      berubah = true
      toast(`Meja ${nomorLama} kini bernomor ${nomor}.`, 'success')
      await muat()
      return
    }

    const ya = await confirmDialog({
      title: `Nonaktifkan Meja ${nomorLama}?`,
      message: 'Meja disembunyikan dari peta kasir. Riwayat bon lamanya tetap utuh, '
        + 'dan meja bisa diaktifkan kembali lewat ERP tatreport.',
      confirmText: 'Ya, nonaktifkan',
      danger: true
    })
    if (!ya) return
    tombol.disabled = true
    const r = await api.table.nonaktifkan({ id })
    tombol.disabled = false
    // 409 = masih ada bon terbuka; pesan server menyebut nomor bonnya.
    if (!r.ok) { toast(firstError(r) || 'Gagal menonaktifkan meja.', 'error', 6000); return }
    berubah = true
    toast(`Meja ${nomorLama} dinonaktifkan.`, 'success')
    await muat()
  })

  footer.querySelector('#mk-tambah').addEventListener('click', async () => {
    const input = footer.querySelector('#mk-nomor')
    const nomor = input.value.trim()
    if (!nomor) { toast('Isi nomor meja lebih dulu.', 'error'); return }
    const btn = footer.querySelector('#mk-tambah')
    btn.disabled = true
    const r = await api.table.tambah({ nomor })
    btn.disabled = false
    if (!r.ok) { toast(firstError(r) || 'Gagal menambah meja.', 'error', 6000); return }
    berubah = true
    input.value = ''
    toast(`Meja ${nomor} ditambahkan. Cetak QR-nya dari layar Meja & QR.`, 'success', 5000)
    await muat()
  })

  muat()
  return close
}

/** Dialog kecil untuk mengetik nomor baru. Mengembalikan string atau null. */
function mintaNomor(nomorLama) {
  return new Promise((resolve) => {
    const body = document.createElement('div')
    body.innerHTML = `
      <label class="field__label" for="mk-nomor-baru">Nomor meja</label>
      <input class="input" id="mk-nomor-baru" type="text" maxlength="30" value="${esc(nomorLama)}" />
      <p class="field__hint">Kode QR meja tidak berubah, jadi stiker yang sudah tertempel tetap berlaku.</p>`
    const footer = document.createElement('div')
    footer.innerHTML = `
      <button type="button" class="btn btn--ghost" id="mk-batal">Batal</button>
      <button type="button" class="btn btn--primary" id="mk-simpan">Simpan</button>`

    let hasil = null
    const { close } = showModal({
      title: `Ubah Meja ${nomorLama}`,
      body,
      footer,
      onClose: () => resolve(hasil)
    })
    const input = body.querySelector('#mk-nomor-baru')
    input.focus()
    input.select()
    const simpan = () => { hasil = input.value.trim(); close() }
    footer.querySelector('#mk-simpan').addEventListener('click', simpan)
    footer.querySelector('#mk-batal').addEventListener('click', () => close())
    input.addEventListener('keydown', (e) => { if (e.key === 'Enter') simpan() })
  })
}

/** Nama toko untuk judul (dipakai pemanggil bila perlu). */
export function namaToko() {
  return getState().toko?.nama || getState().company?.nama || 'Tuléh'
}
