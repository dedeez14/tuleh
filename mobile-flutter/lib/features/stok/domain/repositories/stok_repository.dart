import '../../../../core/network/api_result.dart';
import '../entities/stok_item.dart';

abstract interface class StokRepository {
  Future<Result<List<StokItem>>> list();
}
