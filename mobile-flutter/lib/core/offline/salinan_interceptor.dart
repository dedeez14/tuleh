import 'dart:convert';

import 'package:dio/dio.dart';

import 'koneksi.dart';
import 'salinan_store.dart';

/// Mode offline fase 1 — salinan baca, transparan bagi seluruh lapisan data.
///
/// Dipasang PALING AKHIR di rantai interceptor Dio (setelah header/toko_id
/// dan Mode Demo), sehingga:
/// - kunci salinan sudah memuat `toko_id` (data per toko tidak tertukar);
/// - jawaban Mode Demo tidak pernah disalin (DemoInterceptor menyelesaikan
///   permintaan sebelum sampai ke sini).
///
/// Aturan:
/// - Hanya GET yang disalin, dan hanya jawaban sukses (2xx + success:true).
/// - Gagal jaringan (bukan HTTP 4xx/5xx) pada GET → jawab dari salinan bila
///   ada, tandai koneksi offline. Tanpa salinan → galat asli diteruskan.
/// - Saat sudah diketahui offline, GET dijawab dari salinan SEGERA tanpa
///   menunggu timeout; permintaan tulis tetap dicoba ke jaringan (fase 2:
///   antrean).
/// - Jawaban dari salinan membawa header [headerSalinan] = waktu tarik ISO.
class SalinanInterceptor extends Interceptor {
  SalinanInterceptor({
    required this.store,
    required this.koneksi,
    this.jangan = const ['/app/versi', '/demo/'],
  });

  final SalinanStore store;

  /// Penanda status koneksi; null bila tidak dipantau (test).
  final PenandaKoneksi? koneksi;

  /// Awalan jalur yang tidak pernah disalin (cek versi, masa coba).
  final List<String> jangan;

  static const headerSalinan = 'x-tuleh-salinan';

  bool _bolehSalin(RequestOptions o) {
    if (o.method.toUpperCase() != 'GET') return false;
    final path = o.path;
    for (final j in jangan) {
      if (path.startsWith(j)) return false;
    }
    return true;
  }

  /// Kunci stabil: jalur + query terurut (termasuk toko_id).
  static String kunci(RequestOptions o) {
    final q = o.queryParameters.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final query = q.map((e) => '${e.key}=${e.value}').join('&');
    return query.isEmpty ? o.path : '${o.path}?$query';
  }

  static bool _sukses(Response<dynamic> r) {
    final code = r.statusCode ?? 0;
    final body = r.data;
    return code >= 200 && code < 300 && body is Map && body['success'] == true;
  }

  static bool _gagalJaringan(DioException e) => switch (e.type) {
    DioExceptionType.connectionError ||
    DioExceptionType.connectionTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.unknown => true,
    _ => false,
  };

  Future<Response<dynamic>?> _dariSalinan(RequestOptions o) async {
    final s = await store.baca(kunci(o));
    if (s == null) return null;
    koneksi?.tandaiOffline(ditarikPada: s.ditarikPada);
    return Response<dynamic>(
      requestOptions: o,
      statusCode: 200,
      data: jsonDecode(s.json),
      headers: Headers.fromMap({
        headerSalinan: [s.ditarikPada.toIso8601String()],
      }),
    );
  }

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final offline = koneksi?.offline ?? false;
    if (offline && _bolehSalin(options)) {
      final r = await _dariSalinan(options);
      if (r != null) {
        handler.resolve(r);
        return;
      }
    }
    handler.next(options);
  }

  @override
  Future<void> onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) async {
    final o = response.requestOptions;
    if (_bolehSalin(o) && _sukses(response)) {
      try {
        await store.tulis(kunci(o), jsonEncode(response.data), DateTime.now());
      } catch (_) {
        // Gagal menulis salinan tidak boleh mengganggu jawaban.
      }
    }
    // Sampai ke server (kode apa pun) = online.
    if ((response.statusCode ?? 0) > 0 &&
        response.headers.value(headerSalinan) == null) {
      koneksi?.tandaiOnline();
    }
    handler.next(response);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (_gagalJaringan(err)) {
      if (_bolehSalin(err.requestOptions)) {
        final r = await _dariSalinan(err.requestOptions);
        if (r != null) {
          handler.resolve(r);
          return;
        }
      }
      // Gagal jaringan apa pun (termasuk tulis) = offline; pita status tampil.
      koneksi?.tandaiOffline();
    }
    handler.next(err);
  }
}
