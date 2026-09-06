import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/offline/koneksi.dart';
import 'package:tuleh_pos/core/offline/pita_koneksi.dart';
import 'package:tuleh_pos/core/offline/salinan_interceptor.dart';
import 'package:tuleh_pos/core/offline/salinan_store.dart';
import 'package:tuleh_pos/core/theme/app_theme.dart';

/// Mode offline fase 1 (salinan baca) — sesuai "Tuléh Offline-First":
/// jawaban GET disalin; saat jaringan putus, salinan disajikan dan pita
/// "Offline · menampilkan data terakhir HH:MM" tampil; saat kembali, hilang.

/// Penanda koneksi sederhana untuk uji pencegat.
class _Penanda implements PenandaKoneksi {
  bool offlineNilai = false;
  DateTime? salinan;
  int online = 0;
  @override
  bool get offline => offlineNilai;
  @override
  void tandaiOffline({DateTime? ditarikPada}) {
    offlineNilai = true;
    salinan = ditarikPada ?? salinan;
  }

  @override
  void tandaiOnline() {
    offlineNilai = false;
    online++;
  }
}

/// Server tiruan sebagai adapter HTTP — jawaban & galatnya melewati SEMUA
/// interceptor persis seperti jaringan sungguhan. [hidup] = jawab; mati =
/// galat koneksi.
class _Server implements HttpClientAdapter {
  bool hidup = true;
  int panggilan = 0;
  Map<String, dynamic> data = const {'success': true, 'data': ['A', 'B']};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    panggilan++;
    if (!hidup) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    }
    return ResponseBody.fromString(
      jsonEncode(data),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('SalinanInterceptor', () {
    late _Server server;
    late SalinanMemori store;
    late _Penanda penanda;
    late Dio dio;

    setUp(() {
      server = _Server();
      store = SalinanMemori();
      penanda = _Penanda();
      dio = Dio(BaseOptions(validateStatus: (_) => true));
      dio.httpClientAdapter = server;
      dio.interceptors.add(
        SalinanInterceptor(store: store, koneksi: penanda),
      );
    });

    test('GET sukses disalin per jalur+query (toko_id ikut)', () async {
      await dio.get<dynamic>('/produk', queryParameters: {'toko_id': 'T1', 'page': 1});
      await dio.get<dynamic>('/produk', queryParameters: {'page': 1, 'toko_id': 'T2'});
      expect(store.jumlah, 2);
      expect(await store.baca('/produk?page=1&toko_id=T1'), isNotNull);
      expect(await store.baca('/produk?page=1&toko_id=T2'), isNotNull);
      expect(penanda.offlineNilai, isFalse);
    });

    test('jaringan putus: GET dijawab dari salinan, header umur, koneksi ditandai offline', () async {
      await dio.get<dynamic>('/produk', queryParameters: {'toko_id': 'T1'});
      server.hidup = false;
      final r = await dio.get<dynamic>('/produk', queryParameters: {'toko_id': 'T1'});
      expect(r.statusCode, 200);
      expect((r.data as Map)['data'], ['A', 'B']);
      expect(r.headers.value(SalinanInterceptor.headerSalinan), isNotNull);
      expect(penanda.offlineNilai, isTrue);
      expect(penanda.salinan, isNotNull);
    });

    test('jaringan putus tanpa salinan: galat asli diteruskan (bukan data palsu)', () async {
      server.hidup = false;
      await expectLater(
        dio.get<dynamic>('/pelanggan', queryParameters: {'toko_id': 'T1'}),
        throwsA(isA<DioException>()),
      );
      expect(penanda.offlineNilai, isTrue);
    });

    test('sudah diketahui offline: salinan disajikan SEGERA tanpa menyentuh jaringan', () async {
      await dio.get<dynamic>('/sesi/aktif', queryParameters: {'toko_id': 'T1'});
      final sebelum = server.panggilan;
      penanda.offlineNilai = true;
      final r = await dio.get<dynamic>('/sesi/aktif', queryParameters: {'toko_id': 'T1'});
      expect(r.headers.value(SalinanInterceptor.headerSalinan), isNotNull);
      expect(server.panggilan, sebelum, reason: 'tidak ada permintaan ke server');
    });

    test('POST tidak pernah disalin; gagal jaringan menandai offline', () async {
      await dio.post<dynamic>('/transaksi/checkout', data: {'x': 1});
      expect(store.jumlah, 0);
      server.hidup = false;
      await expectLater(
        dio.post<dynamic>('/transaksi/checkout', data: {'x': 1}),
        throwsA(isA<DioException>()),
      );
      expect(penanda.offlineNilai, isTrue);
    });

    test('jawaban sukses dari server menandai online kembali', () async {
      penanda.offlineNilai = true;
      await dio.post<dynamic>('/sesi/buka', data: {}); // bukan GET → ke jaringan
      expect(penanda.offlineNilai, isFalse);
      expect(penanda.online, 1);
    });

    test('/app/versi dan /demo/* tidak disalin; jawaban gagal (success:false) tidak disalin', () async {
      await dio.get<dynamic>('/app/versi', queryParameters: {'versi': '1'});
      await dio.get<dynamic>('/demo/perangkat/x');
      server.data = const {'success': false, 'message': 'x'};
      await dio.get<dynamic>('/laporan/keuangan');
      expect(store.jumlah, 0);
    });
  });

  group('KoneksiNotifier', () {
    test('jaringan hilang → offline; pemeriksaan berhasil → online', () async {
      final probeHidup = Dio(BaseOptions(validateStatus: (_) => true));
      probeHidup.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) => h.resolve(
            Response(requestOptions: o, statusCode: 200, data: const {'success': true}),
          ),
        ),
      );
      final c = ProviderContainer(
        overrides: [
          koneksiProvider.overrideWith(
            () => KoneksiNotifier(
              dioProbe: probeHidup,
              jaringan: Stream.fromIterable([
                [ConnectivityResult.none],
              ]),
            ),
          ),
        ],
      );
      addTearDown(c.dispose);
      c.listen(koneksiProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);
      expect(c.read(koneksiProvider).online, isFalse);

      expect(await c.read(koneksiProvider.notifier).periksa(), isTrue);
      expect(c.read(koneksiProvider).online, isTrue);
    });
  });

  group('PitaKoneksi', () {
    testWidgets('tampil saat offline dengan jam salinan, hilang saat online', (t) async {
      final c = ProviderContainer(
        overrides: [
          koneksiProvider.overrideWith(
            () => KoneksiNotifier(jaringan: const Stream.empty()),
          ),
        ],
      );
      addTearDown(c.dispose);
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: PitaKoneksi(child: Text('isi'))),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('Offline'), findsNothing);

      c.read(koneksiProvider.notifier).tandaiOffline(
        ditarikPada: DateTime(2026, 9, 5, 14, 2),
      );
      await t.pumpAndSettle();
      expect(find.text('Offline · menampilkan data terakhir 14:02'), findsOneWidget);
      expect(find.text('Coba lagi'), findsOneWidget);

      c.read(koneksiProvider.notifier).tandaiOnline();
      await t.pumpAndSettle();
      expect(find.textContaining('Offline'), findsNothing);
      expect(find.text('isi'), findsOneWidget);
    });
  });
}
