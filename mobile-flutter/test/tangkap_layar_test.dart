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
import 'package:tuleh_pos/core/theme/tema_provider.dart';
import 'package:tuleh_pos/features/auth/presentation/controllers/auth_controller.dart';
import 'package:tuleh_pos/features/demo/data/masa_coba_service.dart';
import 'package:tuleh_pos/features/kasir/presentation/controllers/cart_controller.dart';
import 'package:tuleh_pos/features/kasir/data/parkir_store.dart';
import 'package:tuleh_pos/features/kasir/presentation/widgets/parkir_sheet.dart';
import 'package:tuleh_pos/features/kasir/domain/entities/cart_item.dart';
import 'package:tuleh_pos/features/cetak/domain/entities/struk.dart';
import 'package:tuleh_pos/features/kasir/presentation/widgets/cart_sheet.dart';
import 'package:tuleh_pos/features/kasir/presentation/widgets/hasil_transaksi_sheet.dart';
import 'package:tuleh_pos/features/kasir/presentation/controllers/keranjang_meta.dart';
import 'package:tuleh_pos/features/kasir/presentation/widgets/pilih_pelanggan_sheet.dart';
import 'package:tuleh_pos/features/pelanggan/domain/entities/pelanggan.dart';
import 'package:tuleh_pos/features/cetak/presentation/screens/printer_screen.dart';
import 'package:tuleh_pos/features/products/presentation/screens/product_form_sheet.dart';
import 'package:tuleh_pos/features/riwayat/presentation/providers/riwayat_providers.dart';
import 'package:tuleh_pos/features/riwayat/presentation/screens/detail_transaksi_screen.dart';
import 'package:tuleh_pos/features/sesi/presentation/widgets/buka_sesi_dialog.dart';
import 'package:tuleh_pos/features/products/presentation/providers/products_provider.dart';
import 'package:tuleh_pos/features/toko/presentation/providers/toko_providers.dart';

import 'helpers/masa_coba_palsu.dart';
import 'helpers/parkir_memori.dart';

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

const _ikon = String.fromEnvironment('TANGKAP_IKON');

Future<void> _muatFont() async {
  if (_font.isNotEmpty) {
    final bytes = await File(_font).readAsBytes();
    // Nama keluarga yang dipakai google_fonts untuk tiap varian bobot.
    for (final v in [
      'regular',
      '500',
      '600',
      '700',
      '800',
      'italic',
      '300',
      '500italic',
      '700italic',
    ]) {
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

  testWidgets('tangkap layar demo', (t) async {
    t.view.physicalSize = const Size(1080, 2280);
    t.view.devicePixelRatio = 2.5;
    addTearDown(t.view.reset);
    // Bayangan asli (bukan garis hitam pengganti); wajib dipulihkan sebelum
    // test selesai karena flutter_test memeriksa variabel debug.
    debugDisableShadows = false;
    try {
      await _jalankan(t);
    } finally {
      debugDisableShadows = true;
    }
  });
}

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

Future<void> _jalankan(WidgetTester t) async {
  {
    final c = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(_Storage()),
        masaCobaServiceProvider.overrideWithValue(MasaCobaPalsu()),
        parkirStoreProvider.overrideWithValue(ParkirMemori()),
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
            darkTheme: AppTheme.dark(),
            themeMode: ref.watch(temaProvider),
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

    // Laporan bagian bawah: peringkat produk terlaris (di bawah lipatan).
    router.go('/laporan');
    await pompa(t, 40);
    await t.drag(find.byType(ListView).first, const Offset(0, -1150));
    await pompa(t, 20);
    await simpan(t, 'laporan-terlaris');

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
    // Dengan pelanggan, diskon, catatan terisi.
    c.read(keranjangMetaProvider.notifier)
      ..pilihPelanggan(
        const Pelanggan(
          id: 'C1',
          nama: 'Budi Santoso',
          telepon: '0812-3456-7890',
        ),
      )
      ..aturDiskon(10)
      ..aturCatatan('Tanpa es, ambil jam 5');
    await pompa(t, 20);
    await simpan(t, 'keranjang-tambahan');
    Navigator.of(ctx).pop();
    await pompa(t, 20);

    // Daftar keranjang terparkir (parkir keranjang, 2.17.0).
    await c.read(parkirStoreProvider).simpan(
      c.read(activeTokoIdProvider).valueOrNull,
      items: [for (final p in produk.take(2)) CartItem(product: p, qty: 2)],
      meta: const KeranjangMeta(
        pelanggan: Pelanggan(id: 'C1', nama: 'Budi Santoso'),
        catatan: 'Diambil sore',
      ),
    );
    await c.read(parkirStoreProvider).simpan(
      c.read(activeTokoIdProvider).valueOrNull,
      items: [CartItem(product: produk.first, qty: 1)],
    );
    c.read(parkirVersiProvider.notifier).state++;
    await pompa(t, 10);
    showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const ParkirSheet(),
    );
    await pompa(t, 40);
    await simpan(t, 'parkir');
    Navigator.of(ctx).pop();
    await pompa(t, 20);

    showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const PilihPelangganSheet(),
    );
    await pompa(t, 40);
    await simpan(t, 'pilih-pelanggan');
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
          baris: [
            for (final p in produk.take(3))
              StrukBaris(nama: p.nama, kuantitas: 1, harga: p.harga),
          ],
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
    Navigator.of(ctx).pop();
    await pompa(t, 20);

    // Layar sekunder yang dibuka lewat Navigator (bukan rute).
    {
      final riwayat = await c.read(riwayatListProvider.future);
      final nav = Navigator.of(t.element(find.byType(Scaffold).first), rootNavigator: true);
      nav.push(MaterialPageRoute<void>(builder: (_) => DetailTransaksiScreen(id: riwayat.first.id)));
      await pompa(t, 40);
      await simpan(t, 'detail-transaksi');
      nav.pop();
      await pompa(t, 20);
      nav.push(MaterialPageRoute<void>(builder: (_) => const PrinterScreen()));
      await pompa(t, 40);
      await simpan(t, 'printer');
      nav.pop();
      await pompa(t, 20);
      final ctx2 = t.element(find.byType(Scaffold).first);
      showModalBottomSheet<void>(
        context: ctx2,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => const ProductFormSheet(),
      );
      await pompa(t, 40);
      await simpan(t, 'form-produk');
      Navigator.of(ctx2).pop();
      await pompa(t, 20);
      showBukaSesiDialog(ctx2);
      await pompa(t, 40);
      await simpan(t, 'buka-sesi');
      Navigator.of(ctx2, rootNavigator: true).pop();
      await pompa(t, 20);
    }

    // Mode gelap: layar utama yang sama.
    await c.read(temaProvider.notifier).pilih(ThemeMode.dark);
    await pompa(t, 20);
    for (final (rute, nama) in [
      ('/home', 'gelap-home'),
      ('/kasir', 'gelap-kasir'),
      ('/riwayat', 'gelap-riwayat'),
      ('/laporan', 'gelap-laporan'),
      ('/pengaturan', 'gelap-pengaturan'),
      ('/sesi', 'gelap-sesi'),
    ]) {
      router.go(rute);
      await pompa(t, 40);
      await simpan(t, nama);
    }
    router.go('/kasir');
    await pompa(t, 30);
    showModalBottomSheet<void>(
      context: t.element(find.byType(Scaffold).first),
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const CartSheet(),
    );
    await pompa(t, 40);
    await simpan(t, 'gelap-keranjang');
    Navigator.of(t.element(find.byType(Scaffold).first)).pop();
    await pompa(t, 20);
    await c.read(temaProvider.notifier).pilih(ThemeMode.light);

    // Tablet lanskap 1280×800 (dp): rail samping, kasir dua panel,
    // riwayat master-detail, beranda dua kolom, daftar berlebar terbatas.
    t.view.physicalSize = const Size(2560, 1600);
    t.view.devicePixelRatio = 2.0;
    await pompa(t, 30);
    for (final (rute, nama) in [
      ('/home', 'tablet-home'),
      ('/kasir', 'tablet-kasir'),
      ('/riwayat', 'tablet-riwayat'),
      ('/laporan', 'tablet-laporan'),
      ('/produk', 'tablet-produk'),
      ('/pengaturan', 'tablet-pengaturan'),
    ]) {
      router.go(rute);
      await pompa(t, 40);
      if (nama == 'tablet-riwayat') {
        await t.tap(find.textContaining('TRX/').first);
        await pompa(t, 40);
      }
      await simpan(t, nama);
    }
    // Kasir tablet: keranjang menetap berisi + langkah bayar di panel.
    router.go('/kasir');
    await pompa(t, 30);
    await t.tap(find.text('Lanjut ke pembayaran'));
    await pompa(t, 30);
    await simpan(t, 'tablet-kasir-bayar');
    // Login tablet.
    await t.runAsync(() async {
      await c.read(authControllerProvider.notifier).logout();
    });
    await pompa(t, 40);
    await simpan(t, 'tablet-login');
  }
}
