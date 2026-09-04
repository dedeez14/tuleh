import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_config.dart';
import '../../../core/widgets/app_background.dart';
import '../../../core/widgets/splash_screen.dart' show BrandAssets;
import '../../auth/presentation/controllers/auth_controller.dart';

/// Kunci Mode Demo setelah masa coba 7 hari berakhir. Satu-satunya jalan
/// keluar: masuk dengan akun berlangganan. Tidak ada tombol "coba lagi".
class DemoBerakhirScreen extends ConsumerWidget {
  const DemoBerakhirScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final host =
        Uri.tryParse(AppConfig.defaultBaseUrl)?.host ?? AppConfig.defaultBaseUrl;

    return Scaffold(
      body: AppBackground(
        pola: true,
        ombak: false,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Image.asset(
                        BrandAssets.icon,
                        height: 72,
                        semanticLabel: 'Logo Tuléh',
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      'Masa coba berakhir',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Mode Demo di ponsel ini sudah dipakai 7 hari. Untuk terus '
                      'memakai Tuléh, masuk dengan akun berlangganan.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.5,
                        color: cs.onSurface.withValues(alpha: 0.75),
                      ),
                    ),
                    const SizedBox(height: 26),
                    FilledButton.icon(
                      onPressed: () async {
                        await ref.read(authControllerProvider.notifier).logout();
                        if (context.mounted) context.go('/login');
                      },
                      icon: const Icon(Icons.login_rounded),
                      label: const Text('Masuk dengan akun'),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Belum punya akun? Daftar dan berlangganan di $host, '
                      'lalu masuk dengan email dan kata sandi Anda.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: cs.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
