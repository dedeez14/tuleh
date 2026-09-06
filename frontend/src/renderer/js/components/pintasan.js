// Daftar pintasan keyboard — satu sumber untuk panel bantuan (F1) dan
// dokumentasi. Ditulis dari sudut pandang kasir: apa yang terjadi, bukan
// nama fungsinya.

import { showModal } from './ui.js'
import { esc } from '../utils/format.js'

export const PINTASAN = Object.freeze({
  umum: [
    ['F1', 'Tampilkan daftar pintasan ini'],
    ['Esc', 'Tutup jendela; di layar lain: kembali ke Beranda'],
    ['Ctrl + 0', 'Beranda'],
    ['Ctrl + 1 … 9', 'Pindah layar sesuai urutan menu'],
    ['Ctrl + Shift + Q', 'Keluar akun']
  ],
  pos: [
    ['F2  /  /', 'Fokus ke kolom cari / scan barcode'],
    ['Tab', 'Dari kolom cari langsung ke produk pertama (lewati filter)'],
    ['↑ ↓ ← →', 'Pilih produk di katalog'],
    ['Home / End', 'Produk pertama / terakhir'],
    ['Enter / Spasi', 'Tambahkan produk yang dipilih ke keranjang'],
    ['+  /  −', 'Tambah / kurangi jumlah (produk yang dipilih, atau baris terakhir)'],
    ['Delete', 'Hapus baris keranjang (produk yang dipilih, atau baris terakhir)'],
    ['Huruf / angka', 'Di mana pun: langsung mengetik di kolom cari (scanner pun begitu)'],
    ['Esc', 'Kosongkan pencarian → lalu kembali ke Beranda'],
    ['F4  /  Ctrl + Enter', 'Bayar'],
    ['F8', 'Kosongkan keranjang'],
    ['F9', 'Parkir keranjang (simpan, lanjutkan nanti)'],
    ['F10', 'Buka daftar keranjang terparkir'],
    ['Shift + Tab', 'Dari katalog kembali ke kolom cari']
  ],
  bayar: [
    ['F5 / F6 / F7', 'Pilih metode bayar ke-1 / 2 / 3 (mis. Tunai / QRIS / Transfer)'],
    ['Angka', 'Ketik uang diterima; 50000 tampil 50.000; boleh "50rb"'],
    ['Enter', 'Selesaikan pembayaran'],
    ['Esc', 'Batal, kembali ke keranjang']
  ]
})

const JUDUL = { umum: 'Umum', pos: 'Kasir', bayar: 'Jendela pembayaran' }

function kbd(teks) {
  return teks.split('/').map((k) => `<span class="kbd">${esc(k.trim())}</span>`).join('<span class="pintasan__atau">/</span>')
}

/** Buka panel bantuan; `fokus` = kelompok yang ditaruh paling atas. */
export function bukaBantuanPintasan(fokus = 'umum') {
  if (document.querySelector('.pintasan')) return
  const urutan = [fokus, ...Object.keys(PINTASAN).filter((k) => k !== fokus)]
  const body = document.createElement('div')
  body.className = 'pintasan'
  body.innerHTML = urutan.map((k) => `
    <section class="pintasan__grup">
      <h3 class="pintasan__judul">${esc(JUDUL[k] || k)}</h3>
      <dl class="pintasan__daftar">
        ${PINTASAN[k].map(([tombol, arti]) => `<dt>${kbd(tombol)}</dt><dd>${esc(arti)}</dd>`).join('')}
      </dl>
    </section>`).join('')
  showModal({ title: 'Pintasan keyboard', body, size: 'md' })
}
