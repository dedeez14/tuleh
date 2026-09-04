import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/router/app_router.dart';
import 'package:tuleh_pos/core/storage/secure_storage.dart';
import 'package:tuleh_pos/core/theme/app_theme.dart';
import 'package:tuleh_pos/features/auth/presentation/controllers/auth_controller.dart';
import 'package:tuleh_pos/features/home/presentation/screens/home_screen.dart';
import 'package:tuleh_pos/features/kasir/presentation/screens/kasir_screen.dart';
import 'package:tuleh_pos/features/laporan/presentation/screens/laporan_screen.dart';
import 'package:tuleh_pos/features/pesanan/presentation/screens/papan_pesanan_screen.dart';
import 'package:tuleh_pos/features/riwayat/presentation/screens/riwayat_screen.dart';
import 'package:tuleh_pos/features/toko/presentation/providers/toko_providers.dart';
import 'helpers/masa_coba_palsu.dart';
import 'package:tuleh_pos/features/demo/data/masa_coba_service.dart';

/// Kerangka navigasi Material 3 — dijalankan lewat router sungguhan dengan
/// Mode Demo, sehingga yang diuji adalah alur yang benar-benar dipakai:
/// bilah bawah, cabang ketiga yang menyesuaikan bidang usaha, lembar Lainnya.

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer c;

  /// Masuk Mode Demo, pilih toko, lalu pompa aplikasi sampai beranda tampil.
  Future<void> jalankan(WidgetTester t, {String toko = 'TOKO-6'}) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    c = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(_FakeStorage()),
        masaCobaServiceProvider.overrideWithValue(MasaCobaPalsu()),
      ],
    );
    addTearDown(c.dispose);

    // Dio menjadwalkan Future lewat event loop; di FakeAsync milik testWidgets
    // itu tidak pernah maju kecuali dipompa → jalankan dengan waktu sungguhan.
    await t.runAsync(() async {
      await c.read(authControllerProvider.notifier).startDemo();
      await c.read(activeTokoIdProvider.notifier).select(toko);
    });

    await t.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: c.read(routerProvider),
        ),
      ),
    );
    for (var i = 0; i < 30; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('bilah bawah: empat tujuan utama + Lainnya', (t) async {
    await jalankan(t);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    for (final label in ['Beranda', 'Kasir', 'Laporan', 'Lainnya']) {
      expect(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        ),
        findsOneWidget,
        reason: 'tujuan $label ada',
      );
    }
  });

  testWidgets('toko bertahap (salon): tab ketiga = papan pesanan dari manifest',
      (t) async {
    await jalankan(t, toko: 'TOKO-6');
    // Label bilah dipendekkan per jenis papan (manifest: "Antrian Cukur").
    expect(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Antrian'),
      ),
      findsOneWidget,
    );
    await t.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Antrian')));
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(PapanPesananScreen), findsOneWidget);
  });

  testWidgets('toko retail (minimarket): tab ketiga = riwayat', (t) async {
    await jalankan(t, toko: 'TOKO-1');
    expect(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Riwayat'),
      ),
      findsOneWidget,
    );
    await t.tap(find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Riwayat'),
    ));
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(RiwayatScreen), findsOneWidget);
  });

  testWidgets('berpindah tab Kasir & Laporan tanpa lewat beranda', (t) async {
    await jalankan(t);
    await t.tap(find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Kasir'),
    ));
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(KasirScreen), findsOneWidget);

    await t.tap(find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Laporan'),
    ));
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(LaporanScreen), findsOneWidget);
    // Bilah bawah tetap ada di tiap tab.
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('Lainnya membuka lembar menu sekunder, bukan mengganti tab',
      (t) async {
    await jalankan(t);
    await t.tap(find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Lainnya'),
    ));
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Menu lainnya'), findsOneWidget);
    for (final m in ['Produk', 'Stok', 'Pelanggan', 'Pengeluaran', 'Sesi Kasir', 'Pengaturan']) {
      expect(find.text(m), findsWidgets, reason: 'menu $m ada');
    }
    // Riwayat masuk Lainnya karena tab ketiga sudah dipakai papan pesanan.
    expect(find.text('Riwayat'), findsWidgets);
    // Beranda masih di belakang lembar (tab tidak berganti).
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('beranda: dasbor menampilkan sesi & aksi cepat, bukan grid menu',
      (t) async {
    await jalankan(t);
    expect(find.text('Aksi cepat'), findsOneWidget);
    expect(find.text('Transaksi terbaru'), findsOneWidget);
    // Demo membuka sesi hari ini → kartu sesi berstatus Buka.
    expect(find.textContaining('Sesi SK-'), findsOneWidget);
    // Grid menu lama sudah tidak ada.
    expect(find.text('Menu'), findsNothing);
  });

  testWidgets(
    'pilih toko: lembar di atas bilah bawah, bisa digulir, toko terakhir bisa dipilih',
    (t) async {
      // Ponsel pendek agar 6 toko demo tidak muat tanpa gulir — kasus nyata:
      // pilihan tertutup bilah bawah dan toko di bawah tak bisa dipilih.
      await jalankan(t, toko: 'TOKO-1');
      t.view.physicalSize = const Size(320, 520);
      await t.pump();

      await t.tap(find.textContaining('Minimarket Demo').first);
      for (var i = 0; i < 12; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('Pilih toko'), findsOneWidget);

      // Lembar berada di navigator akar: bilah navigasi tertutup penghalang,
      // bukan sebaliknya (lembar di bawah bilah).
      final sheet = find.byType(BottomSheet);
      expect(sheet, findsOneWidget);
      final bilah = find.byType(NavigationBar);
      expect(
        t.getBottomLeft(sheet).dy,
        greaterThan(t.getTopLeft(bilah).dy),
        reason: 'lembar harus menutupi area bilah bawah',
      );

      // Toko terakhir ada di luar layar → gulir lalu ketuk.
      final terakhir = find.byKey(const ValueKey('toko-TOKO-6'));
      await t.scrollUntilVisible(terakhir, 120, scrollable: find.byType(Scrollable).last);
      await t.pump();
      await t.tap(terakhir);
      for (var i = 0; i < 12; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(c.read(activeTokoIdProvider).valueOrNull, 'TOKO-6');
      expect(find.text('Pilih toko'), findsNothing);
    },
  );
}
