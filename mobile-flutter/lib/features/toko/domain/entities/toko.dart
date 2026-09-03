import 'package:freezed_annotation/freezed_annotation.dart';

part 'toko.freezed.dart';

/// Entitas toko (outlet) — POS Tuléh mendukung multi-toko per tenant.
@freezed
abstract class Toko with _$Toko {
  const factory Toko({
    required String id,
    required String nama,
    String? bidangUsaha,
    String? kategori,
  }) = _Toko;
}
