import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/layout/lebar.dart';
import 'package:tuleh_pos/core/offline/antrean.dart';
import 'package:tuleh_pos/core/storage/secure_storage.dart';
import 'package:tuleh_pos/core/theme/app_theme.dart';
import 'package:tuleh_pos/features/auth/presentation/controllers/auth_controller.dart';
import 'package:tuleh_pos/features/demo/data/masa_coba_service.dart';
import 'package:tuleh_pos/features/kasir/presentation/controllers/cart_controller.dart';
import 'package:tuleh_pos/features/kasir/presentation/screens/kasir_screen.dart';
import 'package:tuleh_pos/features/products/presentation/providers/products_provider.dart';
import 'package:tuleh_pos/features/riwayat/presentation/screens/riwayat_screen.dart';
import 'package:tuleh_pos/features/toko/presentation/providers/toko_providers.dart';

import 'helpers/masa_coba_palsu.dart';

/// Tata letak tablet (≥ 720 dp) ala desktop: kasir dua panel dengan keranjang
/// menetap, riwayat master-detail, lembar tampil sebagai dialog; di ponsel
/// tetap bilah keranjang & layar detail terpisah.

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

Future<ProviderContainer> _demo() async {
  final c = ProviderContainer(
    overrides: [
      secureStorageProvider.overrideWithValue(_Storage()),
      masaCobaServiceProvider.overrideWithValue(MasaCobaPalsu()),
      ...overrideOffline(antrean: AntreanMemori()),
    ],
  );
  await c.read(authControllerProvider.notifier).startDemo();
  await c.read(activeTokoIdProvider.notifier).select('TOKO-1');
  return c;
}

Future<void> _pompa(WidgetTester t, [int kali = 20]) async {
  for (var i = 0; i < kali; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

Widget _app(ProviderContainer c, Widget home) => UncontrolledProviderScope(
  container: c,
  child: MaterialApp(theme: AppTheme.light(), home: home),
);

void main() {
  test('layarLebar: ambang 720 dp', () {
    expect(lebarTablet, 720);
  });

  testWidgets('tablet: kasir dua panel, keranjang menetap tanpa bilah bawah', (t) async {
    t.view.physicalSize = const Size(2560, 1600);
    t.view.devicePixelRatio = 2.0;
    addTearDown(t.view.reset);
    late final ProviderContainer c;
    await t.runAsync(() async => c = await _demo());
    addTearDown(c.dispose);

    await t.pumpWidget(_app(c, const KasirScreen()));
    await _pompa(t);
    expect(find.byType(GridView), findsOneWidget, reason: 'katalog grid');
    expect(find.text('Keranjang masih kosong'), findsOneWidget, reason: 'panel keranjang menetap');
    expect(find.byType(BilahKeranjang), findsNothing);

    final produk = await c.read(productsProvider.future);
    c.read(cartControllerProvider.notifier).add(produk.first);
    await _pompa(t);
    expect(find.text('Lanjut ke pembayaran'), findsOneWidget);
    await t.tap(find.text('Lanjut ke pembayaran'));
    await _pompa(t);
    expect(find.text('Pembayaran'), findsOneWidget, reason: 'langkah bayar di panel yang sama');
    expect(find.text('Uang pas'), findsOneWidget, reason: 'label saran nominal terlihat');
  });

  testWidgets('ponsel: kasir daftar + bilah keranjang, tanpa panel', (t) async {
    t.view.physicalSize = const Size(1080, 2280);
    t.view.devicePixelRatio = 2.5;
    addTearDown(t.view.reset);
    late final ProviderContainer c;
    await t.runAsync(() async => c = await _demo());
    addTearDown(c.dispose);

    await t.pumpWidget(_app(c, const KasirScreen()));
    await _pompa(t);
    expect(find.byType(GridView), findsNothing);
    expect(find.byType(BilahKeranjang), findsOneWidget);
    expect(find.text('Keranjang masih kosong'), findsNothing);
  });

  testWidgets('tablet: riwayat master-detail; ketuk baris membuka detail di kanan', (t) async {
    t.view.physicalSize = const Size(2560, 1600);
    t.view.devicePixelRatio = 2.0;
    addTearDown(t.view.reset);
    late final ProviderContainer c;
    await t.runAsync(() async => c = await _demo());
    addTearDown(c.dispose);

    await t.pumpWidget(_app(c, const RiwayatScreen()));
    await _pompa(t);
    expect(find.text('Pilih transaksi'), findsOneWidget);
    await t.tap(find.textContaining('TRX/').first);
    await _pompa(t);
    expect(find.text('Pilih transaksi'), findsNothing);
    expect(find.text('Cetak ulang'), findsOneWidget, reason: 'detail tampil di panel kanan');
    expect(find.text('Detail Transaksi'), findsNothing, reason: 'tanpa layar terpisah');
  });
}
