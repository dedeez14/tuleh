import '../../../../core/network/api_result.dart';
import '../entities/transaksi.dart';
import '../entities/transaksi_detail.dart';

abstract interface class RiwayatRepository {
  Future<Result<List<Transaksi>>> list();
  Future<Result<TransaksiDetail>> detail(String id);

  /// Batalkan transaksi di server (online saja).
  Future<Result<void>> batal(String id);
}
