import '../../../../core/network/api_result.dart';
import '../entities/sesi.dart';
import '../entities/sesi_rekap.dart';

abstract interface class SesiRepository {
  /// Sesi aktif saat ini (null bila belum ada) — untuk gating checkout.
  Future<Result<Sesi?>> aktif();

  /// Rekap sesi aktif (kas & penjualan) — null bila belum ada.
  Future<Result<SesiRekap?>> rekapAktif();

  /// Id sesi berstatus BUKA (dari daftar) — dibutuhkan untuk tutup.
  Future<Result<String?>> aktifId();

  /// Id gudang pertama — dibutuhkan untuk buka sesi.
  Future<Result<String?>> firstGudangId();

  Future<Result<void>> buka({
    required double kasAwal,
    required String gudangId,
    String? catatan,
  });

  Future<Result<void>> tutup({
    required String id,
    required double kasAkhirFisik,
    String? catatan,
  });
}
