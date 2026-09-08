// Dialog stok masuk / opname di detail produk (2.20.1): controller dimiliki
// dialog sendiri, koma desimal diterima, dan opname membawa keterangan.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/offline/antrean.dart';
import 'package:tuleh_pos/core/storage/secure_storage.dart';
import 'package:tuleh_pos/core/theme/app_theme.dart';
import 'package:tuleh_pos/features/auth/presentation/controllers/auth_controller.dart';
import 'package:tuleh_pos/features/demo/data/masa_coba_service.dart';
import 'package:tuleh_pos/features/inventory/data/datasources/inventory_remote_datasource.dart';
import 'package:tuleh_pos/features/inventory/presentation/providers/inventory_providers.dart';
import 'package:tuleh_pos/features/products/domain/entities/product.dart';
import 'package:tuleh_pos/features/products/presentation/screens/produk_screen.dart';
import 'package:tuleh_pos/features/toko/presentation/providers/toko_providers.dart';

import 'helpers/masa_coba_palsu.dart';

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

/// Mencatat badan yang dikirim ke endpoint stok, tanpa jaringan.
class _Inventory implements InventoryRemoteDataSource {
  final masuk = <Map<String, dynamic>>[];
  final opname = <Map<String, dynamic>>[];

  @override
  Future<void> stokMasukBody(Map<String, dynamic> badan) async => masuk.add(badan);

  @override
  Future<void> opnameBody(Map<String, dynamic> badan) async => opname.add(badan);

  @override
  Future<void> stokMasuk({required String idProduk, required double jumlah}) =>
      stokMasukBody({'id_produk': idProduk, 'jumlah': jumlah});

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const _produk = Product(
  id: 'P1',
  nama: 'Kopi Susu',
  harga: 18000,
  tipe: 'PRODUK',
  satuan: 'cup',
  stok: 10,
);

Future<void> _pompa(WidgetTester t, [int kali = 20]) async {
  for (var i = 0; i < kali; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  Future<(ProviderContainer, _Inventory)> wadah(WidgetTester t) async {
    final inv = _Inventory();
    late final ProviderContainer c;
    await t.runAsync(() async {
      c = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(_Storage()),
          masaCobaServiceProvider.overrideWithValue(MasaCobaPalsu()),
          inventoryDataSourceProvider.overrideWithValue(inv),
          ...overrideOffline(antrean: AntreanMemori()),
        ],
      );
      await c.read(authControllerProvider.notifier).startDemo();
      await c.read(activeTokoIdProvider.notifier).select('TOKO-1');
    });
    addTearDown(c.dispose);
    return (c, inv);
  }

  /// Lembar detail produk (yang memuat tombol Tambah Stok & Opname).
  Widget app(ProviderContainer c) => UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: DetailProdukSheet(product: _produk)),
    ),
  );

  testWidgets('tambah stok: koma desimal diterima, dikirim sebagai stok masuk', (t) async {
    final (c, inv) = await wadah(t);
    await t.pumpWidget(app(c));
    await _pompa(t);

    await t.tap(find.text('Tambah Stok'));
    await _pompa(t);
    expect(find.textContaining('Tambah Stok — Kopi Susu'), findsOneWidget);
    await t.enterText(find.byType(TextField).first, '2,5');
    await t.tap(find.widgetWithText(FilledButton, 'Simpan'));
    await _pompa(t, 30);

    expect(inv.masuk.single['id_produk'], 'P1');
    expect(inv.masuk.single['jumlah'], 2.5);
    expect(inv.opname, isEmpty);
    // Tidak ada galat controller-setelah-dispose saat dialog menutup.
    expect(t.takeException(), isNull);
  });

  testWidgets('opname: jumlah + keterangan dikirim ke /inventory/opname', (t) async {
    final (c, inv) = await wadah(t);
    await t.pumpWidget(app(c));
    await _pompa(t);

    await t.tap(find.textContaining('Opname'));
    await _pompa(t);
    expect(find.textContaining('Stok saat ini 10'), findsOneWidget);
    await t.enterText(find.byType(TextField).first, '3');
    await t.enterText(find.byType(TextField).last, 'kemasan rusak');
    await t.tap(find.widgetWithText(FilledButton, 'Simpan'));
    await _pompa(t, 30);

    expect(inv.opname.single['id_produk'], 'P1');
    expect(inv.opname.single['jumlah'], 3);
    expect(inv.opname.single['keterangan'], 'kemasan rusak');
    expect(inv.masuk, isEmpty);
    expect(t.takeException(), isNull);
  });

  testWidgets('opname melebihi stok ditolak sebelum dikirim', (t) async {
    final (c, inv) = await wadah(t);
    await t.pumpWidget(app(c));
    await _pompa(t);

    await t.tap(find.textContaining('Opname'));
    await _pompa(t);
    await t.enterText(find.byType(TextField).first, '99');
    await t.tap(find.widgetWithText(FilledButton, 'Simpan'));
    await _pompa(t, 30);

    expect(inv.opname, isEmpty);
    expect(find.textContaining('Stok tidak mencukupi'), findsOneWidget);
  });

  testWidgets('batal atau jumlah kosong tidak mengirim apa pun', (t) async {
    final (c, inv) = await wadah(t);
    await t.pumpWidget(app(c));
    await _pompa(t);

    await t.tap(find.text('Tambah Stok'));
    await _pompa(t);
    await t.tap(find.widgetWithText(TextButton, 'Batal'));
    await _pompa(t, 20);
    expect(inv.masuk, isEmpty);

    await t.tap(find.text('Tambah Stok'));
    await _pompa(t);
    await t.tap(find.widgetWithText(FilledButton, 'Simpan')); // tanpa mengisi
    await _pompa(t, 20);
    expect(inv.masuk, isEmpty);
    expect(t.takeException(), isNull);
  });
}
