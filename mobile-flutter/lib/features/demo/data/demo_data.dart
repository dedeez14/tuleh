/// Data statis Mode Demo — cermin `frontend/src/main/demo-data.js` (desktop).
/// Semua nilai fiktif. Enam toko contoh mewakili tiap alur POS universal:
/// retail (bayar = selesai), F&B (dapur + antrian + bon meja), dan jasa
/// bertahap (laundry, bengkel, doorsmeer, salon).
library;

const demoCompany = {
  'id': 'DEMO-CO',
  'nama': 'Toko Demo Tuléh',
  'alamat': 'Jl. Melati No. 12, Bandung',
  'telepon': '022-7301234',
  'email': null,
  'npwp': null,
  'logo': null,
};

const demoUser = {
  'id': 'DEMO-USR',
  'name': 'Kasir Demo',
  'email': 'demo@tuleh.local',
  'pos_role': 'OWNER',
  'is_admin': true,
};

const demoGudang = [
  {'id': 'GDG-1', 'kode': 'GU', 'nama': 'Gudang Utama'},
  {'id': 'GDG-2', 'kode': 'GC', 'nama': 'Gudang Cabang'},
];

const demoPelanggan = [
  {'id': 'CUST-1', 'kode': 'PLG-001', 'nama': 'Budi Santoso', 'telepon': '081234567801'},
  {'id': 'CUST-2', 'kode': 'PLG-002', 'nama': 'Siti Aminah', 'telepon': '081234567802'},
  {'id': 'CUST-3', 'kode': 'PLG-003', 'nama': 'Rudi Hartono', 'telepon': null},
  {'id': 'CUST-4', 'kode': 'PLG-004', 'nama': 'Dewi Lestari', 'telepon': '081234567804'},
];

/// Daftar toko — `GET /tokos`.
const demoTokos = [
  {
    'id': 'TOKO-1',
    'nama': 'Minimarket Demo',
    'bidang_usaha': {
      'code': 'minimarket',
      'nama': 'Minimarket / Toko Kelontong',
      'kategori': 'Retail',
      'archetype': 'inventory_sale',
    },
    'is_active': true,
  },
  {
    'id': 'TOKO-2',
    'nama': 'Bakso Mantap Demo',
    'bidang_usaha': {
      'code': 'bakso',
      'nama': 'Warung Bakso / Kuliner',
      'kategori': 'F&B',
      'archetype': 'food_order',
    },
    'is_active': true,
  },
  {
    'id': 'TOKO-3',
    'nama': 'Laundry Bersih Demo',
    'bidang_usaha': {
      'code': 'laundry',
      'nama': 'Laundry Kiloan & Satuan',
      'kategori': 'Jasa',
      'archetype': 'service_job',
    },
    'is_active': true,
  },
  {
    'id': 'TOKO-4',
    'nama': 'Bengkel Jaya Demo',
    'bidang_usaha': {
      'code': 'bengkel',
      'nama': 'Bengkel Motor/Mobil',
      'kategori': 'Jasa Lifecycle',
      'archetype': 'service_lifecycle',
    },
    'is_active': true,
  },
  {
    'id': 'TOKO-5',
    'nama': 'Doorsmeer Kinclong Demo',
    'bidang_usaha': {
      'code': 'doorsmeer',
      'nama': 'Doorsmeer / Cuci Mobil & Motor',
      'kategori': 'Jasa Lifecycle',
      'archetype': 'service_lifecycle',
    },
    'is_active': true,
  },
  {
    'id': 'TOKO-6',
    'nama': 'Barbershop Rapi Demo',
    'bidang_usaha': {
      'code': 'salon',
      'nama': 'Salon / Barbershop',
      'kategori': 'Jasa Lifecycle',
      'archetype': 'service_lifecycle',
    },
    'is_active': true,
  },
];

// ---------- Manifest per toko (`GET /tokos/{id}/manifest`) ----------

const _allRoles = ['OWNER', 'MANAGER', 'KASIR'];
const _omRoles = ['OWNER', 'MANAGER'];
const _menuManajemen = {
  'dashboard',
  'inventory',
  'pelanggan',
  'pengeluaran',
  'laporan',
  'pengaturan',
  'stasiun',
};

Map<String, dynamic> _menu(String id, String label, int order) => {
  'id': id,
  'label': label,
  'icon': id,
  'route_key': id,
  'capability': id,
  'order': order,
  'roles': _menuManajemen.contains(id) ? _omRoles : _allRoles,
};

const _premiumFeatures = [
  {
    'kode': 'multi_cabang',
    'label': 'Multi Cabang',
    'deskripsi': 'Dashboard terpusat banyak lokasi.',
    'enabled': false,
  },
  {
    'kode': 'absensi_payroll',
    'label': 'Absensi & Payroll',
    'deskripsi': 'Catat jam kerja & gaji staf.',
    'enabled': false,
  },
  {
    'kode': 'crm_membership',
    'label': 'CRM & Membership',
    'deskripsi': 'Sistem poin loyalitas & voucher.',
    'enabled': false,
  },
];

/// Rantai transisi berurutan dari daftar tahap.
List<Map<String, dynamic>> _transitions(List<String> states, String actor) => [
  for (var i = 0; i < states.length - 1; i++)
    {
      'from': states[i],
      'to': states[i + 1],
      'actor': i == states.length - 2 ? 'cashier' : actor,
    },
];

Map<String, dynamic> _manifest({
  required String vertical,
  required List<Map<String, dynamic>> menus,
  required List<String> capabilities,
  required List<String> flow,
  required List<String> states,
  required List<Map<String, dynamic>> stations,
  String actor = 'staff',
  Map<String, dynamic> itemConfig = const {
    'unit_mode': 'unit',
    'identity': 'none',
    'weighable': false,
  },
}) => {
  'vertical_code': vertical,
  'schema_version': 1,
  'min_app_build': 1,
  'menus': menus,
  'premium_features': _premiumFeatures,
  'capabilities': capabilities,
  'transaction_flow': flow,
  'lifecycle': {'states': states, 'transitions': _transitions(states, actor)},
  'item_config': itemConfig,
  'payment_modes': ['TUNAI', 'QRIS', 'TRANSFER'],
  'station_types': stations,
  'revision': 1,
};

/// Manifest lengkap per toko demo.
final demoManifests = <String, Map<String, dynamic>>{
  'TOKO-1': _manifest(
    vertical: 'minimarket',
    menus: [
      _menu('dashboard', 'Dashboard', 1),
      _menu('kasir', 'Kasir', 2),
      _menu('produk', 'Produk & Jasa', 3),
      _menu('inventory', 'Inventory', 4),
      _menu('riwayat', 'Riwayat', 5),
      _menu('sesi', 'Sesi Kasir', 6),
      _menu('pelanggan', 'Pelanggan', 7),
      _menu('pengeluaran', 'Pengeluaran', 8),
      _menu('laporan', 'Laporan', 9),
      _menu('pengaturan', 'Pengaturan', 10),
    ],
    capabilities: [
      'catalog_grid',
      'barcode_scan',
      'cart',
      'payment',
      'receipt_print',
      'inventory_fifo',
    ],
    flow: ['SELECT_ITEMS', 'PAYMENT', 'PRINT'],
    states: ['SELESAI'],
    stations: [
      {'type': 'cashier', 'label': 'Kasir', 'min': 1},
    ],
  ),
  'TOKO-2': _manifest(
    vertical: 'bakso',
    menus: [
      _menu('dashboard', 'Dashboard', 1),
      _menu('kasir', 'Kasir', 2),
      _menu('dapur', 'Dapur (KDS)', 3),
      _menu('antrian', 'Antrian', 4),
      _menu('meja', 'Meja & QR', 5),
      _menu('produk', 'Produk & Jasa', 6),
      _menu('inventory', 'Inventory', 7),
      _menu('riwayat', 'Riwayat', 8),
      _menu('sesi', 'Sesi Kasir', 9),
      _menu('stasiun', 'Stasiun', 10),
      _menu('pelanggan', 'Pelanggan', 11),
      _menu('pengeluaran', 'Pengeluaran', 12),
      _menu('laporan', 'Laporan', 13),
      _menu('pengaturan', 'Pengaturan', 14),
    ],
    capabilities: [
      'catalog_grid',
      'cart',
      'payment',
      'receipt_print',
      'kitchen',
      'queue',
      'tables_qr',
      'customer_tracking',
      'open_bill',
    ],
    flow: [
      'OPEN_BILL',
      'SELECT_ITEMS',
      'KITCHEN_QUEUE',
      'READY',
      'SERVE',
      'PAYMENT',
    ],
    states: ['ANTRIAN', 'DIPROSES', 'READY', 'SELESAI'],
    actor: 'kitchen',
    stations: [
      {'type': 'cashier', 'label': 'Kasir', 'min': 1},
      {'type': 'kitchen', 'label': 'Dapur', 'min': 1},
      {'type': 'waiter', 'label': 'Waiter', 'min': 0},
    ],
  ),
  'TOKO-3': _manifest(
    vertical: 'laundry',
    menus: [
      _menu('dashboard', 'Dashboard', 1),
      _menu('kasir', 'Kasir / Penerimaan', 2),
      _menu('proses', 'Papan Proses', 3),
      _menu('produk', 'Layanan & Produk', 4),
      _menu('inventory', 'Inventory', 5),
      _menu('riwayat', 'Riwayat', 6),
      _menu('sesi', 'Sesi Kasir', 7),
      _menu('stasiun', 'Stasiun', 8),
      _menu('pelanggan', 'Pelanggan', 9),
      _menu('pengeluaran', 'Pengeluaran', 10),
      _menu('laporan', 'Laporan', 11),
      _menu('pengaturan', 'Pengaturan', 12),
    ],
    capabilities: [
      'cart',
      'payment',
      'receipt_print',
      'stages',
      'queue',
      'customer_tracking',
      'weighing',
      'labels',
    ],
    flow: ['INTAKE', 'PAYMENT_OR_LATER', 'STAGES', 'PICKUP'],
    states: [
      'ANTRIAN',
      'DIPROSES',
      'PENCUCIAN',
      'PENGERINGAN',
      'LIPAT',
      'SIAP_AMBIL',
      'SELESAI',
    ],
    itemConfig: {
      'unit_mode': 'weight_or_unit',
      'identity': 'label',
      'weighable': true,
    },
    stations: [
      {'type': 'cashier', 'label': 'Kasir / Penerimaan', 'min': 1},
      {'type': 'washer', 'label': 'Mesin Cuci', 'min': 0},
      {'type': 'dryer', 'label': 'Pengering', 'min': 0},
      {'type': 'folder', 'label': 'Meja Lipat', 'min': 0},
    ],
  ),
  'TOKO-4': _manifest(
    vertical: 'bengkel',
    menus: [
      _menu('dashboard', 'Dashboard', 1),
      _menu('kasir', 'Kasir / Servis Baru', 2),
      _menu('proses', 'Antrian Servis', 3),
      _menu('produk', 'Jasa & Suku Cadang', 4),
      _menu('inventory', 'Inventory', 5),
      _menu('riwayat', 'Riwayat', 6),
      _menu('sesi', 'Sesi Kasir', 7),
      _menu('stasiun', 'Stasiun', 8),
      _menu('pelanggan', 'Pelanggan', 9),
      _menu('pengeluaran', 'Pengeluaran', 10),
      _menu('laporan', 'Laporan', 11),
      _menu('pengaturan', 'Pengaturan', 12),
    ],
    capabilities: [
      'cart',
      'payment',
      'receipt_print',
      'stages',
      'queue',
      'customer_tracking',
    ],
    flow: ['INTAKE', 'PAYMENT_OR_LATER', 'STAGES', 'PICKUP'],
    states: ['ANTRIAN', 'PEMERIKSAAN', 'PENGERJAAN', 'SIAP_AMBIL', 'SELESAI'],
    stations: [
      {'type': 'cashier', 'label': 'Kasir', 'min': 1},
      {'type': 'mechanic', 'label': 'Mekanik', 'min': 1},
      {'type': 'bay', 'label': 'Pit / Bay', 'min': 0},
    ],
  ),
  'TOKO-5': _manifest(
    vertical: 'doorsmeer',
    menus: [
      _menu('dashboard', 'Dashboard', 1),
      _menu('kasir', 'Kasir / Penerimaan', 2),
      _menu('proses', 'Papan Cuci', 3),
      _menu('produk', 'Layanan & Produk', 4),
      _menu('inventory', 'Inventory', 5),
      _menu('riwayat', 'Riwayat', 6),
      _menu('sesi', 'Sesi Kasir', 7),
      _menu('stasiun', 'Bay & Stasiun', 8),
      _menu('pelanggan', 'Pelanggan', 9),
      _menu('pengeluaran', 'Pengeluaran', 10),
      _menu('laporan', 'Laporan', 11),
      _menu('pengaturan', 'Pengaturan', 12),
    ],
    capabilities: [
      'cart',
      'payment',
      'receipt_print',
      'stages',
      'queue',
      'customer_tracking',
    ],
    flow: ['INTAKE', 'PAYMENT_OR_LATER', 'STAGES', 'PICKUP'],
    states: [
      'ANTRIAN',
      'PENCUCIAN',
      'PENGERINGAN',
      'FINISHING',
      'SIAP_AMBIL',
      'SELESAI',
    ],
    itemConfig: {
      'unit_mode': 'unit',
      'identity': 'plate',
      'weighable': false,
    },
    stations: [
      {'type': 'cashier', 'label': 'Kasir', 'min': 1},
      {'type': 'washing', 'label': 'Pencucian', 'min': 1},
      {'type': 'finishing', 'label': 'Finishing & Poles', 'min': 0},
    ],
  ),
  'TOKO-6': _manifest(
    vertical: 'salon',
    menus: [
      _menu('dashboard', 'Dashboard', 1),
      _menu('kasir', 'Kasir', 2),
      _menu('antrian', 'Antrian Cukur', 3),
      _menu('produk', 'Layanan & Produk', 4),
      _menu('inventory', 'Inventory', 5),
      _menu('riwayat', 'Riwayat', 6),
      _menu('sesi', 'Sesi Kasir', 7),
      _menu('stasiun', 'Kursi & Kapster', 8),
      _menu('pelanggan', 'Pelanggan', 9),
      _menu('pengeluaran', 'Pengeluaran', 10),
      _menu('laporan', 'Laporan', 11),
      _menu('pengaturan', 'Pengaturan', 12),
    ],
    capabilities: [
      'cart',
      'payment',
      'receipt_print',
      'stages',
      'queue',
      'customer_tracking',
    ],
    flow: ['QUEUE', 'SERVICE', 'PAYMENT_OR_LATER'],
    states: ['ANTRIAN', 'DILAYANI', 'SELESAI'],
    stations: [
      {'type': 'cashier', 'label': 'Kasir', 'min': 1},
      {'type': 'chair', 'label': 'Kursi / Kapster', 'min': 1},
    ],
  ),
};

/// Prefix nomor antrian per toko (cermin `antrian_prefix` server).
const demoAntrianPrefix = {
  'TOKO-2': 'A',
  'TOKO-3': 'L',
  'TOKO-4': 'B',
  'TOKO-5': 'D',
  'TOKO-6': 'S',
};

// ---------- Katalog per toko ----------

int _prd = 0;

Map<String, dynamic> _item(
  String prefix,
  String kode,
  String nama,
  num harga,
  String satuan,
  String kategori, {
  bool stok = false,
  int jumlah = 0,
  String? barcode,
}) {
  _prd += 1;
  return {
    'id': '$prefix-${_prd.toString().padLeft(3, '0')}',
    'kode': kode,
    'nama': nama,
    'barcode': barcode,
    'tipe': stok ? 'PRODUK' : 'JASA',
    'harga_jual': harga,
    'harga_beli': stok ? (harga * 0.65).round() : null,
    'pajak_persen': 0,
    'satuan': satuan,
    'satuan_id': null,
    'kategori': kategori,
    'kelola_stok': stok,
    'stok': jumlah,
    'gambar': null,
  };
}

/// Katalog + kategori tiap toko. Dibuat ulang tiap demo dimulai (state segar).
Map<String, Map<String, List<Map<String, dynamic>>>> buatKatalogDemo() {
  _prd = 0;
  final minimarket = [
    _item('PRD', 'MNM-005', 'Teh Botol Sosro 450ml', 5000, 'Botol', 'Minuman',
        stok: true, jumlah: 48, barcode: '8886008101053'),
    _item('PRD', 'MNM-006', 'Air Mineral 600ml', 4000, 'Botol', 'Minuman',
        stok: true, jumlah: 120, barcode: '8886008101015'),
    _item('PRD', 'SNK-001', 'Chitato Sapi Panggang 68g', 12500, 'Pcs', 'Snack',
        stok: true, jumlah: 36, barcode: '089686043433'),
    _item('PRD', 'SNK-002', 'Oreo Original 137g', 10000, 'Pcs', 'Snack',
        stok: true, jumlah: 4, barcode: '089686598101'),
    _item('PRD', 'SNK-003', 'Kacang Garuda 100g', 9000, 'Pcs', 'Snack',
        stok: true, jumlah: 22),
    _item('PRD', 'SMB-001', 'Beras Premium 5kg', 72000, 'Pcs', 'Sembako',
        stok: true, jumlah: 15),
    _item('PRD', 'SMB-002', 'Minyak Goreng 1L', 19000, 'Pcs', 'Sembako',
        stok: true, jumlah: 3),
    _item('PRD', 'SMB-003', 'Gula Pasir 1kg', 16000, 'Pcs', 'Sembako',
        stok: true, jumlah: 28),
    _item('PRD', 'SMB-004', 'Telur Ayam 1kg', 28000, 'Kg', 'Sembako',
        stok: true, jumlah: 11),
    _item('PRD', 'SMB-005', 'Indomie Goreng', 3500, 'Pcs', 'Sembako',
        stok: true, jumlah: 96, barcode: '089686010947'),
    _item('PRD', 'LAIN-001', 'Tissue 250 lembar', 11000, 'Pcs', 'Lainnya',
        stok: true, jumlah: 0),
    _item('PRD', 'LAIN-002', 'Sabun Mandi Batang', 5500, 'Pcs', 'Lainnya',
        stok: true, jumlah: 17),
  ];

  _prd = 0;
  final bakso = [
    _item('BSO', 'BKS-001', 'Bakso Urat Spesial', 20000, 'Porsi', 'Bakso'),
    _item('BSO', 'BKS-002', 'Bakso Halus Jumbo', 18000, 'Porsi', 'Bakso'),
    _item('BSO', 'BKS-003', 'Bakso Campur', 23000, 'Porsi', 'Bakso'),
    _item('BSO', 'BKS-004', 'Bakso Beranak', 28000, 'Porsi', 'Bakso'),
    _item('BSO', 'MIE-001', 'Mie Ayam', 15000, 'Porsi', 'Mie'),
    _item('BSO', 'MIE-002', 'Mie Ayam Bakso', 18000, 'Porsi', 'Mie'),
    _item('BSO', 'MIN-001', 'Es Teh Manis', 5000, 'Cup', 'Minuman'),
    _item('BSO', 'MIN-002', 'Es Jeruk', 7000, 'Cup', 'Minuman'),
    _item('BSO', 'MIN-003', 'Teh Hangat', 4000, 'Cup', 'Minuman'),
    _item('BSO', 'TMB-001', 'Kerupuk', 3000, 'Bungkus', 'Tambahan',
        stok: true, jumlah: 40),
    _item('BSO', 'TMB-002', 'Nasi Putih', 5000, 'Porsi', 'Tambahan'),
  ];

  _prd = 0;
  final laundry = [
    _item('LDR', 'KIL-001', 'Cuci Kering Lipat', 7000, 'Kg', 'Kiloan'),
    _item('LDR', 'KIL-002', 'Cuci Kering Setrika', 9000, 'Kg', 'Kiloan'),
    _item('LDR', 'KIL-003', 'Setrika Saja', 5000, 'Kg', 'Kiloan'),
    _item('LDR', 'EXP-001', 'Express 6 Jam (CKL)', 12000, 'Kg', 'Express'),
    _item('LDR', 'SAT-001', 'Bed Cover', 25000, 'Pcs', 'Satuan'),
    _item('LDR', 'SAT-002', 'Selimut', 20000, 'Pcs', 'Satuan'),
    _item('LDR', 'SAT-003', 'Boneka Besar', 30000, 'Pcs', 'Satuan'),
    _item('LDR', 'SAT-004', 'Sepatu (pasang)', 35000, 'Pcs', 'Satuan'),
  ];

  _prd = 0;
  final bengkel = [
    _item('BKL', 'JSV-001', 'Ganti Oli (jasa)', 20000, 'Unit', 'Jasa Servis'),
    _item('BKL', 'JSV-002', 'Servis Ringan / Tune Up', 75000, 'Unit', 'Jasa Servis'),
    _item('BKL', 'JSV-003', 'Ganti Kampas Rem (jasa)', 35000, 'Unit', 'Jasa Servis'),
    _item('BKL', 'JSV-004', 'Tambal Ban', 15000, 'Unit', 'Jasa Servis'),
    _item('BKL', 'JSV-005', 'Servis Besar / Turun Mesin', 350000, 'Unit', 'Jasa Servis'),
    _item('BKL', 'OLI-001', 'Oli Mesin 1 L', 55000, 'Botol', 'Oli & Pelumas',
        stok: true, jumlah: 24),
    _item('BKL', 'OLI-002', 'Oli Gardan 120 ml', 18000, 'Botol', 'Oli & Pelumas',
        stok: true, jumlah: 15),
    _item('BKL', 'SPR-001', 'Busi', 25000, 'Pcs', 'Suku Cadang',
        stok: true, jumlah: 30),
    _item('BKL', 'SPR-002', 'Kampas Rem Depan', 65000, 'Set', 'Suku Cadang',
        stok: true, jumlah: 12),
    _item('BKL', 'SPR-003', 'Filter Udara', 40000, 'Pcs', 'Suku Cadang',
        stok: true, jumlah: 8),
    _item('BKL', 'SPR-004', 'Ban Dalam', 35000, 'Pcs', 'Suku Cadang',
        stok: true, jumlah: 10),
  ];

  _prd = 0;
  final doorsmeer = [
    _item('DSM', 'MTR-001', 'Cuci Motor', 15000, 'Unit', 'Motor'),
    _item('DSM', 'MTR-002', 'Cuci Motor Besar / Moge', 25000, 'Unit', 'Motor'),
    _item('DSM', 'MTR-003', 'Cuci Motor + Semir Ban', 20000, 'Unit', 'Motor'),
    _item('DSM', 'MBL-001', 'Cuci Mobil Kecil (City Car)', 40000, 'Unit', 'Mobil'),
    _item('DSM', 'MBL-002', 'Cuci Mobil Besar (SUV/MPV)', 55000, 'Unit', 'Mobil'),
    _item('DSM', 'MBL-003', 'Cuci + Vacuum Interior', 70000, 'Unit', 'Mobil'),
    _item('DSM', 'DTL-001', 'Cuci Mesin', 60000, 'Unit', 'Detailing'),
    _item('DSM', 'DTL-002', 'Poles Body', 150000, 'Unit', 'Detailing'),
    _item('DSM', 'PRD-001', 'Parfum Mobil Gantung', 25000, 'Pcs', 'Produk',
        stok: true, jumlah: 12),
    _item('DSM', 'PRD-002', 'Shampo Mobil 1L', 35000, 'Botol', 'Produk',
        stok: true, jumlah: 4),
    _item('DSM', 'PRD-003', 'Kanebo / Lap Chamois', 20000, 'Pcs', 'Produk',
        stok: true, jumlah: 9),
  ];

  _prd = 0;
  final salon = [
    _item('SLN', 'PTG-001', 'Potong Rambut Dewasa', 35000, 'Unit', 'Potong'),
    _item('SLN', 'PTG-002', 'Potong Rambut Anak', 25000, 'Unit', 'Potong'),
    _item('SLN', 'PTG-003', 'Potong + Cuci + Pijat', 55000, 'Unit', 'Potong'),
    _item('SLN', 'PTG-004', 'Cukur Jenggot & Kumis', 15000, 'Unit', 'Potong'),
    _item('SLN', 'PTG-005', 'Hair Tattoo / Ukir', 20000, 'Unit', 'Potong'),
    _item('SLN', 'RWT-001', 'Creambath', 45000, 'Unit', 'Perawatan'),
    _item('SLN', 'RWT-002', 'Semir Rambut', 60000, 'Unit', 'Perawatan'),
    _item('SLN', 'PRD-001', 'Pomade Water Based 100g', 60000, 'Pcs', 'Produk',
        stok: true, jumlah: 9),
    _item('SLN', 'PRD-002', 'Hair Tonic 120ml', 45000, 'Botol', 'Produk',
        stok: true, jumlah: 3),
    _item('SLN', 'PRD-003', 'Sisir Saku', 10000, 'Pcs', 'Produk',
        stok: true, jumlah: 20),
  ];

  Map<String, List<Map<String, dynamic>>> pack(
    List<Map<String, dynamic>> produk,
    List<String> kategori,
  ) => {
    'produk': produk,
    'kategori': [
      for (var i = 0; i < kategori.length; i++)
        {'id': 'KAT-${kategori[i]}', 'kode': kategori[i], 'nama': kategori[i]},
    ],
  };

  return {
    'TOKO-1': pack(minimarket, ['Minuman', 'Snack', 'Sembako', 'Lainnya']),
    'TOKO-2': pack(bakso, ['Bakso', 'Mie', 'Minuman', 'Tambahan']),
    'TOKO-3': pack(laundry, ['Kiloan', 'Satuan', 'Express']),
    'TOKO-4': pack(bengkel, ['Jasa Servis', 'Oli & Pelumas', 'Suku Cadang']),
    'TOKO-5': pack(doorsmeer, ['Motor', 'Mobil', 'Detailing', 'Produk']),
    'TOKO-6': pack(salon, ['Potong', 'Perawatan', 'Produk']),
  };
}

/// Meja ber-QR untuk toko F&B (bon meja / open bill).
const demoMejaBakso = [
  {'id': 'MEJA-1', 'toko_id': 'TOKO-2', 'nomor': '1', 'kode': 'MJ-BAKSO-01'},
  {'id': 'MEJA-2', 'toko_id': 'TOKO-2', 'nomor': '2', 'kode': 'MJ-BAKSO-02'},
  {'id': 'MEJA-3', 'toko_id': 'TOKO-2', 'nomor': '3', 'kode': 'MJ-BAKSO-03'},
  {'id': 'MEJA-4', 'toko_id': 'TOKO-2', 'nomor': '4', 'kode': 'MJ-BAKSO-04'},
  {'id': 'MEJA-5', 'toko_id': 'TOKO-2', 'nomor': '5', 'kode': 'MJ-BAKSO-05'},
  {'id': 'MEJA-6', 'toko_id': 'TOKO-2', 'nomor': '6', 'kode': 'MJ-BAKSO-06'},
];

/// Pesanan hidup awal per toko: {kode item: kuantitas}, tahap, pelanggan.
/// Dipakai `DemoEngine.seed()` untuk mengisi papan pesanan agar langsung hidup.
const demoSeedPesanan = <String, List<Map<String, dynamic>>>{
  'TOKO-2': [
    {
      'items': {'MIE-002': 2, 'MIN-001': 2},
      'stage': 'DIPROSES',
      'menitLalu': 12,
      'meja': 'Meja 1',
    },
    {
      'items': {'BKS-002': 1, 'MIN-002': 1},
      'stage': 'ANTRIAN',
      'menitLalu': 4,
      'meja': 'Meja 3',
    },
    {
      'items': {'BKS-001': 2, 'MIN-001': 3},
      'stage': 'READY',
      'menitLalu': 26,
      'meja': 'Meja 5',
    },
  ],
  'TOKO-3': [
    {
      'items': {'KIL-001': 4},
      'stage': 'ANTRIAN',
      'menitLalu': 25,
      'pelanggan': 'Budi Santoso',
      'belumBayar': true,
    },
    {
      'items': {'KIL-001': 6, 'SAT-001': 1},
      'stage': 'PENCUCIAN',
      'menitLalu': 95,
      'pelanggan': 'Siti Aminah',
    },
    {
      'items': {'KIL-002': 3},
      'stage': 'PENGERINGAN',
      'menitLalu': 150,
      'pelanggan': 'Rudi Hartono',
    },
    {
      'items': {'KIL-001': 5},
      'stage': 'LIPAT',
      'menitLalu': 240,
      'pelanggan': 'Dewi Lestari',
    },
    {
      'items': {'SAT-002': 2},
      'stage': 'SIAP_AMBIL',
      'menitLalu': 420,
      'pelanggan': 'Budi Santoso',
      'belumBayar': true,
    },
  ],
  'TOKO-4': [
    {
      'items': {'JSV-001': 1, 'OLI-001': 1},
      'stage': 'ANTRIAN',
      'menitLalu': 15,
      'pelanggan': 'Rudi Hartono (B 4521 KTA)',
      'belumBayar': true,
    },
    {
      'items': {'JSV-002': 1},
      'stage': 'PEMERIKSAAN',
      'menitLalu': 40,
      'pelanggan': 'Budi Santoso (B 3120 KJ)',
    },
    {
      'items': {'JSV-003': 1, 'SPR-002': 1},
      'stage': 'PENGERJAAN',
      'menitLalu': 90,
      'pelanggan': 'Siti Aminah (D 1290 ABC)',
      'belumBayar': true,
    },
    {
      'items': {'JSV-004': 1},
      'stage': 'SIAP_AMBIL',
      'menitLalu': 130,
      'pelanggan': 'Dewi Lestari (B 8812 TT)',
    },
  ],
  'TOKO-5': [
    {
      'items': {'MTR-001': 1},
      'stage': 'ANTRIAN',
      'menitLalu': 3,
      'pelanggan': 'Rudi Hartono (B 4521 KTA)',
    },
    {
      'items': {'MBL-002': 1, 'PRD-001': 1},
      'stage': 'PENCUCIAN',
      'menitLalu': 14,
      'pelanggan': 'Siti Aminah (D 1290 ABC)',
      'belumBayar': true,
    },
    {
      'items': {'MBL-001': 1},
      'stage': 'PENGERINGAN',
      'menitLalu': 27,
      'pelanggan': 'Budi Santoso (B 7788 XYZ)',
    },
    {
      'items': {'MBL-003': 1},
      'stage': 'FINISHING',
      'menitLalu': 41,
      'pelanggan': 'Dewi Lestari (F 3344 QQ)',
      'belumBayar': true,
    },
    {
      'items': {'MTR-003': 1},
      'stage': 'SIAP_AMBIL',
      'menitLalu': 55,
      'pelanggan': 'Rudi Hartono (B 9001 ZZ)',
    },
  ],
  'TOKO-6': [
    {
      'items': {'PTG-001': 1},
      'stage': 'ANTRIAN',
      'menitLalu': 2,
      'pelanggan': 'Budi Santoso',
      'belumBayar': true,
    },
    {
      'items': {'PTG-002': 1},
      'stage': 'ANTRIAN',
      'menitLalu': 6,
      'belumBayar': true,
    },
    {
      'items': {'PTG-003': 1},
      'stage': 'DILAYANI',
      'menitLalu': 18,
      'pelanggan': 'Rudi Hartono',
      'belumBayar': true,
    },
    {
      'items': {'PTG-001': 1, 'PTG-004': 1},
      'stage': 'DILAYANI',
      'menitLalu': 9,
      'pelanggan': 'Dewi Lestari',
    },
  ],
};

/// Stasiun kerja per toko: {type, nama, status, kapasitas}.
const demoStasiun = <String, List<Map<String, dynamic>>>{
  'TOKO-1': [
    {'type': 'cashier', 'nama': 'Kasir 1'},
  ],
  'TOKO-2': [
    {'type': 'cashier', 'nama': 'Kasir 1'},
    {'type': 'kitchen', 'nama': 'Dapur 1', 'kapasitas': 5},
    {'type': 'kitchen', 'nama': 'Dapur 2', 'status': 'ISTIRAHAT', 'kapasitas': 5},
    {'type': 'waiter', 'nama': 'Waiter A'},
  ],
  'TOKO-3': [
    {'type': 'cashier', 'nama': 'Penerimaan 1'},
    {'type': 'washer', 'nama': 'Mesin Cuci 1', 'kapasitas': 8},
    {'type': 'washer', 'nama': 'Mesin Cuci 2', 'status': 'NONAKTIF', 'kapasitas': 8},
    {'type': 'dryer', 'nama': 'Pengering 1', 'kapasitas': 8},
    {'type': 'folder', 'nama': 'Meja Lipat 1'},
  ],
  'TOKO-4': [
    {'type': 'cashier', 'nama': 'Kasir 1'},
    {'type': 'mechanic', 'nama': 'Mekanik Andi'},
    {'type': 'mechanic', 'nama': 'Mekanik Yusuf', 'status': 'ISTIRAHAT'},
    {'type': 'bay', 'nama': 'Pit 1', 'kapasitas': 1},
    {'type': 'bay', 'nama': 'Pit 2', 'kapasitas': 1},
  ],
  'TOKO-5': [
    {'type': 'cashier', 'nama': 'Kasir 1'},
    {'type': 'washing', 'nama': 'Bay 1 (Mobil)', 'kapasitas': 1},
    {'type': 'washing', 'nama': 'Bay 2 (Mobil)', 'kapasitas': 1},
    {'type': 'washing', 'nama': 'Bay 3 (Motor)', 'kapasitas': 2},
    {'type': 'finishing', 'nama': 'Finishing 1', 'kapasitas': 2},
  ],
  'TOKO-6': [
    {'type': 'cashier', 'nama': 'Kasir 1'},
    {'type': 'chair', 'nama': 'Kursi 1 — Andi', 'kapasitas': 1},
    {'type': 'chair', 'nama': 'Kursi 2 — Bima', 'kapasitas': 1},
    {'type': 'chair', 'nama': 'Kursi 3 — Candra', 'status': 'ISTIRAHAT', 'kapasitas': 1},
  ],
};
