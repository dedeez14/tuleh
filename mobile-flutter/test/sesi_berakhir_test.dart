// 401 = sesi berakhir (kontrak kesiapan produksi 2026-09-15). Dulu interceptor
// hanya menyalakan `sessionExpiredProvider` yang tak pernah dibaca: kasir
// tetap di layar dengan token mati, semua kiriman ditolak diam-diam.
// Sekarang: token dihapus dari Keystore, kembali ke layar masuk dengan pesan,
// antrean offline utuh — dikirim lagi hanya bila AKUN YANG SAMA masuk.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/network/api_client.dart';
import 'package:tuleh_pos/core/offline/antrean.dart';
import 'package:tuleh_pos/core/offline/koneksi.dart';
import 'package:tuleh_pos/core/offline/pengurai.dart';
import 'package:tuleh_pos/core/offline/salinan_store.dart';
import 'package:tuleh_pos/core/offline/sinkronisasi_screen.dart';
import 'package:tuleh_pos/core/router/app_router.dart';
import 'package:tuleh_pos/core/storage/secure_storage.dart';
import 'package:tuleh_pos/core/theme/app_theme.dart';
import 'package:tuleh_pos/features/auth/presentation/controllers/auth_controller.dart';
import 'package:tuleh_pos/features/auth/presentation/screens/login_screen.dart';
import 'package:tuleh_pos/features/auth/presentation/widgets/sesi_berakhir_gate.dart';
import 'package:tuleh_pos/features/demo/data/masa_coba_service.dart';

import 'helpers/masa_coba_palsu.dart';

class _Storage extends SecureStorage {
  _Storage() : super(const FlutterSecureStorage());
  final Map<String, String> m = {};
  void _set(String k, String? v) => v == null || v.isEmpty ? m.remove(k) : m[k] = v;
  @override
  Future<String?> readToken() async => m['token'];
  @override
  Future<void> writeToken(String? v) async => _set('token', v);
  @override
  Future<String?> readActiveTokoId() async => m['toko'];
  @override
  Future<void> writeActiveTokoId(String? v) async => _set('toko', v);
  @override
  Future<String?> readAkunTerakhir() async => m['akun'];
  @override
  Future<void> writeAkunTerakhir(String? v) async => _set('akun', v);
  @override
  Future<String?> bacaNilai(String k) async => m[k];
  @override
  Future<void> tulisNilai(String k, String? v) async => _set(k, v);
  @override
  Future<void> clearSession() async {
    m.remove('token');
    m.remove('toko');
  }
}

/// Server: dua akun (A, B). `cabut` = token A dicabut (401 untuk A).
class _Server implements HttpClientAdapter {
  bool cabut = false;
  final List<String> diminta = [];
  final List<Map<String, dynamic>> kiriman = [];

  ResponseBody _json(Object body, int code) => ResponseBody.fromString(
    jsonEncode(body),
    code,
    headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
  );

  Map<String, dynamic> _user(String id) => {
    'pos_role': 'KASIR',
    'user': {'id': id, 'name': 'Kasir $id'},
    'company': {'nama': 'Toko $id'},
  };

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? s, Future<void>? c) async {
    diminta.add('${o.method} ${o.path}');
    final auth = '${o.headers['Authorization'] ?? ''}';
    final akun = auth.endsWith('tok-A') ? 'A' : auth.endsWith('tok-B') ? 'B' : null;
    if (o.path == '/auth/login') {
      final login = '${(o.data as Map)['login']}';
      return _json({'success': true, 'data': {'token': 'tok-$login', ..._user(login)}}, 200);
    }
    if (akun == null || (akun == 'A' && cabut)) {
      return _json({'success': false, 'message': 'Unauthenticated.', 'data': null, 'errors': null}, 401);
    }
    if (o.path == '/auth/me') return _json({'success': true, 'data': _user(akun)}, 200);
    if (o.method == 'POST') {
      kiriman.add({'akun': akun, ...Map<String, dynamic>.from(o.data as Map)});
      return _json({'success': true, 'data': {'id': 'S${kiriman.length}'}}, 201);
    }
    return _json({'success': true, 'data': <dynamic>[]}, 200);
  }

  @override
  void close({bool force = false}) {}
}

PesanAntrean _baris(String ref, String? pemilik) => PesanAntrean(
  urut: 0, clientRef: ref, jenis: 'PENGELUARAN', path: '/pengeluaran',
  body: {'keterangan': 'Galon $ref', 'nominal': 25000, 'client_ref': ref},
  dibuat: DateTime(2026, 9, 15, 9), pemilik: pemilik,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Storage storage;
  late _Server server;
  late AntreanMemori antrean;

  setUp(() {
    storage = _Storage()..m['token'] = 'tok-A';
    server = _Server();
    antrean = AntreanMemori();
  });

  ProviderContainer wadah() {
    final c = ProviderContainer(overrides: [
      secureStorageProvider.overrideWithValue(storage),
      salinanStoreProvider.overrideWithValue(SalinanMemori()),
      antreanStoreProvider.overrideWithValue(antrean),
      masaCobaServiceProvider.overrideWithValue(MasaCobaPalsu()),
      koneksiProvider.overrideWith(() => KoneksiNotifier(jaringan: const Stream.empty())),
    ]);
    addTearDown(c.dispose);
    c.read(dioProvider).httpClientAdapter = server;
    return c;
  }

  testWidgets('401 di tengah pemakaian → token dihapus, layar masuk + pesan, antrean utuh', (t) async {
    t.view.physicalSize = const Size(420, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    final c = wadah();
    await t.runAsync(() async {
      // TINJAU: pengurai tidak mengirimnya selama layar diuji (tanpa timer).
      await antrean.antrekan(_baris('p1', 'A'));
      await antrean.perbarui('p1', status: StatusAntrean.tinjau, galatTerakhir: 'uji');
      expect((await c.read(authControllerProvider.future))?.id, 'A');
    });
    expect(c.read(akunAktifProvider), 'A');

    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp.router(
        theme: AppTheme.light(),
        routerConfig: c.read(routerProvider),
        builder: (context, child) => SesiBerakhirGate(child: child ?? const SizedBox.shrink()),
      ),
    ));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(LoginScreen), findsNothing);

    // Token dicabut di server; permintaan berikutnya dibalas 401.
    server.cabut = true;
    await t.runAsync(() => c.read(dioProvider).get<dynamic>('/produk'));
    for (var i = 0; i < 20; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await t.pump(const Duration(milliseconds: 50));
    }

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.textContaining('Sesi Anda telah berakhir'), findsOneWidget);
    expect(find.textContaining('1 data belum terkirim tetap tersimpan'), findsOneWidget);
    expect(storage.m['token'], isNull, reason: 'token mati harus dihapus dari Keystore');
    expect(c.read(akunAktifProvider), isNull);
    expect(c.read(sessionExpiredProvider), isFalse, reason: 'bendera dipadamkan setelah ditangani');
    final sisa = await t.runAsync(() => antrean.semua());
    expect(sisa!.single.clientRef, 'p1', reason: 'penjualan offline tidak boleh hilang');
    expect(storage.m['akun'], 'A', reason: 'akun terakhir diingat untuk memutuskan pemilik antrean');

    // Pesan hilang setelah berhasil masuk lagi.
    server.cabut = false;
    await t.runAsync(() => c.read(authControllerProvider.notifier).login(login: 'A', password: 'x', deviceName: 'uji'));
    expect(c.read(pesanMasukProvider), isNull);
  });

  test('401 dari /auth/login (sandi salah) BUKAN sesi berakhir', () async {
    final c = wadah(); // token tersimpan → header Authorization ikut terkirim
    await c.read(authControllerProvider.future);
    final dio = c.read(dioProvider);
    dio.httpClientAdapter = _SandiSalah();
    await dio.post<dynamic>('/auth/login', data: {'login': 'x', 'password': 'y'});
    expect(c.read(sessionExpiredProvider), isFalse);
  });

  test('masuk lagi dengan AKUN YANG SAMA → antrean dilanjutkan', () async {
    storage.m['akun'] = 'A';
    storage.m.remove('token'); // sesi A sudah berakhir
    await antrean.antrekan(_baris('p1', 'A'));
    final c = wadah();
    await c.read(authControllerProvider.future);
    await c.read(authControllerProvider.notifier).login(login: 'A', password: 'x', deviceName: 'uji');
    expect(await c.read(penguraiProvider).jalankan(), 1);
    expect(server.kiriman.single['akun'], 'A');
    expect((await antrean.cari('p1'))!.status, StatusAntrean.terkirim);
  });

  test('AKUN LAIN masuk → antrean akun sebelumnya TIDAK dikirim, tetap tersimpan', () async {
    storage.m['akun'] = 'A';
    storage.m.remove('token');
    await antrean.antrekan(_baris('milik-A', 'A'));
    await antrean.antrekan(_baris('lama-tanpa-pemilik', null));
    final c = wadah();
    await c.read(authControllerProvider.future);
    await c.read(authControllerProvider.notifier).login(login: 'B', password: 'x', deviceName: 'uji');
    expect(c.read(akunAktifProvider), 'B');

    expect(await c.read(penguraiProvider).jalankan(), 0);
    expect(server.kiriman, isEmpty, reason: 'penjualan A tidak boleh tercatat atas nama B');
    expect((await antrean.cari('milik-A'))!.status, StatusAntrean.menunggu);
    expect((await antrean.cari('lama-tanpa-pemilik'))!.pemilik, isNull,
        reason: 'baris versi lama tidak diklaim akun yang berbeda dari akun terakhir');

    final r = await c.read(ringkasAntreanProvider.future);
    expect(r.menunggu, 0);
    expect(r.milikLain, 2);
  });

  test('pembaruan aplikasi: baris lama tanpa pemilik diklaim akun yang sama saat masuk otomatis', () async {
    // Belum ada akun terakhir tercatat (versi lama) & token masih hidup.
    await antrean.antrekan(_baris('lama', null));
    final c = wadah();
    expect((await c.read(authControllerProvider.future))?.id, 'A');
    expect((await antrean.cari('lama'))!.pemilik, 'A');
    expect(storage.m['akun'], 'A');
    expect(await c.read(penguraiProvider).jalankan(), 1);
  });

  testWidgets('layar Sinkronisasi menampilkan antrean akun lain terpisah, tanpa aksi', (t) async {
    t.view.physicalSize = const Size(420, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await antrean.antrekan(_baris('milik-A', 'A'));
    await antrean.antrekan(_baris('milik-B', 'B'));
    final c = ProviderContainer(overrides: [
      antreanStoreProvider.overrideWithValue(antrean),
      koneksiProvider.overrideWith(() => KoneksiNotifier(jaringan: const Stream.empty())),
      akunAktifProvider.overrideWith((_) => 'B'),
    ]);
    addTearDown(c.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(theme: AppTheme.light(), home: const SinkronisasiScreen()),
    ));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(find.byKey(const Key('antrean-milik-lain')), findsOneWidget);
    expect(find.text('Milik akun lain (1)'), findsOneWidget);
    expect(find.textContaining('1 menunggu dikirim'), findsOneWidget);
  });
}

class _SandiSalah implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? s, Future<void>? c) async =>
      ResponseBody.fromString(
        jsonEncode({'success': false, 'message': 'Email atau kata sandi salah.'}),
        401,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
      );

  @override
  void close({bool force = false}) {}
}
