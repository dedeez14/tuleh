import '../../../../core/network/api_result.dart';
import '../entities/refund.dart';
import '../entities/transaksi.dart';
import '../entities/transaksi_detail.dart';

abstract interface class RiwayatRepository {
  Future<Result<List<Transaksi>>> list();
  Future<Result<TransaksiDetail>> detail(String id);

  /// Batalkan transaksi di server (online saja). [otorisasiToken] = token
  /// persetujuan atasan bila kasir tak punya hak batal sendiri (§2c).
  Future<Result<void>> batal(String id, {String? otorisasiToken});

  /// Catat refund di server (online saja) → dokumen refund bernomor.
  Future<Result<Refund>> refund(String id, PermintaanRefund permintaan);
}
