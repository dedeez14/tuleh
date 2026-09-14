// Tampilan & input produk mengikuti bidang usaha toko (server 2026-09-14):
// mode jual per produk (per satuan / per ukuran / per ukuran atau rupiah),
// jenis item katalog kasir dari manifest, nominal ikut checkout, dan toko yang
// menjual produk. Server lama tanpa bidang-bidang ini tetap berjalan seperti
// dulu (tebakan nama satuan). Padanan desktop: frontend/tests/mode-jual-kontrak.test.js.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/network/api_client.dart';
import 'package:tuleh_pos/core/offline/antrean.dart';
import 'package:tuleh_pos/core/offline/koneksi.dart';
import 'package:tuleh_pos/core/offline/nomor_lokal.dart';
import 'package:tuleh_pos/core/storage/secure_storage.dart';
import 'package:tuleh_pos/core/theme/app_theme.dart';
import 'package:tuleh_pos/features/auth/presentation/controllers/auth_controller.dart';
import 'package:tuleh_pos/features/cetak/data/struk_teks.dart';
import 'package:tuleh_pos/features/cetak/domain/entities/struk.dart';
import 'package:tuleh_pos/features/demo/data/demo_engine.dart';
import 'package:tuleh_pos/features/demo/data/masa_coba_service.dart';
import 'package:tuleh_pos/features/kasir/data/checkout_repository.dart';
import 'package:tuleh_pos/features/kasir/data/datasources/transaction_remote_datasource.dart';
import 'package:tuleh_pos/features/kasir/data/parkir_store.dart';
import 'package:tuleh_pos/features/kasir/domain/entities/cart_item.dart';
import 'package:tuleh_pos/features/kasir/presentation/widgets/lembar_ukuran.dart';
import 'package:tuleh_pos/features/products/data/datasources/product_remote_datasource.dart';
import 'package:tuleh_pos/features/products/domain/entities/product.dart';
import 'package:tuleh_pos/features/products/presentation/providers/products_provider.dart';
import 'package:tuleh_pos/features/products/presentation/screens/product_form_sheet.dart';
import 'package:tuleh_pos/features/toko/domain/entities/toko_manifest.dart';
import 'package:tuleh_pos/features/toko/presentation/providers/toko_providers.dart';

import 'helpers/masa_coba_palsu.dart';

/// Server tiruan: mencatat permintaan, menjawab dengan [jawab].
class _Server implements HttpClientAdapter {
  _Server(this.jawab);
  final Object? Function(RequestOptions o) jawab;
  final permintaan = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? s, Future<void>? c) async {
    permintaan.add(o);
    return ResponseBody.fromString(
      jsonEncode({'success': true, 'data': jawab(o)}),
      200,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );
  }

  @override
  void close({bool force = false}) {}
}

Dio _dio(_Server s) => Dio(BaseOptions(baseUrl: 'https://x.test/api', validateStatus: (_) => true))
  ..httpClientAdapter = s;

class _Penanda implements PenandaKoneksi {
  @override
  bool get offline => false;
  @override
  void tandaiOffline({DateTime? ditarikPada}) {}
  @override
  void tandaiOnline() {}
}

class _Storage extends SecureStorage {
  _Storage() : super(const FlutterSecureStorage());
  final Map<String, String> m = {};
  @override
  Future<String?> readToken() async => m['token'];
  @override
  Future<void> writeToken(String? v) async => v == null ? m.remove('token') : m['token'] = v;
  @override
  Future<String?> readActiveTokoId() async => m['toko'];
  @override
  Future<void> writeActiveTokoId(String? v) async => v == null ? m.remove('toko') : m['toko'] = v;
  @override
  Future<String?> bacaNilai(String k) async => m[k];
  @override
  Future<void> tulisNilai(String k, String? v) async => v == null ? m.remove(k) : m[k] = v;
  @override
  Future<void> clearSession() async {
    m.remove('token');
    m.remove('toko');
  }
}

Future<ProviderContainer> _demo(String toko) async {
  final c = ProviderContainer(
    overrides: [
      secureStorageProvider.overrideWithValue(_Storage()),
      masaCobaServiceProvider.overrideWithValue(MasaCobaPalsu()),
      ...overrideOffline(antrean: AntreanMemori()),
    ],
  );
  await c.read(authControllerProvider.notifier).startDemo();
  await c.read(activeTokoIdProvider.notifier).select(toko);
  return c;
}

/// Produk laundry kiloan dari server baru.
const _cuciKiloan = Product(
  id: 'P-CKL',
  nama: 'Cuci Kering Lipat',
  harga: 7000,
  satuan: 'Kg',
  tipe: 'JASA',
  modeJual: 'UKUR_NOMINAL',
  modeJualAsal: 'SATUAN',
  desimal: true,
  bolehNominal: true,
  langkah: 0.01,
);

/// Beras per karung setengahan: terukur, tapi tanpa nominal.
const _berasKarung = Product(
  id: 'P-BRS',
  nama: 'Beras Karung',
  harga: 300000,
  satuan: 'Karung',
  modeJual: 'UKUR',
  modeJualAsal: 'PRODUK',
  desimal: true,
  bolehNominal: false,
  langkah: 0.5,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('datasource produk', () {
    test('membaca mode jual server; server lama tanpa bidang → tebakan satuan', () async {
      final server = _Server((_) => [
        {
          'id': 'A', 'nama': 'Beras', 'harga_jual': 14000, 'satuan': {'nama': 'Kg'},
          'mode_jual': 'UKUR_NOMINAL', 'mode_jual_nama': 'Per ukuran atau per rupiah',
          'mode_jual_asal': 'SATUAN', 'desimal': true, 'boleh_nominal': true, 'langkah': 0.01,
          'toko_ids': ['enc-1'],
        },
        {
          'id': 'B', 'nama': 'Telur', 'harga_jual': 28000, 'satuan': 'kg',
          'mode_jual': 'SATUAN', 'mode_jual_asal': 'PRODUK', 'desimal': false,
          'boleh_nominal': false, 'langkah': 1,
        },
        {'id': 'C', 'nama': 'Mangga', 'harga_jual': 27000, 'satuan': 'kg'},
      ]);
      final rows = await ProductRemoteDataSource(_dio(server)).list(tipe: 'SEMUA');
      expect(server.permintaan.single.queryParameters['tipe'], 'SEMUA');

      final beras = rows[0];
      expect(beras.modeJual, 'UKUR_NOMINAL');
      expect(beras.modeJualNama, 'Per ukuran atau per rupiah');
      expect(beras.perilaku.terukur, isTrue);
      expect(beras.perilaku.bolehNominal, isTrue);
      expect(beras.perilaku.langkah, 0.01);

      final telur = rows[1];
      expect(telur.modeJualAsal, 'PRODUK');
      expect(telur.perilaku.terukur, isFalse, reason: 'kg dipaksa per satuan oleh pemilik');

      final lama = rows[2];
      expect(lama.modeJual, isNull);
      expect(lama.desimal, isNull);
      expect(lama.perilaku.terukur, isTrue, reason: 'server lama: kg tetap ditimbang');
      expect(lama.perilaku.bolehNominal, isTrue);
    });

    test('tanpa tipe → query tidak membawa tipe (bawaan server)', () async {
      final server = _Server((_) => const []);
      await ProductRemoteDataSource(_dio(server)).list();
      expect(server.permintaan.single.queryParameters.containsKey('tipe'), isFalse);
    });

    test('create membawa satuan, mode jual, toko; update mode "" = kembali otomatis', () async {
      final server = _Server((_) => const {});
      final ds = ProductRemoteDataSource(_dio(server));
      await ds.create(
        nama: 'Cuci Kiloan', tipe: 'JASA', hargaJual: 7000,
        satuanId: 'S-KG', modeJual: 'UKUR_NOMINAL', tokoIds: const ['T1'],
      );
      final buat = server.permintaan.last.data as Map;
      expect(buat['satuan_id'], 'S-KG');
      expect(buat['mode_jual'], 'UKUR_NOMINAL');
      expect(buat['toko_ids'], ['T1']);

      await ds.create(nama: 'Kopi', tipe: 'PRODUK', hargaJual: 5000);
      final polos = server.permintaan.last.data as Map;
      for (final k in ['satuan_id', 'mode_jual', 'toko_ids']) {
        expect(polos.containsKey(k), isFalse, reason: '$k tak dikirim: otomatis / semua toko');
      }

      await ds.update(id: 'P1', modeJual: '');
      final reset = server.permintaan.last;
      expect(reset.method, 'PATCH');
      expect(reset.data, {'mode_jual': null});

      await ds.update(id: 'P1', nama: 'Beras');
      expect(server.permintaan.last.data, {'nama': 'Beras'}, reason: 'mode tidak disebut = tidak diubah');

      await ds.update(id: 'P1', satuanId: 'S9', modeJual: 'UKUR');
      expect(server.permintaan.last.data, {'satuan_id': 'S9', 'mode_jual': 'UKUR'});
    });

    test('master mode jual, satuan, dan toko produk', () async {
      final server = _Server((o) => switch (o.path) {
        '/mode-jual' => [
          {'kode': 'SATUAN', 'nama': 'Per satuan', 'desimal': false, 'boleh_nominal': false},
          {'kode': 'UKUR_NOMINAL', 'nama': 'Per ukuran atau per rupiah', 'keterangan': 'Rp', 'desimal': true, 'boleh_nominal': true},
        ],
        '/satuan' => [
          {'id': 'S1', 'kode': 'KG', 'nama': 'Kg'},
        ],
        _ => {
          'semua_toko': false,
          'tokos': [
            {'id': 'T1', 'nama': 'Laundry Pusat', 'dijual': true},
            {'id': 'T2', 'nama': 'Laundry Cabang', 'dijual': false},
          ],
        },
      });
      final ds = ProductRemoteDataSource(_dio(server));

      final mode = await ds.modeJual();
      expect(mode.map((m) => m.kode), ['SATUAN', 'UKUR_NOMINAL']);
      expect(mode.last.bolehNominal, isTrue);
      expect(mode.last.keterangan, 'Rp');

      final satuan = await ds.satuan();
      expect(satuan.single.nama, 'Kg');

      final toko = await ds.tokoProduk('P 1');
      expect(server.permintaan.last.path, '/produk-toko/P%201');
      expect(toko.semuaToko, isFalse);
      expect([for (final t in toko.tokos) if (t.dijual) t.id], ['T1']);

      await ds.aturToko('P1', const []);
      expect(server.permintaan.last.method, 'PUT');
      expect(server.permintaan.last.path, '/produk-toko/P1');
      expect(server.permintaan.last.data, {'toko_ids': <String>[]}, reason: 'kosong = semua toko');
    });
  });

  group('jenis item katalog kasir', () {
    test('manifest membawa item_config.jenis_item; server lama → null', () {
      final baru = TokoManifest.fromJson({
        'item_config': {'jenis_item': ['JASA', 'PRODUK']},
      });
      expect(baru.jenisItem, ['JASA', 'PRODUK']);
      expect(TokoManifest.fromJson({'item_config': {'unit_mode': 'unit'}}).jenisItem, isNull);
      expect(TokoManifest.fromJson(const {}).jenisItem, isNull);
    });

    test('tipe dari jenis item; tanpa jenis item ditebak dari bidang usaha', () {
      expect(tipeKatalogKasir(['JASA', 'PRODUK']), 'SEMUA');
      expect(tipeKatalogKasir(['JASA']), 'JASA');
      expect(tipeKatalogKasir(['PRODUK']), isNull, reason: 'retail: bawaan server');
      expect(tipeKatalogKasir([]), isNull);
      expect(tipeKatalogKasir(null, sinyalBidang: 'Jasa Laundry Kiloan & Satuan'), 'SEMUA');
      expect(tipeKatalogKasir(null, sinyalBidang: 'Retail Minimarket'), isNull);
      // jenis_item dari server menang atas tebakan nama.
      expect(tipeKatalogKasir(['PRODUK'], sinyalBidang: 'laundry'), isNull);
    });

    test('provider toko demo: laundry memuat jasa + barang, minimarket bawaan', () async {
      final laundry = await _demo('TOKO-3');
      addTearDown(laundry.dispose);
      expect(await laundry.read(tipeKatalogKasirProvider.future), 'SEMUA');
      expect(await laundry.read(productsProvider.future), isNotEmpty);

      final minimarket = await _demo('TOKO-1');
      addTearDown(minimarket.dispose);
      expect(await minimarket.read(tipeKatalogKasirProvider.future), isNull);
    });
  });

  group('keranjang, checkout, struk', () {
    test('baris mengikuti mode jual produk, bukan nama satuan', () {
      const karung = CartItem(product: _berasKarung, qty: 1.5, cara: CaraInput.ukuran);
      expect(karung.terukur, isTrue);
      expect(karung.labelQty, '1,5 Karung');
      expect(karung.nominalCheckout, isNull);

      const telur = CartItem(
        product: Product(id: 'T', nama: 'Telur', harga: 28000, satuan: 'kg', modeJual: 'SATUAN', desimal: false, langkah: 1),
        qty: 2,
      );
      expect(telur.terukur, isFalse);
      expect(telur.labelQty, '2');
    });

    test('checkout mengirim nominal hanya pada baris per rupiah (kuantitas tetap untuk server lama)', () async {
      Map<String, dynamic>? badan;
      final server = _Server((o) {
        badan = Map<String, dynamic>.from(o.data as Map);
        return {'nomor': '26-POS-000077', 'kembalian': 0};
      });
      final repo = CheckoutRepository(
        remote: TransactionRemoteDataSource(_dio(server)),
        antrean: AntreanMemori(),
        nomorLokal: NomorLokal(_Storage()),
        koneksi: _Penanda(),
        tokoId: 'T1',
      );
      await repo.bayar(
        items: const [
          CartItem(product: _cuciKiloan, qty: 2.85, cara: CaraInput.nominal, nominalDiminta: 20000),
          CartItem(product: _berasKarung, qty: 1.5, cara: CaraInput.ukuran),
        ],
        metode: 'QRIS',
        dibayar: 469950,
        total: 469950,
        buatStruk: (n, _) => Struk(namaToko: 'X', nomor: n, waktu: DateTime(2026), baris: const [], total: 469950),
      );
      final items = (badan!['items'] as List).cast<Map>();
      expect(items[0]['nominal'], 20000);
      expect(items[0]['kuantitas'], 2.85);
      expect(items[1].containsKey('nominal'), isFalse);
    });

    test('struk: satuan non-tabel tetap terukur, "(diminta …)" tercetak, JSON utuh', () {
      final s = Struk(
        namaToko: 'Laundry', nomor: 'N1', waktu: DateTime(2026, 9, 14, 9),
        baris: const [
          StrukBaris(nama: 'Cuci Kering Lipat', kuantitas: 2.85, harga: 7000, satuan: 'Kg', dijualPerUkuran: true, nominalDiminta: 20000),
          StrukBaris(nama: 'Beras Karung', kuantitas: 1.5, harga: 300000, satuan: 'Karung', dijualPerUkuran: true),
          StrukBaris(nama: 'Kopi', kuantitas: 2, harga: 5000),
        ],
        total: 479950,
      );
      expect(s.baris[1].labelKuantitas, '1,5 Karung');
      expect(s.jumlahItem, 1 + 1 + 2);
      final teks = const StrukTeks().bangun(s);
      expect(teks, contains('  2,85 Kg x Rp 7.000'));
      expect(teks, contains('  (diminta Rp 20.000)'));
      expect(teks.split('\n').where((b) => b.contains('diminta')).length, 1);

      final json = s.toJson();
      expect((json['baris'] as List)[2], {'nama': 'Kopi', 'kuantitas': 2, 'harga': 5000.0},
          reason: 'baris biasa tetap ringkas');
      final ulang = Struk.fromJson(jsonDecode(jsonEncode(json)) as Map<String, dynamic>);
      expect(ulang.baris[0].nominalDiminta, 20000);
      expect(ulang.baris[1].labelKuantitas, '1,5 Karung');
      expect(ulang.baris[2].terukur, isFalse);
    });

    test('keranjang terparkir menyimpan mode jual produk', () {
      final parkir = KeranjangParkir(
        id: 'k1', nomor: 1, waktu: DateTime(2026, 9, 14),
        items: const [CartItem(product: _berasKarung, qty: 1.5, cara: CaraInput.ukuran)],
      );
      final ulang = KeranjangParkir.fromJson(
        jsonDecode(jsonEncode(parkir.toJson())) as Map<String, dynamic>,
      )!;
      final p = ulang.items.single.product;
      expect(p.modeJual, 'UKUR');
      expect(p.perilaku.langkah, 0.5);
      expect(p.perilaku.bolehNominal, isFalse);
      expect(ulang.items.single.labelQty, '1,5 Karung');
    });
  });

  group('mesin demo', () {
    late DemoEngine engine;
    setUp(() => engine = DemoEngine());
    const laundry = {'toko_id': 'TOKO-3'};

    DemoResponse req(String method, String path, [dynamic body]) =>
        engine.handle(method: method, path: path, query: laundry, body: body);
    Map<String, dynamic> produkBernama(String nama) => Map<String, dynamic>.from(
          (req('GET', '/produk').body['data'] as List).cast<Map>().firstWhere((p) => p['nama'] == nama),
        );

    test('/mode-jual & /satuan tersedia', () {
      final mode = req('GET', '/mode-jual').body['data'] as List;
      expect(mode.map((m) => m['kode']), ['SATUAN', 'UKUR', 'UKUR_NOMINAL']);
      expect((req('GET', '/satuan').body['data'] as List).map((s) => s['nama']), contains('Kg'));
    });

    test('produk baru dengan mode jual & satuan; PATCH null kembali otomatis', () {
      final r = req('POST', '/produk', {
        'nama': 'Beras Karung', 'tipe': 'PRODUK', 'harga_jual': 300000,
        'satuan_id': 'SAT-8', 'mode_jual': 'UKUR',
      });
      expect(r.status, 201);
      final baru = produkBernama('Beras Karung');
      expect(baru['satuan'], 'Karung');
      expect(baru['mode_jual'], 'UKUR');
      expect(baru['mode_jual_asal'], 'PRODUK');
      expect(baru['desimal'], isTrue);
      expect(baru['boleh_nominal'], isFalse);
      expect(baru['langkah'], 0.01);

      req('PATCH', '/produk/${baru['id']}', {'satuan_id': 'SAT-5'});
      expect(produkBernama('Beras Karung')['mode_jual'], 'UKUR', reason: 'ganti satuan tak menghapus pilihan');

      req('PATCH', '/produk/${baru['id']}', {'mode_jual': null});
      final otomatis = produkBernama('Beras Karung');
      expect(otomatis.containsKey('mode_jual'), isFalse);
      expect(otomatis['satuan'], 'Kg');
    });

    test('/produk-toko: hanya toko aktif, PUT diterima', () {
      final id = produkBernama('Cuci Kering Lipat')['id'];
      final d = req('GET', '/produk-toko/$id').body['data'] as Map;
      expect(d['semua_toko'], isTrue);
      expect((d['tokos'] as List).single['id'], 'TOKO-3');
      expect(req('PUT', '/produk-toko/$id', {'toko_ids': <String>[]}).status, 200);
      expect(req('GET', '/produk-toko/TIDAK-ADA').status, 404);
    });

    test('checkout per nominal dihitung ulang seperti server; aturan mode ditegakkan', () {
      final ckl = produkBernama('Cuci Kering Lipat');
      final r = req('POST', '/transaksi/checkout', {
        'items': [
          {'id_produk': ckl['id'], 'kuantitas': 3, 'harga': 7000, 'nominal': 20000},
        ],
        'tipe_pembayaran': 'TUNAI',
        'dibayar': 20000,
      });
      expect(r.status, 201, reason: '${r.body['message']}');
      final item = ((r.body['data'] as Map)['items'] as List).single as Map;
      expect(item['kuantitas'], 2.85, reason: 'Rp 20.000 @ Rp 7.000/kg');
      expect(item['nominal_diminta'], 20000);
      expect(item['subtotal'], closeTo(19950, 0.001));

      final bedCover = produkBernama('Bed Cover');
      final nominalDitolak = req('POST', '/transaksi/checkout', {
        'items': [{'id_produk': bedCover['id'], 'kuantitas': 1, 'harga': 25000, 'nominal': 50000}],
        'tipe_pembayaran': 'TUNAI', 'dibayar': 50000,
      });
      expect(nominalDitolak.status, 422);

      final pecahanDitolak = req('POST', '/transaksi/checkout', {
        'items': [{'id_produk': bedCover['id'], 'kuantitas': 1.5, 'harga': 25000}],
        'tipe_pembayaran': 'TUNAI', 'dibayar': 50000,
      });
      expect(pecahanDitolak.status, 422);
      expect('${pecahanDitolak.body['message']}', contains('bilangan bulat'));
    });
  });

  group('layar', () {
    Future<void> pompa(WidgetTester t, [int kali = 15]) async {
      for (var i = 0; i < kali; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('lembar ukuran: produk UKUR tanpa nominal & pintasan ikut langkah', (t) async {
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => tanyaUkuran(ctx, _berasKarung),
                child: const Text('buka'),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.text('buka'));
      await pompa(t);

      final segmen = t.widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>));
      expect(segmen.segments.firstWhere((s) => s.value == true).enabled, isFalse);
      expect(find.text('0,25 Karung'), findsNothing, reason: 'bukan kelipatan 0,5');
      expect(find.text('0,5 Karung'), findsOneWidget);

      await t.enterText(find.byType(TextField).first, '1,3');
      await pompa(t);
      expect(find.textContaining('1,5 Karung × Rp 300.000'), findsOneWidget);
    });

    testWidgets('lembar ukuran: laundry kiloan tetap bisa per nominal', (t) async {
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (ctx) => Scaffold(
            body: ElevatedButton(onPressed: () => tanyaUkuran(ctx, _cuciKiloan), child: const Text('buka')),
          ),
        ),
      ));
      await t.tap(find.text('buka'));
      await pompa(t);
      await t.tap(find.text('Nominal'));
      await pompa(t);
      await t.enterText(find.byType(TextField).first, '20000');
      await pompa(t);
      expect(find.textContaining('2,85 Kg × Rp 7.000'), findsOneWidget);
      expect(find.text('Rp 19.950'), findsOneWidget);
    });

    testWidgets('formulir produk: cara input & toko, tersimpan ke katalog', (t) async {
      t.view.physicalSize = const Size(420, 1600);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      late final ProviderContainer c;
      await t.runAsync(() async => c = await _demo('TOKO-3'));
      addTearDown(c.dispose);

      await t.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: ctx,
                  isScrollControlled: true,
                  builder: (_) => const ProductFormSheet(),
                ),
                child: const Text('buka'),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.text('buka'));
      await pompa(t, 30);

      expect(find.text('Cara input di kasir'), findsOneWidget);
      expect(find.text('Dijual di toko'), findsOneWidget);
      expect(find.text('Tidak ada yang dicentang = dijual di semua toko.'), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsNWidgets(6));

      await t.enterText(find.widgetWithText(TextFormField, 'Nama produk'), 'Karpet Kiloan');
      await t.enterText(find.widgetWithText(TextFormField, 'Harga jual (Rp)'), '15000');
      await t.tap(find.text('Otomatis (ikut satuan)'));
      await pompa(t);
      await t.tap(find.text('Per ukuran atau per rupiah').last);
      await pompa(t);
      expect(find.textContaining('isi nominal Rp'), findsOneWidget);

      await t.ensureVisible(find.text('Tambah Produk').last);
      await t.tap(find.text('Tambah Produk').last);
      await pompa(t, 30);

      final res = await t.runAsync(() => c.read(dioProvider).get<dynamic>('/produk'));
      final baru = ((res!.data as Map)['data'] as List).cast<Map>().firstWhere((p) => p['nama'] == 'Karpet Kiloan');
      expect(baru['mode_jual'], 'UKUR_NOMINAL');
      expect(baru['mode_jual_asal'], 'PRODUK');
      await t.pump(const Duration(seconds: 5)); // habiskan pewaktu SnackBar
    });
  });
}
