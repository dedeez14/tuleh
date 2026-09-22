import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/network/api_result.dart';
import 'package:tuleh_pos/core/offline/koneksi.dart';
import 'package:tuleh_pos/core/storage/secure_storage.dart';
import 'package:tuleh_pos/core/theme/app_theme.dart';
import 'package:tuleh_pos/core/utils/format.dart';
import 'package:tuleh_pos/features/demo/data/masa_coba_service.dart';
import 'package:tuleh_pos/features/kasir/presentation/controllers/cart_controller.dart';
import 'package:tuleh_pos/features/kasir/presentation/controllers/keranjang_meta.dart';
import 'package:tuleh_pos/features/kasir/presentation/widgets/cart_sheet.dart';
import 'package:tuleh_pos/features/pengaturan/domain/entities/pengaturan_pembayaran.dart';
import 'package:tuleh_pos/features/pengaturan/domain/entities/profil_usaha.dart';
import 'package:tuleh_pos/features/pengaturan/presentation/providers/pengaturan_providers.dart';
import 'package:tuleh_pos/features/pesanan/domain/entities/hasil_pesanan.dart';
import 'package:tuleh_pos/features/pesanan/domain/entities/pesanan.dart';
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

const _produk = Product(id: 'LDR-001', nama: 'Cuci Setrika', harga: 28000);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RepoPesananPalsu repo;

  setUp(() => repo = _RepoPesananPalsu());

  Future<ProviderContainer> pumpKeranjang(
    WidgetTester t, {
    List<String> alur = const ['INTAKE', 'PAYMENT_OR_LATER'],
    bool online = true,
    double diskonPersen = 0,
  }) async {
    final c = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(_FakeStorage()),
        masaCobaServiceProvider.overrideWithValue(MasaCobaPalsu()),
        ...overrideOffline(),
        if (!online) koneksiProvider.overrideWith(_KoneksiMati.new),
        pengaturanPembayaranProvider.overrideWith(
          (_) async => const PengaturanPembayaran(),
        ),
        profilUsahaProvider.overrideWith(
          (_) async => const ProfilUsaha(nama: 'Laundry Uji'),
        ),
        metodePembayaranProvider.overrideWith((_) async => ['TUNAI', 'QRIS']),
        activeManifestProvider.overrideWith(() => _ManifestPalsu(alur)),
        pesananRepositoryProvider.overrideWithValue(repo),
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
          home: const Scaffold(body: CartSheet()),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Lanjut ke pembayaran'));
    await t.pumpAndSettle();
    return c;
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
