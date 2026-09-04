import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/router/app_router.dart';
import '../../auth/presentation/controllers/auth_controller.dart';
import '../data/masa_coba_service.dart';
import '../demo_session.dart';
import '../domain/masa_coba.dart';

/// Memeriksa masa coba Mode Demo setiap aplikasi kembali ke depan. Bila
/// sudah berakhir saat demo sedang dipakai → keluar dari demo dan tampilkan
/// layar kunci. Tidak melakukan apa pun di luar demo.
class MasaCobaGate extends ConsumerStatefulWidget {
  const MasaCobaGate({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<MasaCobaGate> createState() => _MasaCobaGateState();
}

class _MasaCobaGateState extends ConsumerState<MasaCobaGate>
    with WidgetsBindingObserver {
  bool _sibuk = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _periksa();
  }

  Future<void> _periksa() async {
    if (_sibuk || !ref.read(demoSessionProvider).active) return;
    _sibuk = true;
    try {
      final st = await ref.read(masaCobaServiceProvider).periksa();
      if (!mounted) return;
      ref.invalidate(masaCobaStatusProvider);
      if (st.kode == KodeMasaCoba.berakhir || st.kode == KodeMasaCoba.rusak) {
        await ref.read(authControllerProvider.notifier).logout();
        if (mounted) ref.read(routerProvider).go('/demo-berakhir');
      }
    } finally {
      _sibuk = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
