import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../controllers/auth_controller.dart';

/// Pembungkus akar yang menindaklanjuti 401: interceptor Dio hanya menyalakan
/// [sessionExpiredProvider]; di sini sesi dibersihkan dari Keystore dan
/// router (yang mendengarkan [authControllerProvider]) kembali ke layar
/// masuk dengan pesan. Antrean offline tidak disentuh.
class SesiBerakhirGate extends ConsumerWidget {
  const SesiBerakhirGate({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<bool>(sessionExpiredProvider, (prev, next) async {
      if (!next) return;
      final auth = ref.read(authControllerProvider.notifier);
      final flag = ref.read(sessionExpiredProvider.notifier);
      if (ref.read(authControllerProvider).valueOrNull != null) {
        await auth.sesiBerakhir();
      } else {
        // Token kedaluwarsa terdeteksi saat masuk otomatis: repositori sudah
        // membersihkan sesi; cukup beri tahu alasannya di layar masuk.
        ref.read(pesanMasukProvider.notifier).state = AuthController.pesanSesiBerakhir;
      }
      flag.state = false;
    });
    return child;
  }
}
