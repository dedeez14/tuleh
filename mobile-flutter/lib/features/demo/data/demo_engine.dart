import 'dart:math';

import 'demo_data.dart';

/// Balasan palsu Mode Demo: status HTTP + body envelope MOVERA.
typedef DemoResponse = ({int status, Map<String, dynamic> body});

/// Mesin Mode Demo — mensimulasikan MOVERA POS API sepenuhnya di memori,
/// cermin `frontend/src/main/demo.js` (desktop). Tidak ada permintaan jaringan
/// yang keluar saat demo aktif; state hidup selama sesi aplikasi saja.
///
/// Bentuk balasan mengikuti persis yang dibaca tiap datasource (mis. `/produk`
/// harus List telanjang, `/bills` harus `{tables: [...]}`, `/laporan/penjualan-harian`
/// harus `{rows: [...]}`). Status 401/426 tidak pernah dipakai karena memicu
/// bendera sesi-berakhir / wajib-perbarui di interceptor.
class DemoEngine {
  DemoEngine() {
    seed();
  }

  // ---- state ----
  late Map<String, Map<String, List<Map<String, dynamic>>>> _katalog;
  late List<Map<String, dynamic>> _pelanggan;
  final List<Map<String, dynamic>> _transaksi = []; // + toko_id, terbaru dulu
  final List<Map<String, dynamic>> _sesi = []; // + toko_id, terbaru dulu
  final List<Map<String, dynamic>> _orders = []; // + toko_id
  final List<Map<String, dynamic>> _bills = []; // + toko_id
  final List<Map<String, dynamic>> _pengeluaran = []; // + toko_id
  late Map<String, dynamic> _usaha;
  final Map<String, int> _antrian = {};
  int _nTrx = 0, _nSesi = 0, _nOrder = 0, _nBill = 0, _nExp = 0, _nCust = 0;

  final _rand = Random(20260904);

  // ---- util ----
  static String _iso(DateTime d) => d.toIso8601String();
  static String _tgl(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static DemoResponse _ok(dynamic data, {int status = 200}) =>
      (status: status, body: {'success': true, 'message': null, 'data': data});
  static DemoResponse _err(int status, String pesan) =>
      (status: status, body: {'success': false, 'message': pesan, 'data': null});

  List<Map<String, dynamic>> _produk(String toko) =>
      _katalog[toko]?['produk'] ?? const [];

  Map<String, dynamic>? _cariProduk(String toko, String id) {
    for (final p in _produk(toko)) {
      if (p['id'] == id) return p;
    }
    return null;
  }

  /// Data direset tiap Mode Demo dimulai (state segar, seperti desktop).
  void seed() {
    _katalog = buatKatalogDemo();
    _pelanggan = [for (final c in demoPelanggan) Map<String, dynamic>.from(c)];
    _transaksi.clear();
    _sesi.clear();
    _orders.clear();
    _bills.clear();
    _pengeluaran.clear();
    _antrian.clear();
    _nTrx = _nSesi = _nOrder = _nBill = _nExp = 0;
    _nCust = _pelanggan.length;
    _usaha = {
      ...demoCompany,
      'struk': {'footer': 'Terima kasih atas kunjungan Anda.', 'tampil_logo': true},
    };

    for (final toko in demoTokos) {
      final id = toko['id'] as String;
      _seedRiwayat(id);
      _seedPengeluaran(id);
      _seedPesanan(id);
      _seedBon(id);
    }
  }

  /// Riwayat 8 hari: sesi tertutup untuk hari-hari lalu, sesi hari ini BUKA.
  void _seedRiwayat(String toko) {
    final produk = _produk(toko);
    if (produk.isEmpty) return;
    final metode = ['TUNAI', 'TUNAI', 'TUNAI', 'QRIS', 'TRANSFER'];

    for (var hari = 7; hari >= 0; hari--) {
      final dasar = DateTime.now().subtract(Duration(days: hari));
      final buka = DateTime(dasar.year, dasar.month, dasar.day, 8);
      _nSesi += 1;
      final sesi = <String, dynamic>{
        'id': 'SES-$_nSesi',
        'toko_id': toko,
        'nomor': 'SK-${_nSesi.toString().padLeft(5, '0')}',
        'status': hari > 0 ? 'TUTUP' : 'BUKA',
        'kasir': demoUser['name'],
        'waktu_buka': _iso(buka),
        'waktu_tutup': null,
        'kas_awal': 500000,
        'total_tunai': 0,
        'total_transfer': 0,
        'total_qris': 0,
        'total_penjualan': 0,
        'jumlah_transaksi': 0,
        'kas_akhir_sistem': 500000,
        'kas_akhir_fisik': null,
        'selisih': null,
      };

      final jumlah = 4 + _rand.nextInt(5);
      for (var n = 0; n < jumlah; n++) {
        final jam = buka.add(Duration(minutes: 60 + _rand.nextInt(690)));
        final items = <Map<String, dynamic>>[];
        for (var i = 0; i < 1 + _rand.nextInt(3); i++) {
          final p = produk[_rand.nextInt(produk.length)];
          final qty = p['satuan'] == 'Kg' ? 3 + _rand.nextInt(4) : 1 + _rand.nextInt(2);
          final harga = (p['harga_jual'] as num).toDouble();
          items.add({
            'nama': p['nama'],
            'kuantitas': qty,
            'harga': harga,
            'subtotal': harga * qty,
          });
        }
        final grand = items.fold<double>(0, (s, i) => s + (i['subtotal'] as double));
        final tipe = metode[_rand.nextInt(metode.length)];
        final dibayar = tipe == 'TUNAI' ? (grand / 5000).ceil() * 5000.0 : grand;
        _nTrx += 1;
        _transaksi.insert(0, {
          'id': 'TRX-$_nTrx',
          'toko_id': toko,
          'nomor': 'TRX/${_nTrx.toString().padLeft(4, '0')}',
          'tanggal': _iso(jam),
          'status': 'SELESAI',
          'pelanggan': _rand.nextDouble() < 0.3
              ? _pelanggan[_rand.nextInt(_pelanggan.length)]['nama']
              : null,
          'kasir': demoUser['name'],
          'tipe_pembayaran': tipe,
          'metode_bayar': tipe,
          'subtotal': grand,
          'total_diskon': 0,
          'total_pajak': 0,
          'grand_total': grand,
          'dibayar': dibayar,
          'kembalian': dibayar - grand,
          'items': items,
        });
        _tambahKeSesi(sesi, tipe, grand);
      }

      if (hari > 0) {
        final tutup = DateTime(dasar.year, dasar.month, dasar.day, 21);
        final noise = [0, 0, 0, -5000, 2000][_rand.nextInt(5)].toDouble();
        sesi['waktu_tutup'] = _iso(tutup);
        sesi['kas_akhir_fisik'] = (sesi['kas_akhir_sistem'] as num) + noise;
        sesi['selisih'] = noise;
      }
      _sesi.insert(0, sesi);
    }
  }

  void _tambahKeSesi(Map<String, dynamic> sesi, String tipe, double grand) {
    final kunci = switch (tipe) {
      'TUNAI' => 'total_tunai',
      'QRIS' => 'total_qris',
      _ => 'total_transfer',
    };
    sesi[kunci] = (sesi[kunci] as num) + grand;
    sesi['total_penjualan'] = (sesi['total_penjualan'] as num) + grand;
    sesi['jumlah_transaksi'] = (sesi['jumlah_transaksi'] as num) + 1;
    sesi['kas_akhir_sistem'] = (sesi['kas_awal'] as num) + (sesi['total_tunai'] as num);
  }

  void _seedPengeluaran(String toko) {
    const contoh = [
      {'keterangan': 'LISTRIK & AIR', 'nominal': 85000, 'hariLalu': 1},
      {'keterangan': 'BELANJA BAHAN', 'nominal': 60000, 'hariLalu': 2},
      {'keterangan': 'KEBERSIHAN', 'nominal': 40000, 'hariLalu': 3},
    ];
    final bulanIni = _tgl(DateTime.now()).substring(0, 7);
    for (final b in contoh) {
      final t = DateTime.now().subtract(Duration(days: b['hariLalu'] as int));
      if (_tgl(t).substring(0, 7) != bulanIni) continue;
      _nExp += 1;
      _pengeluaran.add({
        'id': 'EXP-$_nExp',
        'toko_id': toko,
        'tanggal': _tgl(t),
        'keterangan': b['keterangan'],
        'nominal': b['nominal'],
      });
    }
  }

  String _nomorAntrian(String toko) {
    final n = (_antrian[toko] ?? 0) + 1;
    _antrian[toko] = n;
    final prefix = demoAntrianPrefix[toko] ?? 'Q';
    return '$prefix-${n.toString().padLeft(3, '0')}';
  }

  List<String> _tahapan(String toko) => List<String>.from(
    (demoManifests[toko]?['lifecycle'] as Map?)?['states'] as List? ?? const [],
  );

  void _seedPesanan(String toko) {
    final seeds = demoSeedPesanan[toko];
    if (seeds == null) return;
    for (final s in seeds) {
      final items = <Map<String, dynamic>>[];
      var total = 0.0;
      (s['items'] as Map).forEach((kode, qty) {
        final p = _produk(toko).firstWhere(
          (x) => x['kode'] == kode,
          orElse: () => const {},
        );
        if (p.isEmpty) return;
        final harga = (p['harga_jual'] as num).toDouble();
        final n = (qty as num).toDouble();
        items.add({
          'id_produk': p['id'],
          'nama': p['nama'],
          'kuantitas': qty,
          'harga': harga,
          'catatan': null,
        });
        total += harga * n;
      });
      if (items.isEmpty) continue;

      final meja = s['meja'] as String?;
      _nOrder += 1;
      _orders.add({
        'id': 'ORD-$_nOrder',
        'toko_id': toko,
        'nomor': 'ORD/${_nOrder.toString().padLeft(4, '0')}',
        // Tiket bon dine-in beridentitas meja, tanpa nomor antrian.
        'no_antrian': meja == null ? _nomorAntrian(toko) : null,
        'meja': meja,
        'ronde': meja == null ? null : 1,
        'stage': s['stage'],
        'bayar': s['belumBayar'] == true ? 'BELUM' : 'LUNAS',
        'pelanggan': s['pelanggan'],
        'total': total,
        'created_at': _iso(
          DateTime.now().subtract(Duration(minutes: s['menitLalu'] as int)),
        ),
        'items': items,
      });
    }
  }

  /// Bon meja berjalan untuk toko F&B (peta meja langsung terisi).
  void _seedBon(String toko) {
    if (toko != 'TOKO-2') return;
    for (final o in _orders.where((x) => x['toko_id'] == toko && x['meja'] != null)) {
      _nBill += 1;
      _bills.add({
        'id': 'BILL-$_nBill',
        'toko_id': toko,
        'nomor': 'BON/${_nBill.toString().padLeft(4, '0')}',
        'meja': o['meja'],
        'label': o['meja'],
        'pax': 2 + _rand.nextInt(3),
        'status': 'BUKA',
        'total': o['total'],
        'items': [
          for (final i in (o['items'] as List).cast<Map<String, dynamic>>())
            {
              'nama': i['nama'],
              'kuantitas': i['kuantitas'],
              'harga': i['harga'],
              'subtotal': (i['harga'] as num) * (i['kuantitas'] as num),
            },
        ],
      });
    }
  }

  // ---- routing ----

  /// Tangani satu permintaan. [path] sudah tanpa prefix `/api/pos/v1`.
  DemoResponse handle({
    required String method,
    required String path,
    required Map<String, dynamic> query,
    dynamic body,
  }) {
    final toko = (query['toko_id'] as String?) ?? 'TOKO-1';
    final data = body is Map ? Map<String, dynamic>.from(body) : const <String, dynamic>{};
    final seg = path.split('/').where((s) => s.isNotEmpty).toList();
    final m = method.toUpperCase();

    // --- auth ---
    if (path == '/auth/login' && m == 'POST') return _ok(_sesiUser(token: true));
    if (path == '/auth/me') return _ok(_sesiUser());
    if (path == '/auth/logout') return _ok(null);

    // --- toko & manifest ---
    if (path == '/tokos') return _ok(demoTokos);
    if (seg.length == 3 && seg[0] == 'tokos' && seg[2] == 'manifest') {
      final man = demoManifests[Uri.decodeComponent(seg[1])];
      return man == null ? _err(404, 'Manifest tidak ditemukan.') : _ok(man);
    }

    // --- katalog ---
    if (path == '/produk' && m == 'GET') {
      final q = (query['q'] as String?)?.toLowerCase().trim() ?? '';
      var rows = _produk(toko);
      if (q.isNotEmpty) {
        rows = rows
            .where((p) =>
                '${p['nama']}'.toLowerCase().contains(q) ||
                '${p['kode']}'.toLowerCase().contains(q) ||
                '${p['barcode'] ?? ''}'.contains(q))
            .toList();
      }
      return _ok(rows); // List telanjang — kontrak datasource produk
    }
    if (path == '/produk' && m == 'POST') return _buatProduk(toko, data);
    if (seg.length == 2 && seg[0] == 'produk' && m == 'PATCH') {
      return _ubahProduk(toko, seg[1], data);
    }

    // --- pelanggan ---
    if (path == '/pelanggan' && m == 'GET') return _ok(_pelanggan);
    if (path == '/pelanggan' && m == 'POST') {
      _nCust += 1;
      final baru = {
        'id': 'CUST-$_nCust',
        'kode': 'PLG-${_nCust.toString().padLeft(3, '0')}',
        'nama': data['nama'] ?? 'Pelanggan',
        'telepon': data['no_whatsapp'],
        'alamat': null,
      };
      _pelanggan.add(baru);
      return _ok(baru);
    }

    // --- transaksi ---
    if (path == '/transaksi' && m == 'GET') {
      return _ok(_transaksi.where((t) => t['toko_id'] == toko).toList());
    }
    if (path == '/transaksi/checkout' && m == 'POST') return _checkout(toko, data);
    if (seg.length == 2 && seg[0] == 'transaksi' && m == 'GET') {
      final t = _transaksi.firstWhere(
        (x) => x['id'] == seg[1],
        orElse: () => const {},
      );
      return t.isEmpty ? _err(404, 'Transaksi tidak ditemukan.') : _ok(t);
    }

    // --- sesi & gudang ---
    if (path == '/sesi/aktif') {
      final s = _sesiAktif(toko);
      return _ok(s); // null = belum ada sesi terbuka
    }
    if (path == '/sesi' && m == 'GET') {
      return _ok(_sesi.where((s) => s['toko_id'] == toko).toList());
    }
    if (path == '/sesi/buka' && m == 'POST') return _bukaSesi(toko, data);
    if (seg.length == 3 && seg[0] == 'sesi' && seg[2] == 'tutup') {
      return _tutupSesi(toko, Uri.decodeComponent(seg[1]), data);
    }
    if (path == '/gudang') return _ok(demoGudang);

    // --- laporan ---
    if (path == '/laporan/keuangan') return _ok(_laporanKeuangan(toko));
    if (path == '/laporan/penjualan-harian') {
      return _ok({'rows': _penjualanHarian(toko)}); // kontrak: {rows: []}
    }
    if (path == '/laporan/rekap-kasir') {
      return _ok(_sesi.where((s) => s['toko_id'] == toko).toList());
    }
    if (path == '/laporan/stok') {
      return _ok([
        for (final p in _produk(toko))
          if (p['kelola_stok'] == true)
            {'id': p['id'], 'kode': p['kode'], 'produk': p['nama'], 'stok': p['stok']},
      ]);
    }

    // --- pengeluaran ---
    if (path == '/pengeluaran' && m == 'GET') {
      final bulan = query['bulan'] as String?;
      return _ok(_pengeluaran
          .where((e) =>
              e['toko_id'] == toko &&
              (bulan == null || '${e['tanggal']}'.startsWith(bulan)))
          .toList());
    }
    if (path == '/pengeluaran' && m == 'POST') {
      _nExp += 1;
      _pengeluaran.add({
        'id': 'EXP-$_nExp',
        'toko_id': toko,
        'tanggal': (data['tanggal'] as String?) ?? _tgl(DateTime.now()),
        'keterangan': data['keterangan'] ?? '-',
        'nominal': data['nominal'] ?? 0,
      });
      return _ok(null, status: 201);
    }
    if (seg.length == 2 && seg[0] == 'pengeluaran' && m == 'DELETE') {
      final id = Uri.decodeComponent(seg[1]);
      _pengeluaran.removeWhere((e) => e['id'] == id);
      return _ok(null);
    }

    // --- pengaturan ---
    if (path == '/pengaturan/usaha' && m == 'GET') return _ok(_usaha);
    if (path == '/pengaturan/usaha' && (m == 'PUT' || m == 'POST')) {
      _usaha = {
        ..._usaha,
        'nama': data['nama'] ?? _usaha['nama'],
        'alamat': data['alamat'],
        'telepon': data['telepon'],
        'email': data['email'],
        'struk': {
          'footer': data['struk_footer'],
          'tampil_logo': data['struk_tampil_logo'] != false,
        },
      };
      return _ok(null);
    }

    // --- bon meja ---
    if (path == '/bills' && m == 'GET') return _ok({'tables': _petaMeja(toko)});
    if (path == '/bills' && m == 'POST') return _bukaBon(toko, data);
    if (seg.length == 2 && seg[0] == 'bills' && m == 'GET') {
      final b = _bills.firstWhere((x) => x['id'] == seg[1], orElse: () => const {});
      return b.isEmpty ? _err(404, 'Bon tidak ditemukan.') : _ok(b);
    }
    if (seg.length == 3 && seg[0] == 'bills' && seg[2] == 'rounds') {
      return _tambahRonde(toko, seg[1], data);
    }
    if (seg.length == 3 && seg[0] == 'bills' && seg[2] == 'settle') {
      return _lunasiBon(toko, seg[1], data);
    }

    // --- pesanan hidup ---
    if (path == '/orders' && m == 'GET') {
      final stage = query['stage'] as String?;
      final tahap = _tahapan(toko);
      final terminal = tahap.isEmpty ? null : tahap.last;
      var rows = _orders.where((o) => o['toko_id'] == toko);
      rows = stage != null && stage.isNotEmpty
          ? rows.where((o) => o['stage'] == stage)
          : rows.where((o) => o['stage'] != terminal);
      final out = rows.toList()
        ..sort((a, b) => '${a['created_at']}'.compareTo('${b['created_at']}'));
      return _ok(out);
    }
    if (seg.length == 3 && seg[0] == 'orders' && seg[2] == 'transition') {
      return _transisi(Uri.decodeComponent(seg[1]), data);
    }

    // --- inventory ---
    if (path == '/inventory/stok-masuk' && m == 'POST') {
      final p = _cariProduk(toko, '${data['id_produk']}');
      if (p == null) return _err(422, 'Produk tidak ditemukan.');
      p['stok'] = (p['stok'] as num) + ((data['jumlah'] as num?) ?? 0);
      return _ok(null);
    }

    // --- auto-update: demo tidak pernah menawarkan pembaruan ---
    if (path == '/app/versi') {
      return _ok({'wajib': false, 'update_tersedia': false});
    }

    return _err(404, 'Endpoint "$path" tidak tersedia di Mode Demo.');
  }

  // ---- handler rinci ----

  Map<String, dynamic> _sesiUser({bool token = false}) => {
    if (token) 'token': 'demo-token',
    'pos_role': demoUser['pos_role'],
    'user': {
      'id': demoUser['id'],
      'name': demoUser['name'],
      'email': demoUser['email'],
      'role': demoUser['pos_role'],
    },
    'company': {'nama': _usaha['nama']},
  };

  Map<String, dynamic>? _sesiAktif(String toko) {
    for (final s in _sesi) {
      if (s['toko_id'] == toko && s['status'] == 'BUKA') return s;
    }
    return null;
  }

  DemoResponse _buatProduk(String toko, Map<String, dynamic> data) {
    final nama = '${data['nama'] ?? ''}'.trim();
    if (nama.isEmpty) return _err(422, 'Nama produk wajib diisi.');
    final harga = (data['harga_jual'] as num?) ?? 0;
    if (harga <= 0) return _err(422, 'Harga jual harus lebih dari nol.');

    final tipe = '${data['tipe'] ?? 'PRODUK'}'.toUpperCase() == 'JASA'
        ? 'JASA'
        : 'PRODUK';
    final katalog = _katalog[toko]?['produk'];
    if (katalog == null) return _err(404, 'Toko tidak ditemukan.');

    final baru = {
      'id': 'NEW-${katalog.length + 1}',
      'kode': 'NEW-${(katalog.length + 1).toString().padLeft(3, '0')}',
      'nama': nama,
      'barcode': data['barcode'],
      'tipe': tipe,
      'harga_jual': harga,
      'harga_beli': tipe == 'JASA' ? null : data['harga_beli'],
      'pajak_persen': 0,
      'satuan': tipe == 'JASA' ? 'Unit' : 'Pcs',
      'satuan_id': null,
      'kategori': tipe == 'JASA' ? 'Jasa' : 'Lainnya',
      'kelola_stok': tipe != 'JASA',
      'stok': 0,
      'gambar': null,
    };
    katalog.add(baru);
    return _ok(baru, status: 201);
  }

  DemoResponse _ubahProduk(String toko, String id, Map<String, dynamic> data) {
    final p = _cariProduk(toko, id);
    if (p == null) return _err(404, 'Produk tidak ditemukan.');
    for (final k in ['nama', 'harga_jual', 'harga_beli', 'barcode']) {
      if (data.containsKey(k)) p[k] = data[k];
    }
    return _ok(p);
  }

  DemoResponse _checkout(String toko, Map<String, dynamic> data) {
    if (_sesiAktif(toko) == null) {
      return _err(409, 'Belum ada sesi kasir terbuka. Buka sesi lebih dulu.');
    }
    final rawItems = data['items'];
    if (rawItems is! List || rawItems.isEmpty) {
      return _err(422, 'Keranjang masih kosong.');
    }

    final items = <Map<String, dynamic>>[];
    var grand = 0.0;
    for (final raw in rawItems) {
      if (raw is! Map) continue;
      final p = _cariProduk(toko, '${raw['id_produk']}');
      if (p == null) return _err(422, 'Item tidak ditemukan di katalog.');
      final qty = (raw['kuantitas'] as num?)?.toDouble() ?? 0;
      if (qty <= 0) return _err(422, 'Kuantitas "${p['nama']}" tidak valid.');
      final harga = (raw['harga'] as num?)?.toDouble() ??
          (p['harga_jual'] as num).toDouble();
      final subtotal = harga * qty;
      grand += subtotal;
      items.add({
        'nama': p['nama'],
        'kuantitas': qty,
        'harga': harga,
        'subtotal': subtotal,
      });
      // Sparepart/produk berstok berkurang; jasa tidak.
      if (p['kelola_stok'] == true) {
        p['stok'] = ((p['stok'] as num) - qty).clamp(0, double.infinity);
      }
    }

    final tipe = '${data['tipe_pembayaran'] ?? 'TUNAI'}';
    final dibayar = (data['dibayar'] as num?)?.toDouble() ?? grand;
    if (tipe == 'TUNAI' && dibayar < grand) {
      return _err(422, 'Uang dibayar kurang dari total.');
    }

    _nTrx += 1;
    final now = DateTime.now();
    final struk = <String, dynamic>{
      'id': 'TRX-$_nTrx',
      'toko_id': toko,
      'nomor': 'TRX/${_nTrx.toString().padLeft(4, '0')}',
      'tanggal': _iso(now),
      'status': 'SELESAI',
      'pelanggan': null,
      'kasir': demoUser['name'],
      'tipe_pembayaran': tipe,
      'metode_bayar': tipe,
      'subtotal': grand,
      'total_diskon': 0,
      'total_pajak': 0,
      'grand_total': grand,
      'dibayar': dibayar,
      'kembalian': dibayar - grand, // wajib num (bukan string)
      'items': items,
    };
    _transaksi.insert(0, struk);
    _tambahKeSesi(_sesiAktif(toko)!, tipe, grand);

    // Toko bertahap: checkout juga menerbitkan pesanan bernomor antrian.
    final tahap = _tahapan(toko);
    if (tahap.length > 1) {
      _nOrder += 1;
      final noAntrian = _nomorAntrian(toko);
      _orders.add({
        'id': 'ORD-$_nOrder',
        'toko_id': toko,
        'nomor': 'ORD/${_nOrder.toString().padLeft(4, '0')}',
        'no_antrian': noAntrian,
        'meja': null,
        'ronde': null,
        'stage': tahap.first,
        'bayar': 'LUNAS',
        'pelanggan': null,
        'total': grand,
        'created_at': _iso(now),
        'items': items,
      });
      struk['no_antrian'] = noAntrian;
    }
    return _ok(struk, status: 201);
  }

  DemoResponse _bukaSesi(String toko, Map<String, dynamic> data) {
    if (_sesiAktif(toko) != null) return _err(409, 'Sesi kasir sudah terbuka.');
    _nSesi += 1;
    _sesi.insert(0, {
      'id': 'SES-$_nSesi',
      'toko_id': toko,
      'nomor': 'SK-${_nSesi.toString().padLeft(5, '0')}',
      'status': 'BUKA',
      'kasir': demoUser['name'],
      'waktu_buka': _iso(DateTime.now()),
      'waktu_tutup': null,
      'kas_awal': (data['kas_awal'] as num?) ?? 0,
      'total_tunai': 0,
      'total_transfer': 0,
      'total_qris': 0,
      'total_penjualan': 0,
      'jumlah_transaksi': 0,
      'kas_akhir_sistem': (data['kas_awal'] as num?) ?? 0,
      'kas_akhir_fisik': null,
      'selisih': null,
    });
    return _ok(null, status: 201);
  }

  DemoResponse _tutupSesi(String toko, String id, Map<String, dynamic> data) {
    final s = _sesi.firstWhere(
      (x) => x['id'] == id && x['toko_id'] == toko,
      orElse: () => const {},
    );
    if (s.isEmpty) return _err(404, 'Sesi tidak ditemukan.');
    if (s['status'] != 'BUKA') return _err(409, 'Sesi sudah ditutup.');
    final fisik = (data['kas_akhir_fisik'] as num?) ?? 0;
    s['status'] = 'TUTUP';
    s['waktu_tutup'] = _iso(DateTime.now());
    s['kas_akhir_fisik'] = fisik;
    s['selisih'] = fisik - (s['kas_akhir_sistem'] as num);
    return _ok(null);
  }

  Map<String, dynamic> _laporanKeuangan(String toko) {
    final bulan = _tgl(DateTime.now()).substring(0, 7);
    var omset = 0.0;
    var jumlah = 0;
    for (final t in _transaksi) {
      if (t['toko_id'] != toko) continue;
      if (!'${t['tanggal']}'.startsWith(bulan)) continue;
      if (t['status'] == 'DIBATALKAN') continue;
      omset += (t['grand_total'] as num).toDouble();
      jumlah += 1;
    }
    final keluar = _pengeluaran
        .where((e) => e['toko_id'] == toko && '${e['tanggal']}'.startsWith(bulan))
        .fold<double>(0, (s, e) => s + (e['nominal'] as num).toDouble());
    return {
      'bulan': bulan,
      'omset': omset,
      'jumlah_transaksi': jumlah,
      'pengeluaran': keluar,
      'laba': omset - keluar,
    };
  }

  List<Map<String, dynamic>> _penjualanHarian(String toko) {
    final out = <Map<String, dynamic>>[];
    for (var hari = 7; hari >= 0; hari--) {
      final tgl = _tgl(DateTime.now().subtract(Duration(days: hari)));
      var omzet = 0.0;
      var jumlah = 0;
      for (final t in _transaksi) {
        if (t['toko_id'] != toko) continue;
        if (!'${t['tanggal']}'.startsWith(tgl)) continue;
        omzet += (t['grand_total'] as num).toDouble();
        jumlah += 1;
      }
      out.add({'tanggal': tgl, 'jumlah_transaksi': jumlah, 'total_omzet': omzet});
    }
    return out;
  }

  List<Map<String, dynamic>> _petaMeja(String toko) {
    final meja = demoMejaBakso.where((m) => m['toko_id'] == toko);
    return [
      for (final m in meja)
        () {
          final bon = _bills.firstWhere(
            (b) =>
                b['toko_id'] == toko &&
                b['meja'] == 'Meja ${m['nomor']}' &&
                b['status'] == 'BUKA',
            orElse: () => const {},
          );
          return {
            'id': m['id'],
            'nomor': m['nomor'],
            'kode': m['kode'],
            'bill': bon.isEmpty
                ? null
                : {
                    'id': bon['id'],
                    'total': bon['total'],
                    'pax': bon['pax'], // wajib num
                  },
          };
        }(),
    ];
  }

  DemoResponse _bukaBon(String toko, Map<String, dynamic> data) {
    final mejaId = '${data['meja_id']}';
    final meja = demoMejaBakso.firstWhere(
      (m) => m['id'] == mejaId,
      orElse: () => const {},
    );
    if (meja.isEmpty) return _err(404, 'Meja tidak ditemukan.');
    final label = 'Meja ${meja['nomor']}';
    final sudah = _bills.any(
      (b) => b['toko_id'] == toko && b['meja'] == label && b['status'] == 'BUKA',
    );
    if (sudah) return _err(409, 'Meja ini sudah punya bon berjalan.');
    _nBill += 1;
    _bills.add({
      'id': 'BILL-$_nBill',
      'toko_id': toko,
      'nomor': 'BON/${_nBill.toString().padLeft(4, '0')}',
      'meja': label,
      'label': label,
      'pax': (data['pax'] as num?)?.toInt() ?? 1,
      'status': 'BUKA',
      'total': 0,
      'items': <Map<String, dynamic>>[],
    });
    return _ok(null, status: 201);
  }

  DemoResponse _tambahRonde(String toko, String billId, Map<String, dynamic> data) {
    final bon = _bills.firstWhere((b) => b['id'] == billId, orElse: () => const {});
    if (bon.isEmpty) return _err(404, 'Bon tidak ditemukan.');
    final rawItems = data['items'];
    if (rawItems is! List || rawItems.isEmpty) {
      return _err(422, 'Pesanan ronde masih kosong.');
    }

    final items = (bon['items'] as List).cast<Map<String, dynamic>>();
    final tiket = <Map<String, dynamic>>[];
    var tambahan = 0.0;
    for (final raw in rawItems) {
      if (raw is! Map) continue;
      final p = _cariProduk(toko, '${raw['id_produk']}');
      if (p == null) continue;
      final qty = (raw['kuantitas'] as num?)?.toDouble() ?? 0;
      final harga = (p['harga_jual'] as num).toDouble();
      tambahan += harga * qty;
      items.add({
        'nama': p['nama'],
        'kuantitas': qty,
        'harga': harga,
        'subtotal': harga * qty,
      });
      tiket.add({
        'id_produk': p['id'],
        'nama': p['nama'],
        'kuantitas': qty,
        'harga': harga,
        'catatan': null,
      });
    }
    bon['total'] = (bon['total'] as num) + tambahan;

    // Tiap ronde jadi tiket dapur berlabel meja.
    final ronde = _orders
            .where((o) => o['meja'] == bon['meja'] && o['toko_id'] == toko)
            .length +
        1;
    _nOrder += 1;
    _orders.add({
      'id': 'ORD-$_nOrder',
      'toko_id': toko,
      'nomor': 'ORD/${_nOrder.toString().padLeft(4, '0')}',
      'no_antrian': null,
      'meja': bon['meja'],
      'ronde': ronde,
      'stage': _tahapan(toko).first,
      'bayar': 'BON',
      'pelanggan': null,
      'total': tambahan,
      'created_at': _iso(DateTime.now()),
      'items': tiket,
    });
    return _ok(null, status: 201);
  }

  DemoResponse _lunasiBon(String toko, String billId, Map<String, dynamic> data) {
    final bon = _bills.firstWhere((b) => b['id'] == billId, orElse: () => const {});
    if (bon.isEmpty) return _err(404, 'Bon tidak ditemukan.');
    if (bon['status'] != 'BUKA') return _err(409, 'Bon ini sudah dilunasi.');
    final sesi = _sesiAktif(toko);
    if (sesi == null) return _err(409, 'Belum ada sesi kasir terbuka.');

    final grand = (bon['total'] as num).toDouble();
    final tipe = '${data['tipe_pembayaran'] ?? 'TUNAI'}';
    final dibayar = (data['dibayar'] as num?)?.toDouble() ?? grand;
    _nTrx += 1;
    _transaksi.insert(0, {
      'id': 'TRX-$_nTrx',
      'toko_id': toko,
      'nomor': 'TRX/${_nTrx.toString().padLeft(4, '0')}',
      'tanggal': _iso(DateTime.now()),
      'status': 'SELESAI',
      'pelanggan': bon['label'],
      'kasir': demoUser['name'],
      'tipe_pembayaran': tipe,
      'metode_bayar': tipe,
      'subtotal': grand,
      'total_diskon': 0,
      'total_pajak': 0,
      'grand_total': grand,
      'dibayar': dibayar,
      'kembalian': dibayar - grand,
      'items': bon['items'],
    });
    _tambahKeSesi(sesi, tipe, grand);

    bon['status'] = 'LUNAS';
    // Tiket meja ini dianggap selesai agar papan & peta meja ikut bersih.
    final terminal = _tahapan(toko).last;
    for (final o in _orders) {
      if (o['toko_id'] == toko && o['meja'] == bon['meja']) o['stage'] = terminal;
    }
    return _ok(null);
  }

  DemoResponse _transisi(String id, Map<String, dynamic> data) {
    final o = _orders.firstWhere((x) => x['id'] == id, orElse: () => const {});
    if (o.isEmpty) return _err(404, 'Pesanan tidak ditemukan.');
    final tahap = _tahapan('${o['toko_id']}');
    final idx = tahap.indexOf('${o['stage']}');
    if (idx == -1 || idx == tahap.length - 1) {
      return _err(409, 'Pesanan sudah selesai.');
    }
    final next = tahap[idx + 1];
    final to = data['to'] as String?;
    if (to != null && to != next && to != 'SELESAI') {
      return _err(409, 'Transisi tidak valid. Berikutnya harus $next.');
    }
    o['stage'] = to == 'SELESAI' ? tahap.last : next;
    if (data['tipe_pembayaran'] != null) o['bayar'] = 'LUNAS';
    return _ok(o);
  }
}
