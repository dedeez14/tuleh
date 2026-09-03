import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/user.dart';
import '../providers/auth_providers.dart';

/// State autentikasi sesi: `AsyncData(user)` = masuk, `AsyncData(null)` = keluar,
/// `AsyncLoading` = proses, `AsyncError` = gagal (pesan ditampilkan layar).
class AuthController extends AsyncNotifier<User?> {
  @override
  Future<User?> build() async {
    // Auto-login: bila token tersimpan & valid, langsung masuk.
    final result = await ref.read(authRepositoryProvider).currentUser();
    return result.when(ok: (user) => user, err: (_) => null);
  }

  Future<void> login({
    required String login,
    required String password,
    required String deviceName,
  }) async {
    state = const AsyncLoading();
    final result = await ref.read(loginUseCaseProvider).call(
          login: login,
          password: password,
          deviceName: deviceName,
        );
    state = result.when(
      ok: (user) => AsyncData(user),
      err: (e) => AsyncError(e, StackTrace.current),
    );
  }

  Future<void> logout() async {
    await ref.read(authRepositoryProvider).logout();
    state = const AsyncData(null);
  }
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, User?>(AuthController.new);
