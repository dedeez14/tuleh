import 'dart:io' show HttpDate;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/secure_storage.dart';
import '../domain/masa_coba.dart';

/// Membaca waktu server dan catatan tersimpan, lalu memutuskan lewat
/// [MasaCoba.periksa]. Dio-nya TERPISAH dari klien aplikasi agar tidak
/// dicegat Mode Demo (DemoInterceptor menjawab /app/versi sendiri).
class MasaCobaService {
  MasaCobaService(this._storage, {Dio? dio, String? versi})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: AppConfig.defaultBaseUrl + AppConfig.apiPrefix,
              connectTimeout: const Duration(seconds: 6),
              receiveTimeout: const Duration(seconds: 6),
              validateStatus: (_) => true,
            ),
          ),
      _versi = versi ?? '0.0.0';

  static const _kMulai = 'demo_mulai';
  static const _kServerTerakhir = 'demo_server_terakhir';

  final SecureStorage _storage;
  final Dio _dio;
  final String _versi;

  /// Header `Date` dari endpoint publik /app/versi; null bila tak terjangkau.
  Future<DateTime?> waktuServer() async {
    try {
      final res = await _dio.get<dynamic>(
        '/app/versi',
        queryParameters: {'versi': _versi},
      );
      final raw = res.headers.value('date');
      if (raw == null) return null;
      return HttpDate.parse(raw).toUtc();
    } catch (_) {
      return null;
    }
  }

  Future<CatatanMasaCoba?> _baca() async {
    final m = DateTime.tryParse(await _storage.bacaNilai(_kMulai) ?? '');
    if (m == null) return null;
    final t = DateTime.tryParse(
      await _storage.bacaNilai(_kServerTerakhir) ?? '',
    );
    return CatatanMasaCoba(mulai: m, serverTerakhir: t ?? m);
  }

  Future<void> _simpan(CatatanMasaCoba c) async {
    await _storage.tulisNilai(_kMulai, c.mulai.toUtc().toIso8601String());
    await _storage.tulisNilai(
      _kServerTerakhir,
      c.serverTerakhir.toUtc().toIso8601String(),
    );
  }

  /// [mulaiBaru] = true saat pengguna menekan "Coba Mode Demo" (boleh memulai
  /// masa coba); false untuk pemeriksaan berkala.
  Future<StatusMasaCoba> periksa({bool mulaiBaru = false}) async {
    final catatan = await _baca();
    final server = await waktuServer();
    final status = MasaCoba.periksa(
      catatan: catatan,
      waktuServer: server,
      perangkat: DateTime.now(),
      mulaiBaru: mulaiBaru,
    );
    if (status.catatan != null) await _simpan(status.catatan!);
    return status;
  }
}

final masaCobaServiceProvider = Provider<MasaCobaService>(
  (ref) => MasaCobaService(
    ref.watch(secureStorageProvider),
    versi: ref.watch(appVersionProvider),
  ),
);

/// Status masa coba untuk lencana "DEMO · sisa N hari" (diperbarui saat
/// dibaca ulang; tidak memulai masa coba).
final masaCobaStatusProvider = FutureProvider<StatusMasaCoba>(
  (ref) => ref.watch(masaCobaServiceProvider).periksa(),
);
