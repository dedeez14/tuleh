import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../domain/entities/app_version_info.dart';
import '../providers/update_providers.dart';
import '../screens/update_required_screen.dart';
import 'update_banner.dart';

/// Pembungkus akar app (via MaterialApp.builder) untuk Auto-Update:
///  - WAJIB (server `wajib=true` atau HTTP 426) → [UpdateRequiredScreen] memblokir.
///  - OPSIONAL (`update_tersedia`) → banner di bawah konten (maks 1×/hari).
/// Fail-open: selama cek loading / gagal → app tampil normal.
class UpdateGate extends ConsumerStatefulWidget {
  const UpdateGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends ConsumerState<UpdateGate>
    with WidgetsBindingObserver {
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
    // Cek ulang versi saat kembali ke depan.
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(appVersionInfoProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Saat 426 terdeteksi, segarkan /app/versi agar dapat flag wajib + URL unduh.
    ref.listen<bool>(updateRequiredProvider, (prev, next) {
      if (next == true) ref.invalidate(appVersionInfoProvider);
    });

    // Self-heal: bila /app/versi terkonfirmasi TIDAK wajib, lepas latch 426 yang
    // mungkin nyasar (mis. 426 dari proxy) tanpa perlu mulai ulang aplikasi.
    ref.listen<AsyncValue<AppVersionInfo>>(appVersionInfoProvider, (prev, next) {
      final info = next.valueOrNull;
      if (info != null &&
          info.versiTerbaru.isNotEmpty &&
          !info.wajib &&
          ref.read(updateRequiredProvider)) {
        ref.read(updateRequiredProvider.notifier).state = false;
      }
    });

    final blocked426 = ref.watch(updateRequiredProvider);
    final info =
        ref.watch(appVersionInfoProvider).valueOrNull ?? AppVersionInfo.none;
    final mustUpdate = blocked426 || info.wajib;

    if (mustUpdate) {
      return UpdateRequiredScreen(info: info);
    }

    final snoozed = ref.watch(updateSnoozedTodayProvider).valueOrNull ?? true;
    final showBanner = info.updateTersedia && !info.wajib && !snoozed;

    // Banner DI-INSET (bukan menimpa) agar tak menutup aksi bawah (kasir/bayar).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: widget.child),
        if (showBanner) SafeArea(top: false, child: UpdateBanner(info: info)),
      ],
    );
  }
}
