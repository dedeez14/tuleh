import '../../../../core/network/api_exception.dart';
import '../../../../core/network/api_result.dart';
import '../../../sesi/domain/entities/sesi_rekap.dart';
import '../../domain/entities/laporan_keuangan.dart';
import '../../domain/entities/penjualan_hari.dart';
import '../../domain/entities/penjualan_produk.dart';
import '../../domain/repositories/laporan_repository.dart';
import '../datasources/laporan_remote_datasource.dart';

class LaporanRepositoryImpl implements LaporanRepository {
  LaporanRepositoryImpl(this.remote);

  final LaporanRemoteDataSource remote;

  @override
  Future<Result<LaporanKeuangan>> keuangan() async {
    try {
      return Ok(await remote.keuangan());
    } on ApiException catch (e) {
      return Err(e);
    }
  }

  @override
  Future<Result<List<PenjualanHari>>> penjualanHarian() async {
    try {
      return Ok(await remote.penjualanHarian());
    } on ApiException catch (e) {
      return Err(e);
    }
  }

  /// Produk terlaris adalah bagian pelengkap laporan: bila server ini belum
  /// mengenal endpointnya (404 / 405), balas daftar kosong supaya layar
  /// Laporan tetap utuh. Galat lain (401, 5xx) tetap diteruskan.
  @override
  Future<Result<List<PenjualanProduk>>> penjualanProduk() async {
    try {
      return Ok(await remote.penjualanProduk());
    } on ApiException catch (e) {
      if (e.statusCode == 404 || e.statusCode == 405) {
        return const Ok(<PenjualanProduk>[]);
      }
      return Err(e);
    }
  }

  @override
  Future<Result<List<SesiRekap>>> rekapKasir() async {
    try {
      return Ok(await remote.rekapKasir());
    } on ApiException catch (e) {
      return Err(e);
    }
  }
}
