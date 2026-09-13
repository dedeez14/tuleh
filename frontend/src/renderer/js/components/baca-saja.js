// Kartu pengaturan versi BACA untuk pengguna tanpa kunci ubah (mis. Manager pada profil usaha,
// pembayaran): isian & tombol dimatikan, baris aksi disembunyikan, diberi catatan. Hanya
// tampilan — server tetap penentu hak ubah.

import { esc } from '../utils/format.js'

export const CATATAN_PEMILIK = 'Hanya pemilik usaha yang dapat mengubah pengaturan ini.'

export function jadikanBacaSaja(body, catatan = CATATAN_PEMILIK) {
  if (!body) return
  body.querySelectorAll('input, select, textarea, button').forEach((el) => { el.disabled = true })
  body.querySelectorAll('.set-actions, .pb-bank-del').forEach((el) => el.classList.add('u-hidden'))
  body.insertAdjacentHTML('afterbegin', `<div class="field__hint baca-saja">${esc(catatan)}</div>`)
}
