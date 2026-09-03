import '../../../../core/network/api_exception.dart';
import '../../../../core/network/api_result.dart';
import '../../../sesi/domain/entities/sesi_rekap.dart';
import '../../domain/entities/laporan_keuangan.dart';
import '../../domain/entities/penjualan_hari.dart';
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

  @override
  Future<Result<List<SesiRekap>>> rekapKasir() async {
    try {
      return Ok(await remote.rekapKasir());
    } on ApiException catch (e) {
      return Err(e);
    }
  }
}
