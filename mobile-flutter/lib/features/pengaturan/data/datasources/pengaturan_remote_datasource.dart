import 'package:dio/dio.dart';

import '../../../../core/network/api_error_mapper.dart';
import '../../../products/domain/entities/pilihan_produk.dart';
import '../../domain/entities/pengaturan_pembayaran.dart';
import '../../domain/entities/profil_usaha.dart';

class PengaturanRemoteDataSource {
  PengaturanRemoteDataSource(this._dio);

  final Dio _dio;

  /// GET /pengaturan/usaha → profil + struk.
  Future<ProfilUsaha> profilUsaha() async {
    final body = await _send(() => _dio.get<dynamic>('/pengaturan/usaha'));
    final d = body['data'] is Map ? Map<String, dynamic>.from(body['data'] as Map) : const <String, dynamic>{};
    final struk = d['struk'] is Map ? Map<String, dynamic>.from(d['struk'] as Map) : const <String, dynamic>{};
    final sb = d['satuan_bawaan'];
    return ProfilUsaha(
      satuanBawaan: sb is Map && sb['id'] != null
          ? SatuanPilihan(
              id: sb['id'].toString(),
              nama: (sb['nama'] ?? sb['kode'] ?? '').toString(),
              kode: sb['kode']?.toString(),
            )
          : null,
      nama: (d['nama'] ?? '').toString(),
      alamat: d['alamat']?.toString(),
      telepon: d['telepon']?.toString(),
      email: d['email']?.toString(),
      npwp: d['npwp']?.toString(),
      // Logo struk yang diunggah di desktop ada di `struk.logo`; `logo`
      // tingkat atas (logo usaha) sering null — sebelumnya hanya yang ini
      // dibaca, sehingga struk Android tak pernah berlogo.
      logo: (struk['logo'] ?? d['logo'])?.toString(),
      strukFooter: struk['footer']?.toString(),
      strukTampilLogo: struk['tampil_logo'] != false,
    );
  }

  /// GET /pengaturan/pembayaran → QRIS statis + daftar rekening.
  Future<PengaturanPembayaran> pembayaran() async {
    final body = await _send(() => _dio.get<dynamic>('/pengaturan/pembayaran'));
    final d = body['data'] is Map ? Map<String, dynamic>.from(body['data'] as Map) : const <String, dynamic>{};
    final bank = d['bank'];
    final qr = d['qr_statis']?.toString();
    return PengaturanPembayaran(
      qrStatis: qr == null || qr.isEmpty ? null : qr,
      bank: [
        if (bank is List)
          for (final b in bank)
            if (b is Map)
              RekeningBank(
                bank: (b['bank'] ?? '').toString(),
                rekening: (b['rekening'] ?? '').toString(),
                atasNama: (b['atas_nama'] ?? '').toString(),
              ),
      ],
      midtransAktif: d['midtrans_aktif'] == true,
    );
  }

  /// GET /config → kode metode pembayaran aktif (master `pos_metode_pembayaran`).
  /// Bentuk tak terduga → daftar kosong; pemanggil memakai daftar bawaan.
  Future<List<String>> metodePembayaran() async {
    final body = await _send(() => _dio.get<dynamic>('/config'));
    final d = body['data'] is Map ? Map<String, dynamic>.from(body['data'] as Map) : const <String, dynamic>{};
    final m = d['payment_methods'];
    return [
      if (m is List)
        for (final e in m)
          if (e is String && e.isNotEmpty) e,
    ];
  }

  /// PUT /pengaturan/usaha (partial). Teks kosong → null (mengosongkan di server).
  /// [ubahSatuanBawaan] = kirim `satuan_bawaan_id` ([satuanBawaanId] null =
  /// kosongkan); false = kunci itu tidak dikirim (tidak diubah).
  Future<void> simpan({
    required String nama,
    String? alamat,
    String? telepon,
    String? email,
    String? strukFooter,
    required bool strukTampilLogo,
    bool ubahSatuanBawaan = false,
    String? satuanBawaanId,
  }) async {
    String? tn(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
    await _send(() => _dio.put<dynamic>('/pengaturan/usaha', data: {
          'nama': nama.trim(),
          'alamat': tn(alamat),
          'telepon': tn(telepon),
          'email': tn(email),
          'struk_footer': tn(strukFooter),
          'struk_tampil_logo': strukTampilLogo,
          if (ubahSatuanBawaan) 'satuan_bawaan_id': tn(satuanBawaanId),
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
      throw ApiErrorMapper.fromResponse(res);
    }
    return body;
  }
}
