// Fase 4 (kritik B-9): mode batch diputuskan di pengurai aplikasi (provider)
// DAN di isolate sinkron latar dari `GET /config` `sync_batch.versi`, dengan
// device_id dari secure storage yang sama — isolate latar tidak menguras
// antrean per baris sementara aplikasi memakai batch.
//
// Bawaan review Task 23/25: tanda batch di SalinanInterceptor, kunci isolate
// (detak sebelum tiap POST, hasil hanya untuk baris yang masih MENGIRIM),
// batch tanpa `?toko_id`, id perangkat dibuat sejak startup.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/network/api_client.dart';
import 'package:tuleh_pos/core/offline/antrean.dart';
import 'package:tuleh_pos/core/offline/koneksi.dart';
import 'package:tuleh_pos/core/offline/operasi_batch.dart';
import 'package:tuleh_pos/core/offline/pengurai.dart';
import 'package:tuleh_pos/core/offline/perangkat_sinkron.dart';
import 'package:tuleh_pos/core/offline/salinan_db.dart';
import 'package:tuleh_pos/core/offline/salinan_interceptor.dart';
import 'package:tuleh_pos/core/offline/sinkron_latar.dart';
import 'package:tuleh_pos/core/storage/secure_storage.dart';
import 'package:tuleh_pos/features/demo/data/masa_coba_service.dart';

import 'helpers/masa_coba_palsu.dart';

class _Storage extends SecureStorage {
  _Storage(this.m, {this.toko}) : super(const FlutterSecureStorage());
  final Map<String, String> m;

  /// Toko aktif aplikasi (disisipkan pencegat `dioProvider` sebagai `?toko_id`).
  final String? toko;
  @override
  Future<String?> readToken() async => m['token'];
  @override
  Future<String?> readActiveTokoId() async => toko;
  @override
  Future<String?> bacaNilai(String k) async => m[k];
  @override
  Future<void> tulisNilai(String k, String? v) async => v == null ? m.remove(k) : m[k] = v;
}

/// Server v2: `/config` mengiklankan batch; batch menerima semua.
class _ServerV2 implements HttpClientAdapter {
  final List<RequestOptions> diminta = [];
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? s, Future<void>? c) async {
    diminta.add(o);
    final Object body;
    if (o.method == 'GET' && o.path.endsWith('/config')) {
      body = {'success': true, 'data': {'sync_batch': {'versi': 2, 'path': jalurSyncBatch, 'maks_operasi': 200}}};
    } else if (o.path.endsWith(jalurSyncBatch)) {
      final ops = (o.data as Map)['operations'] as List;
      body = {
        'success': true,
        'data': {
          'versi': 2,
          'results': [
            for (final op in ops.cast<Map>())
              {'idempotency_key': op['idempotency_key'], 'type': op['type'], 'accepted': true, 'server_id': 'S1', 'nomor': 'POS/1', 'kode': 'OK', 'peringatan': <String>[]},
          ],
        },
      };
    } else {
      body = {'success': true, 'data': <String, dynamic>{}};
    }
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }

  @override
  void close({bool force = false}) {}

  List<RequestOptions> get batch => [for (final o in diminta) if (o.path.endsWith(jalurSyncBatch)) o];
}

PesanAntrean _checkout(String ref, {String? pemilik}) => PesanAntrean(
  urut: 0, clientRef: ref, jenis: 'CHECKOUT', path: '/transaksi/checkout', tokoId: 'T1', pemilik: pemilik,
  body: {'client_ref': ref, 'items': <Object>[], 'tipe_pembayaran': 'TUNAI', 'dibayar': 0}, dibuat: DateTime(2026, 9, 24, 9),
);

/// Server tiruan fleksibel: jawaban (status, badan) atau DioExceptionType,
/// boleh asinkron (mis. meniru isolate lain yang menulis store selama POST).
/// Tiap POST dicatat ke [jejak] bersama (urutan terhadap detak kunci).
class _Server implements HttpClientAdapter {
  _Server([FutureOr<Object> Function(RequestOptions o)? jawab, this.jejak]) : jawab = jawab ?? _jawabBawaan;
  final FutureOr<Object> Function(RequestOptions o) jawab;
  final List<String>? jejak;
  final List<RequestOptions> diminta = [];

  List<RequestOptions> get batch => [for (final o in diminta) if (o.path.endsWith(jalurSyncBatch)) o];
  List<RequestOptions> get kiriman => [for (final o in diminta) if (o.method == 'POST') o];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? s, Future<void>? c) async {
    diminta.add(o);
    if (o.method == 'POST') jejak?.add('POST ${o.path}');
    final r = await jawab(o);
    if (r is DioExceptionType) throw DioException(requestOptions: o, type: r);
    final (int code, Object body) = r as (int, Object);
    return ResponseBody.fromString(jsonEncode(body), code, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }

  @override
  void close({bool force = false}) {}
}

/// Jawaban batch v2: semua diterima kecuali [tolak] (client_ref → kode).
(int, Object) _hasilBatch(RequestOptions o, {Map<String, String> tolak = const {}}) => (200, {
  'success': true,
  'data': {
    'versi': 2,
    'results': [
      for (final op in ((o.data as Map)['operations'] as List).cast<Map>())
        if (tolak[op['idempotency_key']] case final kode?)
          {'idempotency_key': op['idempotency_key'], 'type': op['type'], 'accepted': false, 'kode': kode, 'retriable': true, 'message': 'Ditolak ($kode).'}
        else
          {'idempotency_key': op['idempotency_key'], 'type': op['type'], 'accepted': true, 'server_id': 'srv-${op['idempotency_key']}', 'nomor': 'N-${op['idempotency_key']}', 'kode': 'OK', 'peringatan': <String>[]},
    ],
  },
});

Object _jawabBawaan(RequestOptions o) {
  if (o.method == 'GET' && o.path.endsWith('/config')) {
    return (200, {'success': true, 'data': {'sync_batch': {'versi': 2, 'path': jalurSyncBatch, 'maks_operasi': 200}}});
  }
  if (o.path.endsWith(jalurSyncBatch)) return _hasilBatch(o);
  if (o.method == 'GET') return (200, {'success': true, 'data': <String, dynamic>{}});
  return (201, {'success': true, 'data': {'id': 'S-${(o.data as Map?)?['client_ref']}'}});
}

PesanAntrean _pengeluaran(String ref, {String? pemilik}) => PesanAntrean(
  urut: 0, clientRef: ref, jenis: 'PENGELUARAN', path: '/pengeluaran', tokoId: 'T1', pemilik: pemilik,
  body: {'client_ref': ref, 'keterangan': 'Galon', 'nominal': 25000}, dibuat: DateTime(2026, 9, 24, 9),
);

class _KunciCatat extends KunciPengurai {
  _KunciCatat(this.jejak);
  final List<String> jejak;
  @override
  Future<bool> terkunci() async => false;
  @override
  Future<void> kunci() async => jejak.add('kunci');
  @override
  Future<void> buka() async => jejak.add('buka');
}

/// Tiap POST di [jejak] didahului langsung oleh detak kunci.
void _cekDetakSebelumPost(List<String> jejak, {required int jumlahPost}) {
  final posisi = [for (var i = 0; i < jejak.length; i++) if (jejak[i].startsWith('POST ')) i];
  expect(posisi, hasLength(jumlahPost), reason: '$jejak');
  for (final i in posisi) {
    expect(i > 0 && jejak[i - 1] == 'kunci', isTrue, reason: 'detak kunci sebelum ${jejak[i]}: $jejak');
  }
}

class _Penanda implements PenandaKoneksi {
  bool offlineNilai = false;
  @override
  bool get offline => offlineNilai;
  @override
  void tandaiOffline({DateTime? ditarikPada}) => offlineNilai = true;
  @override
  void tandaiOnline() => offlineNilai = false;
}

class _StorageRusak extends _Storage {
  _StorageRusak() : super({});
  @override
  Future<String?> bacaNilai(String k) async => throw StateError('keystore terkunci');
}

class _StorageMacet extends _Storage {
  _StorageMacet() : super({});
  @override
  Future<String?> bacaNilai(String k) => Completer<String?>().future;
}

/// Wadah aplikasi dengan rantai `dioProvider` ASLI (pencegat header/toko,
/// Mode Demo, SalinanInterceptor) dan server tiruan di adapter-nya.
ProviderContainer _wadah(AntreanStore a, HttpClientAdapter server, {String? toko}) {
  final c = ProviderContainer(overrides: [
    secureStorageProvider.overrideWithValue(_Storage({'token': 'tok', kunciPerangkatSinkron: 'dev-app'}, toko: toko)),
    masaCobaServiceProvider.overrideWithValue(MasaCobaPalsu()),
    ...overrideOffline(antrean: a),
  ]);
  addTearDown(c.dispose);
  c.read(dioProvider).httpClientAdapter = server;
  return c;
}

void main() {
  test('penguraiProvider: /config sync_batch v2 → POST /sync/v2/batch dengan device_id secure storage', () async {
    final a = AntreanMemori();
    await a.antrekan(_checkout('c1'));
    final server = _ServerV2();
    final c = ProviderContainer(overrides: [
      secureStorageProvider.overrideWithValue(_Storage({'token': 'tok', kunciPerangkatSinkron: 'dev-provider'})),
      masaCobaServiceProvider.overrideWithValue(MasaCobaPalsu()),
      ...overrideOffline(antrean: a),
    ]);
    addTearDown(c.dispose);
    c.read(dioProvider).httpClientAdapter = server;
    final p = c.read(penguraiProvider);
    addTearDown(p.hentikan);
    expect(await p.jalankan(), 1);
    expect(server.batch, hasLength(1));
    expect((server.batch.single.data as Map)['device_id'], 'dev-provider');
    expect((await a.cari('c1'))!.status, StatusAntrean.terkirim);
  });

  test('isolate latar: mode batch dari /config, device_id dari penyimpanan yang sama', () async {
    final dir = await Directory.systemTemp.createTemp('tuleh-latar-batch-');
    addTearDown(() => dir.delete(recursive: true));
    final db = SalinanDb(NativeDatabase.memory());
    addTearDown(db.close);
    final store = AntreanDriftStore(db);
    await store.antrekan(_checkout('c1', pemilik: 'U1'));
    final server = _ServerV2();
    final dio = Dio(BaseOptions(validateStatus: (_) => true))..httpClientAdapter = server;
    await jalankanSinkronLatar(
      db: db, dio: dio, kunci: KunciPengurai(dir: dir), token: 'tok', versi: '2.34.0',
      pemilik: 'U1', pemilikDiketahui: true, storage: _Storage({kunciPerangkatSinkron: 'dev-latar'}),
    );
    expect(server.batch, hasLength(1));
    expect((server.batch.single.data as Map)['device_id'], 'dev-latar');
    expect((await store.cari('c1'))!.status, StatusAntrean.terkirim);
  });

  group('bawaan 1: tanda batch di SalinanInterceptor (rantai dioProvider asli)', () {
    test('POST bertanda antrean_batch: timeout setelah terkirim, 503 BATCH_TIDAK_TERSEDIA, 5xx & 408 tidak menandai offline; galat koneksi & 429 tanpa kode tetap offline', () async {
      for (final (jawab, offline) in <(Object, bool)>[
        (DioExceptionType.receiveTimeout, false),
        (DioExceptionType.sendTimeout, false),
        ((503, {'success': false, 'message': 'Tidak tersedia', 'errors': {'kode': ['BATCH_TIDAK_TERSEDIA']}}), false),
        ((500, {'success': false, 'message': 'Server error'}), false),
        ((502, {'success': false, 'message': 'Bad Gateway'}), false),
        ((408, {'success': false, 'message': 'Request Timeout'}), false),
        (DioExceptionType.connectionError, true),
        (DioExceptionType.connectionTimeout, true),
        ((429, {'success': false, 'message': 'Terlalu banyak permintaan'}), true),
      ]) {
        final c = _wadah(AntreanMemori(), _Server((_) => jawab));
        try {
          await c.read(dioProvider).post<dynamic>(
            jalurSyncBatch,
            data: const {'operations': <Object>[]},
            options: Options(extra: const {SalinanInterceptor.tandaAntreanBatch: true}),
          );
        } on DioException catch (_) {}
        expect(c.read(koneksiProvider).online, !offline, reason: '$jawab');
      }
    });

    test('POST tanpa tanda tetap seperti semula: timeout & 503 menandai offline', () async {
      for (final jawab in <Object>[
        DioExceptionType.receiveTimeout,
        (503, {'success': false, 'message': 'Tidak tersedia', 'errors': {'kode': ['BATCH_TIDAK_TERSEDIA']}}),
      ]) {
        final c = _wadah(AntreanMemori(), _Server((_) => jawab));
        try {
          await c.read(dioProvider).post<dynamic>('/transaksi/checkout', data: const <String, dynamic>{});
        } on DioException catch (_) {}
        expect(c.read(koneksiProvider).online, isFalse, reason: '$jawab');
      }
    });

    test('penguraiProvider: jawaban batch timeout / 503 BATCH_TIDAK_TERSEDIA / 5xx tak pernah menyalakan pita offline; galat koneksi & 429 tanpa kode menyalakannya', () async {
      for (final (jawabBatch, offline) in <(Object, bool)>[
        (DioExceptionType.receiveTimeout, false),
        ((503, {'success': false, 'message': 'Tidak tersedia', 'errors': {'kode': ['BATCH_TIDAK_TERSEDIA']}}), false),
        ((500, {'success': false, 'message': 'Server error'}), false),
        (DioExceptionType.connectionError, true),
        ((429, {'success': false, 'message': 'Terlalu banyak permintaan'}), true),
      ]) {
        final a = AntreanMemori();
        await a.antrekan(_checkout('c1'));
        final server = _Server((o) => o.path.endsWith(jalurSyncBatch) ? jawabBatch : _jawabBawaan(o));
        final c = _wadah(a, server);
        final jejak = <bool>[];
        c.listen<StatusKoneksi>(koneksiProvider, (_, n) => jejak.add(n.online), fireImmediately: true);
        await c.read(penguraiProvider).jalankan();
        expect(server.batch, hasLength(1), reason: '$jawabBatch');
        expect(server.batch.single.extra[SalinanInterceptor.tandaAntreanBatch], isTrue);
        expect(jejak.contains(false), offline, reason: '$jawabBatch: $jejak');
        final c1 = (await a.cari('c1'))!;
        if (jawabBatch is (int, Object) && jawabBatch.$1 == 503) {
          expect(c1.status, StatusAntrean.terkirim, reason: '503 BATCH_TIDAK_TERSEDIA → per baris');
        } else {
          expect(c1.status, StatusAntrean.menunggu, reason: '$jawabBatch');
          expect(c1.cobaLagiSetelah, isNotNull, reason: '$jawabBatch');
        }
      }
    });
  });

  group('bawaan 2: kunci isolate', () {
    test('pengurai berdetak kunci SEBELUM tiap POST — per baris maupun batch', () async {
      final jejak = <String>[];
      final a = AntreanMemori();
      await a.antrekan(_pengeluaran('x1'));
      await a.antrekan(_checkout('c1'));
      await a.antrekan(_pengeluaran('x2'));
      final server = _Server(null, jejak);
      final p = PenguraiAntrean(
        store: a,
        dio: Dio(BaseOptions(validateStatus: (_) => true))..httpClientAdapter = server,
        koneksi: _Penanda(),
        tanpaPemulih: true,
        kunci: _KunciCatat(jejak),
        konfigBatch: () async => const KonfigSyncBatch(versi: 2),
        idPerangkat: () async => 'dev-uji',
      );
      addTearDown(p.hentikan);
      expect(await p.jalankan(), 3);
      expect([for (final o in server.kiriman) o.path], ['/pengeluaran', jalurSyncBatch, '/pengeluaran']);
      _cekDetakSebelumPost(jejak, jumlahPost: 3);
      expect(jejak.last, 'buka');
    });

    test('isolate latar memberikan kunci ke pengurai: detak sebelum tiap POST', () async {
      final jejak = <String>[];
      final db = SalinanDb(NativeDatabase.memory());
      addTearDown(db.close);
      final store = AntreanDriftStore(db);
      await store.antrekan(_pengeluaran('x1', pemilik: 'U1'));
      await store.antrekan(_checkout('c1', pemilik: 'U1'));
      await store.antrekan(_pengeluaran('x2', pemilik: 'U1'));
      final server = _Server(null, jejak);
      final dio = Dio(BaseOptions(validateStatus: (_) => true))..httpClientAdapter = server;
      await jalankanSinkronLatar(
        db: db, dio: dio, kunci: _KunciCatat(jejak), token: 'tok', versi: '2.34.0',
        pemilik: 'U1', pemilikDiketahui: true, storage: _Storage({kunciPerangkatSinkron: 'dev-latar'}),
      );
      expect([for (final o in server.kiriman) o.path], ['/pengeluaran', jalurSyncBatch, '/pengeluaran']);
      _cekDetakSebelumPost(jejak, jumlahPost: 3);
      for (final r in ['x1', 'c1', 'x2']) {
        expect((await store.cari(r))!.status, StatusAntrean.terkirim, reason: r);
      }
    });

    test('per baris: hasil POST tidak menurunkan baris yang dicatat TERKIRIM isolate lain selama POST', () async {
      for (final jawab in <Object>[
        (503, {'success': false, 'message': 'Gangguan'}),
        (422, {'success': false, 'message': 'Tidak valid'}),
        (401, {'success': false, 'message': 'Sesi berakhir'}),
        (201, {'success': true, 'data': {'id': 'DARI-SINI'}}),
        DioExceptionType.connectionError,
        DioExceptionType.receiveTimeout,
      ]) {
        final a = AntreanMemori();
        await a.antrekan(_pengeluaran('x1'));
        final server = _Server((o) async {
          // Isolate lain (sinkron latar) mencatat baris ini selagi POST berjalan.
          if (o.method == 'POST') await a.selesai('x1', hasil: {'id': 'DARI-LATAR'});
          return jawab;
        });
        final p = PenguraiAntrean(
          store: a,
          dio: Dio(BaseOptions(validateStatus: (_) => true))..httpClientAdapter = server,
          koneksi: _Penanda(),
          tanpaPemulih: true,
        );
        addTearDown(p.hentikan);
        await p.jalankan();
        final x1 = (await a.cari('x1'))!;
        expect(x1.status, StatusAntrean.terkirim, reason: '$jawab');
        expect(x1.hasil!['id'], 'DARI-LATAR', reason: '$jawab');
        expect(x1.percobaan, 0, reason: '$jawab');
        expect(x1.galatServer, 0, reason: '$jawab');
        expect(x1.galatTerakhir, isNull, reason: '$jawab');
        expect(x1.cobaLagiSetelah, isNull, reason: '$jawab');
      }
    });

    test('batch (isolate latar, SQLite bersama): hanya baris yang MASIH MENGIRIM dinilai — baris yang dicatat TERKIRIM aplikasi tidak diturunkan', () async {
      for (final jawabBatch in <String>['hasil', 'jaringan', '500']) {
        final db = SalinanDb(NativeDatabase.memory());
        addTearDown(db.close);
        final latar = AntreanDriftStore(db);
        final aplikasi = AntreanDriftStore(db); // isolate aplikasi: koneksi lain ke basis data yang sama
        await latar.antrekan(_checkout('c1', pemilik: 'U1'));
        await latar.antrekan(_checkout('c2', pemilik: 'U1'));
        final server = _Server((o) async {
          if (!o.path.endsWith(jalurSyncBatch)) return _jawabBawaan(o);
          await aplikasi.selesai('c1', hasil: {'id': 'DARI-APP'});
          return switch (jawabBatch) {
            'hasil' => _hasilBatch(o, tolak: {'c1': 'GALAT_SERVER'}),
            'jaringan' => DioExceptionType.connectionError,
            _ => (500, {'success': false, 'message': 'Server error'}),
          };
        });
        final dio = Dio(BaseOptions(validateStatus: (_) => true))..httpClientAdapter = server;
        await jalankanSinkronLatar(
          db: db, dio: dio, kunci: _KunciCatat([]), token: 'tok', versi: '2.34.0',
          pemilik: 'U1', pemilikDiketahui: true, storage: _Storage({kunciPerangkatSinkron: 'dev-latar'}),
        );
        expect(server.batch, hasLength(1), reason: jawabBatch);
        final c1 = (await latar.cari('c1'))!;
        expect(c1.status, StatusAntrean.terkirim, reason: jawabBatch);
        expect(c1.hasil!['id'], 'DARI-APP', reason: jawabBatch);
        expect(c1.galatServer, 0, reason: jawabBatch);
        expect(c1.galatTerakhir, isNull, reason: jawabBatch);
        final c2 = (await latar.cari('c2'))!;
        if (jawabBatch == 'hasil') {
          expect(c2.status, StatusAntrean.terkirim);
          expect(c2.hasil!['id'], 'srv-c2');
        } else {
          expect(c2.status, StatusAntrean.menunggu, reason: jawabBatch);
          expect(c2.percobaan, 1, reason: jawabBatch);
        }
      }
    });
  });

  group('bawaan 3: batch tanpa ?toko_id', () {
    test('rantai dioProvider asli dengan toko aktif: POST batch tanpa query sama sekali; per baris & GET tetap bertoko', () async {
      final a = AntreanMemori();
      await a.antrekan(_pengeluaran('x1'));
      await a.antrekan(_checkout('c1'));
      final server = _Server();
      final c = _wadah(a, server, toko: 'T-AKTIF');
      expect(await c.read(penguraiProvider).jalankan(), 2);
      final batch = server.batch.single;
      expect(batch.uri.query, isEmpty, reason: 'bukan ?toko_id kosong / toko aktif: ${batch.uri}');
      expect(batch.extra[ekstraTanpaTokoAktif], isTrue);
      expect(((batch.data as Map)['operations'] as List).cast<Map>().single['payload']['toko_id'], 'T1');
      final perBaris = server.kiriman.firstWhere((o) => o.path == '/pengeluaran');
      expect(perBaris.uri.queryParameters, {'toko_id': 'T1'}, reason: 'atas nama toko saat pesan dibuat');
      final config = server.diminta.firstWhere((o) => o.method == 'GET' && o.path == '/config');
      expect(config.uri.queryParameters['toko_id'], 'T-AKTIF', reason: 'permintaan biasa tetap disisipi toko aktif');
    });
  });

  group('bawaan 4: id perangkat sejak startup', () {
    test('SinkronLatar.siapkan memastikan id tersimpan sebelum tugas latar didaftarkan; isolate latar memakai id yang sama', () async {
      final m = <String, String>{};
      await SinkronLatar.siapkan(storage: _Storage(m));
      final id = m[kunciPerangkatSinkron];
      expect(id, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));

      // Isolate latar: instans penyimpanan lain atas keystore yang sama.
      final db = SalinanDb(NativeDatabase.memory());
      addTearDown(db.close);
      final store = AntreanDriftStore(db);
      await store.antrekan(_checkout('c1', pemilik: 'U1'));
      final server = _Server();
      final dio = Dio(BaseOptions(validateStatus: (_) => true))..httpClientAdapter = server;
      await jalankanSinkronLatar(
        db: db, dio: dio, kunci: _KunciCatat([]), token: 'tok', versi: '2.34.0',
        pemilik: 'U1', pemilikDiketahui: true, storage: _Storage(m),
      );
      expect((server.batch.single.data as Map)['device_id'], id);
      expect(m[kunciPerangkatSinkron], id, reason: 'isolate latar tidak membuat id kedua');
    });

    test('startup tidak terhambat: secure storage gagal atau macet → selesai tanpa melempar', () async {
      await SinkronLatar.siapkan(storage: _StorageRusak());
      final jam = Stopwatch()..start();
      await pastikanIdPerangkatSinkron(_StorageMacet(), batas: const Duration(milliseconds: 50));
      expect(jam.elapsed, lessThan(const Duration(seconds: 2)));
      // Gagal saat startup tidak memo-kan galat: pemakaian berikutnya mencoba lagi.
      final pulih = _Storage({});
      await pastikanIdPerangkatSinkron(pulih);
      expect(pulih.m[kunciPerangkatSinkron], isNotNull);
    });
  });
}
