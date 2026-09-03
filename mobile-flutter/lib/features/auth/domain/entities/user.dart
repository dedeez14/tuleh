import 'package:freezed_annotation/freezed_annotation.dart';

part 'user.freezed.dart';

/// Entitas domain — pengguna terautentikasi. Imutable (freezed), bebas dari
/// detail transport/JSON (dipetakan di lapisan data).
@freezed
abstract class User with _$User {
  const factory User({
    required String id,
    required String name,
    String? email,
    String? role,
    String? companyName,
  }) = _User;
}
