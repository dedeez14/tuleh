// Kontrak kesiapan produksi 2026-09-15 — "Klien: perilaku wajib":
// 5xx/408/429 & gateway 502/503/504 = GANGGUAN (antre + mundur, GET dari
// salinan, pita offline), bukan penolakan. 402 = layar langganan (tidak
// diantrekan). 4xx lain = penolakan. Dulu: checkout & antrean hanya mengantre
// pada status 0, dan pengurai menaruh 5xx/429 di "perlu ditinjau" — penjualan
// tersangkut atau hilang saat server sesaat bermasalah.

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/constants/app_config.dart';
import 'package:tuleh_pos/core/network/api_error_mapper.dart';
import 'package:tuleh_pos/core/network/api_exception.dart';
import 'package:tuleh_pos/core/offline/antrean.dart';
import 'package:tuleh_pos/core/offline/antrean_tulis.dart';
import 'package:tuleh_pos/core/offline/koneksi.dart';
import 'package:tuleh_pos/core/offline/nomor_lokal.dart';
import 'package:tuleh_pos/core/offline/pengurai.dart';
import 'package:tuleh_pos/core/offline/salinan_db.dart';
import 'package:tuleh_pos/core/offline/salinan_interceptor.dart';
import 'package:tuleh_pos/core/offline/salinan_store.dart';
import 'package:tuleh_pos/core/offline/sinkron_latar.dart';
import 'package:tuleh_pos/core/offline/sinkronisasi_screen.dart';
import 'package:tuleh_pos/core/storage/secure_storage.dart';
import 'package:tuleh_pos/features/cetak/domain/entities/struk.dart';
import 'package:tuleh_pos/features/kasir/data/checkout_repository.dart';
import 'package:tuleh_pos/features/kasir/data/datasources/transaction_remote_datasource.dart';
import 'package:tuleh_pos/features/kasir/domain/entities/cart_item.dart';
import 'package:tuleh_pos/features/products/domain/entities/product.dart';

class _Storage extends SecureStorage {
  _Storage() : super(const FlutterSecureStorage());
  final Map<String, String> m = {};
  @override
  Future<String?> bacaNilai(String k) async => m[k];
  @override
  Future<void> tulisNilai(String k, String? v) async => v == null ? m.remove(k) : m[k] = v;
}

class _Penanda implements PenandaKoneksi {
  bool offlineNilai = false;
  int ditandaiOffline = 0;
  @override
  bool get offline => offlineNilai;
  @override
  void tandaiOffline({DateTime? ditarikPada}) {
    offlineNilai = true;
    ditandaiOffline++;
  }

  @override
  void tandaiOnline() => offlineNilai = false;
}

/// Jawaban server tiruan: (status, badan, header) atau DioExceptionType.
class _Server implements HttpClientAdapter {
  _Server(this.jawab);
  final Object Function(RequestOptions o) jawab;
  final List<RequestOptions> diminta = [];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? s, Future<void>? c) async {
    diminta.add(o);
    final r = jawab(o);
    if (r is DioExceptionType) throw DioException(requestOptions: o, type: r);
    final (int code, Map<String, dynamic> body, Map<String, String> header) =
        r as (int, Map<String, dynamic>, Map<String, String>);
    return ResponseBody.fromString(jsonEncode(body), code, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      for (final e in header.entries) e.key: [e.value],
    });
  }

  @override
  void close({bool force = false}) {}
}

(int, Map<String, dynamic>, Map<String, String>) _jawab(int code, [Map<String, String> header = const {}]) => (
  code,
  code < 300
      ? {'success': true, 'data': {'nomor': 'POS-1', 'kembalian': 0, 'id': 'X1'}}
      : {'success': false, 'message': 'HTTP $code dari server', 'data': null, 'errors': null},
  header,
);

Dio _dio(_Server s) => Dio(BaseOptions(validateStatus: (_) => true))..httpClientAdapter = s;

const _aqua = Product(id: 'P1', nama: 'Aqua', harga: 4000, stok: 40);
Struk _struk(String nomor, double kembalian) => Struk(
  namaToko: 'Toko',
  nomor: nomor,
  waktu: DateTime(2026, 9, 15, 10),
  baris: const [StrukBaris(nama: 'Aqua', kuantitas: 2, harga: 4000)],
  total: 8000,
  metode: 'TUNAI',
  dibayar: 10000,
  kembalian: kembalian,
);

const _gangguan = [408, 429, 500, 502, 503, 504];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('klasifikasi status', () {
    test('gangguan: 0, 408, 429, 5xx; penolakan: 4xx lain', () {
      for (final c in [0, 408, 429, 500, 502, 503, 504, 599]) {
        expect(statusGangguan(c), isTrue, reason: 'HTTP $c');
        expect(ApiException(message: '', statusCode: c).isGangguan, isTrue);
      }
      for (final c in [200, 400, 401, 402, 403, 404, 405, 409, 422, 426]) {
        expect(statusGangguan(c), isFalse, reason: 'HTTP $c');
      }
      expect(const ApiException(message: '', statusCode: 402).isLanggananBerakhir, isTrue);
    });

    test('Retry-After: detik atau tanggal HTTP; tidak ada / lewat → null', () {
      Headers h(String v) => Headers.fromMap({'retry-after': [v]});
      expect(ApiErrorMapper.retryAfter(h('120')), const Duration(seconds: 120));
      final kini = DateTime.utc(2026, 9, 15, 3);
      final tanggal = HttpDate.format(kini.add(const Duration(minutes: 3)));
      expect(ApiErrorMapper.retryAfter(h(tanggal), sekarang: kini), const Duration(minutes: 3));
      expect(ApiErrorMapper.retryAfter(Headers()), isNull);
      expect(ApiErrorMapper.retryAfter(h('0')), isNull);
      expect(ApiErrorMapper.retryAfter(h('bukan-tanggal')), isNull);
    });

    test('fromResponse membawa pesan, errors, meta, Retry-After', () {
      final res = Response<dynamic>(
        requestOptions: RequestOptions(path: '/x'),
        statusCode: 429,
        data: {'success': false, 'message': 'Pelan-pelan', 'errors': {'a': ['b']}, 'meta': {'k': 1}},
        headers: Headers.fromMap({'retry-after': ['30']}),
      );
      final e = ApiErrorMapper.fromResponse(res);
      expect(e.statusCode, 429);
      expect(e.message, 'Pelan-pelan');
      expect(e.firstError(), 'b');
      expect(e.meta, {'k': 1});
      expect(e.cobaLagiSetelah, const Duration(seconds: 30));
      expect(e.isGangguan, isTrue);
    });
  });

  group('checkout langsung', () {
    CheckoutRepository repo(_Server s, AntreanStore a) => CheckoutRepository(
      remote: TransactionRemoteDataSource(_dio(s)),
      antrean: a,
      nomorLokal: NomorLokal(_Storage()),
      koneksi: _Penanda(),
      tokoId: 'T1',
      pemilik: 'U1',
    );

    for (final code in _gangguan) {
      test('HTTP $code → diantrekan (tidak hilang, tidak ditolak)', () async {
        final a = AntreanMemori();
        final hasil = await repo(_Server((_) => _jawab(code)), a).bayar(
          items: const [CartItem(product: _aqua, qty: 2)],
          metode: 'TUNAI',
          dibayar: 10000,
          total: 8000,
          buatStruk: _struk,
        );
        expect(hasil.tertunda, isTrue);
        expect(hasil.nomor, startsWith('L-'));
        final baris = (await a.semua()).single;
        expect(baris.status, StatusAntrean.menunggu);
        expect(baris.pemilik, 'U1');
        expect(baris.body['client_ref'], hasil.clientRef, reason: 'server menolak kiriman ganda lewat client_ref');
      });
    }

    test('Retry-After pada 503 dihormati sejak baris dibuat', () async {
      final a = AntreanMemori();
      final sebelum = DateTime.now();
      await repo(_Server((_) => _jawab(503, {'Retry-After': '600'})), a).bayar(
        items: const [CartItem(product: _aqua, qty: 1)],
        metode: 'TUNAI',
        dibayar: 4000,
        total: 4000,
        buatStruk: _struk,
      );
      final baris = (await a.semua()).single;
      expect(baris.cobaLagiSetelah, isNotNull);
      expect(baris.cobaLagiSetelah!.difference(sebelum).inSeconds, greaterThanOrEqualTo(599));
    });

    for (final code in [402, 409, 422]) {
      test('HTTP $code → dilempar apa adanya, TIDAK diantrekan', () async {
        final a = AntreanMemori();
        await expectLater(
          repo(_Server((_) => _jawab(code)), a).bayar(
            items: const [CartItem(product: _aqua, qty: 1)],
            metode: 'TUNAI',
            dibayar: 4000,
            total: 4000,
            buatStruk: _struk,
          ),
          throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', code)),
        );
        expect(await a.semua(), isEmpty);
      });
    }
  });

  group('AntreanTulis (pengeluaran, stok, sesi, bon)', () {
    test('500 → diantrekan; 429 + Retry-After → jadwal coba lagi; 422 → dilempar', () async {
      final a = AntreanMemori();
      final tulis = AntreanTulis(antrean: a, koneksi: _Penanda(), tokoId: 'T1', pemilik: 'U1');
      Future<void> kirimDengan(int code, [Map<String, String> h = const {}]) async {
        final dio = _dio(_Server((_) => _jawab(code, h)));
        final res = await dio.post<dynamic>('/pengeluaran');
        if ((res.statusCode ?? 0) >= 300) throw ApiErrorMapper.fromResponse(res);
      }

      final r500 = await tulis.jalankan(jenis: 'PENGELUARAN', path: '/pengeluaran', body: const {'nominal': 1}, kirim: (_) => kirimDengan(500));
      expect(r500.tertunda, isTrue);

      final sebelum = DateTime.now();
      final r429 = await tulis.jalankan(
        jenis: 'PENGELUARAN',
        path: '/pengeluaran',
        body: const {'nominal': 2},
        kirim: (_) => kirimDengan(429, {'Retry-After': '90'}),
      );
      expect(r429.tertunda, isTrue);
      final baris = (await a.cari(r429.clientRef!))!;
      expect(baris.cobaLagiSetelah!.difference(sebelum).inSeconds, greaterThanOrEqualTo(89));
      expect(baris.pemilik, 'U1');

      await expectLater(
        tulis.jalankan(jenis: 'PENGELUARAN', path: '/pengeluaran', body: const {}, kirim: (_) => kirimDengan(422)),
        throwsA(isA<ApiException>()),
      );
      expect((await a.semua()).length, 2);
    });
  });

  group('pengurai antrean', () {
    Future<AntreanMemori> isi(int n, {String? pemilik}) async {
      final a = AntreanMemori();
      for (var i = 1; i <= n; i++) {
        await a.antrekan(PesanAntrean(
          urut: 0, clientRef: 'c$i', jenis: 'CHECKOUT', path: '/transaksi/checkout',
          body: {'i': i}, dibuat: DateTime(2026, 9, 15, 10, i), tokoId: 'T1', pemilik: pemilik,
        ));
      }
      return a;
    }

    for (final code in _gangguan) {
      test('HTTP $code → baris itu MENUNGGU + mundur sendiri; baris lain tetap dikirim (bukan TINJAU)', () async {
        final server = _Server((o) => (o.data as Map)['i'] == 1 ? _jawab(code) : _jawab(201));
        final a = await isi(2);
        final kini = DateTime(2026, 9, 15, 10);
        final p = PenguraiAntrean(store: a, dio: _dio(server), koneksi: _Penanda(), sekarang: () => kini, tanpaPemulih: true);
        addTearDown(p.hentikan);
        expect(await p.jalankan(), 1);
        final c1 = (await a.cari('c1'))!;
        expect(c1.status, StatusAntrean.menunggu);
        expect(c1.percobaan, 1);
        expect(c1.galatServer, 1);
        expect(c1.cobaLagiSetelah, kini.add(PenguraiAntrean.mundur(1)));
        expect(c1.galatTerakhir, contains('HTTP $code'));
        expect((await a.cari('c2'))!.status, StatusAntrean.terkirim);
      });
    }

    group('tanpa head-of-line blocking', () {
      Future<(AntreanMemori, _Server, PenguraiAntrean, void Function(Duration))> siap({
        Map<String, dynamic>? config,
        _Penanda? penanda,
      }) async {
        final a = await isi(3); // c1 = beracun, c2 & c3 sehat
        final server = _Server((o) {
          if (o.path == '/config') {
            return config == null
                ? (404, {'success': false, 'message': 'x'}, const <String, String>{})
                : (200, {'success': true, 'data': config}, const <String, String>{});
          }
          return (o.data as Map)['i'] == 1 ? _jawab(500) : _jawab(201);
        });
        var kini = DateTime(2026, 9, 15, 10);
        final dio = _dio(server);
        final p = PenguraiAntrean(
          store: a,
          dio: dio,
          koneksi: penanda ?? _Penanda(),
          sekarang: () => kini,
          tanpaPemulih: true,
          batas: () => ambilBatasAntrean(dio),
        );
        addTearDown(p.hentikan);
        return (a, server, p, (Duration d) => kini = kini.add(d));
      }

      test('satu baris beracun + dua sehat → yang sehat terkirim', () async {
        final (a, server, p, _) = await siap();
        expect(await p.jalankan(), 2);
        expect((await a.cari('c1'))!.status, StatusAntrean.menunggu);
        expect((await a.cari('c2'))!.status, StatusAntrean.terkirim);
        expect((await a.cari('c3'))!.status, StatusAntrean.terkirim);
        // Putaran berikutnya sebelum jeda habis: baris beracun tidak dipukul lagi.
        final kirimSebelum = server.diminta.where((o) => o.method == 'POST').length;
        expect(await p.jalankan(), 0);
        expect(server.diminta.where((o) => o.method == 'POST').length, kirimSebelum);
      });

      test('batas dari server (/config) tercapai → baris beracun pindah ke TINJAU dengan pesan server', () async {
        final (a, _, p, maju) = await siap(config: {'antrean_maks_percobaan_galat_server': 3, 'antrean_maks_umur_jam': null});
        for (var i = 0; i < 3; i++) {
          await p.jalankan();
          maju(const Duration(minutes: 11));
        }
        final c1 = (await a.cari('c1'))!;
        expect(c1.status, StatusAntrean.tinjau);
        expect(c1.galatServer, 3);
        expect(c1.galatTerakhir, contains('HTTP 500 dari server'));
        await p.jalankan();
        expect((await a.cari('c1'))!.status, StatusAntrean.tinjau, reason: 'TINJAU tidak dikirim otomatis');
      });

      test('batas umur (jam) dari server juga berlaku', () async {
        final (a, _, p, maju) = await siap(config: {'antrean_maks_percobaan_galat_server': null, 'antrean_maks_umur_jam': 2});
        await p.jalankan();
        expect((await a.cari('c1'))!.status, StatusAntrean.menunggu);
        maju(const Duration(hours: 3));
        await p.jalankan();
        expect((await a.cari('c1'))!.status, StatusAntrean.tinjau);
      });

      test('server tidak menetapkan batas → tidak pernah pindah sendiri, walau 12 kali gagal', () async {
        final (a, _, p, maju) = await siap();
        for (var i = 0; i < 12; i++) {
          await p.jalankan();
          maju(const Duration(minutes: 11));
        }
        final c1 = (await a.cari('c1'))!;
        expect(c1.status, StatusAntrean.menunggu);
        expect(c1.galatServer, 12);
      });

      test('402/426 tetap menunggu walau ada batas', () async {
        final a = await isi(1);
        for (final code in [402, 426]) {
          final dio = _dio(_Server((o) => o.path == '/config'
              ? (200, {'success': true, 'data': {'antrean_maks_percobaan_galat_server': 1}}, const <String, String>{})
              : _jawab(code)));
          final p = PenguraiAntrean(store: a, dio: dio, koneksi: _Penanda(), tanpaPemulih: true, batas: () => ambilBatasAntrean(dio));
          addTearDown(p.hentikan);
          await p.jalankan();
          await p.jalankan();
          expect((await a.cari('c1'))!.status, StatusAntrean.menunggu, reason: 'HTTP $code');
        }
      });

      test('turunan bon menunggu induk yang sedang mundur (bukan TINJAU); SESI_BUKA menahan toko yang sama', () async {
        final a = AntreanMemori();
        await a.antrekan(PesanAntrean(urut: 0, clientRef: 'bon', jenis: 'BILL_BUKA', path: '/bills', body: const {'i': 1}, dibuat: DateTime(2026, 9, 15), tokoId: 'T1'));
        await a.antrekan(PesanAntrean(urut: 0, clientRef: 'ronde', jenis: 'BILL_RONDE', path: '/bills/lokal:bon/ronde', body: const {'i': 2}, dibuat: DateTime(2026, 9, 15), tokoId: 'T1'));
        await a.antrekan(PesanAntrean(urut: 0, clientRef: 'sesi', jenis: 'SESI_BUKA', path: '/sesi/buka', body: const {'i': 3}, dibuat: DateTime(2026, 9, 15), tokoId: 'T2'));
        await a.antrekan(PesanAntrean(urut: 0, clientRef: 'trx-t2', jenis: 'CHECKOUT', path: '/transaksi/checkout', body: const {'i': 4}, dibuat: DateTime(2026, 9, 15), tokoId: 'T2'));
        await a.antrekan(PesanAntrean(urut: 0, clientRef: 'trx-t3', jenis: 'CHECKOUT', path: '/transaksi/checkout', body: const {'i': 5}, dibuat: DateTime(2026, 9, 15), tokoId: 'T3'));
        final server = _Server((o) {
          final i = (o.data as Map)['i'];
          return i == 1 || i == 3 ? _jawab(503) : _jawab(201);
        });
        final p = PenguraiAntrean(store: a, dio: _dio(server), koneksi: _Penanda(), tanpaPemulih: true);
        addTearDown(p.hentikan);
        expect(await p.jalankan(), 1);
        expect((await a.cari('ronde'))!.status, StatusAntrean.menunggu);
        expect((await a.cari('ronde'))!.galatTerakhir, isNull);
        expect((await a.cari('trx-t2'))!.status, StatusAntrean.menunggu, reason: 'sesi toko T2 belum terbuka di server');
        expect((await a.cari('trx-t3'))!.status, StatusAntrean.terkirim, reason: 'toko lain tidak tertahan');
        expect(server.diminta.map((o) => (o.data as Map)['i']), [1, 3, 5]);
      });

      test('jaringan putus tetap menghentikan putaran (server tak terjangkau)', () async {
        final a = await isi(3);
        final server = _Server((_) => DioExceptionType.connectionError);
        final penanda = _Penanda();
        final p = PenguraiAntrean(store: a, dio: _dio(server), koneksi: penanda, tanpaPemulih: true);
        addTearDown(p.hentikan);
        await p.jalankan();
        expect(server.diminta, hasLength(1));
        expect(penanda.offline, isTrue);
        expect((await a.cari('c1'))!.galatServer, 0, reason: 'offline tidak dihitung sebagai galat server');
      });
    });

    test('Retry-After lebih lama dari mundur dipakai', () async {
      final a = await isi(1);
      final kini = DateTime(2026, 9, 15, 10);
      final p = PenguraiAntrean(
        store: a,
        dio: _dio(_Server((_) => _jawab(503, {'Retry-After': '300'}))),
        koneksi: _Penanda(),
        sekarang: () => kini,
        tanpaPemulih: true,
      );
      addTearDown(p.hentikan);
      await p.jalankan();
      expect((await a.cari('c1'))!.cobaLagiSetelah, kini.add(const Duration(seconds: 300)));
    });

    test('gangguan lalu pulih → terkirim pada putaran berikutnya', () async {
      var gagal = true;
      final a = await isi(1);
      var kini = DateTime(2026, 9, 15, 10);
      final p = PenguraiAntrean(
        store: a,
        dio: _dio(_Server((_) => gagal ? _jawab(502) : _jawab(201))),
        koneksi: _Penanda(),
        sekarang: () => kini,
        tanpaPemulih: true,
      );
      addTearDown(p.hentikan);
      await p.jalankan();
      gagal = false;
      kini = kini.add(const Duration(minutes: 1));
      expect(await p.jalankan(), 1);
      expect((await a.cari('c1'))!.status, StatusAntrean.terkirim);
    });

    for (final code in [401, 402, 426]) {
      test('HTTP $code → berhenti, tetap MENUNGGU tanpa jadwal ulang (tidak memukul server)', () async {
        final server = _Server((_) => _jawab(code));
        final a = await isi(2);
        final p = PenguraiAntrean(store: a, dio: _dio(server), koneksi: _Penanda(), tanpaPemulih: true);
        addTearDown(p.hentikan);
        await p.jalankan();
        expect(server.diminta.length, 1);
        final c1 = (await a.cari('c1'))!;
        expect(c1.status, StatusAntrean.menunggu);
        expect(c1.cobaLagiSetelah, isNull);
        expect(c1.galatTerakhir, isNotEmpty);
        // Tanpa jadwal ulang: 1,5 detik kemudian tidak ada kiriman lagi.
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        expect(server.diminta.length, 1);
      });
    }

    test('422 → TINJAU dan baris berikutnya tetap dikirim', () async {
      final server = _Server((o) => (o.data as Map)['i'] == 1 ? _jawab(422) : _jawab(201));
      final a = await isi(2);
      final p = PenguraiAntrean(store: a, dio: _dio(server), koneksi: _Penanda(), tanpaPemulih: true);
      addTearDown(p.hentikan);
      expect(await p.jalankan(), 1);
      expect((await a.cari('c1'))!.status, StatusAntrean.tinjau);
      expect((await a.cari('c2'))!.status, StatusAntrean.terkirim);
    });

    test('baris MENGIRIM yang tertinggal (aplikasi mati saat kirim) dikirim ulang', () async {
      final a = await isi(1);
      await a.perbarui('c1', status: StatusAntrean.mengirim);
      final p = PenguraiAntrean(store: a, dio: _dio(_Server((_) => _jawab(201))), koneksi: _Penanda(), tanpaPemulih: true);
      addTearDown(p.hentikan);
      expect(await p.jalankan(), 1);
      expect((await a.cari('c1'))!.status, StatusAntrean.terkirim);
    });

    test('hanya baris milik akun token yang dikirim', () async {
      final a = AntreanMemori();
      for (final (ref, pemilik) in [('a1', 'A'), ('b1', 'B'), ('lama', null)]) {
        await a.antrekan(PesanAntrean(
          urut: 0, clientRef: ref, jenis: 'PENGELUARAN', path: '/pengeluaran',
          body: {'ref': ref}, dibuat: DateTime(2026, 9, 15), pemilik: pemilik,
        ));
      }
      final server = _Server((_) => _jawab(201));
      String? akun = 'B';
      final p = PenguraiAntrean(store: a, dio: _dio(server), koneksi: _Penanda(), tanpaPemulih: true, pemilik: () => akun);
      addTearDown(p.hentikan);
      expect(await p.jalankan(), 1);
      expect(server.diminta.map((o) => (o.data as Map)['ref']), ['b1']);
      expect((await a.cari('a1'))!.status, StatusAntrean.menunggu);
      expect((await a.cari('lama'))!.status, StatusAntrean.menunggu);

      final r = ringkasUntuk(await a.semua(), 'B');
      expect(r.menunggu, 0);
      expect(r.milikLain, 2);

      // Belum ada akun tercatat (isolate latar setelah pembaruan) → hanya baris lama.
      akun = null;
      expect(await p.jalankan(), 1);
      expect(server.diminta.last.data['ref'], 'lama');
    });

    test('klaimTanpaPemilik (memori & drift) hanya menandai baris lama', () async {
      final db = SalinanDb(NativeDatabase.memory());
      addTearDown(db.close);
      for (final store in <AntreanStore>[AntreanMemori(), AntreanDriftStore(db)]) {
        await store.antrekan(PesanAntrean(urut: 0, clientRef: 'x', jenis: 'J', path: '/p', body: const {}, dibuat: DateTime(2026)));
        await store.antrekan(PesanAntrean(urut: 0, clientRef: 'y', jenis: 'J', path: '/p', body: const {}, dibuat: DateTime(2026), pemilik: 'B'));
        expect(await store.klaimTanpaPemilik('A'), 1);
        expect((await store.cari('x'))!.pemilik, 'A');
        expect((await store.cari('y'))!.pemilik, 'B');
      }
    });
  });

  group('salinan baca saat gangguan', () {
    Dio dioSalinan(_Server s, SalinanStore store, _Penanda penanda) => Dio(BaseOptions(validateStatus: (_) => true))
      ..httpClientAdapter = s
      ..interceptors.add(SalinanInterceptor(store: store, koneksi: penanda));

    test('GET 503 → dijawab dari salinan & koneksi offline (buka app saat server gangguan)', () async {
      final store = SalinanMemori();
      final penanda = _Penanda();
      var status = 200;
      final server = _Server((_) => (status, {'success': true, 'data': {'user': {'id': 'U1'}}}, const <String, String>{}));
      final dio = dioSalinan(server, store, penanda);
      await dio.get<dynamic>('/auth/me');
      expect(penanda.offline, isFalse);

      status = 503;
      server.diminta.clear();
      final res = await dio.get<dynamic>('/auth/me');
      expect(res.statusCode, 200);
      expect(res.headers.value(SalinanInterceptor.headerSalinan), isNotNull);
      expect((res.data as Map)['data']['user']['id'], 'U1');
      expect(penanda.offline, isTrue);
    });

    test('GET 502 tanpa salinan → jawaban asli diteruskan, tetap ditandai offline', () async {
      final penanda = _Penanda();
      final dio = dioSalinan(_Server((_) => _jawab(502)), SalinanMemori(), penanda);
      final res = await dio.get<dynamic>('/produk');
      expect(res.statusCode, 502);
      expect(penanda.offline, isTrue);
    });

    test('POST 500 menandai offline; 404 tidak (server terjangkau)', () async {
      final penanda = _Penanda();
      await dioSalinan(_Server((_) => _jawab(500)), SalinanMemori(), penanda).post<dynamic>('/transaksi/checkout');
      expect(penanda.offline, isTrue);
      final penanda2 = _Penanda()..offlineNilai = true;
      await dioSalinan(_Server((_) => _jawab(404)), SalinanMemori(), penanda2).get<dynamic>('/tidak-ada');
      expect(penanda2.offline, isFalse);
    });

    test('pemeriksa koneksi: /app/versi 503 = masih offline; 200 = online', () async {
      var status = 503;
      final c = ProviderContainer(overrides: [
        koneksiProvider.overrideWith(() => KoneksiNotifier(
              dioProbe: _dio(_Server((_) => _jawab(status))),
              jaringan: const Stream.empty(),
            )),
      ]);
      addTearDown(c.dispose);
      expect(await c.read(koneksiProvider.notifier).periksa(), isFalse);
      expect(c.read(koneksiProvider).online, isFalse);
      status = 200;
      expect(await c.read(koneksiProvider.notifier).periksa(), isTrue);
      expect(c.read(koneksiProvider).online, isTrue);
    });
  });

  group('sinkron latar (WorkManager)', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('tuleh-latar-'));
    tearDown(() async => dir.delete(recursive: true));

    test('mengirim X-Tuleh-Version & X-Tuleh-Platform; 503 → baris tetap menunggu dengan jadwal', () async {
      final db = SalinanDb(NativeDatabase.memory());
      addTearDown(db.close);
      final store = AntreanDriftStore(db);
      await store.antrekan(PesanAntrean(
        urut: 0, clientRef: 'a', jenis: 'CHECKOUT', path: '/transaksi/checkout',
        body: const {'items': []}, dibuat: DateTime(2026, 9, 15), tokoId: 'T1', pemilik: 'U1',
      ));
      final server = _Server((_) => _jawab(503));
      final dio = Dio(BaseOptions(validateStatus: (_) => true))..httpClientAdapter = server;

      await jalankanSinkronLatar(
        db: db, dio: dio, kunci: KunciPengurai(dir: dir), token: 'tok',
        versi: '2.29.0', pemilik: 'U1', pemilikDiketahui: true,
      );
      final kiriman = server.diminta.where((o) => o.method == 'POST').toList();
      expect(kiriman.length, 1);
      final h = kiriman.single.headers;
      expect(h[AppConfig.versionHeader], '2.29.0');
      expect(h[AppConfig.platformHeader], AppConfig.platform);
      expect(h['Authorization'], 'Bearer tok');
      final baris = (await store.cari('a'))!;
      expect(baris.status, StatusAntrean.menunggu, reason: 'gangguan server tidak boleh jadi TINJAU');
      expect(baris.cobaLagiSetelah, isNotNull);
    });

    test('antrean akun lain tidak dikirim dari isolate latar', () async {
      final db = SalinanDb(NativeDatabase.memory());
      addTearDown(db.close);
      final store = AntreanDriftStore(db);
      await store.antrekan(PesanAntrean(
        urut: 0, clientRef: 'milik-A', jenis: 'PENGELUARAN', path: '/pengeluaran',
        body: const {}, dibuat: DateTime(2026, 9, 15), pemilik: 'A',
      ));
      final server = _Server((_) => _jawab(201));
      final dio = Dio(BaseOptions(validateStatus: (_) => true))..httpClientAdapter = server;
      await jalankanSinkronLatar(
        db: db, dio: dio, kunci: KunciPengurai(dir: dir), token: 'tok-B',
        versi: '2.29.0', pemilik: 'B', pemilikDiketahui: true,
      );
      expect(server.diminta, isEmpty);
      expect((await store.cari('milik-A'))!.status, StatusAntrean.menunggu);
    });
  });

  group('layar Sinkronisasi: peringatan gagal berulang', () {
    Future<void> pompa(WidgetTester t, BatasAntrean? batas, {int galatServer = 10}) async {
      t.view.physicalSize = const Size(420, 900);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final a = AntreanMemori();
      await a.antrekan(PesanAntrean(
        urut: 0, clientRef: 'racun', jenis: 'PENGELUARAN', path: '/pengeluaran',
        body: const {'keterangan': 'Galon', 'nominal': 25000}, dibuat: DateTime(2026, 9, 15),
      ));
      await a.perbarui('racun', percobaan: galatServer, galatServer: galatServer, galatTerakhir: 'Server error (HTTP 500) — dikirim ulang otomatis.');
      final c = ProviderContainer(overrides: [
        antreanStoreProvider.overrideWithValue(a),
        koneksiProvider.overrideWith(() => KoneksiNotifier(jaringan: const Stream.empty())),
        batasAntreanProvider.overrideWith((_) async => batas),
      ]);
      addTearDown(c.dispose);
      await t.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: SinkronisasiScreen()),
      ));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('server tanpa batas + $ambangPeringatanPercobaanUi kali gagal → peringatan menetap, baris tetap menunggu', (t) async {
      await pompa(t, null);
      expect(find.byKey(const Key('peringatan-gagal-berulang')), findsOneWidget);
      expect(find.text('Menunggu'), findsOneWidget);
    });

    testWidgets('server menetapkan batas → tanpa peringatan (server yang memutuskan)', (t) async {
      await pompa(t, const BatasAntrean(maksPercobaanGalatServer: 20));
      expect(find.byKey(const Key('peringatan-gagal-berulang')), findsNothing);
    });

    testWidgets('di bawah ambang tampilan → tanpa peringatan', (t) async {
      await pompa(t, null, galatServer: ambangPeringatanPercobaanUi - 1);
      expect(find.byKey(const Key('peringatan-gagal-berulang')), findsNothing);
    });
  });
}
