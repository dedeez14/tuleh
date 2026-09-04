import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/secure_storage.dart';
import '../../auth/presentation/controllers/auth_controller.dart';
import '../../demo/demo_session.dart';
import '../../toko/presentation/providers/toko_providers.dart';
import '../data/pemantau_task.dart';

/// Jeda antar pemeriksaan ke server (15 dtk ≈ jeda peta meja desktop 5 dtk
/// dikali tiga: cukup cepat untuk pelayan, hemat baterai & kuota).
const jedaPemantau = Duration(seconds: 15);

/// Preferensi "Notifikasi pesanan meja" (tersimpan; bawaan MATI agar layanan
/// hanya berjalan bila pemilik menginginkannya).
class PemantauDiinginkan extends AsyncNotifier<bool> {
  static const _kunci = 'pemantau_pesanan';

  @override
  Future<bool> build() async =>
      (await ref.watch(secureStorageProvider).bacaNilai(_kunci)) == '1';

  Future<void> atur(bool aktif) async {
    await ref
        .read(secureStorageProvider)
        .tulisNilai(_kunci, aktif ? '1' : null);
    state = AsyncData(aktif);
  }
}

final pemantauDiinginkanProvider =
    AsyncNotifierProvider<PemantauDiinginkan, bool>(PemantauDiinginkan.new);

/// Pengendali layanan latar depan (sisi aplikasi). Dipanggil oleh
/// [PemantauSinkron] setiap kali preferensi, akun, atau toko berubah.
class PemantauService {
  PemantauService();

  static bool _terinisialisasi = false;

  bool get didukung => !kIsWeb && Platform.isAndroid;

  void init() {
    if (!didukung || _terinisialisasi) return;
    _terinisialisasi = true;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'pemantau_layanan',
        channelName: 'Pemantau pesanan (berjalan)',
        channelDescription:
            'Tampil selama Tuléh memantau pesanan meja di latar belakang.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(
          jedaPemantau.inMilliseconds,
        ),
        // Token tidak tersedia saat boot tanpa aplikasi dibuka, dan Android 15
        // melarang dataSync dari BOOT_COMPLETED → tidak auto-run saat boot.
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  Future<bool> get berjalan async =>
      didukung && await FlutterForegroundTask.isRunningService;

  /// Minta izin notifikasi (Android 13+; di Android 10–12 langsung diberikan).
  Future<bool> mintaIzin() async {
    if (!didukung) return false;
    final izin = await FlutterForegroundTask.checkNotificationPermission();
    if (izin == NotificationPermission.granted) return true;
    final hasil = await FlutterForegroundTask.requestNotificationPermission();
    return hasil == NotificationPermission.granted;
  }

  Future<void> mulai({
    required String token,
    required String? tokoId,
    required String versi,
    bool pantauMeja = true,
    bool pantauPesanan = true,
  }) async {
    if (!didukung) return;
    init();
    await FlutterForegroundTask.saveData(
      key: KunciPemantau.baseUrl,
      value: AppConfig.defaultBaseUrl + AppConfig.apiPrefix,
    );
    await FlutterForegroundTask.saveData(
      key: KunciPemantau.token,
      value: token,
    );
    await FlutterForegroundTask.saveData(
      key: KunciPemantau.tokoId,
      value: tokoId ?? '',
    );
    await FlutterForegroundTask.saveData(
      key: KunciPemantau.versi,
      value: versi,
    );
    await FlutterForegroundTask.saveData(
      key: KunciPemantau.pantauMeja,
      value: pantauMeja,
    );
    await FlutterForegroundTask.saveData(
      key: KunciPemantau.pantauPesanan,
      value: pantauPesanan,
    );

    if (await FlutterForegroundTask.isRunningService) {
      FlutterForegroundTask.sendDataToTask({'muat_ulang': true});
      return;
    }
    await FlutterForegroundTask.startService(
      serviceId: 7301,
      serviceTypes: [ForegroundServiceTypes.dataSync],
      notificationTitle: 'Tuléh memantau pesanan meja',
      notificationText: 'Menunggu pesanan…',
      notificationInitialRoute: '/',
      callback: mulaiPemantau,
    );
  }

  Future<void> berhenti() async {
    if (!didukung) return;
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
    for (final k in [
      KunciPemantau.token,
      KunciPemantau.tokoId,
      KunciPemantau.baseUrl,
    ]) {
      await FlutterForegroundTask.removeData(key: k);
    }
  }
}

final pemantauServiceProvider = Provider<PemantauService>(
  (_) => PemantauService(),
);

/// Menjaga layanan selaras dengan keadaan aplikasi: hidup hanya bila
/// preferensi aktif, pengguna masuk dengan akun sungguhan (bukan demo), dan
/// toko aktif diketahui; token/toko yang berubah dikirim ulang ke layanan;
/// keluar akun → layanan berhenti dan token dihapus dari penyimpanan layanan.
final pemantauSinkronProvider = Provider<void>((ref) {
  final svc = ref.watch(pemantauServiceProvider);
  if (!svc.didukung) return;

  final ingin = ref.watch(pemantauDiinginkanProvider).valueOrNull ?? false;
  final user = ref.watch(authControllerProvider).valueOrNull;
  final tokoId = ref.watch(activeTokoIdProvider).valueOrNull;
  final demo = ref.watch(demoSessionProvider).active;
  final versi = ref.watch(appVersionProvider);
  final storage = ref.watch(secureStorageProvider);

  Future<void> selaraskan() async {
    if (!ingin || user == null || demo) {
      await svc.berhenti();
      return;
    }
    final token = await storage.readToken();
    if (token == null || token.isEmpty) {
      await svc.berhenti();
      return;
    }
    await svc.mulai(token: token, tokoId: tokoId, versi: versi);
  }

  selaraskan();
});
