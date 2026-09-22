import '../../../../core/network/api_result.dart';
import '../entities/hasil_pesanan.dart';
import '../entities/pesanan.dart';

abstract interface class PesananRepository {
  /// Pesanan hidup toko aktif (tanpa tahap terminal); [stage] menyaring satu tahap,
  /// [bayar] menyaring cara bayar (mis. `BELUM,DP`).
  Future<Result<List<Pesanan>>> list({String? stage, String? bayar});

  /// Majukan pesanan ke tahap [to]. [tipePembayaran] menyertai konfirmasi bayar
  /// (order QR meja) atau pelunasan nota bayar-saat-ambil di tahap terminal.
  Future<Result<HasilTransisi>> transition(
    String id, {
    required String to,
    String? tipePembayaran,
  });

  /// Nota bayar nanti / uang muka (`bayar` = `NANTI` | `DP`).
  Future<Result<NotaPesanan>> buatNota({
    required String bayar,
    required List<ItemNota> items,
    String? idPelanggan,
    String? catatan,
    num? uangMuka,
    String? metodeUangMuka,
    required String clientRef,
  });
}
