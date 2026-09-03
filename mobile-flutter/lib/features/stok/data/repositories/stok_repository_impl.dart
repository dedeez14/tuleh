import '../../../../core/network/api_exception.dart';
import '../../../../core/network/api_result.dart';
import '../../domain/entities/stok_item.dart';
import '../../domain/repositories/stok_repository.dart';
import '../datasources/stok_remote_datasource.dart';

class StokRepositoryImpl implements StokRepository {
  StokRepositoryImpl(this.remote);

  final StokRemoteDataSource remote;

  @override
  Future<Result<List<StokItem>>> list() async {
    try {
      return Ok(await remote.list());
    } on ApiException catch (e) {
      return Err(e);
    }
  }
}
