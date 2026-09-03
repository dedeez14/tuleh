import '../../../../core/network/api_result.dart';
import '../entities/pengeluaran.dart';

abstract interface class PengeluaranRepository {
  Future<Result<List<Pengeluaran>>> list(String bulan);
  Future<Result<void>> tambah({
    required String keterangan,
    required double nominal,
    String? tanggal,
  });
  Future<Result<void>> hapus(String id);
}
