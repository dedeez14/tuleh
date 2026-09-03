import 'package:dio/dio.dart';

import '../../../../core/network/api_error_mapper.dart';
import '../../../../core/network/api_exception.dart';
import '../../domain/entities/profil_usaha.dart';

class PengaturanRemoteDataSource {
  PengaturanRemoteDataSource(this._dio);

  final Dio _dio;

  /// GET /pengaturan/usaha → profil + struk.
  Future<ProfilUsaha> profilUsaha() async {
    final body = await _send(() => _dio.get<dynamic>('/pengaturan/usaha'));
    final d = body['data'] is Map ? Map<String, dynamic>.from(body['data'] as Map) : const <String, dynamic>{};
    final struk = d['struk'] is Map ? Map<String, dynamic>.from(d['struk'] as Map) : const <String, dynamic>{};
    return ProfilUsaha(
      nama: (d['nama'] ?? '').toString(),
      alamat: d['alamat']?.toString(),
      telepon: d['telepon']?.toString(),
      email: d['email']?.toString(),
      npwp: d['npwp']?.toString(),
      logo: d['logo']?.toString(),
      strukFooter: struk['footer']?.toString(),
      strukTampilLogo: struk['tampil_logo'] != false,
    );
  }

  /// PUT /pengaturan/usaha (partial). Teks kosong → null (mengosongkan di server).
  Future<void> simpan({
    required String nama,
    String? alamat,
    String? telepon,
    String? email,
    String? strukFooter,
    required bool strukTampilLogo,
  }) async {
    String? tn(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
    await _send(() => _dio.put<dynamic>('/pengaturan/usaha', data: {
          'nama': nama.trim(),
          'alamat': tn(alamat),
          'telepon': tn(telepon),
          'email': tn(email),
          'struk_footer': tn(strukFooter),
          'struk_tampil_logo': strukTampilLogo,
        }));
  }

  Future<Map<String, dynamic>> _send(Future<Response<dynamic>> Function() call) async {
    late final Response<dynamic> res;
    try {
      res = await call();
    } on DioException catch (e) {
      throw ApiErrorMapper.fromDio(e);
    }
    final code = res.statusCode ?? 0;
    final body = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : const <String, dynamic>{};
    final ok = code >= 200 && code < 300 && body['success'] == true;
    if (!ok) {
      throw ApiException(
        message: (body['message'] as String?) ?? ApiErrorMapper.statusMessage(code),
        statusCode: code,
        errors: ApiErrorMapper.parseErrors(body['errors']),
      );
    }
    return body;
  }
}
