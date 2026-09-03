import '../../../../core/network/api_exception.dart';
import '../../../../core/network/api_result.dart';
import '../../domain/entities/product.dart';
import '../../domain/repositories/product_repository.dart';
import '../datasources/product_remote_datasource.dart';

class ProductRepositoryImpl implements ProductRepository {
  ProductRepositoryImpl(this.remote);

  final ProductRemoteDataSource remote;

  @override
  Future<Result<List<Product>>> list({String? query}) async {
    try {
      return Ok(await remote.list(query: query));
    } on ApiException catch (e) {
      return Err(e);
    }
  }

  @override
  Future<Result<void>> create({
    required String nama,
    required String tipe,
    required double hargaJual,
    double? hargaBeli,
    String? barcode,
  }) async {
    try {
      await remote.create(
        nama: nama,
        tipe: tipe,
        hargaJual: hargaJual,
        hargaBeli: hargaBeli,
        barcode: barcode,
      );
      return const Ok(null);
    } on ApiException catch (e) {
      return Err(e);
    }
  }

  @override
  Future<Result<void>> update({
    required String id,
    String? nama,
    double? hargaJual,
    double? hargaBeli,
    String? barcode,
  }) async {
    try {
      await remote.update(
        id: id,
        nama: nama,
        hargaJual: hargaJual,
        hargaBeli: hargaBeli,
        barcode: barcode,
      );
      return const Ok(null);
    } on ApiException catch (e) {
      return Err(e);
    }
  }
}
