import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../toko/presentation/providers/toko_providers.dart';
import '../../data/datasources/pengaturan_remote_datasource.dart';
import '../../data/repositories/pengaturan_repository_impl.dart';
import '../../domain/entities/profil_usaha.dart';
import '../../domain/repositories/pengaturan_repository.dart';

final pengaturanRepositoryProvider = Provider<PengaturanRepository>(
  (ref) => PengaturanRepositoryImpl(PengaturanRemoteDataSource(ref.watch(dioProvider))),
);

final profilUsahaProvider = FutureProvider<ProfilUsaha>((ref) async {
  ref.watch(activeTokoIdProvider);
  final r = await ref.watch(pengaturanRepositoryProvider).profilUsaha();
  return r.when(ok: (v) => v, err: (e) => throw e);
});
