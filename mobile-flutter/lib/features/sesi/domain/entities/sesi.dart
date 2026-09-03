import 'package:freezed_annotation/freezed_annotation.dart';

part 'sesi.freezed.dart';

/// Sesi kasir (shift) — checkout memerlukan sesi aktif.
@freezed
abstract class Sesi with _$Sesi {
  const factory Sesi({
    required String id,
    String? nomor,
    String? dibukaPada,
  }) = _Sesi;
}
