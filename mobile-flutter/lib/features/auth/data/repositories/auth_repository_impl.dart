import '../../../../core/network/api_exception.dart';
import '../../../../core/network/api_result.dart';
import '../../../../core/storage/secure_storage.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_datasource.dart';

/// Implementasi repository — orkestrasi datasource + penyimpanan token aman.
class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({
    required this.remote,
    required this.storage,
  });

  final AuthRemoteDataSource remote;
  final SecureStorage storage;

  @override
  Future<Result<User>> login({
    required String login,
    required String password,
    required String deviceName,
  }) async {
    try {
      final result = await remote.login(
        login: login,
        password: password,
        deviceName: deviceName,
      );
      await storage.writeToken(result.token); // token disimpan di Keystore
      return Ok(result.user);
    } on ApiException catch (e) {
      return Err(e);
    }
  }

  @override
  Future<void> logout() => storage.clearSession();

  @override
  Future<Result<User?>> currentUser() async {
    final token = await storage.readToken();
    if (token == null || token.isEmpty) return const Ok(null);
    try {
      return Ok(await remote.me());
    } on ApiException catch (e) {
      // Token ditolak → bersihkan sesi agar kembali ke login.
      if (e.isUnauthorized) await storage.clearSession();
      return Err(e);
    }
  }
}
