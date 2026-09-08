// UI 2.17.0: alur parkir keranjang di kasir (parkir → daftar → lanjutkan) dan
// tombol "Batalkan transaksi" di detail riwayat.
//
// Penyimpan parkir di sini in-memory: di dalam testWidgets, Future dari I/O
// berkas nyata tidak pernah selesai (zona async palsu). Perilaku berkasnya
// diuji terpisah di kasir_parkir_batal_opname_test.dart.

import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/offline/antrean.dart';
import 'package:tuleh_pos/core/storage/secure_storage.dart';
import 'package:tuleh_pos/core/theme/app_theme.dart';
import 'package:tuleh_pos/features/auth/presentation/controllers/auth_controller.dart';
import 'package:tuleh_pos/features/demo/data/masa_coba_service.dart';
import 'package:tuleh_pos/features/kasir/data/parkir_store.dart';
import 'package:tuleh_pos/features/kasir/domain/entities/cart_item.dart';
import 'package:tuleh_pos/features/kasir/presentation/controllers/cart_controller.dart';
import 'package:tuleh_pos/features/kasir/presentation/controllers/keranjang_meta.dart';
import 'package:tuleh_pos/features/kasir/presentation/widgets/parkir_sheet.dart';
import 'package:tuleh_pos/features/pelanggan/domain/entities/pelanggan.dart';
import 'package:tuleh_pos/features/products/domain/entities/product.dart';
import 'package:tuleh_pos/features/riwayat/domain/entities/transaksi.dart';
import 'package:tuleh_pos/features/riwayat/presentation/providers/riwayat_providers.dart';
import 'package:tuleh_pos/features/riwayat/presentation/screens/detail_transaksi_screen.dart';
import 'package:tuleh_pos/features/toko/presentation/providers/toko_providers.dart';

import 'helpers/masa_coba_palsu.dart';

const _kopi = Product(id: 'P1', nama: 'Kopi Susu', harga: 18000, stok: 9);
const _roti = Product(id: 'P2', nama: 'Roti Bakar', harga: 15000);

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

/// Parkir in-memory dengan aturan yang sama (nomor urut, batas, per toko).
class _ParkirMemori extends ParkirStore {
  _ParkirMemori() : super(dir: () async => Directory.systemTemp);

  final Map<String, List<KeranjangParkir>> _data = {};
  int _urut = 0;

  List<KeranjangParkir> _bucket(String? tokoId) => _data.putIfAbsent(tokoId ?? '', () => []);

  @override
  Future<List<KeranjangParkir>> daftar(String? tokoId) async => List.of(_bucket(tokoId));

  @override
  Future<KeranjangParkir> simpan(
    String? tokoId, {
    required List<CartItem> items,
    KeranjangMeta meta = const KeranjangMeta(),
  }) async {
    if (items.isEmpty) throw ArgumentError('Keranjang kosong.');
    final bucket = _bucket(tokoId);
    if (bucket.length >= maksParkir) throw const ParkirPenuh();
    final entri = KeranjangParkir(
      id: 'p${++_urut}',
      nomor: (bucket.fold<int>(0, (m, p) => max(m, p.nomor)) % 999) + 1,
      waktu: DateTime(2026, 9, 8, 10, 30),
      items: List.of(items),
      meta: meta,
    );
    bucket.add(entri);
    return entri;
  }

  @override
  Future<KeranjangParkir?> ambil(String? tokoId, String id) async {
    final bucket = _bucket(tokoId);
    final i = bucket.indexWhere((p) => p.id == id);
    if (i < 0) return null;
    return bucket.removeAt(i);
  }

  @override
  Future<void> hapus(String? tokoId, String id) async =>
      _bucket(tokoId).removeWhere((p) => p.id == id);
}

Future<void> _pompa(WidgetTester t, [int kali = 20]) async {
  for (var i = 0; i < kali; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late _ParkirMemori parkir;

  setUp(() => parkir = _ParkirMemori());

  Future<ProviderContainer> buatDemo() async {
    final c = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(_Storage()),
        masaCobaServiceProvider.overrideWithValue(MasaCobaPalsu()),
        parkirStoreProvider.overrideWithValue(parkir),
        ...overrideOffline(antrean: AntreanMemori()),
      ],
    );
    addTearDown(c.dispose);
    await c.read(authControllerProvider.notifier).startDemo();
    await c.read(activeTokoIdProvider.notifier).select('TOKO-1');
    return c;
  }

  /// Wadah demo siap pakai. `startDemo()` menyentuh I/O nyata sehingga harus
  /// berjalan di luar zona async palsu (`runAsync`), seperti tes tata letak.
  Future<ProviderContainer> demo(WidgetTester t) async {
    late final ProviderContainer wadah;
    await t.runAsync(() async => wadah = await buatDemo());
    return wadah;
  }

  /// Halaman uji: menyediakan context & ref untuk memanggil aksi parkir.
  Widget app(ProviderContainer c, void Function(BuildContext, WidgetRef) tangkap) =>
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Consumer(
              builder: (ctx, ref, _) {
                tangkap(ctx, ref);
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );

  testWidgets('parkir mengosongkan keranjang; lanjutkan memulihkan item & meta', (t) async {
    final c = await demo(t);
    c.read(cartControllerProvider.notifier)
      ..add(_kopi)
      ..add(_kopi)
      ..add(_roti);
    c.read(keranjangMetaProvider.notifier)
      ..pilihPelanggan(const Pelanggan(id: 'C1', nama: 'Bu Sari'))
      ..aturDiskon(10)
      ..aturCatatan('tanpa gula');

    late BuildContext ctx;
    late WidgetRef wref;
    await t.pumpWidget(app(c, (context, ref) {
      ctx = context;
      wref = ref;
    }));

    final simpan = parkirKeranjang(ctx, wref);
    await _pompa(t);
    expect(await simpan, isTrue);
    expect(c.read(cartControllerProvider), isEmpty, reason: 'keranjang dikosongkan');
    expect(c.read(keranjangMetaProvider).kosong, isTrue, reason: 'meta ikut kosong');
    expect(find.textContaining('#1'), findsOneWidget, reason: 'umpan balik nomor parkir');

    final tersimpan = await parkir.daftar('TOKO-1');
    expect(tersimpan.single.jumlahItem, 3);
    expect(tersimpan.single.total, 45900); // diskon 10 % ikut tersimpan

    final lanjut = lanjutkanParkir(ctx, wref, tersimpan.single);
    await _pompa(t);
    expect(await lanjut, isTrue);
    final items = c.read(cartControllerProvider);
    expect(items.length, 2);
    expect(items.firstWhere((e) => e.product.id == 'P1').qty, 2);
    final meta = c.read(keranjangMetaProvider);
    expect(meta.pelanggan?.nama, 'Bu Sari');
    expect(meta.diskonPersen, 10);
    expect(meta.catatan, 'tanpa gula');
    expect(await parkir.daftar('TOKO-1'), isEmpty, reason: 'sudah dilanjutkan');
  });

  testWidgets('lanjutkan saat keranjang berisi menawarkan "Parkir dulu"', (t) async {
    final c = await demo(t);
    final lama = await parkir.simpan('TOKO-1', items: const [CartItem(product: _roti, qty: 3)]);
    c.read(cartControllerProvider.notifier).add(_kopi);

    late BuildContext ctx;
    late WidgetRef wref;
    await t.pumpWidget(app(c, (context, ref) {
      ctx = context;
      wref = ref;
    }));

    final aksi = lanjutkanParkir(ctx, wref, lama);
    await _pompa(t);
    expect(find.text('Keranjang aktif masih berisi'), findsOneWidget);
    await t.tap(find.text('Parkir dulu'));
    await _pompa(t);
    expect(await aksi, isTrue);

    // Keranjang berisi item lama; keranjang yang tadi aktif ikut terparkir.
    final items = c.read(cartControllerProvider);
    expect(items.single.product.id, 'P2');
    expect(items.single.qty, 3);
    final sisa = await parkir.daftar('TOKO-1');
    expect(sisa.single.items.single.product.id, 'P1');
  });

  testWidgets('daftar parkir menampilkan entri; Hapus membuangnya', (t) async {
    final c = await demo(t);
    await parkir.simpan(
      'TOKO-1',
      items: const [CartItem(product: _kopi, qty: 2)],
      meta: const KeranjangMeta(catatan: 'bungkus'),
    );

    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(theme: AppTheme.light(), home: const Scaffold(body: ParkirSheet())),
    ));
    await _pompa(t);
    expect(find.text('#1'), findsOneWidget);
    expect(find.textContaining('2× Kopi Susu'), findsOneWidget);
    expect(find.text('bungkus'), findsOneWidget);

    await t.tap(find.text('Hapus'));
    await _pompa(t);
    expect(find.text('Hapus keranjang #1?'), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, 'Hapus'));
    await _pompa(t);
    expect(await parkir.daftar('TOKO-1'), isEmpty);
    expect(find.text('Belum ada keranjang terparkir'), findsOneWidget);
  });

  testWidgets('detail transaksi: Batalkan → dikonfirmasi, status jadi DIBATALKAN', (t) async {
    final c = await demo(t);
    c.read(riwayatListProvider); // mulai memuat lewat mesin demo
    late List<Transaksi> daftar;
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(theme: AppTheme.light(), home: const Scaffold(body: SizedBox())),
    ));
    await _pompa(t, 40);
    daftar = c.read(riwayatListProvider).valueOrNull ?? const [];
    expect(daftar, isNotEmpty, reason: 'mesin demo menyemai riwayat');
    final aktif = daftar.firstWhere((x) => (x.status ?? '').toUpperCase() != 'DIBATALKAN');

    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: DetailTransaksiScreen(id: aktif.id),
      ),
    ));
    await _pompa(t, 40);

    final tombol = find.widgetWithText(OutlinedButton, 'Batalkan transaksi');
    expect(tombol, findsOneWidget);
    expect(t.widget<OutlinedButton>(tombol).enabled, isTrue, reason: 'online → aktif');
    // Struk panjang: gulirkan tombol ke layar sebelum diketuk.
    await t.ensureVisible(tombol);
    await _pompa(t);
    await t.tap(tombol);
    await _pompa(t);
    expect(find.text('Batalkan transaksi ini?'), findsOneWidget);
    await t.tap(find.text('Ya, batalkan'));
    await _pompa(t, 40);

    expect(c.read(transaksiDetailProvider(aktif.id)).valueOrNull?.status, 'DIBATALKAN');
    // Transaksi batal tidak lagi menawarkan aksi cetak/bagikan/batal.
    expect(find.text('Batalkan transaksi'), findsNothing);
    expect(find.text('Cetak ulang'), findsNothing);
  });
}
