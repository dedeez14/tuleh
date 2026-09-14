import '../../../../core/network/api_exception.dart';
import '../../../../core/network/api_result.dart';
import '../../domain/entities/pilihan_produk.dart';
import '../../domain/entities/product.dart';
import '../../domain/repositories/product_repository.dart';
import '../datasources/product_remote_datasource.dart';

class ProductRepositoryImpl implements ProductRepository {
  ProductRepositoryImpl(this.remote);

  final ProductRemoteDataSource remote;

  @override
  Future<Result<List<Product>>> list({String? query, bool includeHabis = false, String? tipe}) =>
      _jalankan(() => remote.list(query: query, includeHabis: includeHabis, tipe: tipe));

  @override
  Future<Result<void>> create({
    required String nama,
    required String tipe,
    required double hargaJual,
    double? hargaBeli,
    String? barcode,
    String? satuanId,
    String? modeJual,
    List<String>? tokoIds,
  }) => _jalankan(() => remote.create(
    nama: nama,
    tipe: tipe,
    hargaJual: hargaJual,
    hargaBeli: hargaBeli,
    barcode: barcode,
    satuanId: satuanId,
    modeJual: modeJual,
    tokoIds: tokoIds,
  ));

  @override
  Future<Result<void>> update({
    required String id,
    String? nama,
    double? hargaJual,
    double? hargaBeli,
    String? barcode,
    String? satuanId,
    String? modeJual,
  }) => _jalankan(() => remote.update(
    id: id,
    nama: nama,
    hargaJual: hargaJual,
    hargaBeli: hargaBeli,
    barcode: barcode,
    satuanId: satuanId,
    modeJual: modeJual,
  ));

  @override
  Future<Result<List<SatuanPilihan>>> satuan() => _jalankan(remote.satuan);

  @override
  Future<Result<List<ModeJualPilihan>>> modeJual() => _jalankan(remote.modeJual);

  @override
  Future<Result<TokoProdukDaftar>> tokoProduk(String id) => _jalankan(() => remote.tokoProduk(id));

  @override
  Future<Result<void>> aturToko(String id, List<String> tokoIds) =>
      _jalankan(() => remote.aturToko(id, tokoIds));

  Future<Result<T>> _jalankan<T>(Future<T> Function() kerja) async {
    try {
      return Ok(await kerja());
    } on ApiException catch (e) {
      return Err(e);
    }
  }
}
