import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/features/update/data/services/apk_installer.dart';

/// Unduhan pembaruan lewat Dio (menggantikan DownloadManager sistem sebagai
/// jalur utama): mengikuti redirect GitHub, menulis berkas utuh dengan
/// progres, menolak berkas tak lengkap/HTTP gagal, bisa dibatalkan, dan
/// mendeteksi unduhan macet.

class _Server implements HttpClientAdapter {
  _Server(this.jawab);
  final Future<ResponseBody> Function(RequestOptions o) jawab;
  final List<String> log = [];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) {
    log.add(o.uri.toString());
    return jawab(o);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _bytes(List<int> data, {int status = 200, Map<String, List<String>>? headers}) =>
    ResponseBody(
      Stream.fromIterable([Uint8List.fromList(data)]),
      status,
      headers: {'content-length': ['${data.length}'], ...?headers},
    );

Dio _dio(_Server s) => Dio(BaseOptions(validateStatus: (_) => true, followRedirects: true))
  ..httpClientAdapter = s;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('tuleh-apk-'));
  tearDown(() async => dir.delete(recursive: true));

  final isi = List<int>.generate(4096, (i) => i % 251);

  test('unduh sukses: berkas utuh, progres sampai 100, tanpa sisa .part', () async {
    final server = _Server((o) async => _bytes(isi));
    final inst = ApkInstaller(dio: _dio(server));
    final progres = <int>[];
    final sub = inst.progress.listen(progres.add);
    final path = await inst.download(
      'https://github.com/dedeez14/tuleh/releases/download/flutter-v9.9.9/Tuleh-9.9.9-arm64-v8a.apk',
      filename: 'Tuleh-9.9.9-arm64-v8a.apk',
      ukuran: isi.length,
      direktori: dir.path,
    );
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(File(path).existsSync(), isTrue);
    expect(File(path).lengthSync(), isi.length);
    expect(File('$path.part').existsSync(), isFalse);
    expect(progres.last, 100);
  });

  test('ukuran tidak cocok → galat UKURAN, berkas dibuang', () async {
    final server = _Server((o) async => _bytes(isi.sublist(0, 1000)));
    final inst = ApkInstaller(dio: _dio(server));
    await expectLater(
      inst.download('https://github.com/x/y/releases/download/a/b.apk',
          filename: 'b.apk', ukuran: isi.length, direktori: dir.path),
      throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'UKURAN')),
    );
    expect(dir.listSync(), isEmpty);
  });

  test('HTTP 404 → galat HTTP dengan kodenya', () async {
    final server = _Server((o) async => _bytes([], status: 404));
    final inst = ApkInstaller(dio: _dio(server));
    await expectLater(
      inst.download('https://github.com/x/y/releases/download/a/b.apk',
          filename: 'b.apk', direktori: dir.path),
      throwsA(isA<PlatformException>()
          .having((e) => e.code, 'code', 'HTTP')
          .having((e) => e.message, 'pesan', contains('404'))),
    );
  });

  test('gagal jaringan → galat JARINGAN dengan sebab', () async {
    final server = _Server((o) async => throw DioException.connectionError(
      requestOptions: o, reason: 'Failed host lookup',
    ));
    final inst = ApkInstaller(dio: _dio(server));
    await expectLater(
      inst.download('https://github.com/x/y/releases/download/a/b.apk',
          filename: 'b.apk', direktori: dir.path),
      throwsA(isA<PlatformException>()
          .having((e) => e.code, 'code', 'JARINGAN')
          .having((e) => e.message, 'pesan', contains('tidak dapat terhubung'))),
    );
  });

  test('cancel() saat berjalan → galat BATAL', () async {
    final tahan = Completer<ResponseBody>();
    final server = _Server((o) => tahan.future);
    final inst = ApkInstaller(dio: _dio(server));
    final fut = inst.download('https://github.com/x/y/releases/download/a/b.apk',
        filename: 'b.apk', direktori: dir.path);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await inst.cancel();
    await expectLater(fut, throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'BATAL')));
  });

  test('tanpa data selama jedaMacet → galat MACET', () async {
    final tahan = Completer<ResponseBody>();
    final server = _Server((o) => tahan.future);
    final inst = ApkInstaller(dio: _dio(server), jedaMacet: const Duration(seconds: 6));
    final fut = inst.download('https://github.com/x/y/releases/download/a/b.apk',
        filename: 'b.apk', direktori: dir.path);
    await expectLater(
      fut.timeout(const Duration(seconds: 20)),
      throwsA(isA<PlatformException>()
          .having((e) => e.code, 'code', 'MACET')
          .having((e) => e.message, 'pesan', contains('macet'))),
    );
  });
}
