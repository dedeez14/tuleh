import 'package:dio/dio.dart';

import '../../domain/entities/app_version_info.dart';
import 'github_release_source.dart';

/// Cek versi (Auto-Update). Dua sumber, berurutan:
///
/// 1. Server MOVERA `GET /app/versi?versi=<v>&platform=android-flutter`
///    (tanpa auth). Sejak 9 Sep 2026 server mengenal jalur rilis Flutter (2.x)
///    terpisah dari aplikasi Android lama (0.9.x). Hanya server yang boleh
///    menyatakan `wajib` (penegakan keras lewat HTTP 426).
/// 2. GitHub Releases `flutter-v*` dipakai sebagai cadangan: bila server tidak
///    menawarkan apa pun, ATAU berkas yang ditawarkan tidak cocok dengan ABI
///    perangkat (server mengiklankan arm64-v8a saja, sementara ponsel 32-bit
///    memerlukan armeabi-v7a — memasang APK ABI yang salah selalu gagal).
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
    if (dariServer.wajib || dariServer.updateTersedia) {
      final cocok = _samakanAbi(dariServer, abiPerangkat);
      if (cocok != null) return cocok;
      // Berkas server tidak cocok ABI perangkat: pakai aset per-ABI di GitHub,
      // tetapi PERTAHANKAN `wajib` dari server — hanya server yang berhak
      // menyatakannya.
      final dariGithub = await _github.cek(versi, abiPerangkat: abiPerangkat);
      if (dariGithub != null) return dariGithub.dengan(wajib: dariServer.wajib);
      return dariServer;
    }

    final dariGithub = await _github.cek(versi, abiPerangkat: abiPerangkat);
    return dariGithub ?? dariServer;
  }

  /// Nama berkas APK server memuat ABI (mis. `Tuleh-2.24.0-arm64-v8a.apk`).
  /// Bila perangkat memakai ABI lain, tukar potongan itu — server melayani
  /// semua varian di jalur yang sama. Mengembalikan null bila tidak yakin.
  static AppVersionInfo? _samakanAbi(AppVersionInfo info, List<String> abiPerangkat) {
    final nama = info.androidNama;
    final url = info.androidUrl;
    if (nama == null || url == null) return info; // tak ada unduhan → apa adanya
    const dikenal = ['arm64-v8a', 'armeabi-v7a', 'x86_64', 'x86'];
    final abiBerkas = dikenal.where(nama.contains).firstOrNull;
    if (abiBerkas == null) return info; // bukan APK per-ABI (mis. universal)
    if (abiPerangkat.isEmpty || abiPerangkat.contains(abiBerkas)) return info;
    final abiTujuan = abiPerangkat.firstWhere(
      dikenal.contains,
      orElse: () => '',
    );
    if (abiTujuan.isEmpty) return null; // ABI asing → serahkan ke GitHub
    return info.dengan(
      androidNama: nama.replaceAll(abiBerkas, abiTujuan),
      androidUrl: url.replaceAll(abiBerkas, abiTujuan),
      // Ukuran milik berkas lain; kosongkan agar pengunduh tidak salah menilai.
      kosongkanUkuran: true,
    );
  }

  Future<AppVersionInfo> _cekServer(String versi) async {
    try {
      final res = await _dio.get<dynamic>(
        '/app/versi',
        // `platform` eksplisit: tanpa ini server menebak dari versi mayor.
        queryParameters: {'versi': versi, 'platform': 'android-flutter'},
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
