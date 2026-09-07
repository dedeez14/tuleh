import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';

/// Jembatan ke native (MainActivity.kt) untuk unduh + pasang APK pembaruan.
/// Hanya Android; platform lain → no-op / tak didukung.
///
/// Unduhan UTAMA dilakukan di sini lewat Dio (mengikuti redirect GitHub ke
/// release-assets.githubusercontent.com, progres per byte, pengawas macet,
/// verifikasi ukuran). DownloadManager sistem hanya cadangan: di sebagian
/// perangkat (mis. MIUI) ia dibatasi/dinonaktifkan sehingga unduhan tak
/// pernah mulai dan selalu "gagal".
class ApkInstaller {
  ApkInstaller({Dio? dio, this.jedaMacet = const Duration(seconds: 60)})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 60),
              followRedirects: true,
              maxRedirects: 5,
              headers: const {'Accept': 'application/octet-stream'},
              validateStatus: (_) => true,
            ),
          );

  static const MethodChannel _method = MethodChannel('tuleh/updater');
  static const EventChannel _progress = EventChannel('tuleh/updater/progress');

  final Dio _dio;

  /// Tanpa byte baru selama ini → unduhan dianggap macet.
  final Duration jedaMacet;

  CancelToken? _batal;
  final _progresDart = StreamController<int>.broadcast();

  /// Auto-Update dalam-app hanya untuk Android (app tak menargetkan web).
  bool get isSupported => Platform.isAndroid;

  /// Apakah izin "Instal aplikasi tak dikenal" sudah diberikan.
  Future<bool> canInstall() async {
    if (!isSupported) return false;
    final r = await _method.invokeMethod<bool>('canInstall');
    return r ?? false;
  }

  /// Buka layar sistem "Instal aplikasi tak dikenal" untuk paket ini.
  Future<void> openInstallPermission() async {
    if (!isSupported) return;
    await _method.invokeMethod<void>('openInstallPermission');
  }

  /// Progres unduhan 0..100 — gabungan unduhan Dart dan cadangan native.
  Stream<int> get progress => StreamGroup.merge([
    _progresDart.stream,
    if (isSupported)
      _progress.receiveBroadcastStream().map((e) => (e as num).toInt()),
  ]);

  /// Info paket terpasang (versi, kode, sidik jari tanda tangan) — diagnosa.
  Future<Map<String, dynamic>> infoPaket() async {
    if (!isSupported) return const {};
    final r = await _method.invokeMethod<dynamic>('infoPaket');
    return r is Map ? Map<String, dynamic>.from(r) : const {};
  }

  /// Unduh APK → kembalikan path lokal. Lempar [PlatformException] bila gagal.
  /// [ukuran] (bila diketahui dari sumber) dipakai memastikan berkas utuh.
  Future<String> download(
    String url, {
    required String filename,
    int? ukuran,
    String? direktori,
  }) async {
    final dir = direktori ?? await _direktoriUnduhan();
    try {
      return await _unduhDio(url, dir: dir, filename: filename, ukuran: ukuran);
    } on PlatformException catch (e) {
      // Dibatalkan pengguna atau berkas rusak: jangan diulang lewat cadangan.
      if (e.code == 'BATAL' || e.code == 'UKURAN') rethrow;
      if (!isSupported) rethrow;
      // Cadangan: DownloadManager sistem (jalur lama).
      try {
        return await _unduhNative(url, filename);
      } on PlatformException {
        rethrow;
      } catch (_) {
        rethrow;
      }
    }
  }

  Future<String> _direktoriUnduhan() async {
    if (!isSupported) return Directory.systemTemp.path;
    final d = await _method.invokeMethod<String>('downloadDir');
    if (d == null || d.isEmpty) {
      throw PlatformException(code: 'STORAGE', message: 'Penyimpanan tidak tersedia.');
    }
    return d;
  }

  Future<String> _unduhDio(
    String url, {
    required String dir,
    required String filename,
    int? ukuran,
  }) async {
    final tujuan = File('$dir/$filename');
    final sementara = File('$dir/$filename.part');
    if (await sementara.exists()) await sementara.delete();
    if (await tujuan.exists()) await tujuan.delete();

    final batal = CancelToken();
    _batal = batal;
    var terakhir = DateTime.now();
    var persenTerakhir = -1;
    final pengawas = Timer.periodic(const Duration(seconds: 5), (_) {
      if (DateTime.now().difference(terakhir) > jedaMacet && !batal.isCancelled) {
        batal.cancel('macet');
      }
    });
    try {
      final res = await _dio.download(
        url,
        sementara.path,
        cancelToken: batal,
        deleteOnError: true,
        onReceiveProgress: (diterima, total) {
          terakhir = DateTime.now();
          final basis = total > 0 ? total : (ukuran ?? 0);
          if (basis > 0) {
            final p = (diterima * 100 ~/ basis).clamp(0, 100);
            if (p != persenTerakhir) {
              persenTerakhir = p;
              _progresDart.add(p);
            }
          }
        },
      );
      final code = res.statusCode ?? 0;
      if (code < 200 || code >= 300) {
        throw PlatformException(code: 'HTTP', message: 'Server unduhan menjawab HTTP $code.');
      }
      final panjang = await sementara.length();
      if (ukuran != null && ukuran > 0 && panjang != ukuran) {
        throw PlatformException(
          code: 'UKURAN',
          message: 'Berkas tidak utuh ($panjang dari $ukuran byte). Periksa koneksi lalu coba lagi.',
        );
      }
      await sementara.rename(tujuan.path);
      _progresDart.add(100);
      return tujuan.path;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        final macet = '${e.error ?? e.message}'.contains('macet');
        throw PlatformException(
          code: macet ? 'MACET' : 'BATAL',
          message: macet
              ? 'Unduhan macet — tidak ada data selama ${jedaMacet.inSeconds} detik. Periksa koneksi lalu coba lagi.'
              : 'Unduhan dibatalkan.',
        );
      }
      throw PlatformException(code: 'JARINGAN', message: 'Unduhan gagal: ${_pesanDio(e)}');
    } finally {
      pengawas.cancel();
      if (identical(_batal, batal)) _batal = null;
      try {
        if (await sementara.exists()) await sementara.delete();
      } catch (_) {}
    }
  }

  static String _pesanDio(DioException e) => switch (e.type) {
    DioExceptionType.connectionTimeout => 'waktu sambung habis',
    DioExceptionType.receiveTimeout => 'server tidak mengirim data',
    DioExceptionType.connectionError => 'tidak dapat terhubung (${e.message ?? 'jaringan'})',
    DioExceptionType.badCertificate => 'sertifikat server tidak valid',
    _ => e.message ?? 'kesalahan jaringan',
  };

  Future<String> _unduhNative(String url, String filename) async {
    final path = await _method.invokeMethod<String>(
      'download',
      {'url': url, 'filename': filename},
    );
    if (path == null || path.isEmpty) {
      throw PlatformException(code: 'DOWNLOAD', message: 'Unduhan gagal.');
    }
    return path;
  }

  /// Buka pemasang sistem untuk APK yang sudah diunduh. Mengembalikan true
  /// bila pemasang langsung terbuka; false bila app sedang di latar belakang —
  /// native menunda dan membuka pemasang otomatis saat app kembali ke depan.
  Future<bool> install(String path) async {
    if (!isSupported) return false;
    final r = await _method.invokeMethod<dynamic>('install', {'path': path});
    if (r is Map) return r['launched'] != false;
    return true;
  }

  /// Batalkan unduhan yang sedang berjalan (Dart maupun cadangan native).
  Future<void> cancel() async {
    _batal?.cancel('batal');
    if (!isSupported) return;
    await _method.invokeMethod<void>('cancel');
  }
}

/// Gabungan beberapa stream (tanpa paket tambahan).
class StreamGroup {
  static Stream<T> merge<T>(Iterable<Stream<T>> streams) {
    final ctrl = StreamController<T>.broadcast();
    final subs = <StreamSubscription<T>>[];
    ctrl.onListen = () {
      for (final s in streams) {
        subs.add(s.listen(ctrl.add, onError: ctrl.addError));
      }
    };
    ctrl.onCancel = () async {
      for (final s in subs) {
        await s.cancel();
      }
      subs.clear();
    };
    return ctrl.stream;
  }
}
