// Regresi untuk temuan audit 8 Sep 2026 (dirilis sebagai 2.22.0).
// Tiap grup di sini menutup satu bug nyata yang pernah lolos ke rilis.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/network/api_exception.dart';
import 'package:tuleh_pos/core/network/api_result.dart';
import 'package:tuleh_pos/core/offline/antrean.dart';
import 'package:tuleh_pos/core/offline/antrean_tulis.dart';
import 'package:tuleh_pos/core/storage/secure_storage.dart';
import 'package:tuleh_pos/core/theme/app_theme.dart';
import 'package:tuleh_pos/features/auth/presentation/controllers/auth_controller.dart';
import 'package:tuleh_pos/features/cetak/data/printer_service.dart';
import 'package:tuleh_pos/features/cetak/domain/entities/struk.dart';
import 'package:tuleh_pos/features/cetak/presentation/providers/printer_providers.dart';
import 'package:tuleh_pos/features/demo/data/demo_engine.dart';
import 'package:tuleh_pos/features/demo/data/masa_coba_service.dart';
import 'package:tuleh_pos/features/kasir/presentation/controllers/cart_controller.dart';
import 'package:tuleh_pos/features/kasir/presentation/controllers/keranjang_meta.dart';
import 'package:tuleh_pos/features/kasir/data/parkir_store.dart';
import 'package:tuleh_pos/features/kasir/domain/entities/cart_item.dart';
import 'package:tuleh_pos/features/kasir/presentation/widgets/cart_sheet.dart';
import 'package:tuleh_pos/features/kasir/presentation/widgets/hasil_transaksi_sheet.dart';
import 'package:tuleh_pos/features/kasir/presentation/widgets/parkir_sheet.dart';
import 'package:tuleh_pos/features/kasir/presentation/widgets/keranjang_kartu_tambahan.dart';
import 'package:tuleh_pos/features/meja/domain/entities/bill_detail.dart';
import 'package:tuleh_pos/features/meja/domain/repositories/meja_repository.dart';
import 'package:tuleh_pos/features/meja/presentation/providers/meja_providers.dart';
import 'package:tuleh_pos/features/meja/presentation/screens/bill_detail_screen.dart';
import 'package:tuleh_pos/features/products/domain/entities/product.dart';
import 'package:tuleh_pos/features/toko/presentation/providers/toko_providers.dart';

import 'helpers/masa_coba_palsu.dart';
import 'helpers/parkir_memori.dart';

class _Storage extends SecureStorage {
  _Storage([Map<String, String>? awal]) : super(const FlutterSecureStorage()) {
    if (awal != null) _m.addAll(awal);
  }
  final Map<String, String> _m = {};
  @override
  Future<String?> readToken() async => _m['token'];
  @override
  Future<void> writeToken(String? v) async => v == null ? _m.remove('token') : _m['token'] = v;
  @override
  Future<String?> readActiveTokoId() async => _m['toko'];
  @override
  Future<void> writeActiveTokoId(String? v) async => v == null ? _m.remove('toko') : _m['toko'] = v;
  @override
  Future<String?> bacaNilai(String k) async => _m[k];
  @override
  Future<void> tulisNilai(String k, String? v) async => v == null ? _m.remove(k) : _m[k] = v;
  @override
  Future<void> clearSession() async {
    _m.remove('token');
    _m.remove('toko');
  }
}

class _PrinterPalsu implements PrinterService {
  final dicetak = <Struk>[];
  @override
  Future<void> cetak(Struk struk, {required PrinterTersimpan printer, Object? lebar}) async =>
      dicetak.add(struk);
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

final _bon = BillDetail(
  id: 'B1',
  nomor: 'Bon offline',
  label: 'Meja 4',
  pax: 2,
  status: 'BUKA',
  total: 500000,
  items: const [BillItem(nama: 'Nasi Goreng', kuantitas: 10, harga: 50000, subtotal: 500000)],
);

class _MejaPalsu implements MejaRepository {
  _MejaPalsu({this.tertunda = false});
  final bool tertunda;
  double? dibayarTerakhir;
  int panggilanBayar = 0;

  @override
  Future<Result<BillDetail>> detail(String billId) async => Ok(_bon);

  @override
  Future<Result<HasilTulis>> bayar(String billId, {required String tipe, required double dibayar}) async {
    panggilanBayar++;
    dibayarTerakhir = dibayar;
    return Ok(tertunda ? HasilTulis(tertunda: true, clientRef: 'c1') : HasilTulis.langsung);
  }

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

PesanAntrean _pesan(String ref, String jenis, String? tokoId) => PesanAntrean(
  urut: 0,
  clientRef: ref,
  jenis: jenis,
  tokoId: tokoId,
  path: '/x',
  body: const {},
  dibuat: DateTime(2026, 9, 8),
);

Future<void> _pompa(WidgetTester t, [int kali = 20]) async {
  for (var i = 0; i < kali; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  group('delta stok tertunda mencakup jenis non-checkout', () {
    // Bug: penyaring toko dibangun dari tabel transaksi lokal (hanya checkout),
    // sehingga opname/stok masuk/bayar bon offline tidak pernah mengubah stok
    // yang tampil — kasir menjual barang yang sudah dicatat rusak.
    test('OPNAME & STOK_MASUK milik toko ikut dihitung', () async {
      final a = AntreanMemori();
      await a.antrekan(_pesan('r1', 'OPNAME', 'T1'), deltaStok: {'P1': -4});
      await a.antrekan(_pesan('r2', 'STOK_MASUK', 'T1'), deltaStok: {'P2': 12});

      expect(await a.deltaStokTertunda(tokoId: 'T1'), {'P1': -4.0, 'P2': 12.0});
      expect(await a.deltaStokTertunda(), {'P1': -4.0, 'P2': 12.0});
    });

    test('delta toko lain tidak bocor; tanpa toko ikut (toko belum dipilih)', () async {
      final a = AntreanMemori();
      await a.antrekan(_pesan('r1', 'OPNAME', 'T1'), deltaStok: {'P1': -4});
      await a.antrekan(_pesan('r2', 'OPNAME', 'T2'), deltaStok: {'P9': -9});
      await a.antrekan(_pesan('r3', 'STOK_MASUK', null), deltaStok: {'P1': 2});

      expect(await a.deltaStokTertunda(tokoId: 'T1'), {'P1': -2.0});
      expect(await a.deltaStokTertunda(tokoId: 'T2'), {'P9': -9.0, 'P1': 2.0});
    });

    test('delta hilang setelah baris selesai / dibatalkan', () async {
      final a = AntreanMemori();
      await a.antrekan(_pesan('r1', 'OPNAME', 'T1'), deltaStok: {'P1': -4});
      await a.selesai('r1');
      expect(await a.deltaStokTertunda(tokoId: 'T1'), isEmpty);

      await a.antrekan(_pesan('r2', 'OPNAME', 'T1'), deltaStok: {'P1': -3});
      await a.batalkan('r2');
      expect(await a.deltaStokTertunda(tokoId: 'T1'), isEmpty);
    });
  });

  group('pesan "perlu ditinjau" menunjuk tempat yang benar', () {
    Future<String?> galat(String jenis) async {
      final a = AntreanMemori();
      final tulis = AntreanTulis(antrean: a, tokoId: 'T1');
      await tulis.jalankan(
        jenis: jenis,
        path: '/x',
        body: const {},
        // Timeout SETELAH kirim = "mungkin sampai" → baris masuk TINJAU.
        kirim: (_) async => throw const ApiException(
          message: 'Server tidak merespons (timeout).',
          mungkinSampai: true,
        ),
      );
      return (await a.semua()).single.galatTerakhir;
    }

    test('opname & stok masuk diarahkan ke layar Produk, bukan Riwayat', () async {
      for (final jenis in ['OPNAME', 'STOK_MASUK']) {
        final pesan = await galat(jenis);
        expect(pesan, contains('layar Produk'), reason: jenis);
        expect(pesan, isNot(contains('Riwayat')), reason: jenis);
      }
    });

    test('checkout tetap diarahkan seperti semula', () async {
      expect(await galat('CHECKOUT'), contains('sudah tercatat'));
    });
  });

  group('bayar bon meja', () {
    Future<ProviderContainer> wadah(
      WidgetTester t, {
      required _MejaPalsu meja,
      _PrinterPalsu? printer,
    }) async {
      late final ProviderContainer c;
      await t.runAsync(() async {
        c = ProviderContainer(
          overrides: [
            secureStorageProvider.overrideWithValue(_Storage()),
            masaCobaServiceProvider.overrideWithValue(MasaCobaPalsu()),
            if (printer != null) printerServiceProvider.overrideWithValue(printer),
            mejaRepositoryProvider.overrideWithValue(meja),
            ...overrideOffline(antrean: AntreanMemori()),
          ],
        );
        await c.read(authControllerProvider.notifier).startDemo();
        await c.read(activeTokoIdProvider.notifier).select('TOKO-6');
      });
      addTearDown(c.dispose);
      return c;
    }

    Widget app(ProviderContainer c) => UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const BillDetailScreen(billId: 'B1', mejaNomor: '4'),
      ),
    );

    testWidgets('uang kurang: tombol Bayar terkunci & sisa kurang ditampilkan', (t) async {
      final meja = _MejaPalsu();
      final c = await wadah(t, meja: meja);
      await t.pumpWidget(app(c));
      await _pompa(t);

      await t.tap(find.widgetWithText(FilledButton, 'Bayar'));
      await _pompa(t);
      // Nominal awal sudah diformat (bukan "500000").
      expect(find.text('500.000'), findsOneWidget);

      await t.enterText(find.byType(TextField), '50000');
      await _pompa(t);
      expect(find.textContaining('Kurang Rp 450.000'), findsOneWidget);

      final tombol = t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Bayar').last);
      expect(tombol.onPressed, isNull, reason: 'kurang bayar tidak boleh diteruskan');

      await t.tap(find.widgetWithText(FilledButton, 'Bayar').last);
      await _pompa(t);
      expect(meja.panggilanBayar, 0);
    });

    testWidgets('uang cukup: kembalian tampil dan pembayaran diteruskan', (t) async {
      final meja = _MejaPalsu();
      final c = await wadah(t, meja: meja);
      await t.pumpWidget(app(c));
      await _pompa(t);

      await t.tap(find.widgetWithText(FilledButton, 'Bayar'));
      await _pompa(t);
      await t.enterText(find.byType(TextField), '600000');
      await _pompa(t);
      expect(find.textContaining('Kembalian Rp 100.000'), findsOneWidget);

      await t.tap(find.widgetWithText(FilledButton, 'Bayar').last);
      await _pompa(t, 30);
      expect(meja.dibayarTerakhir, 600000);
    });

    testWidgets('bon offline: struk memakai nomor lokal, bukan "Bon offline"', (t) async {
      final printer = _PrinterPalsu();
      final c = await wadah(t, meja: _MejaPalsu(tertunda: true), printer: printer);
      await t.pumpWidget(app(c));
      await _pompa(t);

      await t.tap(find.widgetWithText(FilledButton, 'Bayar'));
      await _pompa(t);
      await t.tap(find.widgetWithText(FilledButton, 'Bayar').last);
      await _pompa(t, 40);

      // Nomor lokal berpola L-yymmdd-NNNN dan menggantikan nomor bon kembar.
      expect(find.textContaining('Bon offline'), findsNothing);
      expect(find.textContaining(RegExp(r'L-\d{6}-\d{4}')), findsWidgets);
    });
  });

  group('keranjang: aksi merusak tetap berlabel', () {
    testWidgets('tombol Kosongkan punya teks, bukan ikon telanjang', (t) async {
      late final ProviderContainer c;
      await t.runAsync(() async {
        c = ProviderContainer(
          overrides: [
            secureStorageProvider.overrideWithValue(_Storage()),
            masaCobaServiceProvider.overrideWithValue(MasaCobaPalsu()),
            ...overrideOffline(antrean: AntreanMemori()),
          ],
        );
        await c.read(authControllerProvider.notifier).startDemo();
      });
      addTearDown(c.dispose);
      c.read(cartControllerProvider.notifier).add(
        const Product(id: 'P1', nama: 'Kopi', harga: 18000, stok: 5),
      );

      await t.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(theme: AppTheme.light(), home: const Scaffold(body: CartSheet())),
      ));
      await _pompa(t);

      expect(find.text('Kosongkan'), findsOneWidget);
      expect(find.text('Parkir'), findsOneWidget);
    });
  });

  group('dialog diskon & catatan memiliki controllernya sendiri', () {
    testWidgets('menerapkan diskon lalu membuka dialog lagi tanpa galat', (t) async {
      // Kartu ini murni state lokal keranjang — tidak perlu sesi demo.
      final c = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(_Storage()),
          masaCobaServiceProvider.overrideWithValue(MasaCobaPalsu()),
          ...overrideOffline(antrean: AntreanMemori()),
        ],
      );
      addTearDown(c.dispose);

      await t.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: Scaffold(body: KartuTambahanKeranjang())),
      ));
      await _pompa(t);

      await t.tap(find.text('Diskon transaksi'));
      await _pompa(t);
      await t.enterText(find.byType(TextField), '10');
      await t.tap(find.widgetWithText(FilledButton, 'Terapkan'));
      await _pompa(t, 30);

      expect(c.read(keranjangMetaProvider).diskonPersen, 10);
      expect(t.takeException(), isNull, reason: 'controller tidak dipakai setelah dibuang');

      // Catatan: jalur kedua dengan pola yang sama.
      await t.tap(find.text('Catatan'));
      await _pompa(t);
      await t.enterText(find.byType(TextField), 'ambil jam 5');
      await t.tap(find.widgetWithText(FilledButton, 'Simpan'));
      await _pompa(t, 30);
      expect(c.read(keranjangMetaProvider).catatan, 'ambil jam 5');
      expect(t.takeException(), isNull);
    });
  });

  group('mesin demo sejalan dengan server & desktop', () {
    const toko = {'toko_id': 'TOKO-1'};

    Map<String, dynamic> produkBerstok(DemoEngine e) => Map<String, dynamic>.from(
      (e.handle(method: 'GET', path: '/produk', query: toko).body['data'] as List)
          .cast<Map>()
          .firstWhere((p) => p['kelola_stok'] == true && (p['stok'] as num) > 0),
    );

    num stok(DemoEngine e, String id) => (e
            .handle(method: 'GET', path: '/produk', query: {...toko, 'include_habis': '1'})
            .body['data'] as List)
        .cast<Map>()
        .firstWhere((p) => p['id'] == id)['stok'] as num;

    test('checkout melebihi stok ditolak, stok tidak berubah', () {
      final e = DemoEngine();
      final p = produkBerstok(e);
      final awal = stok(e, '${p['id']}');
      final r = e.handle(
        method: 'POST',
        path: '/transaksi/checkout',
        query: toko,
        body: {
          'items': [
            {'id_produk': p['id'], 'kuantitas': awal + 5, 'harga': p['harga_jual']},
          ],
          'tipe_pembayaran': 'QRIS',
          'dibayar': (p['harga_jual'] as num) * (awal + 5),
        },
      );
      expect(r.status, 422);
      expect(r.body['message'], contains('tidak mencukupi'));
      expect(stok(e, '${p['id']}'), awal, reason: 'stok tidak boleh terpotong saat ditolak');
    });

    test('batas harian ditolak tanpa memotong stok', () {
      final e = DemoEngine();
      final p = produkBerstok(e);
      Map<String, dynamic> badan() => {
        'items': [
          {'id_produk': p['id'], 'kuantitas': 1, 'harga': p['harga_jual']},
        ],
        'tipe_pembayaran': 'QRIS',
        'dibayar': p['harga_jual'],
      };
      for (var i = 0; i < DemoEngine.batasTransaksiPerHari; i++) {
        expect(
          e.handle(method: 'POST', path: '/transaksi/checkout', query: toko, body: badan()).status,
          201,
        );
      }
      final sebelum = stok(e, '${p['id']}');
      final tolak = e.handle(method: 'POST', path: '/transaksi/checkout', query: toko, body: badan());
      expect(tolak.status, 422);
      expect(stok(e, '${p['id']}'), sebelum, reason: 'transaksi ditolak = stok utuh');
    });

    test('laporan harian tidak menghitung transaksi yang dibatalkan', () {
      final e = DemoEngine();
      final p = produkBerstok(e);
      double omzetHariIni() {
        final rows = ((e.handle(method: 'GET', path: '/laporan/penjualan-harian', query: toko)
                .body['data'] as Map)['rows'] as List)
            .cast<Map>();
        return (rows.last['total_omzet'] as num).toDouble();
      }

      final sebelum = omzetHariIni();
      final bayar = e.handle(
        method: 'POST',
        path: '/transaksi/checkout',
        query: toko,
        body: {
          'items': [
            {'id_produk': p['id'], 'kuantitas': 1, 'harga': p['harga_jual']},
          ],
          'tipe_pembayaran': 'QRIS',
          'dibayar': p['harga_jual'],
        },
      );
      expect(omzetHariIni(), greaterThan(sebelum));

      final id = '${(bayar.body['data'] as Map)['id']}';
      e.handle(method: 'POST', path: '/transaksi/$id/batal', query: toko);
      expect(omzetHariIni(), sebelum, reason: 'dibatalkan = keluar dari grafik harian');
    });

    test('bon meja: kurang bayar ditolak; lunas memotong stok lalu batal mengembalikannya', () {
      final e = DemoEngine();
      const tokoBakso = {'toko_id': 'TOKO-2'}; // bakso: satu-satunya toko bermeja
      final peta = ((e.handle(method: 'GET', path: '/bills', query: tokoBakso).body['data']
              as Map)['tables'] as List)
          .cast<Map>();
      final meja = peta.firstWhere((m) => m['bill'] == null, orElse: () => peta.first);
      final buka = e.handle(
        method: 'POST',
        path: '/bills',
        query: tokoBakso,
        body: {'meja_id': meja['id'], 'pax': 2},
      );
      expect(buka.status, anyOf(200, 201));
      // POST /bills membalas tanpa data; id bon diambil dari peta meja.
      String idBon() => '${((e.handle(method: 'GET', path: '/bills', query: tokoBakso).body['data'] as Map)['tables'] as List).cast<Map>().firstWhere((m) => m['id'] == meja['id'])['bill']['id']}';
      final billId = idBon();
      final produk = Map<String, dynamic>.from(
        (e.handle(method: 'GET', path: '/produk', query: tokoBakso).body['data'] as List)
            .cast<Map>()
            .firstWhere((p) => p['kelola_stok'] == true && (p['stok'] as num) >= 3),
      );
      final stokAwal = (produk['stok'] as num).toDouble();
      e.handle(
        method: 'POST',
        path: '/bills/$billId/rounds',
        query: tokoBakso,
        body: {
          'items': [
            {'id_produk': produk['id'], 'kuantitas': 3},
          ],
        },
      );

      final bon = Map<String, dynamic>.from(
        e.handle(method: 'GET', path: '/bills/$billId', query: tokoBakso).body['data'] as Map,
      );
      final total = (bon['total'] as num).toDouble();

      final kurang = e.handle(
        method: 'POST',
        path: '/bills/$billId/settle',
        query: tokoBakso,
        body: {'tipe_pembayaran': 'TUNAI', 'dibayar': total - 1000},
      );
      expect(kurang.status, 422, reason: 'kurang bayar ditolak seperti kasir & desktop');

      final lunas = e.handle(
        method: 'POST',
        path: '/bills/$billId/settle',
        query: tokoBakso,
        body: {'tipe_pembayaran': 'TUNAI', 'dibayar': total},
      );
      expect(lunas.status, 200);

      num stokBakso() => (e
              .handle(method: 'GET', path: '/produk', query: {...tokoBakso, 'include_habis': '1'})
              .body['data'] as List)
          .cast<Map>()
          .firstWhere((p) => p['id'] == produk['id'])['stok'] as num;
      expect(stokBakso(), stokAwal - 3, reason: 'stok berkurang saat bon dilunasi');

      final trx = (e.handle(method: 'GET', path: '/transaksi', query: tokoBakso).body['data'] as List)
          .cast<Map>()
          .first;
      e.handle(method: 'POST', path: '/transaksi/${trx['id']}/batal', query: tokoBakso);
      expect(stokBakso(), stokAwal, reason: 'batal mengembalikan tepat yang dipotong');
    });
  });

  group('cetak otomatis pada transaksi pertama sesi', () {
    // Bug: preferensi printer dibaca async; cuplikan seketika di lembar hasil
    // selalu null pada pemakaian pertama, jadi struk pertama tiap sesi tidak
    // pernah tercetak meski saklarnya nyala.
    testWidgets('provider belum sempat dimuat pun struk tetap tercetak', (t) async {
      final printer = _PrinterPalsu();
      late final ProviderContainer c;
      await t.runAsync(() async {
        c = ProviderContainer(
          overrides: [
            secureStorageProvider.overrideWithValue(
              _Storage({
                'printer_mac': '00:11:22:33:44:55',
                'printer_nama': 'RPP02',
                'printer_otomatis': '1',
              }),
            ),
            masaCobaServiceProvider.overrideWithValue(MasaCobaPalsu()),
            printerServiceProvider.overrideWithValue(printer),
            ...overrideOffline(antrean: AntreanMemori()),
          ],
        );
      });
      addTearDown(c.dispose);
      // Sengaja TIDAK memanaskan printerTerpilihProvider lebih dulu.

      await t.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: HasilTransaksiSheet(
              struk: Struk(
                namaToko: 'X',
                nomor: 'TRX/0001',
                waktu: DateTime(2026, 9, 9),
                baris: const [StrukBaris(nama: 'Kopi', kuantitas: 1, harga: 18000)],
                total: 18000,
                metode: 'TUNAI',
              ),
              kembalian: 0,
            ),
          ),
        ),
      ));
      await _pompa(t, 40);

      expect(printer.dicetak.single.nomor, 'TRX/0001');
    });
  });

  group('keranjang terparkir tidak boleh hilang', () {
    testWidgets('isi dipindahkan ke keranjang walau layar keburu tertutup', (t) async {
      final parkir = ParkirMemori();
      late final ProviderContainer c;
      await t.runAsync(() async {
        c = ProviderContainer(
          overrides: [
            secureStorageProvider.overrideWithValue(_Storage()),
            masaCobaServiceProvider.overrideWithValue(MasaCobaPalsu()),
            parkirStoreProvider.overrideWithValue(parkir),
            ...overrideOffline(antrean: AntreanMemori()),
          ],
        );
        await c.read(activeTokoIdProvider.notifier).select('TOKO-1');
      });
      addTearDown(c.dispose);

      final entri = await parkir.simpan(
        'TOKO-1',
        items: const [CartItem(product: Product(id: 'P1', nama: 'Kopi', harga: 18000), qty: 3)],
      );

      late BuildContext ctx;
      late WidgetRef wref;
      await t.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(builder: (context, ref, _) {
              ctx = context;
              wref = ref;
              return const SizedBox.expand();
            }),
          ),
        ),
      ));

      final aksi = lanjutkanParkir(ctx, wref, entri);
      // Layar diganti selagi entri sedang diambil dari penyimpanan.
      await t.pumpWidget(const MaterialApp(home: Scaffold(body: Text('layar lain'))));
      await _pompa(t, 20);
      await aksi;

      final isi = c.read(cartControllerProvider);
      expect(isi.single.product.id, 'P1', reason: 'belanjaan tidak boleh menguap');
      expect(isi.single.qty, 3);
      expect(await parkir.daftar('TOKO-1'), isEmpty);
    });
  });
}
