import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../data/datasources/transaction_remote_datasource.dart';

final transactionDataSourceProvider = Provider<TransactionRemoteDataSource>(
  (ref) => TransactionRemoteDataSource(ref.watch(dioProvider)),
);
