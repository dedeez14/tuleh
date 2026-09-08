// Cetak struk otomatis setelah pembayaran (2.18.0) — padanan preferensi
// printer desktop 0.9.22.

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/storage/secure_storage.dart';
import 'package:tuleh_pos/core/theme/app_theme.dart';
import 'package:tuleh_pos/features/cetak/data/printer_service.dart';
import 'package:tuleh_pos/features/cetak/domain/entities/struk.dart';
import 'package:tuleh_pos/features/cetak/presentation/providers/printer_providers.dart';
import 'package:tuleh_pos/features/kasir/presentation/widgets/hasil_transaksi_sheet.dart';

class _Storage extends SecureStorage {
  _Storage([Map<String, String>? awal]) : super(const FlutterSecureStorage()) {
    if (awal != null) m.addAll(awal);
  }
  final Map<String, String> m = {};
  @override
  Future<String?> bacaNilai(String k) async => m[k];
  @override
  Future<void> tulisNilai(String k, String? v) async =>
      v == null ? m.remove(k) : m[k] = v;
}

/// Printer palsu: mencatat struk yang dikirim, tanpa Bluetooth.
class _PrinterPalsu implements PrinterService {
  final dicetak = <Struk>[];

  @override
  Future<void> cetak(
    Struk struk, {
    required PrinterTersimpan printer,
    PaperSize lebar = PaperSize.mm58,
  }) async => dicetak.add(struk);

  @override
  Future<List<PrinterTersimpan>> daftarPrinter() async => const [];

  @override
  Future<void> putuskan() async {}

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const _printer = PrinterTersimpan(nama: 'RPP02', mac: '00:11:22:33:44:55');

final _struk = Struk(
  namaToko: 'Minimarket Demo',
  nomor: 'TRX/0051',
  waktu: DateTime(2026, 9, 8, 14, 5),
  baris: const [StrukBaris(nama: 'Kopi Susu', kuantitas: 1, harga: 18000)],
  total: 18000,
  metode: 'TUNAI',
  dibayar: 20000,
  kembalian: 2000,
);

Future<void> _pompa(WidgetTester t, [int kali = 12]) async {
  for (var i = 0; i < kali; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  group('PrinterTerpilih', () {
    test('cetakOtomatis butuh printer terpilih', () {
      expect(const PrinterTerpilih(otomatis: true).cetakOtomatis, isFalse);
      expect(
        const PrinterTerpilih(printer: _printer, otomatis: true).cetakOtomatis,
        isTrue,
      );
      expect(
        const PrinterTerpilih(printer: _printer).cetakOtomatis,
        isFalse,
        reason: 'bawaan mati',
      );
    });

    test('preferensi dibaca & disimpan lewat penyimpanan aman', () async {
      final s = _Storage({
        'printer_mac': _printer.mac,
        'printer_nama': _printer.nama,
        'printer_lebar': '80',
        'printer_otomatis': '1',
      });
      final c = ProviderContainer(
        overrides: [secureStorageProvider.overrideWithValue(s)],
      );
      addTearDown(c.dispose);

      final awal = await c.read(printerTerpilihProvider.future);
      expect(awal.printer?.mac, _printer.mac);
      expect(awal.lebar, PaperSize.mm80);
      expect(awal.otomatis, isTrue);

      await c.read(printerTerpilihProvider.notifier).aturOtomatis(false);
      expect(s.m['printer_otomatis'], '0');
      expect(c.read(printerTerpilihProvider).valueOrNull?.otomatis, isFalse);

      await c.read(printerTerpilihProvider.notifier).aturOtomatis(true);
      expect(s.m['printer_otomatis'], '1');
    });

    test('tanpa preferensi tersimpan: cetak otomatis mati', () async {
      final c = ProviderContainer(
        overrides: [secureStorageProvider.overrideWithValue(_Storage())],
      );
      addTearDown(c.dispose);
      final p = await c.read(printerTerpilihProvider.future);
      expect(p.otomatis, isFalse);
      expect(p.cetakOtomatis, isFalse);
    });
  });

  group('Lembar hasil transaksi', () {
    Future<(ProviderContainer, _PrinterPalsu)> wadah({
      required bool otomatis,
      bool adaPrinter = true,
    }) async {
      final palsu = _PrinterPalsu();
      final c = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(
            _Storage({
              if (adaPrinter) 'printer_mac': _printer.mac,
              if (adaPrinter) 'printer_nama': _printer.nama,
              'printer_otomatis': otomatis ? '1' : '0',
            }),
          ),
          printerServiceProvider.overrideWithValue(palsu),
        ],
      );
      addTearDown(c.dispose);
      await c.read(printerTerpilihProvider.future);
      return (c, palsu);
    }

    Widget app(ProviderContainer c) => UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: HasilTransaksiSheet(struk: _struk, kembalian: 2000),
        ),
      ),
    );

    testWidgets('cetak otomatis nyala: struk dikirim tanpa ketukan', (t) async {
      final (c, palsu) = await wadah(otomatis: true);
      await t.pumpWidget(app(c));
      await _pompa(t);
      expect(palsu.dicetak.single.nomor, 'TRX/0051');
    });

    testWidgets('cetak otomatis mati: menunggu tombol Cetak', (t) async {
      final (c, palsu) = await wadah(otomatis: false);
      await t.pumpWidget(app(c));
      await _pompa(t);
      expect(palsu.dicetak, isEmpty);

      final tombol = find.textContaining('Cetak');
      expect(tombol, findsWidgets);
      await t.ensureVisible(tombol.first);
      await _pompa(t);
      await t.tap(tombol.first);
      await _pompa(t);
      expect(palsu.dicetak.single.nomor, 'TRX/0051');
    });

    testWidgets('otomatis nyala tanpa printer: tidak ada cetak & tanpa dialog', (t) async {
      final (c, palsu) = await wadah(otomatis: true, adaPrinter: false);
      await t.pumpWidget(app(c));
      await _pompa(t);
      expect(palsu.dicetak, isEmpty);
      expect(find.text('Printer belum dipilih'), findsNothing,
          reason: 'jangan mengganggu kasir dengan dialog otomatis');
    });
  });
}
