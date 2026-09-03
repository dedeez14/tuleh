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

/// Cek versi ke server (fail-open). Di-refresh saat start & kembali foreground
/// (UpdateGate memanggil `ref.invalidate`).
final appVersionInfoProvider = FutureProvider<AppVersionInfo>((ref) async {
  final versi = ref.watch(appVersionProvider);
  return ref.watch(updateRemoteProvider).cek(versi);
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
