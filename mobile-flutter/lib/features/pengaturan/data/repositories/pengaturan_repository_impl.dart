import '../../../../core/network/api_exception.dart';
import '../../../../core/network/api_result.dart';
import '../../domain/entities/profil_usaha.dart';
import '../../domain/repositories/pengaturan_repository.dart';
import '../datasources/pengaturan_remote_datasource.dart';

class PengaturanRepositoryImpl implements PengaturanRepository {
  PengaturanRepositoryImpl(this.remote);

  final PengaturanRemoteDataSource remote;

  @override
  Future<Result<ProfilUsaha>> profilUsaha() async {
    try {
      return Ok(await remote.profilUsaha());
    } on ApiException catch (e) {
      return Err(e);
    }
  }

  @override
  Future<Result<void>> simpanProfil({
    required String nama,
    String? alamat,
    String? telepon,
    String? email,
    String? strukFooter,
    required bool strukTampilLogo,
  }) async {
    try {
      await remote.simpan(
        nama: nama,
        alamat: alamat,
        telepon: telepon,
        email: email,
        strukFooter: strukFooter,
        strukTampilLogo: strukTampilLogo,
      );
      return const Ok(null);
    } on ApiException catch (e) {
      return Err(e);
    }
  }
}
