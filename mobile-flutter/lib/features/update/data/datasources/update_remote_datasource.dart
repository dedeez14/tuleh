import 'package:dio/dio.dart';

import '../../domain/entities/app_version_info.dart';

/// Cek versi ke server (Auto-Update). `GET /app/versi?versi=<v>` — TANPA auth.
/// FAIL-OPEN: error jaringan / bentuk tak terduga → [AppVersionInfo.none]
/// (kegagalan cek TAK PERNAH memblokir app; penegakan keras lewat HTTP 426).
class UpdateRemoteDataSource {
  UpdateRemoteDataSource(this._dio);

  final Dio _dio;

  Future<AppVersionInfo> cek(String versi) async {
    try {
      final res = await _dio.get<dynamic>(
        '/app/versi',
        queryParameters: {'versi': versi},
      );
      final code = res.statusCode ?? 0;
      if (code < 200 || code >= 300) return AppVersionInfo.none;
      final body = res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : const <String, dynamic>{};
      if (body['success'] != true || body['data'] is! Map) {
        return AppVersionInfo.none;
      }
      return AppVersionInfo.fromJson(
        Map<String, dynamic>.from(body['data'] as Map),
      );
    } catch (_) {
      return AppVersionInfo.none; // fail-open
    }
  }
}
