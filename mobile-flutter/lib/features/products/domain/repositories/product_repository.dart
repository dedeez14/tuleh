import '../../../../core/network/api_result.dart';
import '../entities/pilihan_produk.dart';
import '../entities/product.dart';

abstract interface class ProductRepository {
  /// [tipe]: PRODUK | JASA | SEMUA; null = bawaan server.
  Future<Result<List<Product>>> list({String? query, bool includeHabis = false, String? tipe});

  Future<Result<void>> create({
    required String nama,
    required String tipe,
    required double hargaJual,
    double? hargaBeli,
    String? barcode,
    String? satuanId,
    String? modeJual,
    List<String>? tokoIds,
  });

  /// [modeJual]: null = tidak diubah; `''` = kembali otomatis ikut satuan.
  Future<Result<void>> update({
    required String id,
    String? nama,
    double? hargaJual,
    double? hargaBeli,
    String? barcode,
    String? satuanId,
    String? modeJual,
  });

  /// Master satuan (`GET /satuan`).
  Future<Result<List<SatuanPilihan>>> satuan();

  /// Master cara input jumlah di kasir (`GET /mode-jual`, server 2026-09-14).
  Future<Result<List<ModeJualPilihan>>> modeJual();

  /// Toko yang menjual produk (`GET /produk-toko/{id}`).
  Future<Result<TokoProdukDaftar>> tokoProduk(String id);

  /// Atur toko yang menjual produk (`PUT /produk-toko/{id}`); kosong = semua toko.
  Future<Result<void>> aturToko(String id, List<String> tokoIds);
}
