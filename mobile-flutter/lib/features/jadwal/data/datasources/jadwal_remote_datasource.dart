import 'package:dio/dio.dart';

import '../../../../core/network/api_error_mapper.dart';
import '../../domain/entities/jadwal.dart';

/// Endpoint modul Jadwal (`/jadwal`). Semua penolakan (403 tanpa hak, 409
/// KUOTA_PENUH/SUDAH_TERDAFTAR/JADWAL_BATAL) dilempar sebagai ApiException
/// dengan pesan siap tampil dari server.
class JadwalRemoteDataSource {
  JadwalRemoteDataSource(this._dio);

  final Dio _dio;

  Future<List<JadwalSlot>> daftar(String tanggal, {bool semua = false}) async {
    final body = await _send(() => _dio.get<dynamic>('/jadwal', queryParameters: {
          'tanggal': tanggal,
          if (semua) 'semua': 1,
        }));
    final data = body['data'];
    return [
      for (final e in data is List ? data : const [])
        if (e is Map) _slot(Map<String, dynamic>.from(e), denganPeserta: false),
    ];
  }

  Future<JadwalSlot> detail(String id) async {
    final body = await _send(() => _dio.get<dynamic>('/jadwal/${Uri.encodeComponent(id)}'));
    return _slot(_map(body['data']));
  }

  Future<JadwalSlot> simpan(IsianJadwal isian) async {
    final body = await _send(() => _dio.post<dynamic>('/jadwal', data: isian.toJson()));
    return _slot(_map(body['data']));
  }

  Future<JadwalSlot> ubah(String id, IsianJadwal isian) async {
    final body = await _send(() => _dio.put<dynamic>('/jadwal/${Uri.encodeComponent(id)}', data: isian.toJson()));
    return _slot(_map(body['data']));
  }

  Future<JadwalSlot> batal(String id) async {
    final body = await _send(() => _dio.delete<dynamic>('/jadwal/${Uri.encodeComponent(id)}'));
    return _slot(_map(body['data']));
  }

  Future<PesertaJadwal> tambahPeserta(String id, String pelangganId) async {
    final body = await _send(() => _dio.post<dynamic>(
          '/jadwal/${Uri.encodeComponent(id)}/peserta',
          data: {'pelanggan_id': pelangganId},
        ));
    return _peserta(_map(body['data']));
  }

  Future<PesertaJadwal> ubahStatusPeserta(String id, String pesertaId, String status) async {
    final body = await _send(() => _dio.patch<dynamic>(
          '/jadwal/${Uri.encodeComponent(id)}/peserta/${Uri.encodeComponent(pesertaId)}',
          data: {'status': status},
        ));
    return _peserta(_map(body['data']));
  }

  Future<void> lepasPeserta(String id, String pesertaId) async {
    await _send(() => _dio.delete<dynamic>(
          '/jadwal/${Uri.encodeComponent(id)}/peserta/${Uri.encodeComponent(pesertaId)}',
        ));
  }

  // ---- helper ----
  Future<Map<String, dynamic>> _send(Future<Response<dynamic>> Function() call) async {
    late final Response<dynamic> res;
    try {
      res = await call();
    } on DioException catch (e) {
      throw ApiErrorMapper.fromDio(e);
    }
    final code = res.statusCode ?? 0;
    final body = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : const <String, dynamic>{};
    if (!(code >= 200 && code < 300 && body['success'] == true)) {
      throw ApiErrorMapper.fromResponse(res);
    }
    return body;
  }

  Map<String, dynamic> _map(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};

  int? _intOrNull(dynamic v) => v == null ? null : int.tryParse('$v');

  /// [denganPeserta] false untuk daftar per hari: server (index) memang tidak
  /// memuat relasi peserta, jadi slot ringkas tidak boleh berpura-pura
  /// membawanya — peserta hanya sah dari detail.
  JadwalSlot _slot(Map<String, dynamic> m, {bool denganPeserta = true}) {
    final raw = denganPeserta ? m['peserta'] : null;
    return JadwalSlot(
      id: (m['id'] ?? '').toString(),
      nama: (m['nama'] ?? '-').toString(),
      tanggal: (m['tanggal'] ?? '').toString(),
      jamMulai: (m['jam_mulai'] ?? '').toString(),
      jamSelesai: m['jam_selesai']?.toString(),
      kuota: _intOrNull(m['kuota']),
      sisaKuota: _intOrNull(m['sisa_kuota']),
      pesertaCount: _intOrNull(m['peserta_count']) ?? 0,
      pengajar: m['pengajar']?.toString(),
      catatan: m['catatan']?.toString(),
      status: (m['status'] ?? 'AKTIF').toString(),
      peserta: [
        for (final e in raw is List ? raw : const [])
          if (e is Map) _peserta(Map<String, dynamic>.from(e)),
      ],
    );
  }

  PesertaJadwal _peserta(Map<String, dynamic> m) => PesertaJadwal(
    id: (m['id'] ?? '').toString(),
    pelangganId: (m['pelanggan_id'] ?? '').toString(),
    nama: (m['nama'] ?? '-').toString(),
    telepon: m['telepon']?.toString(),
    status: (m['status'] ?? 'TERDAFTAR').toString(),
  );
}
