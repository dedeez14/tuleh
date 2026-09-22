import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/network/api_exception.dart';
import 'package:tuleh_pos/core/network/api_result.dart';
import 'package:tuleh_pos/core/offline/antrean.dart';
import 'package:tuleh_pos/core/offline/koneksi.dart';
import 'package:tuleh_pos/core/offline/nomor_lokal.dart';
import 'package:tuleh_pos/core/storage/secure_storage.dart';
import 'package:tuleh_pos/core/theme/app_theme.dart';
import 'package:tuleh_pos/core/utils/format.dart';
import 'package:tuleh_pos/features/cetak/domain/entities/struk.dart';
import 'package:tuleh_pos/features/demo/data/masa_coba_service.dart';
import 'package:tuleh_pos/features/kasir/data/checkout_repository.dart';
import 'package:tuleh_pos/features/kasir/data/datasources/transaction_remote_datasource.dart';
import 'package:tuleh_pos/features/kasir/domain/entities/cart_item.dart';
import 'package:tuleh_pos/features/kasir/presentation/controllers/cart_controller.dart';
import 'package:tuleh_pos/features/kasir/presentation/controllers/keranjang_meta.dart';
import 'package:tuleh_pos/features/kasir/presentation/providers/checkout_providers.dart';
import 'package:tuleh_pos/features/kasir/presentation/widgets/cart_sheet.dart';
import 'package:tuleh_pos/features/kasir/presentation/widgets/keranjang_form_bayar.dart';
import 'package:tuleh_pos/features/pengaturan/domain/entities/pengaturan_pembayaran.dart';
import 'package:tuleh_pos/features/pengaturan/domain/entities/profil_usaha.dart';
import 'package:tuleh_pos/features/pengaturan/presentation/providers/pengaturan_providers.dart';
import 'package:tuleh_pos/features/pesanan/domain/entities/hasil_pesanan.dart';
import 'package:tuleh_pos/features/pesanan/domain/entities/pesanan.dart';
import 'package:tuleh_pos/features/pesanan/domain/logic/ref_nota.dart';
import 'package:tuleh_pos/features/pesanan/domain/repositories/pesanan_repository.dart';
import 'package:tuleh_pos/features/pesanan/presentation/providers/pesanan_providers.dart';
import 'package:tuleh_pos/features/products/domain/entities/product.dart';
import 'package:tuleh_pos/features/toko/domain/entities/toko_manifest.dart';
import 'package:tuleh_pos/features/toko/presentation/providers/toko_providers.dart';

import 'helpers/masa_coba_palsu.dart';

/// Fase 3 (2.33.0): lembar bayar menawarkan Lunas / Bayar nanti / Uang muka
/// hanya bila alur toko `PAYMENT_OR_LATER`. Nota & uang muka memindahkan uang
/// dan kewajiban, jadi keduanya ONLINE-ONLY (tanpa antrean offline — Fase 4).

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
  Future<void> clearSession() async => _m.clear();
}

/// Manifest toko palsu: alur transaksi ditentukan tes (tanpa jaringan).
class _ManifestPalsu extends ManifestNotifier {
  _ManifestPalsu(this.alur);

  final List<String> alur;

  @override
  Future<TokoManifest> build() async => TokoManifest(
    transactionFlow: alur,
    lifecycleStates: const ['ANTRIAN', 'DIPROSES', 'SIAP_AMBIL', 'SELESAI'],
    paymentModes: const ['TUNAI', 'QRIS'],
  );
}

/// Koneksi mati (server tak terjangkau) untuk menguji gerbang online-only.
class _KoneksiMati extends KoneksiNotifier {
  _KoneksiMati() : super(jaringan: const Stream.empty());

  @override
  StatusKoneksi build() {
    super.build();
    return const StatusKoneksi(online: false);
  }
}

/// Argumen `buatNota` yang terakhir diterima repositori.
typedef ArgNota = ({
  String bayar,
  List<ItemNota> items,
  String? idPelanggan,
  String? catatan,
  num? uangMuka,
  String? metodeUangMuka,
  String clientRef,
});

class _RepoPesananPalsu implements PesananRepository {
  ArgNota? terakhir;

  /// Semua kiriman `buatNota`, berurutan.
  final panggilan = <ArgNota>[];

  /// Jawaban kiriman berikutnya, berurutan: galat = ditolak/gagal; habis = sukses.
  final galat = <ApiException>[];

  /// Bila diisi, jawaban ditahan sampai completer ini selesai (permintaan
  /// yang masih di jalan saat lembar ditutup).
  Completer<void>? tahan;

  @override
  Future<Result<List<Pesanan>>> list({String? stage, String? bayar}) async =>
      const Ok(<Pesanan>[]);

  @override
  Future<Result<HasilTransisi>> transition(
    String id, {
    required String to,
    String? tipePembayaran,
  }) async => Ok(HasilTransisi(pesanan: Pesanan(id: id, stage: to)));

  @override
  Future<Result<NotaPesanan>> buatNota({
    required String bayar,
    required List<ItemNota> items,
    String? idPelanggan,
    String? catatan,
    num? uangMuka,
    String? metodeUangMuka,
    required String clientRef,
  }) async {
    terakhir = (
      bayar: bayar,
      items: items,
      idPelanggan: idPelanggan,
      catatan: catatan,
      uangMuka: uangMuka,
      metodeUangMuka: metodeUangMuka,
      clientRef: clientRef,
    );
    panggilan.add(terakhir!);
    if (tahan != null) await tahan!.future;
    if (galat.isNotEmpty) return Err(galat.removeAt(0));
    final total = items.fold<num>(0, (s, i) => s + i.harga * i.kuantitas);
    final dp = bayar == 'DP' ? (uangMuka ?? 0) : 0;
    return Ok(
      NotaPesanan(
        pesanan: Pesanan(
          id: 'ORD-1',
          stage: 'ANTRIAN',
          nomor: 'ORD/0001',
          bayar: bayar == 'DP' ? 'DP' : 'BELUM',
          total: total,
          dibayar: dp,
          sisa: total - dp,
        ),
        nota: {
          'nomor': 'ORD/0001',
          'tanggal': '2026-09-22T10:00:00',
          'status': bayar == 'DP' ? 'UANG MUKA' : 'BELUM LUNAS',
          'grand_total': total,
          'uang_muka': dp,
          'sisa': total - dp,
          'tipe_pembayaran': metodeUangMuka ?? 'BAYAR SAAT AMBIL',
          'items': [
            for (final i in items)
              {'nama': 'Cuci Setrika', 'kuantitas': i.kuantitas, 'harga': i.harga},
          ],
        },
      ),
    );
  }
}

/// Checkout palsu: bayar Lunas selalu diterima; `buatClientRef` asli.
class _CheckoutPalsu extends CheckoutRepository {
  _CheckoutPalsu()
    : super(
        remote: TransactionRemoteDataSource(Dio()),
        antrean: AntreanMemori(),
        nomorLokal: NomorLokal(_FakeStorage()),
      );

  int dibayar = 0;

  @override
  Future<HasilBayar> bayar({
    required List<CartItem> items,
    required String metode,
    required double dibayar,
    required double total,
    required Struk Function(String nomor, double kembalian) buatStruk,
    double diskonPersen = 0,
    String? idPelanggan,
    String? catatan,
  }) async {
    this.dibayar += 1;
    return const HasilBayar(nomor: 'TRX/0001', kembalian: 0);
  }
}

const _produk = Product(id: 'LDR-001', nama: 'Cuci Setrika', harga: 28000);

/// Gagal jaringan (tanpa jawaban HTTP) — kirim ulang harus memakai ref sama.
const _putus = ApiException(message: 'Tidak dapat terhubung ke server.');

/// Pompa berbatas — bukan pumpAndSettle: tombol kirim berputar selama menunggu.
Future<void> _pompa(WidgetTester t, [int kali = 12]) async {
  for (var i = 0; i < kali; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RepoPesananPalsu repo;

  setUp(() => repo = _RepoPesananPalsu());

  /// [tertanam] = panel menetap tablet; selain itu lembar bawah ponsel yang
  /// dibuka persis seperti `KasirScreen._bukaKeranjang`.
  Future<ProviderContainer> pumpKeranjang(
    WidgetTester t, {
    List<String> alur = const ['INTAKE', 'PAYMENT_OR_LATER'],
    bool online = true,
    double diskonPersen = 0,
    bool tertanam = false,
    PengaturanPembayaran pembayaran = const PengaturanPembayaran(),
    CheckoutRepository? checkout,
  }) async {
    t.view.physicalSize = const Size(420, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final c = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(_FakeStorage()),
        masaCobaServiceProvider.overrideWithValue(MasaCobaPalsu()),
        ...overrideOffline(),
        if (!online) koneksiProvider.overrideWith(_KoneksiMati.new),
        pengaturanPembayaranProvider.overrideWith((_) async => pembayaran),
        profilUsahaProvider.overrideWith(
          (_) async => const ProfilUsaha(nama: 'Laundry Uji'),
        ),
        metodePembayaranProvider.overrideWith(
          (_) async => ['TUNAI', 'QRIS', 'TRANSFER'],
        ),
        activeManifestProvider.overrideWith(() => _ManifestPalsu(alur)),
        pesananRepositoryProvider.overrideWithValue(repo),
        if (checkout != null) checkoutRepositoryProvider.overrideWithValue(checkout),
      ],
    );
    addTearDown(c.dispose);
    c.read(cartControllerProvider.notifier).add(_produk);
    if (diskonPersen > 0) {
      c.read(keranjangMetaProvider.notifier).aturDiskon(diskonPersen);
    }
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: tertanam
              ? const Scaffold(body: CartSheet(tertanam: true))
              : Scaffold(
                  body: Builder(
                    builder: (context) => Center(
                      child: FilledButton(
                        onPressed: () => showModalBottomSheet<void>(
                          context: context,
                          useRootNavigator: true,
                          isScrollControlled: true,
                          useSafeArea: true,
                          showDragHandle: true,
                          builder: (_) => const CartSheet(),
                        ),
                        child: const Text('Buka keranjang'),
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
    await t.pumpAndSettle();
    if (!tertanam) {
      await t.tap(find.text('Buka keranjang'));
      await t.pumpAndSettle();
    }
    await t.tap(find.text('Lanjut ke pembayaran'));
    await t.pumpAndSettle();
    return c;
  }

  /// Pilih "Bayar nanti" lalu tekan Simpan (tanpa menunggu jawaban).
  Future<void> kirimNanti(WidgetTester t) async {
    await t.tap(find.text('Bayar nanti'));
    await _pompa(t);
    await t.tap(find.widgetWithText(FilledButton, 'Simpan Nota — Bayar Saat Ambil'));
    await _pompa(t);
  }

  testWidgets('toko tanpa PAYMENT_OR_LATER: tak ada pemilih mode', (t) async {
    // Minimarket: bayar = selesai, tak ada nota bayar nanti maupun uang muka.
    await pumpKeranjang(t, alur: const ['PAYMENT']);
    expect(find.text('Uang muka'), findsNothing);
    expect(find.text('Bayar nanti'), findsNothing);
    expect(find.text('Lunas'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Bayar Rp 28.000'), findsOneWidget);
  });

  testWidgets('uang muka: batas < total ditegakkan di layar; kirim → buatNota bayar DP', (t) async {
    // Toko laundry (PAYMENT_OR_LATER), satu item Rp 28.000.
    await pumpKeranjang(t);
    await t.tap(find.text('Uang muka'));
    await t.pumpAndSettle();

    await t.enterText(find.byKey(const ValueKey('nota-uang-muka')), '28000');
    await t.pumpAndSettle();
    expect(find.textContaining('kurang dari total'), findsOneWidget);
    final tombol = find.widgetWithText(FilledButton, 'Simpan Nota + Uang Muka');
    expect(
      t.widget<FilledButton>(tombol).onPressed,
      isNull,
      reason: 'tombol terkunci saat DP tak sah',
    );

    await t.enterText(find.byKey(const ValueKey('nota-uang-muka')), '10000');
    await t.pumpAndSettle();
    expect(
      find.textContaining('Sisa dibayar saat ambil: ${fmtIDR(18000)}'),
      findsOneWidget,
    );

    await t.tap(find.text('QRIS'));
    await t.pumpAndSettle();
    await t.tap(tombol);
    await t.pumpAndSettle();

    expect(repo.terakhir!.bayar, 'DP');
    expect(repo.terakhir!.uangMuka, 10000);
    expect(repo.terakhir!.metodeUangMuka, 'QRIS');
    expect(repo.terakhir!.clientRef, isNotEmpty);
    expect(find.text('Nota & uang muka tersimpan'), findsOneWidget);
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('bayar nanti: tanpa metode & nominal; kirim → buatNota NANTI', (t) async {
    await pumpKeranjang(t);
    await t.tap(find.text('Bayar nanti'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('nota-uang-muka')), findsNothing);
    expect(find.text('Uang diterima'), findsNothing);
    expect(
      find.textContaining('dibayar saat pesanan diambil'),
      findsOneWidget,
    );

    await t.tap(find.widgetWithText(FilledButton, 'Simpan Nota — Bayar Saat Ambil'));
    await t.pumpAndSettle();
    expect(repo.terakhir!.bayar, 'NANTI');
    expect(repo.terakhir!.uangMuka, isNull);
    expect(repo.terakhir!.metodeUangMuka, isNull);
    expect(find.text('Nota tersimpan'), findsOneWidget);
    // Ponsel: lembar keranjang ditutup seperti sesudah bayar Lunas — tak ada
    // lembar kosong yang tertinggal di balik lembar nota.
    expect(find.byType(CartSheet), findsNothing);
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('offline: nota/DP tidak dikirim, pesan jelas', (t) async {
    await pumpKeranjang(t, online: false);
    await t.tap(find.text('Uang muka'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('nota-uang-muka')), '10000');
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Simpan Nota + Uang Muka'));
    await t.pumpAndSettle();

    expect(repo.terakhir, isNull);
    expect(find.textContaining('terhubung ke server'), findsOneWidget);
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('diskon transaksi + nota: ditolak dengan jalan keluar, bukan kirim diam-diam', (t) async {
    // Server menghitung total nota dari harga katalog — diskon keranjang tak
    // ikut terkirim, jadi menyimpannya akan menagih lebih saat pelunasan.
    await pumpKeranjang(t, diskonPersen: 10);
    await t.tap(find.text('Bayar nanti'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Simpan Nota — Bayar Saat Ambil'));
    await t.pumpAndSettle();
    expect(repo.terakhir, isNull);
    expect(find.textContaining('Diskon belum bisa dipakai'), findsOneWidget);
    await t.pump(const Duration(seconds: 5));
  });

  group('client_ref terikat muatan nota', () {
    testWidgets('gagal jaringan → kirim ulang muatan sama memakai ref SAMA; keranjang berubah → ref BARU', (t) async {
      // Server `pos.idempoten` memutar ulang jawaban pertama per (user,
      // endpoint, client_ref) TANPA melihat isi — ref lama pada keranjang
      // yang sudah berubah akan memutar ulang pesanan pelanggan sebelumnya.
      repo.galat.addAll([_putus, _putus]);
      final c = await pumpKeranjang(t);
      await kirimNanti(t);
      await t.tap(find.widgetWithText(FilledButton, 'Simpan Nota — Bayar Saat Ambil'));
      await _pompa(t);
      expect(repo.panggilan, hasLength(2));
      expect(repo.panggilan[1].clientRef, repo.panggilan[0].clientRef,
          reason: 'kirim ulang muatan yang sama = pesanan yang sama');

      c.read(cartControllerProvider.notifier).add(_produk); // kuantitas 1 → 2
      await _pompa(t);
      await t.tap(find.widgetWithText(FilledButton, 'Simpan Nota — Bayar Saat Ambil'));
      await _pompa(t);
      expect(repo.panggilan, hasLength(3));
      expect(repo.panggilan[2].items.single.kuantitas, 2);
      expect(repo.panggilan[2].clientRef, isNot(repo.panggilan[0].clientRef),
          reason: 'muatan berubah → ref baru, bukan putar ulang nota lama');
      await t.pump(const Duration(seconds: 5));
    });

    testWidgets('tablet: nota tersimpan → nota berikutnya (isi sama) memakai ref baru', (t) async {
      final c = await pumpKeranjang(t, tertanam: true);
      await kirimNanti(t);
      await t.pumpAndSettle();
      expect(find.text('Nota tersimpan'), findsOneWidget);
      await t.tap(find.widgetWithText(TextButton, 'Tutup'));
      await t.pumpAndSettle();

      // Pelanggan berikutnya memesan persis sama.
      c.read(cartControllerProvider.notifier).add(_produk);
      await _pompa(t);
      await t.tap(find.text('Lanjut ke pembayaran'));
      await _pompa(t);
      await kirimNanti(t);
      await t.pumpAndSettle();
      expect(repo.panggilan, hasLength(2));
      expect(repo.panggilan[1].clientRef, isNot(repo.panggilan[0].clientRef));
      await t.tap(find.widgetWithText(TextButton, 'Tutup'));
      await t.pumpAndSettle();
    });

    testWidgets('bayar Lunas sukses juga membuang ref nota yang tertinggal', (t) async {
      // Nota gagal (ref tersimpan), kasir memilih Lunas dan berhasil; nota
      // berikutnya dengan isi yang sama TIDAK boleh memakai ref lama itu.
      repo.galat.add(_putus);
      final checkout = _CheckoutPalsu();
      final c = await pumpKeranjang(t, tertanam: true, checkout: checkout);
      await kirimNanti(t);
      expect(repo.panggilan, hasLength(1));
      // Snackbar galat menutupi tombol kaki panel tablet.
      ScaffoldMessenger.of(t.element(find.byType(CartSheet))).removeCurrentSnackBar();
      await _pompa(t);

      await t.tap(find.text('Lunas'));
      await _pompa(t);
      await t.tap(find.text('QRIS'));
      await _pompa(t);
      await t.tap(find.widgetWithText(FilledButton, 'Bayar Rp 28.000'));
      await t.pumpAndSettle();
      expect(checkout.dibayar, 1);
      await t.tap(find.widgetWithText(TextButton, 'Selesai'));
      await t.pumpAndSettle();

      c.read(cartControllerProvider.notifier).add(_produk);
      await _pompa(t);
      await t.tap(find.text('Lanjut ke pembayaran'));
      await _pompa(t);
      await kirimNanti(t);
      await t.pumpAndSettle();
      expect(repo.panggilan, hasLength(2));
      expect(repo.panggilan[1].clientRef, isNot(repo.panggilan[0].clientRef));
      await t.tap(find.widgetWithText(TextButton, 'Tutup'));
      await t.pumpAndSettle();
    });
  });

  group('lembar ditutup di tengah kiriman', () {
    testWidgets('tombol kembali & ketuk latar tidak menutup lembar selama menyimpan', (t) async {
      repo.tahan = Completer<void>();
      await pumpKeranjang(t);
      await kirimNanti(t);

      // Tombol kembali Android = maybePop pada navigator akar.
      await Navigator.of(t.element(find.byType(CartSheet))).maybePop();
      await _pompa(t);
      expect(find.byType(CartSheet), findsOneWidget, reason: 'PopScope menahan tombol kembali');
      await t.tapAt(const Offset(20, 20)); // latar di atas lembar
      await _pompa(t);
      expect(find.byType(CartSheet), findsOneWidget, reason: 'latar tak menutup lembar');

      repo.tahan!.complete();
      await t.pumpAndSettle();
      expect(find.text('Nota tersimpan'), findsOneWidget);
      await t.pump(const Duration(seconds: 5));
    });

    testWidgets('lembar terlanjur tertutup (seret) → keranjang tetap dikosongkan & nota tampil', (t) async {
      // Seret-tutup memanggil Navigator.pop langsung (melewati PopScope).
      // Nota sudah tersimpan di server; keranjang yang tertinggal penuh akan
      // menjadi pesanan + uang muka KEDUA saat lembar dibuka lagi.
      repo.tahan = Completer<void>();
      final c = await pumpKeranjang(t);
      await kirimNanti(t);
      Navigator.of(t.element(find.byType(CartSheet))).pop();
      await _pompa(t);
      expect(find.byType(CartSheet), findsNothing);

      repo.tahan!.complete();
      await t.pumpAndSettle();
      expect(c.read(cartControllerProvider), isEmpty);
      expect(find.text('Nota tersimpan'), findsOneWidget,
          reason: 'nota tetap bisa dicetak walau lembar keranjang sudah tertutup');
      expect(t.takeException(), isNull);
      await t.pump(const Duration(seconds: 5));
    });
  });

  testWidgets('409 belum ada sesi kasir → tawarkan "Buka sesi" seperti bayar Lunas', (t) async {
    repo.galat.add(
      const ApiException(message: 'Belum ada sesi kasir terbuka.', statusCode: 409),
    );
    await pumpKeranjang(t);
    await kirimNanti(t);
    expect(find.text('Belum ada sesi kasir terbuka.'), findsOneWidget);
    expect(find.widgetWithText(SnackBarAction, 'Buka sesi'), findsOneWidget);
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('uang muka QRIS/TRANSFER: QR statis bernominal UANG MUKA & rekening toko', (t) async {
    await pumpKeranjang(
      t,
      pembayaran: const PengaturanPembayaran(
        qrStatis: 'https://contoh.test/qris.png',
        bank: [RekeningBank(bank: 'BCA', rekening: '4280420510', atasNama: 'Dede')],
      ),
    );
    await t.tap(find.text('Uang muka'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('nota-uang-muka')), '10000');
    await t.pumpAndSettle();
    await t.tap(find.text('QRIS'));
    await t.pumpAndSettle();

    final qris = find.byType(PanduanQris);
    expect(qris, findsOneWidget);
    expect(find.descendant(of: qris, matching: find.text(fmtIDR(10000))), findsOneWidget,
        reason: 'pelanggan memindai sebesar uang muka');
    expect(find.descendant(of: qris, matching: find.text(fmtIDR(28000))), findsNothing,
        reason: 'bukan total pesanan');
    expect(find.descendant(of: qris, matching: find.textContaining('Uang muka')), findsOneWidget);

    await t.tap(find.text('TRANSFER'));
    await t.pumpAndSettle();
    expect(find.byType(PanduanTransfer), findsOneWidget);
    expect(find.text('4280420510'), findsOneWidget);

    await t.tap(find.text('TUNAI'));
    await t.pumpAndSettle();
    expect(find.byType(PanduanQris), findsNothing);
    expect(find.byType(PanduanTransfer), findsNothing);
  });

  group('refNota (murni)', () {
    const item = ItemNota(idProduk: 'LDR-001', kuantitas: 1, harga: 28000);
    String sidik({
      String bayar = 'DP',
      List<ItemNota> items = const [item],
      String? pelanggan = 'PLG-1',
      String? catatan = 'ambil sore',
      num? uangMuka = 10000,
      String? metode = 'QRIS',
    }) => sidikNota(
      bayar: bayar,
      items: items,
      idPelanggan: pelanggan,
      catatan: catatan,
      uangMuka: uangMuka,
      metodeUangMuka: metode,
    );

    var n = 0;
    String buat() => 'ref-${++n}';
    setUp(() => n = 0);

    test('sidik sama → ref sama (kirim ulang aman)', () {
      final a = refNota(null, sidik(), buat);
      final b = refNota(a, sidik(), buat);
      expect(a.ref, 'ref-1');
      expect(identical(a, b), isTrue);
    });

    test('keranjang / isian berubah → ref baru', () {
      final a = refNota(null, sidik(), buat);
      const dua = ItemNota(idProduk: 'LDR-001', kuantitas: 2, harga: 28000);
      expect(refNota(a, sidik(items: const [dua]), buat).ref, isNot(a.ref));
      expect(refNota(a, sidik(items: const [item, item]), buat).ref, isNot(a.ref));
      expect(refNota(a, sidik(bayar: 'NANTI', uangMuka: null, metode: null), buat).ref, isNot(a.ref));
      expect(refNota(a, sidik(pelanggan: 'PLG-2'), buat).ref, isNot(a.ref));
      expect(refNota(a, sidik(catatan: null), buat).ref, isNot(a.ref));
      expect(refNota(a, sidik(uangMuka: 12000), buat).ref, isNot(a.ref));
      expect(refNota(a, sidik(metode: 'TUNAI'), buat).ref, isNot(a.ref));
    });

    test('sesudah sukses (ref dibuang) → ref baru walau isi sama', () {
      final a = refNota(null, sidik(), buat);
      final sesudahSukses = refNota(null, sidik(), buat);
      expect(sesudahSukses.ref, isNot(a.ref));
    });
  });

  group('validasiUangMuka', () {
    test('batas sama dengan server: 0 < uang muka < total', () {
      expect(validasiUangMuka(0, 28000), contains('lebih dari Rp0'));
      expect(validasiUangMuka(-5, 28000), contains('lebih dari Rp0'));
      expect(validasiUangMuka(28000, 28000), contains('kurang dari total'));
      expect(validasiUangMuka(30000, 28000), contains('kurang dari total'));
      expect(validasiUangMuka(10000, 28000), isNull);
    });
  });
}
