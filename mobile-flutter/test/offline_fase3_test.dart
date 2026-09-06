import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/network/api_client.dart';
import 'package:tuleh_pos/core/network/api_exception.dart';
import 'package:tuleh_pos/core/offline/antrean.dart';
import 'package:tuleh_pos/core/offline/antrean_tulis.dart';
import 'package:tuleh_pos/core/offline/koneksi.dart';
import 'package:tuleh_pos/core/offline/pengurai.dart';
import 'package:tuleh_pos/core/offline/rujukan_lokal.dart';
import 'package:tuleh_pos/features/meja/data/datasources/meja_remote_datasource.dart';
import 'package:tuleh_pos/features/meja/data/repositories/meja_offline_repository.dart';
import 'package:tuleh_pos/core/storage/secure_storage.dart';
import 'package:tuleh_pos/features/demo/data/masa_coba_service.dart';
import 'package:tuleh_pos/features/sesi/presentation/providers/sesi_providers.dart';

import 'helpers/masa_coba_palsu.dart';

/// Mode offline fase 3 — sesi kasir & bon meja:
/// - path `lokal:<ref>` diganti id server dari hasil induk (FIFO);
/// - induk belum terkirim → turunan TINJAU, Kirim ulang induk memulihkannya;
/// - SESI_BUKA tanpa gudang_id diisi dari /gudang sebelum kirim;
/// - peta meja & detail bon memuat bon/ronde/bayar yang belum terkirim.

class _Penanda implements PenandaKoneksi {
  bool offlineNilai = false;
  @override
  bool get offline => offlineNilai;
  @override
  void tandaiOffline({DateTime? ditarikPada}) => offlineNilai = true;
  @override
  void tandaiOnline() => offlineNilai = false;
}

class _Server implements HttpClientAdapter {
  _Server(this.jawab);
  final Object Function(RequestOptions o) jawab;
  final List<(String method, String path, Map<String, dynamic>? body)> log = [];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? s, Future<void>? c) async {
    log.add((o.method, o.path, o.data is Map ? Map<String, dynamic>.from(o.data as Map) : null));
    final r = jawab(o);
    if (r is DioExceptionType) throw DioException(requestOptions: o, type: r);
    final (int code, Map<String, dynamic> body) = r as (int, Map<String, dynamic>);
    return ResponseBody.fromString(jsonEncode(body), code, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

Dio _dio(_Server s) => Dio(BaseOptions(validateStatus: (_) => true))..httpClientAdapter = s;

Map<String, dynamic> _ok([Map<String, dynamic>? data]) => {'success': true, 'data': data ?? {}};

PesanAntrean _pesan(String ref, String jenis, String path, Map<String, dynamic> body, {StatusAntrean status = StatusAntrean.menunggu, String? galat}) =>
    PesanAntrean(urut: 0, clientRef: ref, jenis: jenis, path: path, body: body, dibuat: DateTime(2026, 9, 6, 9), tokoId: 'T1', status: status, galatTerakhir: galat);

void main() {
  sesiMain();
  group('pengurai fase 3', () {
    test('rujukan lokal di path diganti id server dari hasil induk; kunci _ dibuang', () async {
      final store = AntreanMemori();
      await store.antrekan(_pesan('b1', 'BILL_BUKA', '/bills', {'meja_id': 'M1', 'pax': 2}));
      await store.antrekan(_pesan('r1', 'BILL_RONDE', '/bills/${rujukanLokal('b1')}/rounds', {
        'items': [{'id_produk': 'P1', 'kuantitas': 2}],
        '_tampilan': [{'id_produk': 'P1', 'nama': 'Kopi', 'harga': 5000, 'kuantitas': 2}],
      }));
      await store.antrekan(_pesan('y1', 'BILL_BAYAR', '/bills/${rujukanLokal('b1')}/settle', {'tipe_pembayaran': 'TUNAI', 'dibayar': 10000}));
      final server = _Server((o) => o.path == '/bills' ? (201, _ok({'id': 'SRV-77'})) : (200, _ok()));
      final pengurai = PenguraiAntrean(store: store, dio: _dio(server), koneksi: _Penanda());

      expect(await pengurai.jalankan(), 3);
      expect(server.log.map((e) => e.$2), ['/bills', '/bills/SRV-77/rounds', '/bills/SRV-77/settle']);
      expect(server.log[1].$3!.containsKey('_tampilan'), isFalse);
      expect(server.log[1].$3!['items'], isNotEmpty);
      expect((await store.cari('b1'))!.hasil!['id'], 'SRV-77');
    });

    test('induk ditolak server → turunan TINJAU; Kirim ulang induk memulihkan turunan', () async {
      final store = AntreanMemori();
      await store.antrekan(_pesan('b1', 'BILL_BUKA', '/bills', {'meja_id': 'M1'}));
      await store.antrekan(_pesan('r1', 'BILL_RONDE', '/bills/${rujukanLokal('b1')}/rounds', {'items': []}));
      var tolak = true;
      final server = _Server((o) => o.path == '/bills' && tolak
          ? (422, {'success': false, 'message': 'Meja sudah terisi.'})
          : (200, _ok({'id': 'SRV-1'})));
      final pengurai = PenguraiAntrean(store: store, dio: _dio(server), koneksi: _Penanda());

      expect(await pengurai.jalankan(), 0);
      expect((await store.cari('b1'))!.status, StatusAntrean.tinjau);
      expect((await store.cari('b1'))!.galatTerakhir, 'Meja sudah terisi.');
      expect((await store.cari('r1'))!.status, StatusAntrean.tinjau);
      expect((await store.cari('r1'))!.galatTerakhir, PenguraiAntrean.pesanIndukBelumTerkirim);
      expect(server.log.length, 1, reason: 'ronde tidak dikirim tanpa id bon');

      tolak = false;
      await pengurai.kirimUlang('b1');
      expect((await store.cari('b1'))!.status, StatusAntrean.terkirim);
      expect((await store.cari('r1'))!.status, StatusAntrean.terkirim);
      expect(server.log.last.$2, '/bills/SRV-1/rounds');
    });

    test('induk dibatalkan → turunan TINJAU dengan pesan jelas', () async {
      final store = AntreanMemori();
      await store.antrekan(_pesan('r1', 'BILL_RONDE', '/bills/${rujukanLokal('hilang')}/rounds', {'items': []}));
      final server = _Server((_) => (200, _ok()));
      await PenguraiAntrean(store: store, dio: _dio(server), koneksi: _Penanda()).jalankan();
      expect((await store.cari('r1'))!.status, StatusAntrean.tinjau);
      expect((await store.cari('r1'))!.galatTerakhir, contains('dibatalkan'));
      expect(server.log, isEmpty);
    });

    test('SESI_BUKA tanpa gudang_id diisi dari /gudang tepat sebelum kirim', () async {
      final store = AntreanMemori();
      await store.antrekan(_pesan('s1', 'SESI_BUKA', '/sesi/buka', {'kas_awal': 100000}));
      final server = _Server((o) => o.path == '/gudang'
          ? (200, _ok({'rows': [{'id': 'G-9', 'nama': 'Utama'}]}))
          : (201, _ok({'id': 'SESI-1'})));
      final dio = _dio(server);
      final pengurai = PenguraiAntrean(
        store: store, dio: dio, koneksi: _Penanda(),
        penyiap: {'SESI_BUKA': (b) => isiGudangId(dio, b)},
      );
      expect(await pengurai.jalankan(), 1);
      expect(server.log.map((e) => e.$2), ['/gudang', '/sesi/buka']);
      expect(server.log.last.$3!['gudang_id'], 'G-9');
      expect(server.log.last.$3!['kas_awal'], 100000);
    });

    test('gagal jaringan saat mengisi gudang → mundur, bukan TINJAU', () async {
      final store = AntreanMemori();
      await store.antrekan(_pesan('s1', 'SESI_BUKA', '/sesi/buka', {'kas_awal': 1}));
      final server = _Server((_) => DioExceptionType.connectionError);
      final dio = _dio(server);
      final pengurai = PenguraiAntrean(
        store: store, dio: dio, koneksi: _Penanda(),
        penyiap: {'SESI_BUKA': (b) => isiGudangId(dio, b)},
      );
      await pengurai.jalankan();
      final p = (await store.cari('s1'))!;
      expect(p.status, StatusAntrean.menunggu);
      expect(p.percobaan, 1);
      pengurai.hentikan();
    });
  });

  group('MejaOfflineRepository', () {
    Map<String, dynamic> peta() => _ok({
      'tables': [
        {'id': 'M1', 'nomor': '1'},
        {'id': 'M2', 'nomor': '2', 'bill': {'id': 'S1', 'total': 10000, 'pax': 3}},
        {'id': 'M3', 'nomor': '3', 'bill': {'id': 'S2', 'total': 5000}},
      ],
    });
    Map<String, dynamic> detailS1() => _ok({
      'id': 'S1', 'nomor': 'B-001', 'total': 10000,
      'items': [{'nama': 'Kopi', 'kuantitas': 2, 'harga': 5000, 'subtotal': 10000}],
    });

    MejaOfflineRepository repo(_Server server, AntreanMemori store, _Penanda penanda) => MejaOfflineRepository(
      remote: MejaRemoteDataSource(_dio(server)),
      antrean: store,
      tulis: AntreanTulis(antrean: store, koneksi: penanda, tokoId: 'T1'),
      tokoId: 'T1',
    );

    test('offline: buka bon → id lokal di peta; ronde & bayar diantrekan tanpa menyentuh server', () async {
      final store = AntreanMemori();
      final penanda = _Penanda()..offlineNilai = true;
      final server = _Server((o) => o.path == '/bills' && o.method == 'GET'
          ? (200, peta())
          : o.path == '/bills/S1' ? (200, detailS1()) : DioExceptionType.connectionError);
      final r = repo(server, store, penanda);

      final buka = (await r.bukaBon('M1', pax: 2)).when(ok: (h) => h, err: (e) => throw e);
      expect(buka.tertunda, isTrue);
      final idLokal = rujukanLokal(buka.clientRef!);

      final ronde = (await r.tambahRonde(idLokal, [{'id_produk': 'P1', 'kuantitas': 2}],
          tampilan: [{'id_produk': 'P1', 'nama': 'Teh', 'harga': 4000, 'kuantitas': 2}]))
          .when(ok: (h) => h, err: (e) => throw e);
      expect(ronde.tertunda, isTrue);

      // Ronde ke bon server S1 & bayar S2 (server tak terjangkau → antre).
      (await r.tambahRonde('S1', [{'id_produk': 'P2', 'kuantitas': 1}],
          tampilan: [{'id_produk': 'P2', 'nama': 'Roti', 'harga': 3000, 'kuantitas': 1}]))
          .when(ok: (h) => expect(h.tertunda, isTrue), err: (e) => throw e);
      (await r.bayar('S2', tipe: 'TUNAI', dibayar: 5000))
          .when(ok: (h) => expect(h.tertunda, isTrue), err: (e) => throw e);
      expect(server.log.where((e) => e.$1 == 'POST'), isEmpty, reason: 'offline: tak ada POST');

      final daftar = (await r.peta()).when(ok: (v) => v, err: (e) => throw e);
      final m1 = daftar.firstWhere((m) => m.id == 'M1');
      expect(m1.billId, idLokal);
      expect(m1.billTotal, 8000);
      expect(m1.pax, 2);
      final m2 = daftar.firstWhere((m) => m.id == 'M2');
      expect(m2.billId, 'S1');
      expect(m2.billTotal, 13000, reason: 'total server + ronde tertunda');
      final m3 = daftar.firstWhere((m) => m.id == 'M3');
      expect(m3.terisi, isFalse, reason: 'dibayar offline → tampil kosong');

      final dLokal = (await r.detail(idLokal)).when(ok: (v) => v, err: (e) => throw e);
      expect(dLokal.nomor, 'Bon offline');
      expect(dLokal.total, 8000);
      expect(dLokal.items.single.nama, 'Teh');

      final dS1 = (await r.detail('S1')).when(ok: (v) => v, err: (e) => throw e);
      expect(dS1.total, 13000);
      expect(dS1.items.map((i) => i.nama), ['Kopi', 'Roti']);
    });

    test('online: langsung ke server, tidak diantrekan; hasil tak tertunda', () async {
      final store = AntreanMemori();
      final server = _Server((o) => o.method == 'GET' ? (200, peta()) : (201, _ok({'id': 'S9'})));
      final r = repo(server, store, _Penanda());
      final h = (await r.bukaBon('M1')).when(ok: (h) => h, err: (e) => throw e);
      expect(h.tertunda, isFalse);
      expect(server.log.last.$2, '/bills');
      expect(server.log.last.$3!['client_ref'], isNotNull);
      expect((await store.semua()), isEmpty);
    });

    test('server menolak (422) saat online → galat dilempar apa adanya, tidak diantrekan', () async {
      final store = AntreanMemori();
      final server = _Server((o) => (422, {'success': false, 'message': 'Meja sudah terisi.'}));
      final r = repo(server, store, _Penanda());
      final res = await r.bukaBon('M1');
      expect(res.when(ok: (_) => null, err: (e) => e.message), 'Meja sudah terisi.');
      expect(await store.semua(), isEmpty);
    });
  });
}

// ---------------------------------------------------------------- sesi

class _StorageSesi extends SecureStorage {
  _StorageSesi() : super(const FlutterSecureStorage());
  final Map<String, String> m = {'token': 'tok', 'toko': 'T1'};
  @override
  Future<String?> readToken() async => m['token'];
  @override
  Future<void> writeToken(String? v) async => v == null ? m.remove('token') : m['token'] = v;
  @override
  Future<String?> readActiveTokoId() async => m['toko'];
  @override
  Future<void> writeActiveTokoId(String? v) async => v == null ? m.remove('toko') : m['toko'] = v;
  @override
  Future<String?> bacaNilai(String k) async => m[k];
  @override
  Future<void> tulisNilai(String k, String? v) async => v == null ? m.remove(k) : m[k] = v;
}

void sesiMain() {
  group('ActiveSesiNotifier offline', () {
    test('buka sesi saat server tak terjangkau → SESI_BUKA diantrekan, sesi lokal aktif, tutup ditahan', () async {
      final store = AntreanMemori();
      final server = _Server((_) => DioExceptionType.connectionError);
      final c = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(_StorageSesi()),
          masaCobaServiceProvider.overrideWithValue(MasaCobaPalsu()),
          dioProvider.overrideWithValue(_dio(server)),
          ...overrideOffline(antrean: store),
        ],
      );
      addTearDown(c.dispose);
      c.listen(activeSesiProvider, (_, _) {});
      // Sebelum buka: server gagal → provider galat (tak ada sesi lokal).
      await expectLater(c.read(activeSesiProvider.future), throwsA(isA<ApiException>()));

      final tertunda = await c.read(activeSesiProvider.notifier).buka(150000);
      expect(tertunda, isTrue);
      final sesi = c.read(activeSesiProvider).valueOrNull;
      expect(sesi, isNotNull);
      expect(adalahRujukanLokal(sesi!.id), isTrue);
      expect(sesi.nomor, 'Sesi offline');

      final antrean = await store.semua();
      expect(antrean.single.jenis, 'SESI_BUKA');
      expect(antrean.single.body['kas_awal'], 150000);
      expect(antrean.single.body.containsKey('gudang_id'), isFalse, reason: 'diisi pengurai sebelum kirim');
      expect(antrean.single.tokoId, 'T1');

      // Tutup ditahan selama antrean toko ini belum kosong.
      await expectLater(
        c.read(activeSesiProvider.notifier).tutup(kasAkhirFisik: 1),
        throwsA(isA<ApiException>().having((e) => e.message, 'pesan', contains('belum terkirim'))),
      );

      // Setelah rebuild (mis. ganti layar), sesi lokal tetap dikenali.
      c.invalidate(activeSesiProvider);
      final lagi = await c.read(activeSesiProvider.future);
      expect(lagi?.id, sesi.id);
    });
  });
}
