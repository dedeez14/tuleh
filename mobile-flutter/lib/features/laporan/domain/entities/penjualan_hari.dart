import 'package:freezed_annotation/freezed_annotation.dart';

part 'penjualan_hari.freezed.dart';

/// Baris penjualan per hari (`/laporan/penjualan-harian` → rows[]).
@freezed
abstract class PenjualanHari with _$PenjualanHari {
  const factory PenjualanHari({
    required String tanggal,
    required int jumlahTransaksi,
    required double totalOmzet,
  }) = _PenjualanHari;
}
