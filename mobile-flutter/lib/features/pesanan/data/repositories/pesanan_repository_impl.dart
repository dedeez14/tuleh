import '../../../../core/network/api_exception.dart';
import '../../../../core/network/api_result.dart';
import '../../domain/entities/pesanan.dart';
import '../../domain/repositories/pesanan_repository.dart';
import '../datasources/pesanan_remote_datasource.dart';

class PesananRepositoryImpl implements PesananRepository {
  PesananRepositoryImpl(this.remote);

  final PesananRemoteDataSource remote;

  @override
  Future<Result<List<Pesanan>>> list({String? stage}) async {
    try {
      return Ok(await remote.list(stage: stage));
    } on ApiException catch (e) {
      return Err(e);
    }
  }

  @override
  Future<Result<Pesanan>> transition(
    String id, {
    required String to,
    String? tipePembayaran,
  }) async {
    try {
      return Ok(
        await remote.transition(id, to: to, tipePembayaran: tipePembayaran),
      );
    } on ApiException catch (e) {
      return Err(e);
    }
  }
}
