import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/storage/secure_storage.dart';
import '../../data/datasources/update_remote_datasource.dart';
import '../../data/services/apk_installer.dart';
import '../../domain/entities/app_version_info.dart';

final apkInstallerProvider = Provider<ApkInstaller>((ref) => ApkInstaller());

final updateRemoteProvider = Provider<UpdateRemoteDataSource>(
  (ref) => UpdateRemoteDataSource(ref.watch(dioProvider)),
);

/// ABI yang didukung perangkat (urutan prioritas sistem) — menentukan APK
/// mana yang diunduh dari rilis split-per-abi. Kosong bila tak terbaca.
final abiPerangkatProvider = FutureProvider<List<String>>((ref) async {
  if (!Platform.isAndroid) return const [];
  try {
    final info = await DeviceInfoPlugin().androidInfo;
    return info.supportedAbis;
  } catch (_) {
    return const [];
  }
});

/// Cek versi: server dulu, lalu GitHub Releases (fail-open). Di-refresh saat
/// start & kembali foreground (UpdateGate memanggil `ref.invalidate`).
final appVersionInfoProvider = FutureProvider<AppVersionInfo>((ref) async {
  final versi = ref.watch(appVersionProvider);
  final abi = await ref.watch(abiPerangkatProvider.future);
  return ref.watch(updateRemoteProvider).cek(versi, abiPerangkat: abi);
});

String _todayKey() {
  final n = DateTime.now();
  final m = n.month.toString().padLeft(2, '0');
  final d = n.day.toString().padLeft(2, '0');
  return '${n.year}-$m-$d';
}

/// true bila banner update opsional sudah ditutup hari ini (tampil maks 1×/hari).
/// Default konservatif: saat masih loading → dianggap snoozed (hindari kedip).
final updateSnoozedTodayProvider = FutureProvider<bool>((ref) async {
  final last = await ref.watch(secureStorageProvider).readUpdateSnooze();
  return last == _todayKey();
});

/// Tandai banner opsional ditutup hari ini (dipanggil dari widget).
Future<void> snoozeUpdateBanner(WidgetRef ref) async {
  await ref.read(secureStorageProvider).writeUpdateSnooze(_todayKey());
  ref.invalidate(updateSnoozedTodayProvider);
}
