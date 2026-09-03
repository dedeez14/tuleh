import '../../../../core/network/api_result.dart';
import '../entities/product.dart';

abstract interface class ProductRepository {
  Future<Result<List<Product>>> list({String? query});

  Future<Result<void>> create({
    required String nama,
    required String tipe,
    required double hargaJual,
    double? hargaBeli,
    String? barcode,
  });

  Future<Result<void>> update({
    required String id,
    String? nama,
    double? hargaJual,
    double? hargaBeli,
    String? barcode,
  });
}
