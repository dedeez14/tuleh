import '../../../../core/network/api_exception.dart';
import '../../../../core/network/api_result.dart';
import '../../domain/entities/toko.dart';
import '../../domain/repositories/toko_repository.dart';
import '../datasources/toko_remote_datasource.dart';

class TokoRepositoryImpl implements TokoRepository {
  TokoRepositoryImpl(this.remote);

  final TokoRemoteDataSource remote;

  @override
  Future<Result<List<Toko>>> list() async {
    try {
      return Ok(await remote.list());
    } on ApiException catch (e) {
      return Err(e);
    }
  }
}
