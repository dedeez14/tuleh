import '../../../../core/network/api_result.dart';
import '../entities/pesanan.dart';

abstract interface class PesananRepository {
  /// Pesanan hidup toko aktif (tanpa tahap terminal); [stage] menyaring satu tahap.
  Future<Result<List<Pesanan>>> list({String? stage});

  /// Majukan pesanan ke tahap [to]. [tipePembayaran] menyertai konfirmasi bayar
  /// (order QR meja) atau pelunasan nota bayar-saat-ambil di tahap terminal.
  Future<Result<Pesanan>> transition(
    String id, {
    required String to,
    String? tipePembayaran,
  });
}
