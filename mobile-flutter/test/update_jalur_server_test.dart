// Jalur pembaruan setelah server MOVERA mengenal rilis Flutter (9 Sep 2026):
// server jadi sumber utama, GitHub tinggal cadangan — termasuk saat berkas yang
// diiklankan server tidak cocok dengan ABI perangkat (server hanya mengiklankan
// arm64-v8a, sementara ponsel 32-bit butuh armeabi-v7a).

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/features/update/data/datasources/github_release_source.dart';
import 'package:tuleh_pos/features/update/data/datasources/update_remote_datasource.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.jawab);
  final ResponseBody Function(RequestOptions o) jawab;
  final permintaan = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? s, Future<void>? c) async {
    permintaan.add(o);
    return jawab(o);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, [int status = 200]) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
);

/// Jawaban `/app/versi` seperti produksi (disalin dari server sungguhan).
Map<String, dynamic> _jawabanServer({
  bool tersedia = true,
  bool wajib = false,
  String nama = 'Tuleh-2.24.0-arm64-v8a.apk',
}) => {
  'success': true,
  'data': {
    'wajib': wajib,
    'update_tersedia': tersedia,
    'versi_terbaru': '2.24.0',
    'versi_minimum': null,
    'catatan': null,
    'unduhan': {
      'windows': null,
      'android': {
        'nama': nama,
        'url': 'https://pos.tatreport.com/unduh/$nama',
        'ukuran': 36157770,
      },
    },
    'jalur': 'flutter',
  },
  'meta': null,
  'message': '',
  'errors': null,
};

/// Rilis GitHub dengan aset lengkap per ABI (sumber cadangan).
final _rilisGithub = [
  {
    'tag_name': 'flutter-v2.24.0',
    'draft': false,
    'prerelease': false,
    'body': '- perbaikan pemindai',
    'assets': [
      for (final abi in ['arm64-v8a', 'armeabi-v7a', 'x86_64'])
        {
          'name': 'Tuleh-2.24.0-$abi.apk',
          'size': 30000000,
          'browser_download_url':
              'https://github.com/dedeez14/tuleh/releases/download/flutter-v2.24.0/Tuleh-2.24.0-$abi.apk',
        },
    ],
  },
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Adapter server;
  late _Adapter github;

  UpdateRemoteDataSource sumber(Map<String, dynamic> jawaban) {
    server = _Adapter((_) => _json(jawaban));
    github = _Adapter((_) => _json(_rilisGithub));
    final dioServer = Dio(BaseOptions(baseUrl: 'https://tatreport.com/api/pos/v1', validateStatus: (_) => true))
      ..httpClientAdapter = server;
    final dioGithub = Dio(BaseOptions(validateStatus: (_) => true))..httpClientAdapter = github;
    return UpdateRemoteDataSource(dioServer, github: GithubReleaseSource(dio: dioGithub));
  }

  test('bertanya ke server dengan platform=android-flutter', () async {
    final s = sumber(_jawabanServer());
    await s.cek('2.20.0', abiPerangkat: const ['arm64-v8a']);
    final o = server.permintaan.single;
    expect(o.path, '/app/versi');
    expect(o.queryParameters['versi'], '2.20.0');
    expect(o.queryParameters['platform'], 'android-flutter');
  });

  test('perangkat arm64: pakai berkas server apa adanya, GitHub tak disentuh', () async {
    final s = sumber(_jawabanServer());
    final info = await s.cek('2.20.0', abiPerangkat: const ['arm64-v8a', 'armeabi-v7a']);
    expect(info.updateTersedia, isTrue);
    expect(info.versiTerbaru, '2.24.0');
    expect(info.androidUrl, 'https://pos.tatreport.com/unduh/Tuleh-2.24.0-arm64-v8a.apk');
    expect(info.ukuran, 36157770);
    expect(github.permintaan, isEmpty, reason: 'server sudah cukup');
  });

  test('ponsel 32-bit: ABI pada URL server ditukar ke armeabi-v7a', () async {
    final s = sumber(_jawabanServer());
    final info = await s.cek('2.20.0', abiPerangkat: const ['armeabi-v7a']);
    expect(info.androidNama, 'Tuleh-2.24.0-armeabi-v7a.apk');
    expect(info.androidUrl, 'https://pos.tatreport.com/unduh/Tuleh-2.24.0-armeabi-v7a.apk');
    expect(info.ukuran, isNull, reason: 'ukuran milik berkas arm64, jangan dipakai');
    expect(info.hasAndroidDownload, isTrue);
    expect(github.permintaan, isEmpty);
  });

  test('ABI asing: jatuh ke aset GitHub, tetapi "wajib" dari server dipertahankan', () async {
    final s = sumber(_jawabanServer(wajib: true));
    final info = await s.cek('2.20.0', abiPerangkat: const ['mips']);
    expect(github.permintaan, isNotEmpty, reason: 'server tak punya varian yang cocok');
    expect(info.wajib, isTrue, reason: 'hanya server yang boleh mewajibkan');
    expect(info.androidUrl, contains('github.com/dedeez14/tuleh/releases/download/'));
    expect(info.hasAndroidDownload, isTrue);
  });

  test('server bilang tidak ada pembaruan: GitHub dipakai sebagai cadangan', () async {
    final s = sumber(_jawabanServer(tersedia: false));
    final info = await s.cek('2.20.0', abiPerangkat: const ['arm64-v8a']);
    expect(github.permintaan, isNotEmpty);
    expect(info.versiTerbaru, '2.24.0');
    expect(info.androidUrl, contains('github.com'));
  });

  test('server tak terjangkau: fail-open, tidak melempar', () async {
    server = _Adapter((o) => throw DioException.connectionError(requestOptions: o, reason: 'x'));
    github = _Adapter((_) => _json(<dynamic>[]));
    final dioServer = Dio(BaseOptions(baseUrl: 'https://tatreport.com/api/pos/v1', validateStatus: (_) => true))
      ..httpClientAdapter = server;
    final dioGithub = Dio(BaseOptions(validateStatus: (_) => true))..httpClientAdapter = github;
    final s = UpdateRemoteDataSource(dioServer, github: GithubReleaseSource(dio: dioGithub));

    final info = await s.cek('2.20.0', abiPerangkat: const ['arm64-v8a']);
    expect(info.updateTersedia, isFalse);
    expect(info.wajib, isFalse);
  });
}
