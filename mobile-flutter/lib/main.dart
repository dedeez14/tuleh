import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app.dart';
import 'core/diagnostik/diagnostik.dart';
import 'core/diagnostik/pelapor_diagnostik.dart';
import 'core/network/api_client.dart';
import 'core/offline/sinkron_latar.dart';
import 'core/storage/secure_storage.dart';

Future<void> main() async {
  // Pelapor dibuat sebelum apa pun agar galat saat inisialisasi ikut terlapor.
  // Versi diisi setelah PackageInfo terbaca (laporan sebelum itu "0.0.0").
  PelaporDiagnostik? pelapor;

  // Zona penjaga: galat asinkron yang lolos dari PlatformDispatcher.onError
  // (mis. dari timer/stream di zona ini) tetap tercatat, bukan hilang senyap.
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      final storage = SecureStorage(const FlutterSecureStorage());

      // Versi app untuk header X-Tuleh-Version (Auto-Update). Gagal baca → fallback.
      var version = '0.0.0';
      try {
        final info = await PackageInfo.fromPlatform();
        version = info.version;
      } catch (_) {
        // biarkan fallback
      }

      pelapor = buatPelaporDiagnostik(versi: version, storage: storage);
      pasangPenangkapGalat(pelapor!);
      unawaited(KonteksPerangkat.muat());

      // Kanal aplikasi ↔ isolate layanan pemantau pesanan (harus sebelum runApp).
      FlutterForegroundTask.initCommunicationPort();
      // Sinkronisasi antrean di latar belakang (WorkManager) — tetap berjalan
      // walau aplikasi ditutup, begitu jaringan tersedia. Versi dicatat agar
      // isolate latar mengirim X-Tuleh-Version yang sama.
      unawaited(storage.writeVersiApp(version).catchError((_) {}));
      await SinkronLatar.siapkan();

      runApp(
        ProviderScope(
          overrides: [
            appVersionProvider.overrideWithValue(version),
            secureStorageProvider.overrideWithValue(storage),
            pelaporDiagnostikProvider.overrideWithValue(pelapor!),
          ],
          child: const TulehApp(),
        ),
      );

      // Laporan yang tertunda dari sesi sebelumnya (mis. crash tanpa sinyal).
      unawaited(pelapor!.kirimTertunda());
    },
    (galat, stack) {
      final p = pelapor;
      if (p != null) {
        laporkanCrashZona(p, galat, stack);
      } else {
        debugPrint('Galat sebelum pelapor siap: $galat\n$stack');
      }
    },
  );
}
