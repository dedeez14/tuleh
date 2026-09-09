import '../../../../core/network/api_result.dart';
import '../../../../core/offline/antrean_tulis.dart';
import '../entities/bill_detail.dart';
import '../entities/meja.dart';

abstract interface class MejaRepository {
  /// Peta meja: daftar meja + status bon (GET /bills → tables[]).
  Future<Result<List<Meja>>> peta();

  /// Buka bon untuk sebuah meja (POST /bills). Offline → diantrekan
  /// ([HasilTulis.tertunda]) dengan id bon lokal.
  Future<Result<HasilTulis>> bukaBon(String mejaId, {int pax = 1});

  /// Detail bon (GET /bills/{id}); ronde yang belum terkirim ikut dihitung.
  Future<Result<BillDetail>> detail(String billId);

  /// Tambah ronde/pesanan ke bon (POST /bills/{id}/rounds). [tampilan] =
  /// nama/harga/kuantitas per item untuk ditampilkan selama belum terkirim.
  Future<Result<HasilTulis>> tambahRonde(
    String billId,
    List<Map<String, dynamic>> items, {
    List<Map<String, dynamic>> tampilan = const [],
  });

  /// Bayar & tutup bon (POST /bills/{id}/settle).
  Future<Result<HasilTulis>> bayar(String billId, {required String tipe, required double dibayar});

  // ---- Kelola meja (pemilik/manajer; server menolak peran lain dgn 403) ----

  /// Daftar meja (GET /tables). [semua] menyertakan yang nonaktif.
  Future<Result<List<Meja>>> daftarMeja({bool semua = false});

  /// Tambah meja baru; server yang membuat kode QR-nya.
  Future<Result<Meja>> tambahMeja(String nomor);

  /// Ubah nomor meja — kode QR TIDAK ikut berubah.
  Future<Result<Meja>> ubahMeja(String id, String nomor);

  /// Nonaktifkan meja (soft delete). 409 bila masih ada bon terbuka.
  Future<Result<Meja>> nonaktifkanMeja(String id);
}
