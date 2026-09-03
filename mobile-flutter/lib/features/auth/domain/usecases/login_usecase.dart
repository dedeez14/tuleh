import '../../../../core/network/api_result.dart';
import '../entities/user.dart';
import '../repositories/auth_repository.dart';

/// Use case — masuk dengan kredensial. Satu tanggung jawab, mudah diuji.
class LoginUseCase {
  const LoginUseCase(this._repository);

  final AuthRepository _repository;

  Future<Result<User>> call({
    required String login,
    required String password,
    required String deviceName,
  }) {
    return _repository.login(
      login: login,
      password: password,
      deviceName: deviceName,
    );
  }
}
