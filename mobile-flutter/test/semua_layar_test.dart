import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/router/app_router.dart';
import 'package:tuleh_pos/core/storage/secure_storage.dart';
import 'package:tuleh_pos/core/theme/app_theme.dart';
import 'package:tuleh_pos/features/auth/presentation/controllers/auth_controller.dart';
import 'package:tuleh_pos/features/toko/presentation/providers/toko_providers.dart';
import 'helpers/masa_coba_palsu.dart';
import 'package:tuleh_pos/features/demo/data/masa_coba_service.dart';

/// Jaring pengaman tata letak: SETIAP layar dirender lewat router sungguhan
/// dengan data Mode Demo, pada ponsel sempit dan tablet, tema terang & gelap.
/// Kesalahan tata letak (luber, lebar tak hingga, Ink di luar Material) tidak
/// menggagalkan build — hanya terlihat sebagai layar rusak di perangkat — jadi
/// di sini setiap pengecualian rendering dianggap kegagalan test.

class _FakeStorage extends SecureStorage {
  _FakeStorage() : super(const FlutterSecureStorage());
  final Map<String, String> _m = {};
  @override
  Future<String?> readToken() async => _m['token'];
  @override
  Future<void> writeToken(String? v) async =>
      v == null || v.isEmpty ? _m.remove('token') : _m['token'] = v;
  @override
  Future<String?> readActiveTokoId() async => _m['toko'];
  @override
  Future<void> writeActiveTokoId(String? v) async =>
      v == null || v.isEmpty ? _m.remove('toko') : _m['toko'] = v;
  @override
  Future<String?> bacaNilai(String k) async => _m[k];
  @override
  Future<void> tulisNilai(String k, String? v) async =>
      v == null ? _m.remove(k) : _m[k] = v;
  @override
  Future<void> clearSession() async {
    _m.remove('token');
    _m.remove('toko');
  }
}

/// Rute yang diuji per toko. Tab utama lewat `go`, layar sekunder lewat `push`.
const _rute = [
  '/home',
  '/kasir',
  '/aktivitas',
  '/laporan',
  '/riwayat',
  '/produk',
  '/pelanggan',
  '/pengeluaran',
  '/sesi',
  '/stok',
  '/pengaturan',
  '/meja',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pompa(WidgetTester t, [int n = 24]) async {
    for (var i = 0; i < n; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> ujiSemuaRute(
    WidgetTester t, {
    required String toko,
    required Size ukuran,
    required Brightness tema,
  }) async {
    t.view.physicalSize = ukuran;
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    final c = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(_FakeStorage()),
        masaCobaServiceProvider.overrideWithValue(MasaCobaPalsu()),
      ],
    );
    addTearDown(c.dispose);
    await t.runAsync(() async {
      await c.read(authControllerProvider.notifier).startDemo();
      await c.read(activeTokoIdProvider.notifier).select(toko);
    });

    final router = c.read(routerProvider);
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp.router(
          theme: tema == Brightness.dark ? AppTheme.dark() : AppTheme.light(),
          routerConfig: router,
        ),
      ),
    );
    await pompa(t);

    for (final r in _rute) {
      router.go(r);
      await pompa(t);
      final e = t.takeException();
      expect(
        e,
        isNull,
        reason:
            '$r ($toko, ${ukuran.width.toInt()}px, ${tema.name}) melempar: $e',
      );
    }
  }

  for (final toko in ['TOKO-1', 'TOKO-2', 'TOKO-4', 'TOKO-6']) {
    testWidgets('semua layar aman: $toko, ponsel sempit, terang', (t) async {
      await ujiSemuaRute(
        t,
        toko: toko,
        ukuran: const Size(320, 640),
        tema: Brightness.light,
      );
    });
  }

  testWidgets('semua layar aman: salon, ponsel umum, gelap', (t) async {
    await ujiSemuaRute(
      t,
      toko: 'TOKO-6',
      ukuran: const Size(390, 844),
      tema: Brightness.dark,
    );
  });

  testWidgets('semua layar aman: bakso, tablet (rail), terang', (t) async {
    await ujiSemuaRute(
      t,
      toko: 'TOKO-2',
      ukuran: const Size(1024, 768),
      tema: Brightness.light,
    );
  });
}
