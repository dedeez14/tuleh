// Uji kering pemeriksa pembaruan terhadap SALINAN NYATA jawaban GitHub
// Releases repo ini (test/data/releases_github.json, ditarik 8 Sep 2026).
//
// Tujuannya menangkap perubahan bentuk data yang membuat pembaruan Android
// diam-diam berhenti bekerja — mis. desktop v0.9.x ikut terpilih, aset per-ABI
// salah dipasangkan, atau catatan rilis kosong di banner.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/features/update/data/datasources/github_release_source.dart';
import 'package:tuleh_pos/features/update/domain/versi.dart';

List<dynamic> _rilis() {
  final f = File('test/data/releases_github.json');
  return jsonDecode(f.readAsStringSync()) as List<dynamic>;
}

void main() {
  late List<dynamic> rilis;

  setUpAll(() => rilis = _rilis());

  test('data uji memuat rilis desktop dan Flutter sekaligus', () {
    final tag = [for (final r in rilis) (r as Map)['tag_name'].toString()];
    expect(tag, contains('flutter-v2.19.0'));
    expect(tag, contains('v0.9.23'), reason: 'rilis desktop ikut di feed yang sama');
  });

  test('dari 2.17.0 menawarkan Flutter terbaru, bukan rilis desktop', () {
    final info = GithubReleaseSource.pilih(
      rilis,
      Versi.parse('2.17.0')!,
      abiPerangkat: const ['arm64-v8a'],
    );
    expect(info, isNotNull);
    expect(info!.versiTerbaru, '2.19.0');
    expect(info.androidNama, 'Tuleh-2.19.0-arm64-v8a.apk');
    expect(info.androidUrl, contains('/releases/download/flutter-v2.19.0/'));
    expect(info.ukuran, greaterThan(20 * 1024 * 1024), reason: 'APK per-ABI ± 30 MB');
    expect(info.wajib, isFalse);
    expect(info.catatan, isNotEmpty, reason: 'banner memerlukan ringkasan catatan');
  });

  test('ABI perangkat menentukan aset yang ditawarkan', () {
    for (final (abi, nama) in [
      ('armeabi-v7a', 'Tuleh-2.19.0-armeabi-v7a.apk'),
      ('x86_64', 'Tuleh-2.19.0-x86_64.apk'),
      ('arm64-v8a', 'Tuleh-2.19.0-arm64-v8a.apk'),
    ]) {
      final info = GithubReleaseSource.pilih(
        rilis,
        Versi.parse('2.10.0')!,
        abiPerangkat: [abi],
      );
      expect(info?.androidNama, nama, reason: 'ABI $abi');
    }
  });

  test('ABI tak dikenal jatuh ke arm64 (ponsel Android 10+ umumnya arm64)', () {
    final info = GithubReleaseSource.pilih(
      rilis,
      Versi.parse('2.10.0')!,
      abiPerangkat: const ['mips'],
    );
    expect(info?.androidNama, 'Tuleh-2.19.0-arm64-v8a.apk');
  });

  test('sudah di versi terbaru → tidak ada tawaran pembaruan', () {
    expect(
      GithubReleaseSource.pilih(
        rilis,
        Versi.parse('2.19.0')!,
        abiPerangkat: const ['arm64-v8a'],
      ),
      isNull,
    );
    expect(
      GithubReleaseSource.pilih(
        rilis,
        Versi.parse('9.9.9')!,
        abiPerangkat: const ['arm64-v8a'],
      ),
      isNull,
      reason: 'versi lokal lebih tinggi (build uji) tidak diturunkan',
    );
  });

  test('semua URL unduhan berasal dari host rilis GitHub', () {
    final info = GithubReleaseSource.pilih(
      rilis,
      Versi.parse('2.0.0')!,
      abiPerangkat: const ['arm64-v8a'],
    );
    expect(info!.androidUrl, startsWith('https://github.com/dedeez14/tuleh/releases/download/'));
  });
}
