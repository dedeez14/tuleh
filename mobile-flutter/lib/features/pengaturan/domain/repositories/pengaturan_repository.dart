import '../../../../core/network/api_result.dart';
import '../entities/pengaturan_pembayaran.dart';
import '../entities/profil_usaha.dart';

abstract interface class PengaturanRepository {
  Future<Result<ProfilUsaha>> profilUsaha();

  Future<Result<PengaturanPembayaran>> pembayaran();

  /// Kode metode pembayaran aktif. Sengaja TANPA [Result]: pemanggil satu-satunya
  /// (`metodePembayaranProvider`) memakai daftar bawaan untuk galat apa pun.
  Future<List<String>> metodePembayaran();

  Future<Result<void>> simpanProfil({
    required String nama,
    String? alamat,
    String? telepon,
    String? email,
    String? strukFooter,
    required bool strukTampilLogo,
    bool ubahSatuanBawaan = false,
    String? satuanBawaanId,
  });
}
