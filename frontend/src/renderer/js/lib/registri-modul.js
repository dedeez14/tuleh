// Registri modul Beranda — route_key manifest server → layar app. Satu sumber untuk desktop &
// Android (renderer yang sama). Menu datang dari manifest (sudah terfilter peran & terurut server);
// app merender apa adanya. Route_key baru dari server cukup didaftarkan SEKALI di sini.

export const MODULES = {
  kasir: { screen: 'pos', title: 'Kasir', icon: null, desc: 'Catat penjualan dengan cepat — katalog, barcode, dan pembayaran.' },
  // Arketipe jasa (laundry, bengkel, salon): order dicatat di layar kasir lalu berjalan di papan tahapan.
  order: { screen: 'pos', title: 'Order Baru', icon: null, desc: 'Catat order pelanggan — layanan, berat/jumlah, dan pembayaran.' },
  // Hospitality: tagihan kamar/layanan tamu dicatat di layar kasir.
  kamar: { screen: 'pos', title: 'Kamar', iconKey: 'store', desc: 'Tagihkan kamar, layanan, dan produk ke tamu.' },
  riwayat: { screen: 'history', title: 'Riwayat', icon: null, desc: 'Telusuri transaksi, cetak ulang struk, atau batalkan.' },
  sesi: { screen: 'sessions', title: 'Sesi Kasir', icon: null, desc: 'Buka/tutup shift kasir dan lihat rekap kas X/Z.' },
  laporan: { screen: 'reports', title: 'Laporan', icon: null, desc: 'Penjualan harian, per produk, stok, dan rekap kasir.' },
  pengaturan: { screen: 'settings', title: 'Pengaturan', icon: null, desc: 'Server, akun, dan informasi aplikasi.' },
  dapur: { screen: 'orders', title: 'Dapur (KDS)', iconKey: 'kitchen', desc: 'Layar dapur: klaim pesanan, mulai masak, tandai siap.' },
  antrian: { screen: 'orders', title: 'Antrian', iconKey: 'queue', desc: 'Papan nomor antrian pesanan yang sedang berjalan.' },
  proses: { screen: 'orders', title: 'Papan Proses', iconKey: 'kanban', desc: 'Tahapan pengerjaan pesanan, dari antrian sampai siap diambil.' },
  reservasi: { screen: 'orders', title: 'Reservasi', iconKey: 'kanban', desc: 'Pantau reservasi tamu dari masuk sampai selesai.' },
  meja: { screen: 'peta-meja', title: 'Meja', iconKey: 'store', desc: 'Buka meja, catat pesanan, dan bayar saat pulang.' },
  stasiun: { screen: 'stations', title: 'Stasiun', iconKey: 'station', desc: 'Atur jumlah & status stasiun kerja di toko ini.' },
  produk: { screen: 'products', title: 'Produk', iconKey: 'box', desc: 'Jelajahi katalog — harga, barcode, dan posisi stok.' },
  layanan: { screen: 'products', title: 'Layanan & Produk', iconKey: 'box', desc: 'Daftar layanan dan produk beserta harganya.' },
  inventory: { screen: 'inventory', title: 'Inventory', iconKey: 'box', desc: 'Tambah/kurangi stok, opname, & riwayat perubahan stok.' },
  pelanggan: { screen: 'customers', title: 'Pelanggan', iconKey: 'user', desc: 'Cari, lihat, dan tambahkan pelanggan.' },
  member: { screen: 'customers', title: 'Member', iconKey: 'user', desc: 'Cari dan kelola member beserta kontaknya.' },
  // Membership (gym, klinik): slot kelas/janji temu per hari + pesertanya.
  jadwal: { screen: 'jadwal', title: 'Jadwal', iconKey: 'session', desc: 'Kelas & janji temu hari ini — kuota, peserta, dan kehadiran.' },
  keuangan: { screen: 'keuangan', title: 'Keuangan', iconKey: 'report', desc: 'Omzet, laba, margin, metode bayar, dan tren.' },
  pengeluaran: { screen: 'pengeluaran', title: 'Pengeluaran', iconKey: 'wallet', desc: 'Catat biaya operasional: sewa, gaji, listrik, bahan.' },
  stok: { screen: 'stok', title: 'Stok', iconKey: 'box', desc: 'Pantau stok menipis, atur batas minimum, & saran restok.' }
}

// Peta id modul → token warna aksen (dipakai kartu Beranda; ikut dark via token)
export const MODULE_ACCENT = {
  kasir: 'kasir', order: 'kasir', kamar: 'kasir', dapur: 'dapur', antrian: 'antrian', proses: 'proses', reservasi: 'antrian',
  meja: 'meja', stasiun: 'stasiun', riwayat: 'riwayat', sesi: 'sesi', jadwal: 'sesi',
  laporan: 'laporan', produk: 'produk', layanan: 'produk', inventory: 'produk', pelanggan: 'pelanggan', member: 'pelanggan',
  pengaturan: 'pengaturan', keuangan: 'laporan', pengeluaran: 'meja', stok: 'dapur'
}

// Fitur ekstra khas app (DI LUAR manifest server) — analisis keuangan UMKM.
// Ditampilkan SETELAH menu manifest, hanya utk peran manajemen. Server tidak
// mengelola menu ini; keputusan pemilik (2 Agu 2026) mempertahankannya sbg
// nilai tambah app. Bukan pelanggaran "menu dari manifest" (itu soal filter peran).
const APP_EXTRA_MODULES = ['keuangan', 'stok']
// Route_key yang menuju tujuan yang sama persis (bukan sekadar berbagi layar seperti papan
// dapur/antrian/proses yang berbeda mode) — hanya satu kartu yang dirender.
const TUJUAN_SAMA = { member: 'pelanggan', layanan: 'produk' }
// Kapabilitas manifest yang membuka bon meja walau katalog tidak mengirim menu `meja`
// (katalog `fnb_kot` tidak punya menunya padahal tokonya memakai meja) — paritas
// `_kapabilitasMeja` di Flutter dan `cakupan()` di pemantau-pesanan.js.
const KAPABILITAS_MEJA = new Set(['tables_qr', 'tables'])
// Route_key yang bukan kartu Beranda (dashboard = Beranda itu sendiri).
const NON_CARD_ROUTES = new Set(['dashboard', 'home'])
// Fallback bila manifest tak menyertakan menus (server lama / tanpa /manifest):
// tampilkan set inti agar app tetap terpakai — bukan filter peran, murni kompatibilitas.
const DEFAULT_MENU_IDS = ['kasir', 'riwayat', 'sesi', 'produk', 'pelanggan', 'laporan', 'pengaturan']

/** Kartu utama Beranda = pintu transaksi (layar kasir). */
export function kartuUtama(id) {
  return !!MODULES[id] && MODULES[id].screen === 'pos'
}

/**
 * Susun kartu Beranda dari menu manifest ternormalisasi.
 * @param {{menus: Array<{id, routeKey, label, order}>, manajemen: boolean, capabilities?: string[], peringatan?: (routeKey) => void}} opsi
 */
export function susunModul({ menus, manajemen, capabilities = null, peringatan = null }) {
  const out = []
  const seen = new Set()
  const tujuanSudah = new Set()

  const push = (key, label, appExtra = false) => {
    if (!key || NON_CARD_ROUTES.has(key) || seen.has(key)) return
    const mod = MODULES[key]
    if (!mod) {
      // route_key yang app belum kenal → jangan render kartu rusak, tapi catat.
      if (peringatan) peringatan(key)
      return
    }
    seen.add(key)
    // Katalog server bisa mengirim dua route_key untuk satu tujuan (membership: member + pelanggan)
    // → satu kartu saja; yang lebih dulu menurut urutan manifest yang dipakai.
    const tujuan = TUJUAN_SAMA[key] || key
    if (tujuanSudah.has(tujuan)) return
    tujuanSudah.add(tujuan)
    out.push({ id: key, ...mod, title: label || mod.title, appExtra })
  }

  const daftar = Array.isArray(menus) ? menus : []
  if (daftar.length > 0) {
    for (const menu of [...daftar].sort((a, b) => (a.order || 0) - (b.order || 0))) {
      push(menu.routeKey || menu.id, menu.label)
    }
  } else {
    for (const id of DEFAULT_MENU_IDS) push(id, '')
  }

  // Bon meja digerbang KAPABILITAS toko, bukan menu: katalog `fnb_kot` tidak mengirim
  // route_key `meja` padahal tokonya memakai bon meja, jadi kartunya hilang saat menu
  // pindah ke manifest. Hanya bila belum ada kartu ke layar meja dari manifest.
  const kapabilitas = Array.isArray(capabilities) ? capabilities : []
  if (!out.some((k) => k.screen === 'peta-meja') && kapabilitas.some((c) => KAPABILITAS_MEJA.has(c))) {
    push('meja', '')
  }

  // Fitur ekstra app (keuangan, stok) memakai endpoint laporan → hanya manajemen.
  if (manajemen) {
    for (const key of APP_EXTRA_MODULES) push(key, '', true)
  }

  // Lantai Pengaturan: server menyaring menu manifest per hak akses dan peran Kasir bawaan
  // tidak memegang `pengaturan.lihat`, sehingga kasir kehilangan pintu ke setelan yang justru
  // LOKAL perangkat (printer, sinkronisasi, info app) — bukan data server. Selalu dikembalikan
  // bila manifest tak mengirimnya, tanpa melihat peran.
  push('pengaturan', '')

  return out
}
