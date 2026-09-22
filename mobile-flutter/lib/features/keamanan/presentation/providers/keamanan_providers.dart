import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../data/datasources/keamanan_remote_datasource.dart';
import '../../domain/entities/otorisasi.dart';

final keamananDataSourceProvider = Provider<KeamananRemoteDataSource>(
  (ref) => KeamananRemoteDataSource(ref.watch(dioProvider)),
);

/// Status PIN persetujuan pengguna sendiri — menentukan tampilnya entri Pengaturan.
final statusPinProvider = FutureProvider<StatusPin>(
  (ref) => ref.watch(keamananDataSourceProvider).statusPin(),
);
