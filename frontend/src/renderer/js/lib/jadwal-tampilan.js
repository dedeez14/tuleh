// Potongan render layar Jadwal yang digerbang hak akses `jadwal.kelola`.
// Murni: HTML/deskriptor dari argumen, tanpa DOM & tanpa jaringan — dipisah dari
// screens/jadwal.js supaya gerbangnya bisa diuji langsung (gagal-tertutup: tanpa
// `kelola` tak ada satu pun kontrol tulis yang ikut dirender, bukan sekadar disembunyikan
// CSS). Server tetap berwenang menolak endpointnya.

import { esc } from '../utils/format.js'
import { icons } from '../components/ui.js'

export const STATUS_PESERTA = [
  { id: 'TERDAFTAR', label: 'Terdaftar' },
  { id: 'HADIR', label: 'Hadir' },
  { id: 'BATAL', label: 'Batal' }
]

// Tombol tulis pada kaki modal detail — urutannya urutan tampil (kiri → kanan).
const AKSI_DETAIL = [
  { kunci: 'batal', kelas: 'btn btn--ghost', label: 'Batalkan jadwal' },
  { kunci: 'ubah', kelas: 'btn btn--outline', label: 'Ubah jadwal' },
  { kunci: 'daftar', kelas: 'btn btn--primary', label: 'Daftarkan peserta' }
]

/** Kepala halaman; tombol "Tambah Jadwal" hanya untuk pemegang `jadwal.kelola`. */
export function kepalaJadwalHTML(kelola) {
  return `<div class="page-head">
          <div>
            <h1 class="page-head__title">Jadwal</h1>
            <p class="page-head__desc">Kelas &amp; janji temu toko ini — kuota, peserta, dan kehadiran.</p>
          </div>
          ${kelola ? `<button type="button" class="btn btn--primary" id="jdw-add">${icons.plus}<span>Tambah Jadwal</span></button>` : ''}
        </div>`
}

/**
 * Daftar peserta slot. Tanpa `kelola`: status jadi lencana baca-saja dan tombol
 * lepas peserta tidak dirender sama sekali.
 */
export function pesertaTabelHTML(peserta, kelola) {
  const rows = Array.isArray(peserta) ? peserta : []
  if (rows.length === 0) return '<p class="u-muted">Belum ada peserta terdaftar.</p>'
  return `<table class="table jdw-peserta"><thead><tr><th>Peserta</th><th>Status</th><th></th></tr></thead><tbody>
                ${rows.map((p) => `
                  <tr data-peserta="${esc(p.id)}">
                    <td>${esc(p.nama)}${p.telepon ? `<div class="u-faint mono">${esc(p.telepon)}</div>` : ''}</td>
                    <td>${kelola
                      ? `<select class="select" data-status>${STATUS_PESERTA.map((x) => `<option value="${x.id}"${x.id === p.status ? ' selected' : ''}>${x.label}</option>`).join('')}</select>`
                      : `<span class="badge">${esc(p.status)}</span>`}</td>
                    <td>${kelola ? `<button type="button" class="icon-btn" data-lepas title="Lepas peserta">${icons.trash}</button>` : ''}</td>
                  </tr>`).join('')}
              </tbody></table>`
}

/** Tombol tulis kaki modal detail — daftar KOSONG tanpa `jadwal.kelola`. */
export function aksiDetailJadwal(kelola) {
  return kelola ? AKSI_DETAIL.map((a) => ({ ...a })) : []
}
