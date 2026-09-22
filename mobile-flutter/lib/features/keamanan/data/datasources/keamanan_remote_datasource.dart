import 'package:dio/dio.dart';

import '../../../../core/network/api_error_mapper.dart';
import '../../domain/entities/otorisasi.dart';
import '../../domain/galat_pin.dart';

/// PIN persetujuan (Tahap B §2c). PIN hanya lewat — tidak pernah disimpan di perangkat,
/// tidak pernah dicatat di log, dan tidak pernah dikembalikan server.
class KeamananRemoteDataSource {
  KeamananRemoteDataSource(this._dio);

  final Dio _dio;

  Future<StatusPin> statusPin() async {
    final d = _data(await _send(() => _dio.get<dynamic>('/keamanan/pin-saya')));
    return StatusPin(
      ada: d['ada'] == true,
      bolehSetel: d['boleh_setel'] == true,
      diubahPada: d['diubah_pada']?.toString(),
    );
  }

  Future<void> simpanPin({required String pin, String? pinLama}) => _send(
    () => _dio.put<dynamic>('/keamanan/pin-saya', data: {
      'pin': pin,
      if (pinLama != null && pinLama.isNotEmpty) 'pin_lama': pinLama,
    }),
  );

  /// Server mewajibkan PIN lama saat menghapus (fix 1f627b45).
  Future<void> hapusPin({required String pinLama}) =>
      _send(() => _dio.delete<dynamic>('/keamanan/pin-saya', data: {'pin_lama': pinLama}));

  Future<List<PemberiOtorisasi>> pemberi() async {
    final body = await _send(() => _dio.get<dynamic>('/keamanan/pemberi-otorisasi'));
    final list = body['data'] is List ? body['data'] as List : const [];
    return [
      for (final e in list)
        if (e is Map)
          PemberiOtorisasi(
            id: (e['id'] ?? '').toString(),
            nama: (e['nama'] ?? '-').toString(),
            peran: e['peran']?.toString(),
          ),
    ];
  }

  Future<Otorisasi> otorisasi({
    required String pemberiId,
    required String pin,
    required String aksi,
    required String transaksiId,
  }) async {
    final d = _data(await _send(() => _dio.post<dynamic>('/keamanan/otorisasi', data: {
      'pemberi_id': pemberiId,
      'pin': pin,
      'aksi': aksi,
      'transaksi_id': transaksiId,
    })));
    final pemberi = d['pemberi'] is Map ? Map<String, dynamic>.from(d['pemberi'] as Map) : const <String, dynamic>{};
    return Otorisasi(
      token: (d['token'] ?? '').toString(),
      kedaluwarsa: d['kedaluwarsa']?.toString(),
      pemberiNama: pemberi['nama']?.toString(),
    );
  }

  Map<String, dynamic> _data(Map<String, dynamic> body) =>
      body['data'] is Map ? Map<String, dynamic>.from(body['data'] as Map) : const <String, dynamic>{};

  Future<Map<String, dynamic>> _send(Future<Response<dynamic>> Function() call) async {
    late final Response<dynamic> res;
    try {
      res = await call();
    } on DioException catch (e) {
      // Jawaban HTTP yang terbawa DioException tetap dibaca lewat galatPin()
      // supaya 429 kuncian PIN tidak kehilangan `data.terkunci_detik`.
      final r = e.response;
      throw r != null && (r.statusCode ?? 0) > 0 ? galatPin(r) : ApiErrorMapper.fromDio(e);
    }
    final code = res.statusCode ?? 0;
    final body = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : const <String, dynamic>{};
    if (!(code >= 200 && code < 300 && body['success'] == true)) {
      throw galatPin(res);
    }
    return body;
  }
}
