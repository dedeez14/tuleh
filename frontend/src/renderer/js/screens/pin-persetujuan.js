// Kartu "PIN persetujuan saya" di Pengaturan — hanya untuk pemegang hak keamanan.pin. PIN dipakai
// menyetujui pembatalan/refund yang diminta kasir di perangkatnya; server menyimpannya ter-hash.

import { api, firstError } from '../api.js'
import { toast } from '../components/ui.js'
import { bisa } from '../akses.js'
import { pesanTerkunci } from '../lib/otorisasi.js'

/** Kalimat penolakan: hitung mundur kunci PIN bila 429, selainnya pesan server apa adanya. */
function galatPin(r) {
  return pesanTerkunci(r) || firstError(r) || r.message || 'Terjadi kesalahan.'
}

export async function mountPinPersetujuan(el) {
  if (!el || !bisa('keamanan.pin')) return
  const status = await api.keamanan.pinSaya()
  // `boleh_setel` = server menilai pengguna ini memang berhak membatalkan/merefund. Tanpa itu,
  // PIN-nya tak akan pernah bisa dipakai menyetujui apa pun — kartunya cuma membingungkan.
  if (!status.ok || !status.data || !status.data.boleh_setel) return
  let ada = !!status.data.ada

  const gambar = () => {
    el.innerHTML = `
      <section class="card">
        <div class="card__header"><h2 class="card__title">PIN persetujuan saya</h2></div>
        <div class="card__body">
          <div class="field__hint" style="margin-bottom:10px">
            Kasir tanpa hak membatalkan/merefund bisa meminta persetujuan Anda di perangkatnya —
            cukup PIN ini, tanpa kata sandi akun. Nama Anda tercatat pada transaksi yang disetujui.
          </div>
          <div class="field">
            <label class="field__label" for="pin-baru">${ada ? 'PIN baru' : 'PIN (4–8 digit)'}</label>
            <input class="input" id="pin-baru" type="password" inputmode="numeric" maxlength="8" autocomplete="off" />
          </div>
          ${ada ? `<div class="field">
            <label class="field__label" for="pin-lama">PIN lama</label>
            <input class="input" id="pin-lama" type="password" inputmode="numeric" maxlength="8" autocomplete="off" />
          </div>` : ''}
          <div class="set-actions">
            <button class="btn btn--primary" id="pin-simpan">${ada ? 'Ganti PIN' : 'Pasang PIN'}</button>
            ${ada ? '<button class="btn btn--danger-outline" id="pin-hapus">Hapus PIN</button>' : ''}
          </div>
        </div>
      </section>`

    el.querySelector('#pin-simpan').addEventListener('click', async () => {
      const r = await api.keamanan.pinSimpan({
        pin: el.querySelector('#pin-baru').value,
        pinLama: ada ? el.querySelector('#pin-lama').value : undefined
      }).catch((e) => ({ ok: false, message: e.message }))
      if (!r.ok) { toast(galatPin(r), 'error'); return }
      ada = true
      toast('PIN persetujuan tersimpan.', 'success')
      gambar()
    })
    // PIN lama WAJIB untuk menghapus (server 1f627b45 & kontrak-kanal): tanpa itu, "hapus lalu
    // pasang baru" adalah jalan pintas mengganti PIN dari sesi yang ditinggal terbuka.
    el.querySelector('#pin-hapus')?.addEventListener('click', async () => {
      const pinLama = el.querySelector('#pin-lama').value
      if (!pinLama) { toast('Isi PIN lama untuk menghapus PIN.', 'error'); return }
      const r = await api.keamanan.pinHapus({ pinLama }).catch((e) => ({ ok: false, message: e.message }))
      if (!r.ok) { toast(galatPin(r), 'error'); return }
      ada = false
      toast('PIN persetujuan dihapus — Anda tidak lagi muncul sebagai pemberi persetujuan.', 'success')
      gambar()
    })
  }
  gambar()
}
