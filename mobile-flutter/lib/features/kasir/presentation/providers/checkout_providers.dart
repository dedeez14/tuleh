import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/offline/koneksi.dart';
import '../../../../core/offline/nomor_lokal.dart';
import '../../../../core/offline/pengurai.dart';
import '../../../../core/storage/secure_storage.dart';
import '../../../toko/presentation/providers/toko_providers.dart';
import '../../data/checkout_repository.dart';
import '../../data/datasources/transaction_remote_datasource.dart';

final transactionDataSourceProvider = Provider<TransactionRemoteDataSource>(
  (ref) => TransactionRemoteDataSource(ref.watch(dioProvider)),
);

/// Checkout dengan jalur offline (antrean). Toko aktif ikut dicatat agar
/// riwayat & delta stok tertunda tidak tertukar antar toko.
final checkoutRepositoryProvider = Provider<CheckoutRepository>(
  (ref) => CheckoutRepository(
    remote: ref.watch(transactionDataSourceProvider),
    antrean: ref.watch(antreanStoreProvider),
    nomorLokal: NomorLokal(ref.watch(secureStorageProvider)),
    koneksi: ref.read(koneksiProvider.notifier),
    tokoId: ref.watch(activeTokoIdProvider).valueOrNull,
  ),
);
