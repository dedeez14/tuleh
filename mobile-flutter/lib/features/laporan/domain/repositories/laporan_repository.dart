import '../../../../core/network/api_result.dart';
import '../../../sesi/domain/entities/sesi_rekap.dart';
import '../entities/laporan_keuangan.dart';
import '../entities/penjualan_hari.dart';

abstract interface class LaporanRepository {
  Future<Result<LaporanKeuangan>> keuangan();
  Future<Result<List<PenjualanHari>>> penjualanHarian();
  Future<Result<List<SesiRekap>>> rekapKasir();
}
