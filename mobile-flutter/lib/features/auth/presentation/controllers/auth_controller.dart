import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/secure_storage.dart';
import '../../../demo/demo_session.dart';
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

  /// Masuk Mode Demo — tanpa akun, tanpa jaringan. Mesin demo menjawab semua
  /// permintaan API di perangkat ini; token demo disimpan agar alur yang
  /// memeriksa token (mis. auto-login & interceptor toko) tetap berjalan.
  Future<void> startDemo() async {
    state = const AsyncLoading();
    ref.read(demoSessionProvider).start();
    final storage = ref.read(secureStorageProvider);
    await storage.writeToken('demo-token');
    await storage.writeActiveTokoId(null); // mulai dari pemilihan toko
    final result = await ref.read(authRepositoryProvider).currentUser();
    state = result.when(
      ok: (user) => AsyncData(user),
      err: (e) => AsyncError(e, StackTrace.current),
    );
  }

  bool get isDemo => ref.read(demoSessionProvider).active;

  Future<void> logout() async {
    ref.read(demoSessionProvider).stop();
    await ref.read(authRepositoryProvider).logout();
    state = const AsyncData(null);
  }
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, User?>(AuthController.new);
