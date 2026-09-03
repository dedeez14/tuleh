import '../../../../core/network/api_result.dart';
import '../entities/pelanggan.dart';

abstract interface class PelangganRepository {
  Future<Result<List<Pelanggan>>> list();
  Future<Result<Pelanggan>> tambah({required String nama, String? telepon});
}
