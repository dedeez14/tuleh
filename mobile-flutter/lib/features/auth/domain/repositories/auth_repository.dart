import '../../../../core/network/api_result.dart';
import '../entities/user.dart';

/// Kontrak domain autentikasi — presentation & use case bergantung pada
/// abstraksi ini, bukan implementasi data (Dependency Inversion).
abstract interface class AuthRepository {
  Future<Result<User>> login({
    required String login,
    required String password,
    required String deviceName,
  });

  Future<void> logout();

  /// Pengguna sesi berjalan bila token tersimpan & masih valid (auto-login).
  /// null bila belum masuk; [Err] bila token ditolak / gangguan.
  Future<Result<User?>> currentUser();
}
