import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:tuleh_pos/core/storage/secure_storage.dart';
import 'package:tuleh_pos/features/demo/data/masa_coba_service.dart';

/// MasaCobaService tanpa jaringan untuk test: Dio-nya membalas /app/versi
/// dengan header Date tetap (waktu server tiruan), penyimpanannya di memori.
/// Tanpa ini, setiap `startDemo()` di test mencoba menghubungi server.
class MasaCobaPalsu extends MasaCobaService {
  /// [offline] = server tak terjangkau (semua permintaan gagal).
  MasaCobaPalsu({DateTime? waktuServer, SecureStorage? storage, bool offline = false})
    : super(
        storage ?? _PenyimpananMemori(),
        dio: _dioTiruan(offline ? null : (waktuServer ?? DateTime.utc(2026, 9, 5, 3))),
        versi: '0.0.0-test',
      );

  static Dio _dioTiruan(DateTime? waktu) {
    final dio = Dio(BaseOptions(validateStatus: (_) => true));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) => waktu == null
            ? h.reject(DioException(requestOptions: o, type: DioExceptionType.connectionError))
            : h.resolve(
                Response(
                  requestOptions: o,
                  statusCode: 200,
                  data: const {'success': true, 'data': {}},
                  headers: Headers.fromMap({
                    'date': [_rfc1123(waktu)],
                  }),
                ),
              ),
      ),
    );
    return dio;
  }

  static String _rfc1123(DateTime t) {
    const hari = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const bulan = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final u = t.toUtc();
    String dua(int n) => n.toString().padLeft(2, '0');
    return '${hari[u.weekday - 1]}, ${dua(u.day)} ${bulan[u.month - 1]} ${u.year} '
        '${dua(u.hour)}:${dua(u.minute)}:${dua(u.second)} GMT';
  }
}

class _PenyimpananMemori extends SecureStorage {
  _PenyimpananMemori() : super(const FlutterSecureStorage());
  final Map<String, String> _m = {};
  @override
  Future<String?> bacaNilai(String k) async => _m[k];
  @override
  Future<void> tulisNilai(String k, String? v) async =>
      v == null ? _m.remove(k) : _m[k] = v;
}
