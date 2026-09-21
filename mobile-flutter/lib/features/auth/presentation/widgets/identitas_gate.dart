import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/akses/identitas_segar.dart';
import '../../../../core/navigation/registri_modul.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/router/app_router.dart';
import '../../../toko/presentation/providers/toko_providers.dart';
import '../controllers/auth_controller.dart';

/// Pembungkus akar yang menjaga identitas tetap mutakhir (Tahap B §2b): saat
/// aplikasi kembali ke depan (`resumed`) dan sesudah 403, `/auth/me` dipanggil
/// ulang sehingga hak akses dan peran yang berubah di server langsung terpakai
/// — tanpa kasir perlu keluar-masuk.
///
/// Jedanya ada di [AuthController.segarkanIdentitas] (60 detik untuk resume,
/// 30 detik tersendiri untuk jalur 403). Di sini tinggal dua akibatnya:
/// manifest dimuat ulang saat hak berubah (server menyaring menu per hak,
/// `manifest_version` tidak ikut bergerak) dan layar yang BARU kehilangan
/// pintunya ditinggalkan ke Beranda — kalau tidak, layarnya terus menabrak 403.
class IdentitasGate extends ConsumerStatefulWidget {
  const IdentitasGate({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<IdentitasGate> createState() => _IdentitasGateState();
}

class _IdentitasGateState extends ConsumerState<IdentitasGate>
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
    if (state == AppLifecycleState.resumed) unawaited(_segarkan());
  }

  String? _layarSekarang() {
    try {
      return ref
          .read(routerProvider)
          .routerDelegate
          .currentConfiguration
          .uri
          .path;
    } catch (_) {
      return null; // router belum siap — tak ada layar untuk dipulangkan
    }
  }

  Future<void> _segarkan({bool paksa = false}) async {
    // Dipotret SEBELUM await: sesudahnya, keadaan yang dibaca sudah keadaan
    // yang baru — membandingkannya berarti membandingkannya dengan dirinya
    // sendiri.
    final layar = _layarSekarang();
    final sebelumnya = rutePunyaPintu(
      ref.read(activeManifestProvider).valueOrNull,
    );

    final berubah = await ref
        .read(authControllerProvider.notifier)
        .segarkanIdentitas(paksa: paksa);
    if (!berubah || !mounted) return;

    // Hak berubah → menu manifest ikut berubah. Dimuat ulang LEBIH DULU supaya
    // pintu dinilai atas menu yang berlaku untuk hak yang baru. Gagal memuat
    // (offline) tidak mengganti manifest lama dan tidak mengusir siapa pun.
    final siap = await ref.read(activeManifestProvider.notifier).segarkan();
    if (!siap || !mounted) return;

    final tujuan = layarTujuan(
      layar,
      rutePunyaPintu(ref.read(activeManifestProvider).valueOrNull),
      sebelumnya,
    );
    if (tujuan != null) ref.read(routerProvider).go(tujuan);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(hakDitolakProvider, (prev, next) {
      if (next > (prev ?? 0)) unawaited(_segarkan(paksa: true));
    });
    return widget.child;
  }
}
