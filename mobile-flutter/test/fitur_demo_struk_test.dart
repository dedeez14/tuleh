import 'dart:convert';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/storage/secure_storage.dart';
import 'package:tuleh_pos/core/theme/tema_provider.dart';
import 'package:tuleh_pos/features/cetak/data/struk_esc_pos.dart';
import 'package:tuleh_pos/features/cetak/data/struk_teks.dart';
import 'package:tuleh_pos/features/cetak/domain/entities/struk.dart';
import 'package:tuleh_pos/features/demo/data/demo_engine.dart';

/// Batasan Mode Demo & aksi struk (2.10.0):
/// - struk demo bertanda "MODE DEMO" di teks bagikan, ESC/POS, dan JSON;
/// - mesin demo menolak checkout ke-21 pada hari yang sama;
/// - pilihan tampilan (tema) tersimpan di perangkat.

class _Storage extends SecureStorage {
  _Storage() : super(const FlutterSecureStorage());
  final Map<String, String> m = {};
  @override
  Future<String?> bacaNilai(String k) async => m[k];
  @override
  Future<void> tulisNilai(String k, String? v) async => v == null ? m.remove(k) : m[k] = v;
}

Struk _struk({bool demo = false}) => Struk(
  namaToko: 'Warung Kopi Tuléh',
  alamat: 'Jl. Melati No. 5, Bandung',
  telepon: '0812-0000-1111',
  nomor: '26-POS-000041',
  waktu: DateTime(2026, 9, 6, 14, 5),
  kasir: 'Dede',
  baris: const [
    StrukBaris(nama: 'Kopi Susu Gula Aren Spesial Ukuran Besar', kuantitas: 2, harga: 18000),
    StrukBaris(nama: 'Roti Bakar', kuantitas: 1, harga: 15000),
  ],
  total: 51000,
  metode: 'TUNAI',
  dibayar: 100000,
  kembalian: 49000,
  demo: demo,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('StrukTeks', () {
    test('lebar 32 kolom, nilai rata kanan, nama panjang dibungkus per kata', () {
      final teks = const StrukTeks().bangun(_struk());
      final baris = teks.split('\n');
      for (final b in baris) {
        expect(b.length, lessThanOrEqualTo(32), reason: 'baris: "$b"');
      }
      expect(baris.first.trim(), 'WARUNG KOPI TULÉH');
      expect(teks, contains('No                 26-POS-000041'));
      expect(teks, contains('TOTAL                  Rp 51.000'));
      expect(teks, contains('Kembali                Rp 49.000'));
      expect(teks, contains('Kopi Susu Gula Aren Spesial'));
      expect(teks, contains('  2 x Rp 18.000        Rp 36.000'));
      expect(teks, isNot(contains('MODE DEMO')));
      expect(teks.trim(), endsWith('Terima kasih atas kunjungan Anda'));
    });

    test('struk demo bertanda di kepala dan kaki', () {
      final teks = const StrukTeks().bangun(_struk(demo: true));
      expect(teks.split('\n').first.trim(), StrukTeks.tandaDemo);
      expect(teks.trim(), endsWith(StrukTeks.tandaDemo));
    });
  });

  group('Struk demo', () {
    test('toJson/fromJson & salinDengan mempertahankan tanda demo', () {
      final s = _struk(demo: true);
      final ulang = Struk.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
      expect(ulang.demo, isTrue);
      expect(ulang.salinDengan(nomor: 'X').demo, isTrue);
      expect(Struk.fromJson(_struk().toJson()).demo, isFalse);
    });

    test('ESC/POS memuat tanda MODE DEMO hanya untuk struk demo', () async {
      final demo = await const StrukEscPos(lebar: PaperSize.mm58).bangun(_struk(demo: true));
      final asli = await const StrukEscPos(lebar: PaperSize.mm58).bangun(_struk());
      expect(latin1.decode(demo, allowInvalid: true), contains('MODE DEMO'));
      expect(latin1.decode(demo, allowInvalid: true), contains('Bukan bukti pembayaran'));
      expect(latin1.decode(asli, allowInvalid: true), isNot(contains('MODE DEMO')));
    });
  });

  group('DemoEngine batas transaksi', () {
    test('checkout ke-${DemoEngine.batasTransaksiPerHari + 1} pada hari yang sama ditolak dengan pesan jelas', () {
      final engine = DemoEngine();
      const toko = {'toko_id': 'TOKO-1'};
      final produk = (engine.handle(method: 'GET', path: '/produk', query: toko).body['data'] as List).first as Map;
      DemoResponse bayar() => engine.handle(
        method: 'POST',
        path: '/transaksi/checkout',
        query: toko,
        body: {
          'items': [{'id_produk': produk['id'], 'kuantitas': 1, 'harga': produk['harga_jual']}],
          'tipe_pembayaran': 'QRIS',
          'dibayar': produk['harga_jual'],
        },
      );
      for (var i = 0; i < DemoEngine.batasTransaksiPerHari; i++) {
        expect(bayar().body['success'], isTrue, reason: 'transaksi ke-${i + 1} harus diterima');
      }
      final tolak = bayar();
      expect(tolak.status, 422);
      expect(tolak.body['message'], DemoEngine.pesanBatasTransaksi);
      expect(tolak.body['message'], contains('20 transaksi per hari'));
    });
  });

  group('TemaNotifier', () {
    test('awal ikuti sistem; pilih() menyimpan; build() membaca yang tersimpan', () async {
      final storage = _Storage();
      final c = ProviderContainer(overrides: [secureStorageProvider.overrideWithValue(storage)]);
      addTearDown(c.dispose);
      expect(c.read(temaProvider), ThemeMode.system);
      await c.read(temaProvider.notifier).pilih(ThemeMode.dark);
      expect(c.read(temaProvider), ThemeMode.dark);
      expect(storage.m[TemaNotifier.kunci], 'dark');

      final c2 = ProviderContainer(overrides: [secureStorageProvider.overrideWithValue(storage)]);
      addTearDown(c2.dispose);
      c2.listen(temaProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);
      expect(c2.read(temaProvider), ThemeMode.dark);
      expect(labelTema(ThemeMode.dark), 'Gelap');
    });
  });
}
