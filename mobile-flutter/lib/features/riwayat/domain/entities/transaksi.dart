import 'package:freezed_annotation/freezed_annotation.dart';

part 'transaksi.freezed.dart';

/// Ringkasan transaksi (untuk daftar Riwayat).
@freezed
abstract class Transaksi with _$Transaksi {
  const factory Transaksi({
    required String id,
    required String nomor,
    required double grandTotal,
    String? tanggal,
    String? status,
    String? metode,
  }) = _Transaksi;
}
