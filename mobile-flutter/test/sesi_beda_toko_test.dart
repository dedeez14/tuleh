// Tahap B §2a di Android: server menolak checkout ke toko selain toko sesi kasir (409 berkode).
// Kasir tak boleh cuma melihat pesan merah — tombol "Pindah ke <toko>" mengganti toko aktif.
//
// Id toko dari server adalah ciphertext non-deterministik (encrypt_id): id toko
// yang SAMA berbeda antara `/tokos` dan `meta.sesi_toko`. Pencocokan karena itu
// memakai `kode` (TK-xxx) lalu `nama`, tidak pernah id.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/network/api_exception.dart';
import 'package:tuleh_pos/core/offline/nomor_lokal.dart';
import 'package:tuleh_pos/core/offline/antrean.dart';
import 'package:tuleh_pos/core/storage/secure_storage.dart';
import 'package:tuleh_pos/core/theme/app_theme.dart';
import 'package:tuleh_pos/features/cetak/domain/entities/struk.dart';
import 'package:tuleh_pos/features/demo/data/masa_coba_service.dart';
import 'package:tuleh_pos/features/kasir/data/checkout_repository.dart';
import 'package:tuleh_pos/features/kasir/data/datasources/transaction_remote_datasource.dart';
import 'package:tuleh_pos/features/kasir/domain/entities/cart_item.dart';
import 'package:tuleh_pos/features/kasir/domain/galat_kasir.dart';
import 'package:tuleh_pos/features/kasir/presentation/controllers/cart_controller.dart';
import 'package:tuleh_pos/features/kasir/presentation/providers/checkout_providers.dart';
import 'package:tuleh_pos/features/kasir/presentation/widgets/cart_sheet.dart';
import 'package:tuleh_pos/features/pengaturan/domain/entities/pengaturan_pembayaran.dart';
import 'package:tuleh_pos/features/pengaturan/presentation/providers/pengaturan_providers.dart';
import 'package:tuleh_pos/features/products/domain/entities/product.dart';
import 'package:tuleh_pos/features/toko/domain/entities/toko.dart';
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
  Future<void> clearSession() async => _m.clear();
}

/// Toko aktif tiruan yang MENCATAT setiap pemilihan: inti pengujian ini adalah
/// id mana yang diserahkan ke `select()` — dan apakah ia dipanggil sama sekali.
class _TokoAktifPalsu extends ActiveTokoNotifier {
  _TokoAktifPalsu(this.dipilih);
  final List<String> dipilih;

  @override
  Future<String?> build() async => 'toko-aktif-sekarang';

  @override
  Future<void> select(String id) async {
    dipilih.add(id);
    state = AsyncData(id);
  }
}

/// Checkout yang selalu ditolak server dengan 409 SESI_BEDA_TOKO.
class _Checkout409 extends CheckoutRepository {
  _Checkout409(this.galat)
    : super(
        remote: TransactionRemoteDataSource(Dio()),
        antrean: AntreanMemori(),
        nomorLokal: NomorLokal(_Storage()),
      );

  final ApiException galat;

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
  }) async => throw galat;
}

const _produk = Product(id: 'MIN-003', nama: 'Teh Hangat', harga: 4000);

void main() {
  const beda = ApiException(
    message: 'Sesi kasir Anda dibuka di toko Toko Pusat. Pilih toko itu atau tutup sesi dulu.',
    statusCode: 409,
    errors: {'kode': ['SESI_BEDA_TOKO']},
    meta: {'sesi_toko': {'id': 'T1', 'nama': 'Toko Pusat'}},
  );

  test('kodeGalat & tokoSesi membaca amplop 409 server', () {
    expect(kodeGalat(beda), 'SESI_BEDA_TOKO');
    expect(tokoSesi(beda)?.id, 'T1');
    expect(tokoSesi(beda)?.nama, 'Toko Pusat');
    expect(tokoSesi(beda)?.kode, isNull, reason: 'server lama belum mengirim kode');
  });

  test('409 lama (belum ada sesi) tidak dikira beda toko', () {
    const lama = ApiException(message: 'Belum ada sesi kasir yang terbuka.', statusCode: 409);
    expect(kodeGalat(lama), '');
    expect(tokoSesi(lama), isNull);
  });

  test('meta tanpa id diabaikan (server lama) — tombol pindah tak ditawarkan', () {
    const separuh = ApiException(message: 'x', statusCode: 409, errors: {'kode': ['SESI_BEDA_TOKO']}, meta: {'sesi_toko': {'nama': 'Toko Pusat'}});
    expect(tokoSesi(separuh), isNull);
  });

  test('kode toko ikut terbaca bila server mengirimnya', () {
    const berkode = ApiException(
      message: 'x',
      statusCode: 409,
      errors: {'kode': ['SESI_BEDA_TOKO']},
      meta: {'sesi_toko': {'id': 'T9', 'nama': 'Toko Pusat', 'kode': 'TK-001'}},
    );
    expect(tokoSesi(berkode)?.kode, 'TK-001');
  });

  group('pilihTokoSesi', () {
    const pusat = Toko(id: 'enc-a', nama: 'Toko Pusat', kode: 'TK-001');
    const cabang = Toko(id: 'enc-b', nama: 'Cabang Dago', kode: 'TK-002');

    test('cocok lewat kode walau id-nya berbeda (ciphertext acak)', () {
      const sesi = TokoSesi(id: 'ciphertext-lain', nama: 'Nama Lama', kode: 'TK-002');
      expect(pilihTokoSesi(const [pusat, cabang], sesi), cabang);
    });

    test('tanpa kode: jatuh ke nama, tanpa peduli spasi & huruf besar', () {
      const sesi = TokoSesi(id: 'z', nama: '  toko PUSAT ');
      expect(pilihTokoSesi(const [pusat, cabang], sesi), pusat);
    });

    test('daftar belum berkode (server lama): nama tetap dipakai', () {
      const lama = Toko(id: 'enc-c', nama: 'Toko Pusat');
      const sesi = TokoSesi(id: 'z', nama: 'Toko Pusat', kode: 'TK-001');
      expect(pilihTokoSesi(const [lama], sesi), lama);
    });

    test('tak ada yang cocok → null (pemanggil pakai id dari amplop 409)', () {
      const sesi = TokoSesi(id: 'z', nama: 'Toko Gudang', kode: 'TK-009');
      expect(pilihTokoSesi(const [pusat, cabang], sesi), isNull);
      expect(pilihTokoSesi(const [], sesi), isNull);
    });

    test('kedua sisi berkode tapi beda: nama senama tidak dianggap cocok', () {
      const sesi = TokoSesi(id: 'z', nama: 'Toko Pusat', kode: 'TK-077');
      expect(pilihTokoSesi(const [pusat, cabang], sesi), isNull);
    });
  });

  // Yang diuji di sini: id mana yang sampai ke `select()`. Id pada amplop 409
  // adalah ciphertext non-deterministik — memakainya sebagai toko aktif hanya
  // klaim kosong: Beranda (cabang yang hidup berdampingan dengan kasir)
  // menyetel ulang toko aktif ke toko pertama dalam satu frame, dan checkout
  // berikutnya ditolak 409 lagi.
  group('keranjang menghadapi 409 SESI_BEDA_TOKO', () {
    const pusat = Toko(id: 'enc-daftar-a', nama: 'Toko Pusat', kode: 'TK-001');

    /// Pompa berbatas — bukan pumpAndSettle: lembar memakai animasi berulang.
    Future<void> pompa(WidgetTester t) async {
      for (var i = 0; i < 12; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    /// Bayar tunai satu item lalu kembalikan id toko yang sempat dipilih.
    Future<List<String>> bayarDitolak(
      WidgetTester t, {
      required List<Toko> daftar,
      required ApiException galat,
    }) async {
      t.view.physicalSize = const Size(420, 900);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);

      final dipilih = <String>[];
      final c = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(_Storage()),
          masaCobaServiceProvider.overrideWithValue(MasaCobaPalsu()),
          ...overrideOffline(),
          tokoListProvider.overrideWith((_) async => daftar),
          activeTokoIdProvider.overrideWith(() => _TokoAktifPalsu(dipilih)),
          metodePembayaranProvider.overrideWith((_) async => const ['TUNAI']),
          // Tanpa ini lembar menunggu jawaban jaringan yang tak pernah datang.
          pengaturanPembayaranProvider.overrideWith((_) async => const PengaturanPembayaran()),
          checkoutRepositoryProvider.overrideWithValue(_Checkout409(galat)),
        ],
      );
      addTearDown(c.dispose);
      // Keranjang dikosongkan tiap toko aktif berganti — item baru sah ditaruh
      // setelah toko aktif selesai dimuat.
      c.read(cartControllerProvider);
      await c.read(activeTokoIdProvider.future);
      await c.read(tokoListProvider.future);
      c.read(cartControllerProvider.notifier).add(_produk);

      await t.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CartSheet()),
          ),
        ),
      );
      await pompa(t);
      await t.tap(find.text('Lanjut ke pembayaran'));
      await pompa(t);
      await t.enterText(find.byType(TextField), '50000');
      await pompa(t);
      await t.tap(find.widgetWithText(FilledButton, 'Bayar Rp 4.000'));
      await pompa(t);
      return dipilih;
    }

    const pesanServer =
        'Sesi kasir Anda dibuka di toko Toko Pusat. Pilih toko itu atau tutup sesi dulu.';
    const galatBerkode = ApiException(
      message: pesanServer,
      statusCode: 409,
      errors: {'kode': ['SESI_BEDA_TOKO']},
      meta: {'sesi_toko': {'id': 'ciphertext-409', 'kode': 'TK-001', 'nama': 'Toko Pusat'}},
    );

    testWidgets('toko sesi ADA di daftar → pindah memakai id daftar', (t) async {
      final dipilih = await bayarDitolak(t, daftar: const [pusat], galat: galatBerkode);
      expect(find.text(pesanServer), findsOneWidget);
      expect(dipilih, isEmpty, reason: 'baru berpindah setelah kasir menekan tombolnya');

      await t.tap(find.widgetWithText(SnackBarAction, 'Pindah ke Toko Pusat'));
      await pompa(t);
      expect(dipilih, ['enc-daftar-a'], reason: 'id dari /tokos, bukan dari amplop 409');
      await t.pump(const Duration(seconds: 5));
    });

    testWidgets('toko sesi TIDAK ada di daftar → tanpa tombol pindah, tanpa select()', (t) async {
      final dipilih = await bayarDitolak(
        t,
        daftar: const [Toko(id: 'enc-daftar-b', nama: 'Cabang Dago', kode: 'TK-002')],
        galat: galatBerkode,
      );
      expect(find.text(pesanServer), findsOneWidget, reason: 'kalimat server apa adanya');
      expect(find.textContaining('Pindah ke'), findsNothing);
      expect(dipilih, isEmpty, reason: 'id amplop 409 tak boleh dipakai sebagai toko aktif');
      await t.pump(const Duration(seconds: 5));
    });

    testWidgets('SESI_BEDA_TOKO tanpa meta.sesi_toko: tak menawarkan "Buka sesi"', (t) async {
      // Server lama (atau amplop tanpa id toko sesi) → tak ada yang bisa
      // dicocokkan. "Buka sesi" bukan jalan keluarnya: sesi kasir memang sudah
      // terbuka, hanya di toko lain, jadi server menolaknya dengan alasan yang
      // sama persis.
      final dipilih = await bayarDitolak(
        t,
        daftar: const [pusat],
        galat: const ApiException(
          message: pesanServer,
          statusCode: 409,
          errors: {'kode': ['SESI_BEDA_TOKO']},
        ),
      );
      expect(find.text(pesanServer), findsOneWidget);
      expect(find.widgetWithText(SnackBarAction, 'Buka sesi'), findsNothing);
      expect(find.textContaining('Pindah ke'), findsNothing);
      expect(dipilih, isEmpty);
      await t.pump(const Duration(seconds: 5));
    });

    testWidgets('409 tanpa kode (belum ada sesi) tetap menawarkan "Buka sesi"', (t) async {
      final dipilih = await bayarDitolak(
        t,
        daftar: const [pusat],
        galat: const ApiException(message: 'Belum ada sesi kasir yang terbuka.', statusCode: 409),
      );
      expect(find.widgetWithText(SnackBarAction, 'Buka sesi'), findsOneWidget);
      expect(dipilih, isEmpty);
      await t.pump(const Duration(seconds: 5));
    });
  });
}
