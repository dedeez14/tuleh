import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_config.dart';

/// Keadaan koneksi ke server MOVERA — bukan sekadar "ada jaringan", melainkan
/// "server terjangkau". Dua sumber: kegagalan permintaan nyata (dari
/// SalinanInterceptor) dan pemeriksaan ringan ke /app/versi.
class StatusKoneksi {
  const StatusKoneksi({
    this.online = true,
    this.sejak,
    this.salinanTerakhir,
  });

  final bool online;

  /// Sejak kapan keadaan ini berlaku.
  final DateTime? sejak;

  /// Waktu tarik salinan terlama yang sedang ditampilkan saat offline —
  /// "menampilkan data terakhir HH:MM".
  final DateTime? salinanTerakhir;

  StatusKoneksi salin({bool? online, DateTime? sejak, DateTime? salinanTerakhir}) =>
      StatusKoneksi(
        online: online ?? this.online,
        sejak: sejak ?? this.sejak,
        salinanTerakhir: salinanTerakhir ?? this.salinanTerakhir,
      );
}

/// Yang dibutuhkan SalinanInterceptor dari pemantau koneksi.
abstract interface class PenandaKoneksi {
  bool get offline;
  void tandaiOffline({DateTime? ditarikPada});
  void tandaiOnline();
}

class KoneksiNotifier extends Notifier<StatusKoneksi>
    implements PenandaKoneksi {
  KoneksiNotifier({this.dioProbe, this.jaringan});

  @override
  bool get offline => !state.online;

  /// Dio untuk pemeriksaan (test menyuntikkan tiruan).
  final Dio? dioProbe;

  /// Aliran perubahan jaringan (test menyuntikkan tiruan).
  final Stream<List<ConnectivityResult>>? jaringan;
  StreamSubscription<List<ConnectivityResult>>? _langganan;
  Timer? _ulang;
  bool _memeriksa = false;

  /// Jeda pemeriksaan ulang selama offline.
  static const jedaUlang = Duration(seconds: 30);

  @override
  StatusKoneksi build() {
    final aliran = jaringan ?? Connectivity().onConnectivityChanged;
    _langganan = aliran.listen(
      (hasil) {
        final adaJaringan = hasil.any((r) => r != ConnectivityResult.none);
        if (adaJaringan) {
          // Jaringan kembali → pastikan server terjangkau, jangan tebak.
          periksa();
        } else {
          tandaiOffline();
        }
      },
      // Tanpa plugin (test) atau kanal gagal: anggap jaringan ada; deteksi
      // offline tetap berjalan dari kegagalan permintaan nyata.
      onError: (_) {},
    );
    ref.onDispose(() {
      _langganan?.cancel();
      _ulang?.cancel();
    });
    return const StatusKoneksi();
  }

  /// Dipanggil SalinanInterceptor saat permintaan gagal karena jaringan dan
  /// salinan dipakai. [ditarikPada] = umur salinan yang ditampilkan.
  @override
  void tandaiOffline({DateTime? ditarikPada}) {
    final s = state;
    final salinan = ditarikPada == null
        ? s.salinanTerakhir
        : (s.salinanTerakhir == null || ditarikPada.isBefore(s.salinanTerakhir!))
        ? ditarikPada
        : s.salinanTerakhir;
    if (s.online) {
      state = StatusKoneksi(
        online: false,
        sejak: DateTime.now(),
        salinanTerakhir: salinan,
      );
      _jadwalkanUlang();
    } else if (salinan != s.salinanTerakhir) {
      state = s.salin(salinanTerakhir: salinan);
    }
  }

  /// Dipanggil saat sebuah permintaan berhasil sampai server.
  @override
  void tandaiOnline() {
    if (state.online) return;
    _ulang?.cancel();
    state = StatusKoneksi(online: true, sejak: DateTime.now());
  }

  void _jadwalkanUlang() {
    _ulang?.cancel();
    _ulang = Timer(jedaUlang, periksa);
  }

  /// Pemeriksaan ringan: GET /app/versi (publik, kecil). true = terjangkau.
  Future<bool> periksa() async {
    if (_memeriksa) return state.online;
    _memeriksa = true;
    try {
      final dio =
          dioProbe ??
          Dio(
            BaseOptions(
              baseUrl: AppConfig.defaultBaseUrl + AppConfig.apiPrefix,
              connectTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 5),
              validateStatus: (_) => true,
            ),
          );
      final res = await dio.get<dynamic>(
        '/app/versi',
        queryParameters: const {'versi': '0.0.0'},
      );
      final ok = (res.statusCode ?? 0) > 0;
      if (ok) {
        tandaiOnline();
      } else {
        tandaiOffline();
      }
      return ok;
    } catch (_) {
      tandaiOffline();
      return false;
    } finally {
      _memeriksa = false;
    }
  }
}

final koneksiProvider = NotifierProvider<KoneksiNotifier, StatusKoneksi>(
  KoneksiNotifier.new,
);
