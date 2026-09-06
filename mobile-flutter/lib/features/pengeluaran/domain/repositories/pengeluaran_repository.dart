import '../../../../core/network/api_result.dart';
import '../../../../core/offline/antrean_tulis.dart';
import '../entities/pengeluaran.dart';

abstract interface class PengeluaranRepository {
  Future<Result<List<Pengeluaran>>> list(String bulan);
  /// Menambah pengeluaran; saat offline diantrekan ([HasilTulis.tertunda]).
  Future<Result<HasilTulis>> tambah({
    required String keterangan,
    required double nominal,
    String? tanggal,
  });
  Future<Result<void>> hapus(String id);
}
