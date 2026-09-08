import '../../../../core/network/api_exception.dart';
import '../../../../core/network/api_result.dart';
import '../../domain/entities/transaksi.dart';
import '../../domain/entities/transaksi_detail.dart';
import '../../domain/repositories/riwayat_repository.dart';
import '../datasources/riwayat_remote_datasource.dart';

class RiwayatRepositoryImpl implements RiwayatRepository {
  RiwayatRepositoryImpl(this.remote);

  final RiwayatRemoteDataSource remote;

  @override
  Future<Result<List<Transaksi>>> list() async {
    try {
      return Ok(await remote.list());
    } on ApiException catch (e) {
      return Err(e);
    }
  }

  @override
  Future<Result<void>> batal(String id) async {
    try {
      await remote.batal(id);
      return const Ok(null);
    } on ApiException catch (e) {
      return Err(e);
    }
  }

  @override
  Future<Result<TransaksiDetail>> detail(String id) async {
    try {
      return Ok(await remote.detail(id));
    } on ApiException catch (e) {
      return Err(e);
    }
  }
}
