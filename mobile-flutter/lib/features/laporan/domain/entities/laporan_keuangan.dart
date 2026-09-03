import 'package:freezed_annotation/freezed_annotation.dart';

part 'laporan_keuangan.freezed.dart';

/// Ringkasan keuangan bulan berjalan (`/laporan/keuangan`).
@freezed
abstract class LaporanKeuangan with _$LaporanKeuangan {
  const factory LaporanKeuangan({
    required String bulan,
    required double omset,
    required int jumlahTransaksi,
    required double pengeluaran,
    required double laba,
  }) = _LaporanKeuangan;
}
