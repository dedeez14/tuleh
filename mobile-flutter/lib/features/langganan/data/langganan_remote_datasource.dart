import 'package:dio/dio.dart';

import '../domain/langganan.dart';

/// `GET /langganan/status` & `GET /kontak-cs` (baca — tidak pernah diblokir
/// langganan). Gagal apa pun → null: fitur ini informatif, tidak boleh
/// menghalangi kasir.
class LanggananRemoteDataSource {
  LanggananRemoteDataSource(this._dio);

  final Dio _dio;

  Future<Map<String, dynamic>?> _data(String path) async {
    try {
      final res = await _dio.get<dynamic>(path);
      final code = res.statusCode ?? 0;
      final body = res.data;
      if (code < 200 || code >= 300 || body is! Map || body['success'] != true) return null;
      final data = body['data'];
      return data is Map ? Map<String, dynamic>.from(data) : null;
    } catch (_) {
      return null;
    }
  }

  Future<StatusLangganan?> status() async {
    final d = await _data('/langganan/status');
    return d == null ? null : StatusLangganan.fromJson(d);
  }

  Future<KontakCs?> kontakCs() async {
    final d = await _data('/kontak-cs');
    return d == null ? null : KontakCs.fromJson(d);
  }
}
