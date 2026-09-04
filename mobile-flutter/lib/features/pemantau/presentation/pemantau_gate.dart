import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/router/app_router.dart';
import '../../meja/presentation/providers/meja_providers.dart';
import '../../pesanan/presentation/providers/pesanan_providers.dart';
import '../data/pemantau_task.dart';
import 'pemantau_providers.dart';

/// Jembatan layanan pemantau ↔ UI. Dipasang di akar aplikasi:
/// - menjaga [pemantauSinkronProvider] hidup (layanan mengikuti akun/toko);
/// - menerima kejadian dari isolate layanan → segarkan peta meja & papan
///   pesanan yang sedang terbuka;
/// - ketukan notifikasi → buka layar tujuan ('/meja' atau '/aktivitas'),
///   termasuk saat aplikasi dibuka dari keadaan tertutup.
class PemantauGate extends ConsumerStatefulWidget {
  const PemantauGate({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<PemantauGate> createState() => _PemantauGateState();
}

class _PemantauGateState extends ConsumerState<PemantauGate> {
  final _notif = FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    if (kIsWeb || !Platform.isAndroid) return;
    FlutterForegroundTask.addTaskDataCallback(_dariLayanan);
    _siapkanNotifikasi();
  }

  Future<void> _siapkanNotifikasi() async {
    try {
      await _notif.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
        onDidReceiveNotificationResponse: (r) => _buka(r.payload),
      );
      final awal = await _notif.getNotificationAppLaunchDetails();
      if (awal?.didNotificationLaunchApp ?? false) {
        _buka(awal!.notificationResponse?.payload);
      }
    } catch (_) {
      // Tanpa plugin notifikasi (mis. test) — tidak apa-apa.
    }
  }

  void _buka(String? tujuan) {
    if (tujuan == null || !tujuan.startsWith('/')) return;
    if (!mounted) return;
    ref.read(routerProvider).go(tujuan);
  }

  void _dariLayanan(Object data) {
    if (data is! Map) return;
    if (data[PesanPemantau.kejadian] != null) {
      ref.invalidate(mejaPetaProvider);
      ref.invalidate(pesananListProvider);
    }
  }

  @override
  void dispose() {
    if (!kIsWeb && Platform.isAndroid) {
      FlutterForegroundTask.removeTaskDataCallback(_dariLayanan);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(pemantauSinkronProvider);
    return widget.child;
  }
}
