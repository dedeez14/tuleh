import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../data/datasources/inventory_remote_datasource.dart';

final inventoryDataSourceProvider = Provider<InventoryRemoteDataSource>(
  (ref) => InventoryRemoteDataSource(ref.watch(dioProvider)),
);
