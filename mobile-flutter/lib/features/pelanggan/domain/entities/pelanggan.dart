import 'package:freezed_annotation/freezed_annotation.dart';

part 'pelanggan.freezed.dart';

/// Entitas pelanggan.
@freezed
abstract class Pelanggan with _$Pelanggan {
  const factory Pelanggan({
    required String id,
    required String nama,
    String? kode,
    String? telepon,
    String? alamat,
  }) = _Pelanggan;
}
