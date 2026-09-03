import '../../../../core/network/api_exception.dart';
import '../../../../core/network/api_result.dart';
import '../../domain/entities/pengeluaran.dart';
import '../../domain/repositories/pengeluaran_repository.dart';
import '../datasources/pengeluaran_remote_datasource.dart';

class PengeluaranRepositoryImpl implements PengeluaranRepository {
  PengeluaranRepositoryImpl(this.remote);

  final PengeluaranRemoteDataSource remote;

  @override
  Future<Result<List<Pengeluaran>>> list(String bulan) async {
    try {
      return Ok(await remote.list(bulan));
    } on ApiException catch (e) {
      return Err(e);
    }
  }

  @override
  Future<Result<void>> tambah({
    required String keterangan,
    required double nominal,
    String? tanggal,
  }) async {
    try {
      await remote.tambah(keterangan: keterangan, nominal: nominal, tanggal: tanggal);
      return const Ok(null);
    } on ApiException catch (e) {
      return Err(e);
    }
  }

  @override
  Future<Result<void>> hapus(String id) async {
    try {
      await remote.hapus(id);
      return const Ok(null);
    } on ApiException catch (e) {
      return Err(e);
    }
  }
}
