import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app.dart';
import 'core/network/api_client.dart';
import 'core/offline/sinkron_latar.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Kanal aplikasi ↔ isolate layanan pemantau pesanan (harus sebelum runApp).
  FlutterForegroundTask.initCommunicationPort();
  // Sinkronisasi antrean di latar belakang (WorkManager) — tetap berjalan
  // walau aplikasi ditutup, begitu jaringan tersedia.
  await SinkronLatar.siapkan();

  // Versi app untuk header X-Tuleh-Version (Auto-Update). Gagal baca → fallback.
  var version = '0.0.0';
  try {
    final info = await PackageInfo.fromPlatform();
    version = info.version;
  } catch (_) {
    // biarkan fallback
  }

  runApp(
    ProviderScope(
      overrides: [appVersionProvider.overrideWithValue(version)],
      child: const TulehApp(),
    ),
  );
}
