import '../../../../core/network/api_result.dart';
import '../entities/bill_detail.dart';
import '../entities/meja.dart';

abstract interface class MejaRepository {
  /// Peta meja: daftar meja + status bon (GET /bills → tables[]).
  Future<Result<List<Meja>>> peta();

  /// Buka bon untuk sebuah meja (POST /bills).
  Future<Result<void>> bukaBon(String mejaId);

  /// Detail bon (GET /bills/{id}).
  Future<Result<BillDetail>> detail(String billId);

  /// Tambah ronde/pesanan ke bon (POST /bills/{id}/rounds).
  Future<Result<void>> tambahRonde(String billId, List<Map<String, dynamic>> items);

  /// Bayar & tutup bon (POST /bills/{id}/settle).
  Future<Result<void>> bayar(String billId, {required String tipe, required double dibayar});
}
