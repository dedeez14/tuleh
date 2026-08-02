'use strict'

// Data statis Mode Demo — dipakai demo.js. Semua nilai fiktif.

const COMPANY = {
  id: 'DEMO-CO',
  nama: 'Toko Demo Tuléh',
  alamat: 'Jl. Melati No. 12, Bandung',
  telepon: '022-7301234',
  npwp: null,
  logo: null
}

const USER = {
  id: 'DEMO-USR',
  name: 'Kasir Demo',
  email: 'demo@mpos.local',
  is_admin: true
}

const BRANCH = { id: 'DEMO-BR', nama: 'Cabang Utama' }

const KATEGORI = [
  { id: 'KAT-1', kode: 'MNM', nama: 'Minuman' },
  { id: 'KAT-2', kode: 'MKN', nama: 'Makanan' },
  { id: 'KAT-3', kode: 'SNK', nama: 'Snack' },
  { id: 'KAT-4', kode: 'SMB', nama: 'Sembako' },
  { id: 'KAT-5', kode: 'LAIN', nama: 'Lainnya' }
]

const GUDANG = [
  { id: 'GDG-1', kode: 'GU', nama: 'Gudang Utama' },
  { id: 'GDG-2', kode: 'GC', nama: 'Gudang Cabang' }
]

const SATUAN = [
  { id: 'SAT-1', kode: 'PCS', nama: 'Pcs' },
  { id: 'SAT-2', kode: 'CUP', nama: 'Cup' },
  { id: 'SAT-3', kode: 'PRS', nama: 'Porsi' },
  { id: 'SAT-4', kode: 'BTL', nama: 'Botol' },
  { id: 'SAT-5', kode: 'KG', nama: 'Kg' }
]

// { id, kode, nama, barcode, harga_jual, pajak_persen, satuan, kategori,
//   kelola_stok, stok, gambar }
function buatProduk() {
  const p = (n, kode, nama, barcode, harga, pajak, satuan, kategori, kelolaStok, stok) => ({
    id: `PRD-${String(n).padStart(3, '0')}`,
    kode,
    nama,
    barcode,
    harga_jual: harga,
    pajak_persen: pajak,
    satuan,
    satuan_id: null,
    kategori,
    kelola_stok: kelolaStok,
    stok,
    gambar: null
  })

  return [
    p(1, 'MNM-001', 'Kopi Susu Gula Aren', '8991002101', 18000, 11, 'Cup', 'Minuman', false, 0),
    p(2, 'MNM-002', 'Americano', '8991002102', 15000, 11, 'Cup', 'Minuman', false, 0),
    p(3, 'MNM-003', 'Cappuccino', '8991002103', 20000, 11, 'Cup', 'Minuman', false, 0),
    p(4, 'MNM-004', 'Es Teh Manis', '8991002104', 8000, 11, 'Cup', 'Minuman', false, 0),
    p(5, 'MNM-005', 'Teh Botol Sosro 450ml', '8886008101053', 5000, 0, 'Botol', 'Minuman', true, 48),
    p(6, 'MNM-006', 'Air Mineral 600ml', '8886008101015', 4000, 0, 'Botol', 'Minuman', true, 120),
    p(7, 'MNM-007', 'Jus Alpukat', '8991002107', 15000, 11, 'Cup', 'Minuman', false, 0),
    p(8, 'MKN-001', 'Nasi Goreng Spesial', '8991003101', 25000, 11, 'Porsi', 'Makanan', false, 0),
    p(9, 'MKN-002', 'Mie Ayam Bakso', '8991003102', 18000, 11, 'Porsi', 'Makanan', false, 0),
    p(10, 'MKN-003', 'Ayam Geprek + Nasi', '8991003103', 22000, 11, 'Porsi', 'Makanan', false, 0),
    p(11, 'MKN-004', 'Roti Bakar Coklat Keju', '8991003104', 15000, 11, 'Porsi', 'Makanan', false, 0),
    p(12, 'SNK-001', 'Chitato Sapi Panggang 68g', '089686043433', 12500, 0, 'Pcs', 'Snack', true, 36),
    p(13, 'SNK-002', 'Oreo Original 137g', '089686598101', 10000, 0, 'Pcs', 'Snack', true, 4),
    p(14, 'SNK-003', 'Kacang Garuda 100g', '089686043440', 9000, 0, 'Pcs', 'Snack', true, 22),
    p(15, 'SNK-004', 'Pisang Goreng (3 pcs)', '8991004104', 10000, 0, 'Porsi', 'Snack', false, 0),
    p(16, 'SMB-001', 'Beras Premium 5kg', '8991005101', 72000, 0, 'Pcs', 'Sembako', true, 15),
    p(17, 'SMB-002', 'Minyak Goreng 1L', '8991005102', 19000, 0, 'Pcs', 'Sembako', true, 3),
    p(18, 'SMB-003', 'Gula Pasir 1kg', '8991005103', 16000, 0, 'Pcs', 'Sembako', true, 28),
    p(19, 'SMB-004', 'Telur Ayam 1kg', '8991005104', 28000, 0, 'Kg', 'Sembako', true, 11),
    p(20, 'SMB-005', 'Indomie Goreng', '089686010947', 3500, 0, 'Pcs', 'Sembako', true, 96),
    p(21, 'LAIN-001', 'Tissue 250 lembar', '8991006101', 11000, 0, 'Pcs', 'Lainnya', true, 0),
    p(22, 'LAIN-002', 'Sabun Mandi Batang', '8991006102', 5500, 0, 'Pcs', 'Lainnya', true, 17)
  ]
}

// ---------- Toko demo (POS universal — tiga wajah aplikasi) ----------
// Format meniru persis GET /tokos & GET /tokos/{id}/manifest server MOVERA.

const TOKOS = [
  {
    id: 'TOKO-1',
    nama: 'Minimarket Demo',
    bidang_usaha: { code: 'minimarket', nama: 'Minimarket / Toko Kelontong', kategori: 'Retail', archetype: 'inventory_sale' },
    manifest_version: 1,
    is_active: true
  },
  {
    id: 'TOKO-2',
    nama: 'Bakso Mantap Demo',
    bidang_usaha: { code: 'bakso', nama: 'Warung Bakso / Kuliner', kategori: 'F&B', archetype: 'food_order' },
    manifest_version: 1,
    is_active: true
  },
  {
    id: 'TOKO-3',
    nama: 'Laundry Bersih Demo',
    bidang_usaha: { code: 'laundry', nama: 'Laundry Kiloan & Satuan', kategori: 'Jasa', archetype: 'service_job' },
    manifest_version: 1,
    is_active: true
  }
]

// Peran per menu (cermin filter server §3.2): menu manajemen hanya OWNER/MANAGER,
// sisanya operasional (semua peran). demo.js memfilter menus per peran aktif.
const ALL_ROLES = ['OWNER', 'MANAGER', 'KASIR']
const OM_ROLES = ['OWNER', 'MANAGER']
const MANAGEMENT_MENUS = new Set(['dashboard', 'inventory', 'pelanggan', 'pengeluaran', 'laporan', 'pengaturan', 'stasiun'])
const menuItem = (id, label, order) => ({
  id, label, icon: id, route_key: id, capability: id, required_permission: 'pos.view', order,
  roles: MANAGEMENT_MENUS.has(id) ? OM_ROLES : ALL_ROLES
})

// Fitur premium (semua nonaktif; menyala kelak hanya lewat perubahan flag server).
const PREMIUM_FEATURES = [
  { kode: 'multi_cabang', label: 'Multi Cabang', deskripsi: 'Dashboard terpusat banyak lokasi.', enabled: false },
  { kode: 'absensi_payroll', label: 'Absensi & Payroll', deskripsi: 'Catat jam kerja & gaji staf.', enabled: false },
  { kode: 'crm_membership', label: 'CRM & Membership', deskripsi: 'Sistem poin loyalitas & voucher.', enabled: false }
]

const MANIFESTS = {
  'TOKO-1': {
    vertical_code: 'minimarket',
    schema_version: 1,
    min_app_build: 1,
    menus: [
      menuItem('dashboard', 'Dashboard', 1),
      menuItem('kasir', 'Kasir', 2),
      menuItem('produk', 'Produk & Jasa', 3),
      menuItem('inventory', 'Inventory', 4),
      menuItem('riwayat', 'Riwayat', 5),
      menuItem('sesi', 'Sesi Kasir', 6),
      menuItem('pelanggan', 'Pelanggan', 7),
      menuItem('pengeluaran', 'Pengeluaran', 8),
      menuItem('laporan', 'Laporan', 9),
      menuItem('pengaturan', 'Pengaturan', 10)
    ],
    premium_features: PREMIUM_FEATURES,
    capabilities: ['catalog_grid', 'barcode_scan', 'cart', 'payment', 'receipt_print', 'inventory_fifo'],
    transaction_flow: ['SELECT_ITEMS', 'PAYMENT', 'PRINT'],
    lifecycle: { states: ['SELESAI'], transitions: [] },
    item_config: { unit_mode: 'single', identity: 'none', weighable: false },
    payment_modes: ['TUNAI', 'TRANSFER', 'QRIS'],
    station_types: [
      { type: 'cashier', label: 'Kasir', min: 1 }
    ],
    revision: 1
  },
  'TOKO-2': {
    vertical_code: 'bakso',
    schema_version: 1,
    min_app_build: 1,
    menus: [
      menuItem('dashboard', 'Dashboard', 1),
      menuItem('kasir', 'Kasir', 2),
      menuItem('dapur', 'Dapur (KDS)', 3),
      menuItem('antrian', 'Antrian', 4),
      menuItem('meja', 'Meja & QR', 5),
      menuItem('produk', 'Produk & Jasa', 6),
      menuItem('inventory', 'Inventory', 7),
      menuItem('riwayat', 'Riwayat', 8),
      menuItem('sesi', 'Sesi Kasir', 9),
      menuItem('stasiun', 'Stasiun', 10),
      menuItem('pelanggan', 'Pelanggan', 11),
      menuItem('pengeluaran', 'Pengeluaran', 12),
      menuItem('laporan', 'Laporan', 13),
      menuItem('pengaturan', 'Pengaturan', 14)
    ],
    premium_features: PREMIUM_FEATURES,
    capabilities: ['catalog_grid', 'cart', 'payment', 'receipt_print', 'kitchen', 'queue', 'tables_qr', 'customer_tracking', 'open_bill'],
    transaction_flow: ['OPEN_BILL', 'SELECT_ITEMS', 'KITCHEN_QUEUE', 'READY', 'SERVE', 'PAYMENT'],
    lifecycle: {
      states: ['ANTRIAN', 'DIPROSES', 'READY', 'SELESAI'],
      transitions: [
        { from: 'ANTRIAN', to: 'DIPROSES', actor: 'kitchen' },
        { from: 'DIPROSES', to: 'READY', actor: 'kitchen' },
        { from: 'READY', to: 'SELESAI', actor: 'waiter' }
      ]
    },
    item_config: { unit_mode: 'single', identity: 'none', weighable: false, notes: true },
    payment_modes: ['TUNAI', 'QRIS', 'TRANSFER'],
    station_types: [
      { type: 'cashier', label: 'Kasir', min: 1 },
      { type: 'kitchen', label: 'Dapur', min: 1 },
      { type: 'waiter', label: 'Waiter', min: 0 }
    ],
    revision: 1
  },
  'TOKO-3': {
    vertical_code: 'laundry',
    schema_version: 1,
    min_app_build: 1,
    menus: [
      menuItem('dashboard', 'Dashboard', 1),
      menuItem('kasir', 'Kasir / Penerimaan', 2),
      menuItem('proses', 'Papan Proses', 3),
      menuItem('produk', 'Layanan & Produk', 4),
      menuItem('inventory', 'Inventory', 5),
      menuItem('riwayat', 'Riwayat', 6),
      menuItem('sesi', 'Sesi Kasir', 7),
      menuItem('stasiun', 'Stasiun', 8),
      menuItem('pelanggan', 'Pelanggan', 9),
      menuItem('pengeluaran', 'Pengeluaran', 10),
      menuItem('laporan', 'Laporan', 11),
      menuItem('pengaturan', 'Pengaturan', 12)
    ],
    premium_features: PREMIUM_FEATURES,
    capabilities: ['cart', 'payment', 'receipt_print', 'stages', 'queue', 'self_service', 'customer_tracking', 'weighing', 'labels'],
    transaction_flow: ['INTAKE', 'PAYMENT_OR_LATER', 'STAGES', 'PICKUP'],
    lifecycle: {
      states: ['ANTRIAN', 'DIPROSES', 'PENCUCIAN', 'PENGERINGAN', 'LIPAT', 'SIAP_AMBIL', 'SELESAI'],
      transitions: [
        { from: 'ANTRIAN', to: 'DIPROSES', actor: 'staff' },
        { from: 'DIPROSES', to: 'PENCUCIAN', actor: 'staff' },
        { from: 'PENCUCIAN', to: 'PENGERINGAN', actor: 'staff' },
        { from: 'PENGERINGAN', to: 'LIPAT', actor: 'staff' },
        { from: 'LIPAT', to: 'SIAP_AMBIL', actor: 'staff' },
        { from: 'SIAP_AMBIL', to: 'SELESAI', actor: 'cashier' }
      ]
    },
    item_config: { unit_mode: 'weight_or_unit', identity: 'label', weighable: true },
    payment_modes: ['TUNAI', 'QRIS', 'TRANSFER'],
    station_types: [
      { type: 'cashier', label: 'Kasir / Penerimaan', min: 1 },
      { type: 'washer', label: 'Mesin Cuci', min: 0 },
      { type: 'dryer', label: 'Pengering', min: 0 },
      { type: 'folder', label: 'Meja Lipat', min: 0 }
    ],
    revision: 1
  }
}

// ---------- Katalog per toko (wajah kasir ikut bidang usaha) ----------

const KATEGORI_BAKSO = [
  { id: 'KB-1', kode: 'BKS', nama: 'Bakso' },
  { id: 'KB-2', kode: 'MIE', nama: 'Mie' },
  { id: 'KB-3', kode: 'MIN', nama: 'Minuman' },
  { id: 'KB-4', kode: 'TMB', nama: 'Tambahan' }
]

const KATEGORI_LAUNDRY = [
  { id: 'KL-1', kode: 'KIL', nama: 'Kiloan' },
  { id: 'KL-2', kode: 'SAT', nama: 'Satuan' },
  { id: 'KL-3', kode: 'EXP', nama: 'Express' }
]

function buatProdukBakso() {
  const p = (n, kode, nama, harga, satuan, kategori, kelolaStok = false, stok = 0) => ({
    id: `BSO-${String(n).padStart(3, '0')}`,
    kode, nama, barcode: null,
    harga_jual: harga, pajak_persen: 0,
    satuan, satuan_id: null, kategori,
    kelola_stok: kelolaStok, stok, gambar: null
  })
  return [
    p(1, 'BKS-001', 'Bakso Urat Spesial', 20000, 'Porsi', 'Bakso'),
    p(2, 'BKS-002', 'Bakso Halus Jumbo', 18000, 'Porsi', 'Bakso'),
    p(3, 'BKS-003', 'Bakso Campur', 23000, 'Porsi', 'Bakso'),
    p(4, 'BKS-004', 'Bakso Beranak', 28000, 'Porsi', 'Bakso'),
    p(5, 'MIE-001', 'Mie Ayam', 15000, 'Porsi', 'Mie'),
    p(6, 'MIE-002', 'Mie Ayam Bakso', 18000, 'Porsi', 'Mie'),
    p(7, 'MIN-001', 'Es Teh Manis', 5000, 'Cup', 'Minuman'),
    p(8, 'MIN-002', 'Es Jeruk', 7000, 'Cup', 'Minuman'),
    p(9, 'MIN-003', 'Teh Hangat', 4000, 'Cup', 'Minuman'),
    p(10, 'TMB-001', 'Kerupuk', 3000, 'Bungkus', 'Tambahan', true, 40),
    p(11, 'TMB-002', 'Nasi Putih', 5000, 'Porsi', 'Tambahan')
  ]
}

function buatProdukLaundry() {
  const p = (n, kode, nama, harga, satuan, kategori) => ({
    id: `LDR-${String(n).padStart(3, '0')}`,
    kode, nama, barcode: null,
    harga_jual: harga, pajak_persen: 0,
    satuan, satuan_id: null, kategori,
    kelola_stok: false, stok: 0, gambar: null
  })
  return [
    p(1, 'KIL-001', 'Cuci Kering Lipat', 7000, 'Kg', 'Kiloan'),
    p(2, 'KIL-002', 'Cuci Kering Setrika', 9000, 'Kg', 'Kiloan'),
    p(3, 'KIL-003', 'Setrika Saja', 5000, 'Kg', 'Kiloan'),
    p(4, 'EXP-001', 'Express 6 Jam (CKL)', 12000, 'Kg', 'Express'),
    p(5, 'SAT-001', 'Bed Cover', 25000, 'Pcs', 'Satuan'),
    p(6, 'SAT-002', 'Selimut', 20000, 'Pcs', 'Satuan'),
    p(7, 'SAT-003', 'Boneka Besar', 30000, 'Pcs', 'Satuan'),
    p(8, 'SAT-004', 'Sepatu (pasang)', 35000, 'Pcs', 'Satuan')
  ]
}

// Meja ber-QR untuk toko F&B (kode dipakai di URL /o/{kode} — stabil & unik)
const TABLES = [
  { id: 'MEJA-1', toko_id: 'TOKO-2', nomor: '1', kode: 'MJ-BAKSO-01' },
  { id: 'MEJA-2', toko_id: 'TOKO-2', nomor: '2', kode: 'MJ-BAKSO-02' },
  { id: 'MEJA-3', toko_id: 'TOKO-2', nomor: '3', kode: 'MJ-BAKSO-03' },
  { id: 'MEJA-4', toko_id: 'TOKO-2', nomor: '4', kode: 'MJ-BAKSO-04' },
  { id: 'MEJA-5', toko_id: 'TOKO-2', nomor: '5', kode: 'MJ-BAKSO-05' },
  { id: 'MEJA-6', toko_id: 'TOKO-2', nomor: '6', kode: 'MJ-BAKSO-06' },
  { id: 'MEJA-7', toko_id: 'TOKO-2', nomor: '7', kode: 'MJ-BAKSO-07' },
  { id: 'MEJA-8', toko_id: 'TOKO-2', nomor: '8', kode: 'MJ-BAKSO-08' }
]

const PELANGGAN_AWAL = [
  { id: 'CUST-1', kode: 'PLG-001', nama: 'Budi Santoso', telepon: '081234567801' },
  { id: 'CUST-2', kode: 'PLG-002', nama: 'Siti Aminah', telepon: '081234567802' },
  { id: 'CUST-3', kode: 'PLG-003', nama: 'Rudi Hartono', telepon: null },
  { id: 'CUST-4', kode: 'PLG-004', nama: 'Dewi Lestari', telepon: '081234567804' }
]

module.exports = {
  COMPANY, USER, BRANCH, KATEGORI, GUDANG, SATUAN, PELANGGAN_AWAL, TOKOS, MANIFESTS, TABLES,
  buatProduk, buatProdukBakso, buatProdukLaundry, KATEGORI_BAKSO, KATEGORI_LAUNDRY
}
