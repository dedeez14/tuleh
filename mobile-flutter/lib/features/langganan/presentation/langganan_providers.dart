import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_client.dart';
import '../../auth/presentation/controllers/auth_controller.dart';
import '../data/langganan_remote_datasource.dart';
import '../domain/langganan.dart';

final langgananRemoteProvider = Provider<LanggananRemoteDataSource>(
  (ref) => LanggananRemoteDataSource(ref.watch(dioProvider)),
);

/// Status langganan akun yang sedang masuk (null = belum masuk / gagal baca).
final statusLanggananProvider = FutureProvider<StatusLangganan?>((ref) async {
  final user = ref.watch(authControllerProvider).valueOrNull;
  if (user == null) return null;
  return ref.watch(langgananRemoteProvider).status();
});

/// Kontak CS dari server (mitra perekrut atau CS pusat).
final kontakCsProvider = FutureProvider<KontakCs?>((ref) async {
  final user = ref.watch(authControllerProvider).valueOrNull;
  if (user == null) return null;
  return ref.watch(langgananRemoteProvider).kontakCs();
});

/// Membuka tautan di aplikasi luar (peramban / WhatsApp). Diganti di uji.
typedef PembukaTautan = Future<bool> Function(Uri uri);

final pembukaTautanProvider = Provider<PembukaTautan>(
  (ref) => (uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  },
);
