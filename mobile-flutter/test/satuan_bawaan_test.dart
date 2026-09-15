// Server 2026-09-15 (agen INTI): satuan produk dari master data per usaha.
// - POST/PATCH /produk tanpa satuan & usaha belum punya satuan bawaan → 422
//   `errors.satuan_id` → ditampilkan DI BAWAH kolom Satuan.
// - GET/PUT /pengaturan/usaha: `satuan_bawaan` / `satuan_bawaan_id` → pemilih
//   "Satuan bawaan" di Profil Usaha, daftar dari `/satuan`.
// - Operasi stok produk tanpa satuan → 422 biasa (bukan antrean).

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/network/api_client.dart';
import 'package:tuleh_pos/core/network/api_exception.dart';
import 'package:tuleh_pos/core/offline/antrean.dart';
import 'package:tuleh_pos/core/offline/antrean_tulis.dart';
import 'package:tuleh_pos/core/storage/secure_storage.dart';
import 'package:tuleh_pos/core/theme/app_theme.dart';
import 'package:tuleh_pos/features/auth/presentation/controllers/auth_controller.dart';
import 'package:tuleh_pos/features/demo/data/demo_engine.dart';
import 'package:tuleh_pos/features/demo/data/masa_coba_service.dart';
import 'package:tuleh_pos/features/pengaturan/data/datasources/pengaturan_remote_datasource.dart';
import 'package:tuleh_pos/features/pengaturan/presentation/screens/profil_usaha_screen.dart';
import 'package:tuleh_pos/features/products/presentation/screens/product_form_sheet.dart';
import 'package:tuleh_pos/features/toko/presentation/providers/toko_providers.dart';

import 'helpers/masa_coba_palsu.dart';

class _Storage extends SecureStorage {
  _Storage() : super(const FlutterSecureStorage());
  final Map<String, String> m = {};
  @override
  Future<String?> readToken() async => m['token'];
  @override
  Future<void> writeToken(String? v) async => v == null || v.isEmpty ? m.remove('token') : m['token'] = v;
  @override
  Future<String?> readActiveTokoId() async => m['toko'];
  @override
  Future<void> writeActiveTokoId(String? v) async => v == null || v.isEmpty ? m.remove('toko') : m['toko'] = v;
  @override
  Future<String?> bacaNilai(String k) async => m[k];
  @override
  Future<void> tulisNilai(String k, String? v) async => v == null ? m.remove(k) : m[k] = v;
}

Future<ProviderContainer> _demo(String toko) async {
  final c = ProviderContainer(overrides: [
    secureStorageProvider.overrideWithValue(_Storage()),
    masaCobaServiceProvider.overrideWithValue(MasaCobaPalsu()),
    ...overrideOffline(antrean: AntreanMemori()),
  ]);
  await c.read(authControllerProvider.notifier).startDemo();
  await c.read(activeTokoIdProvider.notifier).select(toko);
  return c;
}

Future<void> _pompa(WidgetTester t, [int n = 20]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('mesin demo sejalan dengan server', () {
    Map<String, dynamic> data(DemoResponse r) => (r.body['data'] as Map).cast<String, dynamic>();

    test('satuan bawaan: dibaca, diganti, dikosongkan; id asing ditolak per kolom', () {
      final e = DemoEngine();
      const toko = {'toko_id': 'TOKO-1'};
      expect(data(e.handle(method: 'GET', path: '/pengaturan/usaha', query: toko))['satuan_bawaan'], isNotNull);

      final asing = e.handle(method: 'PUT', path: '/pengaturan/usaha', query: toko, body: {'nama': 'X', 'satuan_bawaan_id': 'SAT-TIDAK-ADA'});
      expect(asing.status, 422);
      expect((asing.body['errors'] as Map)['satuan_bawaan_id'], isNotEmpty);

      e.handle(method: 'PUT', path: '/pengaturan/usaha', query: toko, body: {'nama': 'X', 'satuan_bawaan_id': 'SAT-5'});
      expect(data(e.handle(method: 'GET', path: '/pengaturan/usaha', query: toko))['satuan_bawaan']['kode'], 'KG');
      final kg = e.handle(method: 'POST', path: '/produk', query: toko, body: {'nama': 'Gula', 'tipe': 'PRODUK', 'harga_jual': 15000});
      expect(kg.status, 201);
      expect(data(kg)['satuan'], 'Kg', reason: 'tanpa satuan → satuan bawaan usaha');

      e.handle(method: 'PUT', path: '/pengaturan/usaha', query: toko, body: {'nama': 'X', 'satuan_bawaan_id': ''});
      expect(data(e.handle(method: 'GET', path: '/pengaturan/usaha', query: toko))['satuan_bawaan'], isNull);
      final tolak = e.handle(method: 'POST', path: '/produk', query: toko, body: {'nama': 'Garam', 'tipe': 'PRODUK', 'harga_jual': 5000});
      expect(tolak.status, 422);
      expect((tolak.body['errors'] as Map)['satuan_id'], isNotEmpty);

      final dipilih = e.handle(method: 'POST', path: '/produk', query: toko, body: {'nama': 'Garam', 'tipe': 'PRODUK', 'harga_jual': 5000, 'satuan_id': 'SAT-1'});
      expect(dipilih.status, 201);
    });

    test('operasi stok produk tanpa satuan → 422 dengan pesan', () {
      final e = DemoEngine();
      const toko = {'toko_id': 'TOKO-1'};
      final rows = (e.handle(method: 'GET', path: '/produk', query: toko).body['data'] as List).cast<Map>();
      final p = rows.firstWhere((r) => r['kelola_stok'] == true);
      p['satuan'] = null; // disimulasikan: produk lama tanpa satuan
      final r = e.handle(method: 'POST', path: '/inventory/stok-masuk', query: toko, body: {'id_produk': p['id'], 'jumlah': 5});
      expect(r.status, 422, reason: 'mesin demo mengembalikan objek produk yang sama');
      expect('${r.body['message']}', contains('satuan'));
    });

    test('422 "produk tanpa satuan" pada stok = penolakan biasa, TIDAK diantrekan', () async {
      final antrean = AntreanMemori();
      final tulis = AntreanTulis(antrean: antrean, tokoId: 'T1');
      await expectLater(
        tulis.jalankan(
          jenis: 'STOK_MASUK',
          path: '/inventory/stok-masuk',
          body: const {'id_produk': 'P1', 'jumlah': 5},
          kirim: (_) async => throw const ApiException(
            message: 'Produk belum punya satuan.',
            statusCode: 422,
            errors: {'satuan_id': ['Produk belum punya satuan.']},
          ),
        ),
        throwsA(isA<ApiException>()),
      );
      expect(await antrean.semua(), isEmpty);
    });
  });

  test('datasource: satuan_bawaan dibaca; satuan_bawaan_id hanya dikirim bila diubah', () async {
    final dikirim = <Map<String, dynamic>>[];
    final dio = Dio(BaseOptions(validateStatus: (_) => true))
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        if (o.method == 'PUT') dikirim.add(Map<String, dynamic>.from(o.data as Map));
        h.resolve(Response(requestOptions: o, statusCode: 200, data: {
          'success': true,
          'data': {
            'nama': 'Toko',
            'struk': const {},
            'satuan_bawaan': {'id': 'enc-acak', 'kode': 'PCS', 'nama': 'Pcs'},
          },
        }));
      }));
    final ds = PengaturanRemoteDataSource(dio);
    final p = await ds.profilUsaha();
    expect(p.satuanBawaan?.kode, 'PCS');
    await ds.simpan(nama: 'Toko', strukTampilLogo: true);
    expect(dikirim.last.containsKey('satuan_bawaan_id'), isFalse);
    await ds.simpan(nama: 'Toko', strukTampilLogo: true, ubahSatuanBawaan: true, satuanBawaanId: 'enc-kg');
    expect(dikirim.last['satuan_bawaan_id'], 'enc-kg');
    await ds.simpan(nama: 'Toko', strukTampilLogo: true, ubahSatuanBawaan: true, satuanBawaanId: '');
    expect(dikirim.last.containsKey('satuan_bawaan_id'), isTrue);
    expect(dikirim.last['satuan_bawaan_id'], isNull, reason: 'kosong = hapus satuan bawaan');
  });

  testWidgets('formulir produk: errors.satuan_id tampil di bawah kolom Satuan', (t) async {
    t.view.physicalSize = const Size(420, 1600);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    late final ProviderContainer c;
    await t.runAsync(() async {
      c = await _demo('TOKO-1');
      // Usaha belum punya satuan bawaan.
      await c.read(dioProvider).put<dynamic>('/pengaturan/usaha', data: {'nama': 'Demo', 'satuan_bawaan_id': null});
    });
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
    await _pompa(t, 30);
    await t.enterText(find.widgetWithText(TextFormField, 'Nama produk'), 'Garam');
    await t.enterText(find.widgetWithText(TextFormField, 'Harga jual (Rp)'), '5000');
    await t.ensureVisible(find.text('Tambah Produk').last);
    await t.tap(find.text('Tambah Produk').last);
    await _pompa(t, 30);

    final dekorasi = t.widgetList<InputDecorator>(find.byType(InputDecorator)).map((d) => d.decoration);
    final satuan = dekorasi.firstWhere((d) => d.labelText == 'Satuan');
    expect(satuan.errorText, contains('satuan bawaan usaha belum diatur'));
    await t.pump(const Duration(seconds: 5)); // habiskan pewaktu SnackBar
  });

  testWidgets('Profil Usaha: pemilih "Satuan bawaan" dari /satuan, cocok lewat kode, tersimpan', (t) async {
    t.view.physicalSize = const Size(420, 1600);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    late final ProviderContainer c;
    await t.runAsync(() async => c = await _demo('TOKO-1'));
    addTearDown(c.dispose);

    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(theme: AppTheme.light(), home: const ProfilUsahaScreen()),
    ));
    await _pompa(t, 30);

    expect(find.text('Satuan bawaan'), findsOneWidget);
    expect(find.text('Pcs'), findsOneWidget, reason: 'satuan bawaan server terpilih');

    await t.tap(find.text('Pcs'));
    await _pompa(t, 10);
    await t.tap(find.text('Kg').last);
    await _pompa(t, 10);
    await t.ensureVisible(find.byKey(const Key('profil-simpan')));
    await t.tap(find.byKey(const Key('profil-simpan')));
    await _pompa(t, 30);

    final res = await t.runAsync(() => c.read(dioProvider).get<dynamic>('/pengaturan/usaha'));
    expect(((res!.data as Map)['data'] as Map)['satuan_bawaan']['kode'], 'KG');
    await t.pump(const Duration(seconds: 5));
  });
}
