import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/offline/antrean.dart';
import 'package:tuleh_pos/core/offline/pengurai.dart';
import 'package:tuleh_pos/core/offline/salinan_db.dart';
import 'package:tuleh_pos/core/offline/sinkron_latar.dart';

/// Sinkronisasi latar (WorkManager): isolate latar memproses antrean SQLite
/// dengan Dio sendiri, mengalah bila aplikasi sedang memegang kunci, dan
/// pengurai mengirim atas nama toko saat pesan dibuat.

class _Server implements HttpClientAdapter {
  final List<RequestOptions> log = [];
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? s, Future<void>? c) async {
    log.add(o);
    return ResponseBody.fromString(
      jsonEncode({'success': true, 'data': {'nomor': 'N-${log.length}'}}),
      200,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('tuleh-kunci-'));
  tearDown(() async => dir.delete(recursive: true));

  test('KunciPengurai: kunci/buka/terkunci; kunci basi dianggap lepas', () async {
    final k = KunciPengurai(dir: dir, usiaMaks: const Duration(minutes: 3));
    expect(await k.terkunci(), isFalse);
    await k.kunci();
    expect(await k.terkunci(), isTrue);
    await k.buka();
    expect(await k.terkunci(), isFalse);
    final basi = KunciPengurai(dir: dir, usiaMaks: Duration.zero);
    await basi.kunci();
    expect(await basi.terkunci(), isFalse, reason: 'usia 0 → selalu basi');
  });

  test('jalankanSinkronLatar: kirim antrean MENUNGGU atas nama toko pesan, lepas kunci; mengalah bila terkunci', () async {
    final db = SalinanDb(NativeDatabase.memory());
    addTearDown(db.close);
    final store = AntreanDriftStore(db);
    await store.antrekan(PesanAntrean(
      urut: 0, clientRef: 'a', jenis: 'PENGELUARAN', path: '/pengeluaran',
      body: const {'keterangan': 'Galon', 'nominal': 25000}, dibuat: DateTime(2026, 9, 8), tokoId: 'TOKO-X',
    ));
    final server = _Server();
    final dio = Dio(BaseOptions(validateStatus: (_) => true))..httpClientAdapter = server;
    final kunci = KunciPengurai(dir: dir);

    // Aplikasi sedang menguraikan → isolate latar mengalah.
    await kunci.kunci();
    expect(await jalankanSinkronLatar(db: db, dio: dio, kunci: kunci, token: 'tok'), isTrue);
    expect(server.log, isEmpty);
    await kunci.buka();

    expect(await jalankanSinkronLatar(db: db, dio: dio, kunci: kunci, token: 'tok'), isTrue);
    expect(server.log.length, 1);
    expect(server.log.single.path, '/pengeluaran');
    expect(server.log.single.queryParameters['toko_id'], 'TOKO-X');
    expect((await store.cari('a'))!.status, StatusAntrean.terkirim);
    expect(await kunci.terkunci(), isFalse, reason: 'kunci dilepas setelah selesai');

    // Tanpa token → tidak ada yang dikirim.
    expect(await jalankanSinkronLatar(db: db, dio: dio, kunci: kunci, token: ''), isTrue);
    expect(server.log.length, 1);
  });

  test('PenguraiAntrean memegang kunci selama berjalan', () async {
    final store = AntreanMemori();
    await store.antrekan(PesanAntrean(
      urut: 0, clientRef: 'b', jenis: 'PENGELUARAN', path: '/pengeluaran', body: const {}, dibuat: DateTime(2026),
    ));
    final kunci = KunciPengurai(dir: dir);
    var terkunciSaatKirim = false;
    final dio = Dio(BaseOptions(validateStatus: (_) => true));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) async {
      terkunciSaatKirim = await kunci.terkunci();
      h.resolve(Response(requestOptions: o, statusCode: 200, data: const {'success': true, 'data': {}}));
    }));
    final p = PenguraiAntrean(store: store, dio: dio, koneksi: null, kunci: kunci);
    await p.jalankan();
    expect(terkunciSaatKirim, isTrue);
    expect(await kunci.terkunci(), isFalse);
    p.hentikan();
  });
}
