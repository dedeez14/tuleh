import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';

import '../domain/masa_coba.dart';

/// Identitas perangkat untuk masa coba (lapis 2). ANDROID_ID bertahan saat
/// aplikasi dihapus & dipasang ulang; berubah hanya saat factory reset.
/// Di-hash bersama nama paket agar tidak bisa dipakai lintas aplikasi.
class IdentitasPerangkat {
  IdentitasPerangkat({Future<String> Function()? bacaAndroidId})
    : _bacaAndroidId = bacaAndroidId ?? _dariNative;

  static const _kanal = MethodChannel('tuleh/perangkat');
  final Future<String> Function() _bacaAndroidId;
  String? _cache;

  static Future<String> _dariNative() async {
    if (!Platform.isAndroid) return '';
    try {
      return await _kanal.invokeMethod<String>('androidId') ?? '';
    } catch (_) {
      return '';
    }
  }

  static String _sha(String s) => sha256.convert(utf8.encode(s)).toString();

  Future<String> perangkatId() async {
    if (_cache != null) return _cache!;
    final id = await _bacaAndroidId();
    // Tanpa ANDROID_ID (emulator tertentu) → id acak per pemasangan; lapis
    // 2 tetap berjalan meski tidak bertahan pasang ulang.
    final dasar = id.isNotEmpty ? id : 'tanpa-android-id';
    _cache = _sha('$dasar|com.tuleh.tuleh_pos|tuleh');
    return _cache!;
  }

  String sidikJari() => _sha(
    '${Platform.operatingSystem}|${Platform.operatingSystemVersion}|'
    '${Platform.version.split(' ').first}',
  );
}

/// Klien endpoint masa coba (publik, tanpa Bearer). 404 = server belum
/// memasang endpoint → semua metode mengembalikan null (fail-open ke lapis 1).
class MasaCobaRemote {
  MasaCobaRemote(this._dio, this._perangkat, {required this.versiApp});

  final Dio _dio;
  final IdentitasPerangkat _perangkat;
  final String versiApp;

  Future<Map<String, dynamic>> _badan({String? identitasToken}) async => {
    'perangkat_id': await _perangkat.perangkatId(),
    'platform': 'android',
    'sidik_jari': _perangkat.sidikJari(),
    'versi_app': versiApp,
    if (identitasToken != null && identitasToken.isNotEmpty)
      'identitas_token': identitasToken,
  };

  Map<String, dynamic>? _data(Response<dynamic> res) {
    final code = res.statusCode ?? 0;
    final body = res.data;
    if (code < 200 || code >= 300 || body is! Map || body['success'] != true) {
      return null;
    }
    return body['data'] is Map
        ? Map<String, dynamic>.from(body['data'] as Map)
        : null;
  }

  /// Daftar (POST) atau muat status (GET, lalu POST bila belum terdaftar).
  Future<StatusServer?> status({
    required bool mulaiBaru,
    String? identitasToken,
  }) async {
    try {
      final badan = await _badan(identitasToken: identitasToken);
      if (!mulaiBaru) {
        final g = await _dio.get<dynamic>(
          '/demo/perangkat/${Uri.encodeComponent(badan['perangkat_id'] as String)}',
        );
        final d = _data(g);
        if (d != null) return StatusServer.dariJson(d);
        if (g.statusCode != 404) return null;
      }
      final p = await _dio.post<dynamic>('/demo/perangkat', data: badan);
      return StatusServer.dariJson(_data(p));
    } catch (_) {
      return null;
    }
  }

  /// Kirim kode OTP. Mengembalikan pesan galat, atau null bila sukses.
  Future<String?> otpKirim({
    required String jenis,
    required String tujuan,
  }) async {
    try {
      final res = await _dio.post<dynamic>(
        '/demo/otp/kirim',
        data: {
          'perangkat_id': await _perangkat.perangkatId(),
          'jenis': jenis,
          'tujuan': tujuan,
        },
      );
      return _data(res) != null ? null : _pesanGalat(res);
    } catch (_) {
      return 'Tidak bisa menghubungi server. Periksa koneksi.';
    }
  }

  /// Verifikasi kode. Mengembalikan (identitasToken, status) atau galat.
  Future<({String? token, StatusServer? status, String? galat})> otpVerifikasi({
    required String jenis,
    required String tujuan,
    required String kode,
  }) async {
    try {
      final res = await _dio.post<dynamic>(
        '/demo/otp/verifikasi',
        data: {
          'perangkat_id': await _perangkat.perangkatId(),
          'jenis': jenis,
          'tujuan': tujuan,
          'kode': kode,
        },
      );
      final d = _data(res);
      if (d == null) return (token: null, status: null, galat: _pesanGalat(res));
      return (
        token: d['identitas_token']?.toString(),
        status: StatusServer.dariJson(d),
        galat: null,
      );
    } catch (_) {
      return (
        token: null,
        status: null,
        galat: 'Tidak bisa menghubungi server. Periksa koneksi.',
      );
    }
  }

  static String _pesanGalat(Response<dynamic> res) {
    final body = res.data;
    if (body is Map) {
      final errors = body['errors'];
      if (errors is Map && errors.isNotEmpty) {
        final first = errors.values.first;
        if (first is List && first.isNotEmpty) return first.first.toString();
        if (first is String) return first;
      }
      final msg = body['message']?.toString();
      if (msg != null && msg.isNotEmpty) return msg;
    }
    return switch (res.statusCode) {
      429 => 'Terlalu sering. Tunggu sebentar lalu coba lagi.',
      404 => 'Layanan verifikasi belum tersedia di server.',
      _ => 'Verifikasi gagal (${res.statusCode ?? 0}).',
    };
  }
}
