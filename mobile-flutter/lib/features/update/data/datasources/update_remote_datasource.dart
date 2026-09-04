import 'package:dio/dio.dart';

import '../../domain/entities/app_version_info.dart';
import 'github_release_source.dart';

/// Cek versi (Auto-Update). Dua sumber, berurutan:
///
/// 1. Server MOVERA `GET /app/versi?versi=<v>` (tanpa auth). Hanya server yang
///    boleh menyatakan `wajib` (penegakan keras lewat HTTP 426).
/// 2. Bila server tidak menawarkan apa pun: GitHub Releases `flutter-v*` —
///    tempat APK Flutter benar-benar diterbitkan. Server hanya mengenal versi
///    aplikasi Android lama (0.9.x), sehingga tanpa langkah ini aplikasi
///    Flutter tidak pernah tahu ada versi baru.
///
/// FAIL-OPEN: kegagalan cek TAK PERNAH memblokir aplikasi.
class UpdateRemoteDataSource {
  UpdateRemoteDataSource(this._dio, {GithubReleaseSource? github})
    : _github = github ?? GithubReleaseSource();

  final Dio _dio;
  final GithubReleaseSource _github;

  Future<AppVersionInfo> cek(
    String versi, {
    List<String> abiPerangkat = const [],
  }) async {
    final dariServer = await _cekServer(versi);
    if (dariServer.wajib || dariServer.updateTersedia) return dariServer;

    final dariGithub = await _github.cek(versi, abiPerangkat: abiPerangkat);
    return dariGithub ?? dariServer;
  }

  Future<AppVersionInfo> _cekServer(String versi) async {
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
