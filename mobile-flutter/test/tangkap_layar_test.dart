@Tags(['tangkap'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tuleh_pos/core/offline/antrean.dart';
import 'package:tuleh_pos/core/router/app_router.dart';
import 'package:tuleh_pos/core/storage/secure_storage.dart';
import 'package:tuleh_pos/core/theme/app_theme.dart';
import 'package:tuleh_pos/features/auth/presentation/controllers/auth_controller.dart';
import 'package:tuleh_pos/features/demo/data/masa_coba_service.dart';
import 'package:tuleh_pos/features/kasir/presentation/controllers/cart_controller.dart';
import 'package:tuleh_pos/features/cetak/domain/entities/struk.dart';
import 'package:tuleh_pos/features/kasir/presentation/widgets/cart_sheet.dart';
import 'package:tuleh_pos/features/kasir/presentation/widgets/hasil_transaksi_sheet.dart';
import 'package:tuleh_pos/features/products/presentation/providers/products_provider.dart';
import 'package:tuleh_pos/features/toko/presentation/providers/toko_providers.dart';

import 'helpers/masa_coba_palsu.dart';

/// Tangkapan layar untuk tinjauan UI (bukan uji regresi). Jalankan manual:
///
///   flutter test --tags tangkap --update-goldens test/tangkap_layar_test.dart \
///     --dart-define=TANGKAP_DIR=folder --dart-define=TANGKAP_FONT=berkas.ttf \
///     --dart-define=TANGKAP_IKON=MaterialIcons-Regular.otf
///
/// Tanpa TANGKAP_DIR, test dilewati. Font Plus Jakarta Sans dimuat dari
/// berkas agar teks terbaca (di test, google_fonts tidak mengunduh).

const _dir = String.fromEnvironment('TANGKAP_DIR');
const _font = String.fromEnvironment('TANGKAP_FONT');

class _Storage extends SecureStorage {
  _Storage() : super(const FlutterSecureStorage());
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

const _ikon = String.fromEnvironment('TANGKAP_IKON');

Future<void> _muatFont() async {
  if (_font.isNotEmpty) {
    final bytes = await File(_font).readAsBytes();
    // Nama keluarga yang dipakai google_fonts untuk tiap varian bobot.
    for (final v in ['regular', '500', '600', '700', '800', 'italic', '300', '500italic', '700italic']) {
      final loader = FontLoader('PlusJakartaSans_$v')
        ..addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
    }
  }
  if (_ikon.isNotEmpty) {
    final bytes = await File(_ikon).readAsBytes();
    final loader = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
  }
}

void main() {
  if (_dir.isEmpty) {
    test('tangkap layar dilewati (TANGKAP_DIR kosong)', () {});
    return;
  }

  GoogleFonts.config.allowRuntimeFetching = false;
  setUpAll(_muatFont);

  Future<void> pompa(WidgetTester t, [int kali = 25]) async {
    for (var i = 0; i < kali; i++) {
      await t.pump(const Duration(milliseconds: 40));
    }
  }

  Future<void> simpan(WidgetTester t, String nama) async {
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile(Uri.file('$_dir/a-$nama.png')),
    );
  }

  testWidgets('tangkap layar demo', (t) async {
    t.view.physicalSize = const Size(1080, 2280);
    t.view.devicePixelRatio = 2.5;
    addTearDown(t.view.reset);

    final c = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(_Storage()),
        masaCobaServiceProvider.overrideWithValue(MasaCobaPalsu()),
        ...overrideOffline(antrean: AntreanMemori()),
      ],
    );
    addTearDown(c.dispose);

    await t.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: Consumer(
          builder: (_, ref, _) => MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: ref.watch(routerProvider),
            debugShowCheckedModeBanner: false,
          ),
        ),
      ),
    );
    await pompa(t);
    await simpan(t, 'login');

    await t.runAsync(() async {
      await c.read(authControllerProvider.notifier).startDemo();
      await c.read(activeTokoIdProvider.notifier).select('TOKO-1');
    });
    await pompa(t, 40);
    final router = c.read(routerProvider);
    router.go('/home');
    await pompa(t, 40);
    await simpan(t, 'home');

    for (final (rute, nama) in [
      ('/kasir', 'kasir'),
      ('/aktivitas', 'aktivitas'),
      ('/laporan', 'laporan'),
      ('/riwayat', 'riwayat'),
      ('/sesi', 'sesi'),
      ('/produk', 'produk'),
      ('/meja', 'meja'),
      ('/pengeluaran', 'pengeluaran'),
      ('/stok', 'stok'),
      ('/pengaturan', 'pengaturan'),
    ]) {
      router.go(rute);
      await pompa(t, 40);
      await simpan(t, nama);
    }

    // Keranjang terisi + lembar bayar.
    router.go('/kasir');
    await pompa(t, 30);
    final produk = await c.read(productsProvider.future);
    final cart = c.read(cartControllerProvider.notifier);
    for (final p in produk.take(3)) {
      cart.add(p);
    }
    await pompa(t, 10);
    await simpan(t, 'kasir-terisi');
    final ctx = t.element(find.byType(Scaffold).first);
    showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const CartSheet(),
    );
    await pompa(t, 40);
    await simpan(t, 'keranjang');
    Navigator.of(ctx).pop();
    await pompa(t, 20);

    // Lembar hasil transaksi (struk demo bertanda).
    showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => HasilTransaksiSheet(
        struk: Struk(
          namaToko: 'Minimarket Demo',
          nomor: 'TRX/0051',
          waktu: DateTime(2026, 9, 6, 14, 5),
          baris: [for (final p in produk.take(3)) StrukBaris(nama: p.nama, kuantitas: 1, harga: p.harga)],
          total: produk.take(3).fold(0, (s, p) => s + p.harga),
          metode: 'TUNAI',
          dibayar: 50000,
          kembalian: 50000 - produk.take(3).fold(0, (s, p) => s + p.harga),
          barcode: 'TRX/0051',
          demo: true,
        ),
        kembalian: 50000 - produk.take(3).fold(0, (s, p) => s + p.harga),
      ),
    );
    await pompa(t, 40);
    await simpan(t, 'hasil');
  });
}
