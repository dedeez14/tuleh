import 'package:dio/dio.dart';

import '../../domain/entities/app_version_info.dart';
import '../../domain/sumber_apk.dart';
import '../../domain/versi.dart';

/// Sumber pembaruan dari GitHub Releases — tempat APK Flutter sebenarnya
/// diterbitkan (tag `flutter-vX.Y.Z`, workflow flutter-release.yml).
///
/// Server MOVERA (`/app/versi`) hanya mengenal versi aplikasi Android lama
/// (Capacitor, 0.9.x), jadi untuk aplikasi Flutter ia selalu menjawab
/// "tidak ada pembaruan". Sumber ini menutup celah itu tanpa perubahan server.
///
/// Dio-nya TERPISAH dari klien API: tanpa baseUrl tatreport, tanpa header
/// Authorization (token tidak boleh bocor ke GitHub), tanpa interceptor demo.
class GithubReleaseSource {
  GithubReleaseSource({Dio? dio, this.repo = SumberApk.repoGithub})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
              headers: const {'Accept': 'application/vnd.github+json'},
              validateStatus: (_) => true,
            ),
          );

  final Dio _dio;
  final String repo;

  static final _tagFlutter = RegExp(r'^flutter-v(\d+\.\d+\.\d+)$');

  /// Rilis Flutter terbaru yang lebih baru dari [versiSekarang]; null bila
  /// tidak ada atau cek gagal (fail-open, sama seperti cek server).
  Future<AppVersionInfo?> cek(
    String versiSekarang, {
    required List<String> abiPerangkat,
  }) async {
    final sekarang = Versi.parse(versiSekarang);
    if (sekarang == null) return null;

    try {
      final res = await _dio.get<dynamic>(
        'https://api.github.com/repos/$repo/releases',
        queryParameters: {'per_page': 20},
      );
      if ((res.statusCode ?? 0) != 200 || res.data is! List) return null;
      return pilih(res.data as List, sekarang, abiPerangkat: abiPerangkat);
    } catch (_) {
      return null;
    }
  }

  /// Logika murni (bisa diuji tanpa jaringan): dari daftar rilis GitHub,
  /// ambil tag flutter-v* tertinggi yang > [sekarang], lalu aset APK yang
  /// cocok ABI perangkat.
  static AppVersionInfo? pilih(
    List<dynamic> rilis,
    Versi sekarang, {
    required List<String> abiPerangkat,
  }) {
    Map<String, dynamic>? terbaik;
    Versi? versiTerbaik;

    for (final r in rilis) {
      if (r is! Map) continue;
      if (r['draft'] == true || r['prerelease'] == true) continue;
      final tag = r['tag_name']?.toString() ?? '';
      final m = _tagFlutter.firstMatch(tag);
      if (m == null) continue;
      final v = Versi.parse(m.group(1));
      if (v == null || !(v > sekarang)) continue;
      if (versiTerbaik == null || v > versiTerbaik) {
        versiTerbaik = v;
        terbaik = Map<String, dynamic>.from(r);
      }
    }
    if (terbaik == null || versiTerbaik == null) return null;

    final aset = _asetUntuk(terbaik['assets'], abiPerangkat);
    if (aset == null) return null;

    return AppVersionInfo(
      wajib: false, // GitHub tak tahu kebijakan wajib; itu wewenang server.
      updateTersedia: true,
      versiTerbaru: versiTerbaik.toString(),
      versiMinimum: null,
      catatan: _ringkasCatatan(terbaik['body']?.toString()),
      androidUrl: aset['browser_download_url']?.toString(),
      androidNama: aset['name']?.toString(),
      ukuran: aset['size'] is num ? (aset['size'] as num).toInt() : null,
    );
  }

  /// Pilih APK sesuai ABI perangkat (urutan prioritas dari sistem), lalu
  /// jatuh ke arm64 sebagai tebakan terbaik untuk ponsel Android 10+.
  static Map<String, dynamic>? _asetUntuk(
    dynamic assets,
    List<String> abiPerangkat,
  ) {
    if (assets is! List) return null;
    // Hanya aset .apk yang URL-nya lolos kebijakan sumber — URL lain akan
    // ditolak native saat unduh, jadi lebih baik tak ditawarkan sama sekali.
    final apk = [
      for (final a in assets)
        if (a is Map &&
            '${a['name']}'.toLowerCase().endsWith('.apk') &&
            SumberApk.diizinkan(a['browser_download_url']?.toString()))
          Map<String, dynamic>.from(a),
    ];
    if (apk.isEmpty) return null;

    Map<String, dynamic>? cocok(String abi) {
      for (final a in apk) {
        if ('${a['name']}'.toLowerCase().contains(abi.toLowerCase())) return a;
      }
      return null;
    }

    for (final abi in abiPerangkat) {
      final a = cocok(abi);
      if (a != null) return a;
    }
    return cocok('arm64-v8a') ?? apk.first;
  }

  /// Catatan rilis GitHub berbentuk Markdown panjang; ambil beberapa baris
  /// awal saja untuk banner.
  static String _ringkasCatatan(String? body) {
    if (body == null || body.trim().isEmpty) return '';
    final baris = body
        .split('\n')
        .map((b) => b.replaceAll(RegExp(r'^[#*\-\s]+'), '').trim())
        .where((b) => b.isNotEmpty)
        .take(4)
        .join('\n');
    return baris.length > 300 ? '${baris.substring(0, 297)}…' : baris;
  }
}
