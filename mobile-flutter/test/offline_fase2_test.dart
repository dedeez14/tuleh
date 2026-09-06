import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/offline/antrean.dart';
import 'package:tuleh_pos/core/offline/pengurai.dart';
import 'package:tuleh_pos/core/offline/sinkronisasi_screen.dart';
import 'package:tuleh_pos/core/storage/secure_storage.dart';
import 'package:tuleh_pos/core/theme/app_theme.dart';
import 'package:tuleh_pos/features/auth/presentation/controllers/auth_controller.dart';
import 'package:tuleh_pos/features/demo/data/masa_coba_service.dart';
import 'package:tuleh_pos/features/products/presentation/providers/products_provider.dart';
import 'package:tuleh_pos/features/riwayat/presentation/providers/riwayat_providers.dart';
import 'package:tuleh_pos/features/toko/presentation/providers/toko_providers.dart';

import 'helpers/masa_coba_palsu.dart';

/// Fase 2 di layar: stok katalog memperhitungkan penjualan offline yang belum
/// terkirim, riwayat menampilkan transaksi lokal di atas dengan tanda, dan
/// layar Sinkronisasi menampilkan antrean beserta pilihan tinjau.

class _FakeStorage extends SecureStorage {
  _FakeStorage() : super(const FlutterSecureStorage());
  final Map<String, String> _m = {};
  @override
  Future<String?> readToken() async => _m['token'];
  @override
  Future<void> writeToken(String? v) async =>
      v == null ? _m.remove('token') : _m['token'] = v;
  @override
  Future<String?> readActiveTokoId() async => _m['toko'];
  @override
  Future<void> writeActiveTokoId(String? v) async =>
      v == null ? _m.remove('toko') : _m['toko'] = v;
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

Future<ProviderContainer> siapDemo(AntreanMemori antrean) async {
  final c = ProviderContainer(
    overrides: [
      secureStorageProvider.overrideWithValue(_FakeStorage()),
      masaCobaServiceProvider.overrideWithValue(MasaCobaPalsu()),
      ...overrideOffline(antrean: antrean),
    ],
  );
  await c.read(authControllerProvider.notifier).startDemo();
  await c.read(activeTokoIdProvider.notifier).select('TOKO-1');
  return c;
}

void main() {
  test('stok katalog = stok server + delta tertunda; riwayat memuat transaksi lokal di atas', () async {
    final antrean = AntreanMemori();
    final c = await siapDemo(antrean);
    addTearDown(c.dispose);

    final sebelum = await c.read(productsProvider.future);
    final aqua = sebelum.firstWhere((p) => p.stok != null);
    final stokServer = aqua.stok!;

    await antrean.antrekan(
      PesanAntrean(
        urut: 0, clientRef: 'c1', jenis: 'CHECKOUT', path: '/transaksi/checkout',
        body: const {}, dibuat: DateTime(2026, 9, 5, 9), tokoId: 'TOKO-1',
      ),
      transaksi: TransaksiTertunda(
        clientRef: 'c1', tokoId: 'TOKO-1', nomorLokal: 'L-260905-0001',
        tipePembayaran: 'TUNAI', grandTotal: 12000, dibayar: 20000,
        waktuKlien: DateTime(2026, 9, 5, 9), strukJson: '{"nomor":"L-260905-0001","baris":[]}',
      ),
      deltaStok: {aqua.id: -3},
    );
    c.read(antreanVersiProvider.notifier).state++;

    final sesudah = await c.read(productsProvider.future);
    expect(sesudah.firstWhere((p) => p.id == aqua.id).stok, stokServer - 3);

    final riwayat = await c.read(riwayatListProvider.future);
    expect(riwayat.first.nomor, 'L-260905-0001');
    expect(riwayat.first.status, statusBelumSinkron);
    expect(riwayat.first.id, '${awalanIdLokal}c1');
    expect(riwayat.length, greaterThan(1), reason: 'daftar server tetap ada di bawahnya');

    final detail = await c.read(transaksiDetailProvider('${awalanIdLokal}c1').future);
    expect(detail.nomor, 'L-260905-0001');
    expect(detail.status, statusBelumSinkron);

    // Terkirim → hilang dari riwayat lokal dan delta stok.
    await antrean.selesai('c1', hasil: {'nomor': '26-POS-000050'});
    c.read(antreanVersiProvider.notifier).state++;
    expect((await c.read(productsProvider.future)).firstWhere((p) => p.id == aqua.id).stok, stokServer);
    expect((await c.read(riwayatListProvider.future)).first.nomor, isNot('L-260905-0001'));
  });

  testWidgets('layar Sinkronisasi: antrean, baris tinjau dengan Batalkan, kemudian kosong', (t) async {
    t.view.physicalSize = const Size(390, 800);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final antrean = AntreanMemori();
    await antrean.antrekan(
      PesanAntrean(
        urut: 0, clientRef: 't1', jenis: 'CHECKOUT', path: '/transaksi/checkout',
        body: const {'items': [1, 2], 'tipe_pembayaran': 'TUNAI', 'dibayar': 20000},
        dibuat: DateTime(2026, 9, 5, 9), status: StatusAntrean.tinjau,
        galatTerakhir: 'Server tidak menjawab setelah data dikirim.',
      ),
    );
    await antrean.antrekan(
      PesanAntrean(
        urut: 0, clientRef: 'p1', jenis: 'PENGELUARAN', path: '/pengeluaran',
        body: const {'keterangan': 'Galon', 'nominal': 25000}, dibuat: DateTime(2026, 9, 5, 10),
      ),
    );
    late final ProviderContainer c;
    await t.runAsync(() async => c = await siapDemo(antrean));
    addTearDown(c.dispose);

    Future<void> pompa() async {
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    await t.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(theme: AppTheme.light(), home: const SinkronisasiScreen()),
      ),
    );
    await pompa();
    expect(find.text('Sinkronisasi'), findsOneWidget);
    expect(find.text('1 menunggu dikirim · 1 perlu ditinjau'), findsOneWidget);
    expect(find.textContaining('Transaksi · Rp'), findsOneWidget);
    expect(find.textContaining('Pengeluaran · Rp'), findsOneWidget);
    expect(find.text('Perlu ditinjau'), findsOneWidget);
    expect(find.text('Kirim ulang'), findsOneWidget);

    await t.tap(find.text('Batalkan'));
    await pompa();
    expect(find.text('Batalkan transaksi ini?'), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, 'Batalkan'));
    await pompa();
    expect(await antrean.cari('t1'), isNull);
    expect(find.text('Perlu ditinjau'), findsNothing);
    expect(find.text('1 menunggu dikirim · 0 perlu ditinjau'), findsOneWidget);
  });
}
