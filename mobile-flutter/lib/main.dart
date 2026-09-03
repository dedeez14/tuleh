import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app.dart';
import 'core/network/api_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
