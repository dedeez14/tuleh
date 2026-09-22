import 'dart:convert';

import 'package:dio/dio.dart';

import '../network/api_exception.dart';
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
/// - GANGGUAN pada GET — gagal jaringan, atau jawaban HTTP 408/429/5xx
///   (termasuk 502/503/504 dari gateway) → jawab dari salinan bila ada, tandai
///   koneksi offline. Tanpa salinan → jawaban/galat asli diteruskan (koneksi
///   tetap ditandai offline). Tanpa ini, membuka aplikasi saat server sedang
///   gangguan melempar kasir ke layar masuk walau salinan `/auth/me` ada.
/// - Jawaban lain (2xx, 4xx) = server terjangkau → online. 429 berkode domain
///   (`errors.kode`, mis. kuncian PIN) termasuk di sini: itu penolakan yang
///   disengaja server, bukan gangguan.
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

  /// 429 yang membawa kode galat domain (`errors.kode`, mis. `PIN_TERKUNCI`)
  /// BUKAN gangguan: server menolak dengan sadar dan jawabannya harus sampai
  /// utuh ke layar. Tanpa pengecualian ini, pengguna yang salah PIN lima kali
  /// menyalakan pita "offline" seluruh aplikasi dan GET berikutnya dijawab
  /// dari salinan — padahal servernya baik-baik saja. Kontrak `errors.kode`
  /// ini ditetapkan server (`KeamananController::terkunciPin()`).
  static bool _penolakanDomain(Response<dynamic> r) {
    if ((r.statusCode ?? 0) != 429) return false;
    final body = r.data;
    if (body is! Map) return false;
    final errors = body['errors'];
    final kode = errors is Map ? errors['kode'] : null;
    return kode is List ? kode.isNotEmpty : kode != null;
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
    final code = response.statusCode ?? 0;
    final dariSalinan = response.headers.value(headerSalinan) != null;
    if (!dariSalinan && statusGangguan(code) && !_penolakanDomain(response)) {
      if (_bolehSalin(o)) {
        final r = await _dariSalinan(o);
        if (r != null) {
          handler.resolve(r);
          return;
        }
      }
      koneksi?.tandaiOffline();
      handler.next(response);
      return;
    }
    if (_bolehSalin(o) && _sukses(response)) {
      try {
        await store.tulis(kunci(o), jsonEncode(response.data), DateTime.now());
      } catch (_) {
        // Gagal menulis salinan tidak boleh mengganggu jawaban.
      }
    }
    // Server menjawab (bukan gangguan) = online.
    if (code > 0 && !dariSalinan) {
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
