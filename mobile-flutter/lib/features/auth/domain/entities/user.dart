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
    /// Kunci hak akses dari server (`akses[]` pada login & /auth/me): master
    /// data `pos_hak_akses` × permission peran yang diatur pemilik. Kosong =
    /// tanpa hak (gagal-tertutup) — aplikasi tidak punya matriks peran.
    @Default(<String>[]) List<String> akses,
    /// Nama peran dari server (`peran.nama`) — hanya untuk ditampilkan.
    String? peran,
  }) = _User;
}
