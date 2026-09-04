import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/demo/presentation/masa_coba_gate.dart';
import 'features/pemantau/presentation/pemantau_gate.dart';
import 'features/update/presentation/widgets/update_gate.dart';

/// Akar aplikasi — MaterialApp.router dengan tema Tuléh (light/dark ikut sistem).
/// Dibungkus [UpdateGate] (Auto-Update: layar wajib / banner opsional).
class TulehApp extends ConsumerWidget {
  const TulehApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Tuléh POS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: router,
      builder: (context, child) => MasaCobaGate(
        child: PemantauGate(
          child: UpdateGate(child: child ?? const SizedBox.shrink()),
        ),
      ),
    );
  }
}
