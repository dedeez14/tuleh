import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tuleh_pos/core/storage/secure_storage.dart';
import 'package:tuleh_pos/core/theme/app_theme.dart';
import 'package:tuleh_pos/core/utils/rupiah_input.dart';
import 'package:tuleh_pos/features/auth/presentation/controllers/auth_controller.dart';
import 'package:tuleh_pos/features/cetak/data/logo_struk.dart';
import 'package:tuleh_pos/features/cetak/data/printer_service.dart';
import 'package:tuleh_pos/features/cetak/data/struk_esc_pos.dart';
import 'package:tuleh_pos/features/cetak/domain/entities/struk.dart';
import 'package:tuleh_pos/features/kasir/presentation/controllers/cart_controller.dart';
import 'package:tuleh_pos/features/kasir/presentation/widgets/cart_sheet.dart';
import 'package:tuleh_pos/features/pengaturan/data/datasources/pengaturan_remote_datasource.dart';
import 'package:tuleh_pos/features/pengaturan/domain/entities/pengaturan_pembayaran.dart';
import 'package:tuleh_pos/features/pengaturan/presentation/providers/pengaturan_providers.dart';
import 'package:tuleh_pos/features/products/domain/entities/product.dart';
import 'package:tuleh_pos/features/toko/presentation/providers/toko_providers.dart';
import 'helpers/masa_coba_palsu.dart';
import 'package:tuleh_pos/features/demo/data/masa_coba_service.dart';

/// Alur bayar di kasir — temuan uji lapangan 4 Sep 2026 dengan akun sungguhan:
/// 1. kolom uang tanpa pemisah ribuan menyulitkan kasir;
/// 2. Bayar tunai bisa ditekan tanpa mengisi uang diterima;
/// 3. "items.0.id_produk harus bilangan bulat" — item Mode Demo tertinggal di
///    keranjang setelah masuk akun sungguhan;
/// 4. QRIS statis, rekening, dan logo struk yang diatur di desktop tak tampil.

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

const _produk = Product(id: 'MIN-003', nama: 'Teh Hangat', harga: 4000);

TextEditingValue _ketik(String teks) => TextEditingValue(
  text: teks,
  selection: TextSelection.collapsed(offset: teks.length),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('format Rupiah pada kolom uang', () {
    const f = RupiahInputFormatter();

    test('50000 → 50.000, kursor di akhir', () {
      final v = f.formatEditUpdate(const TextEditingValue(), _ketik('50000'));
      expect(v.text, '50.000');
      expect(v.selection.baseOffset, 6);
    });

    test('mengetik bertahap tetap rapi: 1 → 12 → 123 → 1.234 → 12.345', () {
      var v = const TextEditingValue();
      final tampil = <String>[];
      for (final d in ['1', '12', '123', '1234', '12345']) {
        v = f.formatEditUpdate(v, _ketik(d));
        tampil.add(v.text);
      }
      expect(tampil, ['1', '12', '123', '1.234', '12.345']);
    });

    test('huruf & nol di depan dibuang; kosong tetap kosong', () {
      expect(f.formatEditUpdate(const TextEditingValue(), _ketik('a5b')).text, '5');
      expect(f.formatEditUpdate(const TextEditingValue(), _ketik('007')).text, '7');
      expect(f.formatEditUpdate(const TextEditingValue(), _ketik('')).text, '');
    });

    test('parse membaca titik sebagai ribuan, bukan desimal', () {
      expect(parseRupiah('50.000'), 50000);
      expect(parseRupiah('Rp 1.250.000'), 1250000);
      expect(parseRupiah(''), 0);
      expect(parseRupiah(null), 0);
      expect(teksRupiah(1250000), '1.250.000');
      expect(teksRupiah(0), '0');
    });
  });

  group('keranjang dikosongkan saat konteks berganti', () {
    late ProviderContainer c;

    setUp(() {
      c = ProviderContainer(
        overrides: [
        secureStorageProvider.overrideWithValue(_FakeStorage()),
        masaCobaServiceProvider.overrideWithValue(MasaCobaPalsu()),
        ...overrideOffline(),
      ],
      );
      // Aktifkan listener (Notifier dibangun saat pertama dibaca).
      c.read(cartControllerProvider);
    });
    tearDown(() => c.dispose());

    test('ganti toko → keranjang kosong', () async {
      await c.read(activeTokoIdProvider.future);
      await c.read(activeTokoIdProvider.notifier).select('TOKO-1');
      c.read(cartControllerProvider.notifier).add(_produk);
      expect(c.read(cartControllerProvider), hasLength(1));

      await c.read(activeTokoIdProvider.notifier).select('TOKO-2');
      await Future<void>.delayed(Duration.zero);
      expect(c.read(cartControllerProvider), isEmpty);
    });

    test('keluar akun (mis. dari Mode Demo) → keranjang kosong', () async {
      await c.read(authControllerProvider.future);
      c.read(cartControllerProvider.notifier).add(_produk);
      expect(c.read(cartControllerProvider), hasLength(1));

      // Masuk demo lalu keluar: id pengguna berubah dua kali.
      await c.read(authControllerProvider.notifier).startDemo();
      await Future<void>.delayed(Duration.zero);
      expect(c.read(cartControllerProvider), isEmpty,
          reason: 'masuk akun lain harus mengosongkan');

      c.read(cartControllerProvider.notifier).add(_produk);
      await c.read(authControllerProvider.notifier).logout();
      await Future<void>.delayed(Duration.zero);
      expect(c.read(cartControllerProvider), isEmpty,
          reason: 'keluar harus mengosongkan');
    });
  });

  group('lembar bayar', () {
    Future<ProviderContainer> pumpBayar(
      WidgetTester t, {
      PengaturanPembayaran pembayaran = const PengaturanPembayaran(),
    }) async {
      final c = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(_FakeStorage()),
          masaCobaServiceProvider.overrideWithValue(MasaCobaPalsu()),
        ...overrideOffline(),
          pengaturanPembayaranProvider.overrideWith((_) async => pembayaran),
        ],
      );
      addTearDown(c.dispose);
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
      await t.pumpAndSettle();
      await t.tap(find.text('Lanjut ke pembayaran'));
      await t.pumpAndSettle();
      return c;
    }

    FilledButton tombolBayar(WidgetTester t) => t.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Bayar Rp 4.000'),
    );

    testWidgets('tunai: Bayar terkunci sampai uang diterima cukup', (t) async {
      await pumpBayar(t);
      expect(tombolBayar(t).onPressed, isNull);
      expect(find.text('Isi uang diterima dulu'), findsOneWidget);

      await t.enterText(find.byType(TextField), '3000');
      await t.pumpAndSettle();
      expect(find.text('3.000'), findsOneWidget, reason: 'format ribuan');
      expect(tombolBayar(t).onPressed, isNull, reason: 'kurang');
      expect(find.text('Kurang'), findsOneWidget);

      await t.enterText(find.byType(TextField), '50000');
      await t.pumpAndSettle();
      expect(find.text('50.000'), findsOneWidget);
      expect(tombolBayar(t).onPressed, isNotNull);
      expect(find.text('Kembalian'), findsOneWidget);
      expect(find.text('Rp 46.000'), findsOneWidget);
    });

    testWidgets('chip "Uang pas" mengisi kolom dalam format ribuan', (t) async {
      await pumpBayar(t);
      await t.tap(find.text('Uang pas'));
      await t.pumpAndSettle();
      expect(t.widget<TextField>(find.byType(TextField)).controller!.text, '4.000');
      expect(tombolBayar(t).onPressed, isNotNull);
    });

    testWidgets('QRIS & TRANSFER menampilkan pengaturan pembayaran toko', (
      t,
    ) async {
      await pumpBayar(
        t,
        pembayaran: const PengaturanPembayaran(
          qrStatis: 'https://contoh.test/qris.png',
          bank: [
            RekeningBank(bank: 'BCA', rekening: '4280420510', atasNama: 'Dede'),
          ],
        ),
      );
      await t.tap(find.text('QRIS'));
      await t.pumpAndSettle();
      // Gambar QRIS toko dirender dari URL pengaturan (bukan QR nota).
      final gambar = t.widgetList<Image>(find.byType(Image)).where(
        (w) => w.image is NetworkImage &&
            (w.image as NetworkImage).url == 'https://contoh.test/qris.png',
      );
      expect(gambar, hasLength(1));
      expect(tombolBayar(t).onPressed, isNotNull, reason: 'non-tunai tak butuh nominal');

      await t.tap(find.text('TRANSFER'));
      await t.pumpAndSettle();
      expect(find.text('4280420510'), findsOneWidget);
      expect(find.textContaining('a.n. Dede'), findsOneWidget);
    });

    testWidgets('belum diatur → ajakan mengatur di desktop, bukan layar kosong', (
      t,
    ) async {
      await pumpBayar(t);
      await t.tap(find.text('QRIS'));
      await t.pumpAndSettle();
      expect(find.textContaining('QRIS statis belum diunggah'), findsOneWidget);
      await t.tap(find.text('TRANSFER'));
      await t.pumpAndSettle();
      expect(find.textContaining('Belum ada rekening'), findsOneWidget);
    });
  });

  group('logo struk', () {
    Dio dioPalsu(Map<String, dynamic> balasan) {
      final dio = Dio(BaseOptions(validateStatus: (_) => true));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) => h.resolve(
            Response(requestOptions: o, statusCode: 200, data: balasan),
          ),
        ),
      );
      return dio;
    }

    test('logo dibaca dari struk.logo (bentuk respons server sungguhan)', () async {
      final ds = PengaturanRemoteDataSource(
        dioPalsu({
          'success': true,
          'data': {
            'nama': 'Tuléh Demo Pelanggan',
            'logo': null,
            'struk': {
              'logo': 'https://tatreport.com/storage/pos/logo/347/x.png',
              'footer': null,
              'tampil_logo': true,
            },
          },
        }),
      );
      final p = await ds.profilUsaha();
      expect(p.logo, 'https://tatreport.com/storage/pos/logo/347/x.png');
      expect(p.strukTampilLogo, isTrue);

      final pb = await PengaturanRemoteDataSource(
        dioPalsu({
          'success': true,
          'data': {
            'qr_statis': 'https://tatreport.com/storage/pos/qr/347/q.png',
            'bank': [
              {'bank': 'BCA', 'rekening': '4280420510', 'atas_nama': 'Dede'},
            ],
            'midtrans_aktif': false,
          },
        }),
      ).pembayaran();
      expect(pb.qrStatis, endsWith('/q.png'));
      expect(pb.bank.single.rekening, '4280420510');
    });

    test('PNG transparan → bitmap putih-hitam selebar kertas', () {
      // Lingkaran hitam di atas latar transparan (kasus logo umum).
      final src = img.Image(width: 300, height: 100, numChannels: 4);
      img.fillCircle(src, x: 50, y: 50, radius: 30, color: img.ColorRgba8(0, 0, 0, 255));
      final bytes = Uint8List.fromList(img.encodePng(src));

      final bmp = LogoStruk.siapkan(bytes, lebarPx: 224)!;
      expect(bmp.width, 224);
      expect(bmp.height, inInclusiveRange(74, 75)); // rasio 3:1 dipertahankan
      // Latar transparan menjadi PUTIH, bukan hitam.
      expect(bmp.getPixel(220, 5).r, 255);
      // Isi lingkaran menjadi hitam.
      expect(bmp.getPixel(37, 37).r, 0);
      expect(LogoStruk.siapkan(Uint8List.fromList([1, 2, 3])), isNull);
    });

    test('struk dengan logo memuat perintah bit-image ESC *', () async {
      final logo = img.Image(width: 64, height: 16);
      img.fill(logo, color: img.ColorRgb8(255, 255, 255));
      final s = PrinterService.strukUji();
      final tanpa = await const StrukEscPos().bangun(s);
      final dengan = await const StrukEscPos().bangun(s, logo: logo);
      expect(dengan.length, greaterThan(tanpa.length));
      bool adaEscBintang(List<int> b) {
        for (var i = 0; i + 1 < b.length; i++) {
          if (b[i] == 0x1B && b[i + 1] == 0x2A) return true;
        }
        return false;
      }
      expect(adaEscBintang(dengan), isTrue);
      expect(adaEscBintang(tanpa), isFalse);
    });

    test('Struk membawa logoUrl untuk pratinjau & cetak', () {
      final s = Struk(
        namaToko: 'X',
        nomor: '1',
        waktu: DateTime(2026),
        baris: const [],
        total: 0,
        logoUrl: 'https://x/logo.png',
      );
      expect(s.logoUrl, 'https://x/logo.png');
    });
  });
}
