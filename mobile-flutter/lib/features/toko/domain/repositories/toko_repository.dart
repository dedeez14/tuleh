import '../../../../core/network/api_result.dart';
import '../entities/toko.dart';
import '../entities/toko_manifest.dart';

abstract interface class TokoRepository {
  Future<Result<List<Toko>>> list();

  /// Manifest toko — menu & alur kerja yang berlaku untuk bidang usahanya.
  Future<Result<TokoManifest>> manifest(String tokoId);
}
