import '../../../../core/network/api_result.dart';
import '../entities/toko.dart';

abstract interface class TokoRepository {
  Future<Result<List<Toko>>> list();
}
