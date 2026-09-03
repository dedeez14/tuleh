import '../../../../core/network/api_exception.dart';
import '../../../../core/network/api_result.dart';
import '../../domain/entities/pelanggan.dart';
import '../../domain/repositories/pelanggan_repository.dart';
import '../datasources/pelanggan_remote_datasource.dart';

class PelangganRepositoryImpl implements PelangganRepository {
  PelangganRepositoryImpl(this.remote);

  final PelangganRemoteDataSource remote;

  @override
  Future<Result<List<Pelanggan>>> list() async {
    try {
      return Ok(await remote.list());
    } on ApiException catch (e) {
      return Err(e);
    }
  }

  @override
  Future<Result<Pelanggan>> tambah({required String nama, String? telepon}) async {
    try {
      return Ok(await remote.tambah(nama: nama, telepon: telepon));
    } on ApiException catch (e) {
      return Err(e);
    }
  }
}
