// Penjaga aturan pemilik "tanpa hardcode" (spesifikasi kesiapan produksi
// 2026-09-15) dan pengerasan Android. Kontak, tautan WhatsApp/langganan,
// email, dan nama domain bisnis TIDAK boleh tertanam di lib/ — nilainya dari
// server (`/kontak-cs`, `/langganan/status`, `/app/versi`). Pengecualian hanya
// alamat API infrastruktur (AppConfig, bisa diganti --dart-define) dan data
// fiktif Mode Demo.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final lib = Directory('lib');

  Iterable<File> berkasDart() => lib
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !f.path.endsWith('.g.dart') && !f.path.endsWith('.freezed.dart'));

  test('lib/ tanpa nomor telepon, wa.me, email, atau tautan langganan tertanam', () {
    final pola = <String, RegExp>{
      'wa.me': RegExp(r'wa\.me/\d'),
      'api.whatsapp': RegExp(r'api\.whatsapp\.com'),
      'telepon +62/08': RegExp(r'''['"](\+?62|0)8\d{7,12}['"]'''),
      'email': RegExp(r'''['"][\w.+-]+@(?!contoh\.com|toko\.com)[\w-]+\.[\w.]+['"]'''),
      'tautan langganan': RegExp(r'tatreport\.com/langganan'),
      'domain tuleh.id': RegExp(r'tuleh\.id'),
    };
    // Data fiktif Mode Demo (pelanggan & barcode contoh) dan petunjuk isian.
    const dikecualikan = ['lib/features/demo/data/demo_data.dart'];
    final pelanggaran = <String>[];
    for (final f in berkasDart()) {
      final jalur = f.path.replaceAll('\\', '/');
      if (dikecualikan.any(jalur.endsWith)) continue;
      final baris = f.readAsLinesSync();
      for (var i = 0; i < baris.length; i++) {
        final teks = baris[i];
        if (teks.trimLeft().startsWith('//')) continue;
        pola.forEach((nama, re) {
          if (re.hasMatch(teks)) pelanggaran.add('$jalur:${i + 1} [$nama] ${teks.trim()}');
        });
      }
    }
    expect(pelanggaran, isEmpty, reason: pelanggaran.join('\n'));
  });

  test('ambang peringatan langganan tidak dikarang aplikasi', () {
    final isi = File('lib/features/langganan/domain/langganan.dart').readAsStringSync();
    expect(isi, contains("j['ambang_peringatan_hari']"));
    expect(RegExp(r'sisa\s*<=\s*\d').hasMatch(isi), isFalse);
  });

  group('AndroidManifest (pengerasan)', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    test('cadangan dimatikan & aturan ekstraksi data mengecualikan semuanya', () {
      expect(manifest, contains('android:allowBackup="false"'));
      expect(manifest, contains('android:dataExtractionRules="@xml/data_extraction_rules"'));
      expect(manifest, contains('android:fullBackupContent="@xml/backup_rules"'));
      final aturan = File('android/app/src/main/res/xml/data_extraction_rules.xml').readAsStringSync();
      expect(RegExp('<include').hasMatch(aturan), isFalse);
      expect(aturan, contains('<cloud-backup>'));
      expect(aturan, contains('<device-transfer>'));
    });

    test('RebootReceiver plugin tidak diekspor ke aplikasi lain', () {
      final blok = RegExp(r'<receiver[^>]*RebootReceiver[^>]*>', dotAll: true).firstMatch(manifest)?.group(0);
      expect(blok, isNotNull);
      expect(blok, contains('android:exported="false"'));
      expect(blok, contains('tools:replace="android:exported"'));
    });

    test('BLUETOOTH_SCAN dinyatakan neverForLocation', () {
      final blok = RegExp(r'<uses-permission[^>]*BLUETOOTH_SCAN[^>]*/>', dotAll: true).firstMatch(manifest)?.group(0);
      expect(blok, contains('android:usesPermissionFlags="neverForLocation"'));
    });
  });
}
