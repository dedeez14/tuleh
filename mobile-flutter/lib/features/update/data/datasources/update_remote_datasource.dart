import 'package:dio/dio.dart';

import '../../../../core/constants/app_config.dart';
import '../../../../core/network/api_exception.dart';
import '../../domain/entities/app_version_info.dart';
import 'github_release_source.dart';

/// Hasil bertanya ke server: [dijawab] = server terjangkau dan memberi
/// jawaban yang sah (apa pun isinya).
typedef _JawabanServer = ({AppVersionInfo info, bool dijawab});

/// Cek versi (Auto-Update). Server adalah SATU-SATUNYA pemutus kebijakan:
///
/// 1. Server MOVERA `GET /app/versi?versi=<v>&platform=android-flutter`
///    (tanpa auth). Server memegang kebijakan admin — versi terbaru yang
///    boleh ditawarkan (penahanan rilis bertahap), `wajib`, dan batas laju.
///    Bila server menjawab, jawabannya dipakai APA ADANYA — termasuk "tidak
///    ada pembaruan". Dulu jawaban itu diabaikan dan GitHub ditanya secara
///    anonim, sehingga rilis yang sengaja ditahan admin tetap ditawarkan dan
///    batas laju API GitHub per-IP (toko berbagi IP) cepat habis.
/// 2. GitHub Releases `flutter-v*` hanya dipakai bila:
///    - server TIDAK TERJANGKAU (jaringan putus / gangguan 408/429/5xx); atau
///    - server menawarkan versi X tetapi berkasnya tidak cocok dengan ABI
///      perangkat — lalu dari GitHub diambil aset versi X yang SAMA (bukan
///      versi tertinggi), dan `wajib` tetap dari server.
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
    final jawaban = await _cekServer(versi);
    final dariServer = jawaban.info;
    if (!jawaban.dijawab) {
      // Server tak terjangkau: GitHub sebagai cadangan (tanpa `wajib`).
      final dariGithub = await _github.cek(versi, abiPerangkat: abiPerangkat);
      return dariGithub ?? AppVersionInfo.none;
    }
    if (dariServer.wajib || dariServer.updateTersedia) {
      final cocok = _samakanAbi(dariServer, abiPerangkat);
      if (cocok != null) return cocok;
      // Berkas server tidak cocok ABI perangkat: pakai aset per-ABI di GitHub
      // untuk versi yang DITAWARKAN server, dan PERTAHANKAN `wajib` dari
      // server — hanya server yang berhak menyatakannya.
      final dariGithub = await _github.cek(
        versi,
        abiPerangkat: abiPerangkat,
        versiTepat: dariServer.versiTerbaru,
      );
      if (dariGithub != null) return dariGithub.dengan(wajib: dariServer.wajib);
      return dariServer;
    }
    return dariServer; // server menjawab "tidak ada pembaruan" → dipercaya
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

  Future<_JawabanServer> _cekServer(String versi) async {
    try {
      final res = await _dio.get<dynamic>(
        '/app/versi',
        // `platform` eksplisit: tanpa ini server menebak dari versi mayor.
        queryParameters: {'versi': versi, 'platform': AppConfig.platform},
      );
      final code = res.statusCode ?? 0;
      // Gangguan = server tak terjangkau secara efektif → boleh ke cadangan.
      if (statusGangguan(code)) return (info: AppVersionInfo.none, dijawab: false);
      final body = res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : const <String, dynamic>{};
      if (code < 200 || code >= 300 || body['success'] != true || body['data'] is! Map) {
        // Server terjangkau tetapi menolak/aneh (4xx, amplop rusak): jangan
        // melompati kebijakan server lewat GitHub. Fail-open: tak ada tawaran.
        return (info: AppVersionInfo.none, dijawab: true);
      }
      return (
        info: AppVersionInfo.fromJson(Map<String, dynamic>.from(body['data'] as Map)),
        dijawab: true,
      );
    } on DioException catch (e) {
      final code = e.response?.statusCode ?? 0;
      return (info: AppVersionInfo.none, dijawab: !statusGangguan(code));
    } catch (_) {
      // Bentuk jawaban tak terduga dari server yang terjangkau.
      return (info: AppVersionInfo.none, dijawab: true);
    }
  }
}
