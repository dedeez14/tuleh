import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/tema_provider.dart';
import 'features/auth/presentation/widgets/identitas_gate.dart';
import 'features/auth/presentation/widgets/sesi_berakhir_gate.dart';
import 'features/demo/presentation/masa_coba_gate.dart';
import 'features/langganan/presentation/langganan_gate.dart';
import 'features/pemantau/presentation/pemantau_gate.dart';
import 'features/update/presentation/widgets/update_gate.dart';

/// Akar aplikasi — MaterialApp.router dengan tema Tuléh (light/dark ikut sistem).
/// Dibungkus [SesiBerakhirGate] (401 → layar masuk), [IdentitasGate] (kembali
/// ke depan & 403 → hak akses disegarkan), [UpdateGate] (426 / wajib → layar
/// perbarui; banner opsional) dan [LanggananGate] (402 → layar langganan
/// berakhir).
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
      themeMode: ref.watch(temaProvider),
      routerConfig: router,
      builder: (context, child) => SesiBerakhirGate(
        child: IdentitasGate(
          child: MasaCobaGate(
            child: PemantauGate(
              child: UpdateGate(
                child: LanggananGate(child: child ?? const SizedBox.shrink()),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
