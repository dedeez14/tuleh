// Dialog "Minta persetujuan": pilih pemegang hak yang sudah menyetel PIN, ia mengetik PIN-nya di
// perangkat kasir, server menukarnya dengan token sekali pakai (5 menit) untuk SATU aksi & transaksi.
// PIN tidak pernah disimpan, tidak pernah dicatat, dan input-nya tersamar.

import { api, firstError } from '../api.js'
import { showModal, toast } from './ui.js'
import { esc } from '../utils/format.js'
import { labelAksi, validasiIsianOtorisasi, detikTerkunci, pesanTerkunci } from '../lib/otorisasi.js'

/** @returns {Promise<string|null>} token persetujuan, atau null bila dibatalkan/gagal. */
export async function mintaOtorisasi({ aksi, transaksiId }) {
  const daftar = await api.keamanan.pemberi()
  if (!daftar.ok) {
    toast(firstError(daftar), 'error')
    return null
  }
  const pemberi = Array.isArray(daftar.data) ? daftar.data : []
  if (!pemberi.length) {
    toast('Belum ada atasan yang menyetel PIN persetujuan. Minta Owner/Manajer membukanya di Pengaturan → PIN persetujuan saya.', 'error', 9000)
    return null
  }

  return new Promise((resolve) => {
    const body = document.createElement('div')
    body.className = 'otorisasi-form'
    body.innerHTML = `
      <p class="field__hint" style="margin-bottom:12px">${esc(labelAksi(aksi, false))} memerlukan persetujuan. Minta atasan memasukkan PIN-nya di perangkat ini.</p>
      <div class="field">
        <label for="ot-pemberi">Pemberi persetujuan</label>
        <select class="select" id="ot-pemberi">${pemberi.map((p) => `<option value="${esc(p.id)}">${esc(p.nama)}${p.peran ? ` — ${esc(p.peran)}` : ''}</option>`).join('')}</select>
      </div>
      <div class="field">
        <label for="ot-pin">PIN persetujuan</label>
        <input class="input" id="ot-pin" type="password" inputmode="numeric" autocomplete="off" maxlength="8" placeholder="••••" />
        <div class="field__error u-hidden" id="ot-galat"></div>
      </div>`
    const footer = document.createElement('div')
    footer.className = 'hst-detail__foot'
    const btnBatal = document.createElement('button')
    btnBatal.className = 'btn btn--ghost'
    btnBatal.textContent = 'Batal'
    const btnKirim = document.createElement('button')
    btnKirim.className = 'btn btn--primary'
    btnKirim.textContent = 'Setujui'
    footer.append(btnBatal, btnKirim)

    // resolve(null) dipasang di onClose; jalur sukses me-resolve token SEBELUM close() —
    // resolve kedua no-op (pola yang sama dengan confirmDialog di ui.js).
    // Ditutup selagi permintaan melayang (X / overlay / Esc): onClose sudah resolve(null) dan
    // pemanggil berhenti, jadi jawaban yang datang belakangan TIDAK boleh menampilkan "diterima" —
    // token memang terbit di server, tapi tak ada yang membatalkan/merefund.
    let ditutup = false
    const { close } = showModal({ title: 'Minta persetujuan', body, footer, size: 'sm', onClose: () => { ditutup = true; hentikanHitungMundur(); resolve(null) } })
    const galatEl = body.querySelector('#ot-galat')
    const pinEl = body.querySelector('#ot-pin')
    const tampilkan = (pesan) => { galatEl.textContent = pesan; galatEl.classList.toggle('u-hidden', !pesan) }

    // Kunci PIN dipegang server (baris PIN, bukan timer perangkat) — hitung mundur ini hanya
    // memberi tahu kasir kapan pantas mencoba lagi; tombol dikunci selama itu agar tebakan
    // beruntun tidak memperpanjang kuncinya.
    let timer = null
    function hentikanHitungMundur() {
      if (timer) { clearInterval(timer); timer = null }
    }
    function mulaiHitungMundur(detik) {
      hentikanHitungMundur()
      let sisa = detik
      btnKirim.disabled = true
      const tik = () => {
        if (sisa <= 0) {
          hentikanHitungMundur()
          btnKirim.disabled = false
          tampilkan('Silakan coba lagi.')
          return
        }
        tampilkan(`Terlalu banyak PIN salah. Coba lagi dalam ${sisa} detik.`)
        sisa -= 1
      }
      tik()
      timer = setInterval(tik, 1000)
    }

    pinEl.addEventListener('input', () => { if (!timer) tampilkan('') })
    btnBatal.addEventListener('click', () => close())

    btnKirim.addEventListener('click', async () => {
      const pemberiId = body.querySelector('#ot-pemberi').value
      const pin = pinEl.value
      const galat = validasiIsianOtorisasi({ pemberiId, pin })
      if (galat) { tampilkan(galat); return }
      btnKirim.disabled = true
      btnKirim.textContent = 'Memeriksa…'
      const hasil = await api.keamanan.otorisasi({ pemberiId, pin, aksi, transaksiId })
      if (ditutup) return
      btnKirim.textContent = 'Setujui'
      if (!hasil.ok || !hasil.data || !hasil.data.token) {
        pinEl.value = ''
        const detik = detikTerkunci(hasil)
        if (detik) { mulaiHitungMundur(detik); return }
        btnKirim.disabled = false
        tampilkan(pesanTerkunci(hasil) || firstError(hasil))
        return
      }
      btnKirim.disabled = false
      toast(hasil.message || 'Persetujuan diterima.', 'success')
      resolve(hasil.data.token)
      close()
    })
  })
}
