import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/demo/demo_session.dart';
import '../constants/app_config.dart';
import '../storage/secure_storage.dart';

/// Versi aplikasi untuk header `X-Tuleh-Version` (Auto-Update).
/// Di-override di `main()` setelah membaca PackageInfo.
final appVersionProvider = Provider<String>((ref) => '0.0.0');

/// true saat server membalas HTTP 426 → wajib perbarui aplikasi.
final updateRequiredProvider = StateProvider<bool>((ref) => false);

/// true saat token ditolak (401) → sesi berakhir, arahkan ke login.
final sessionExpiredProvider = StateProvider<bool>((ref) => false);

/// Dio terkonfigurasi: base URL MOVERA, interceptor header versi + token +
/// toko aktif, deteksi 426/401. validateStatus longgar → envelope
/// dinormalisasi di lapisan data (bukan lempar DioException untuk 4xx/5xx).
final dioProvider = Provider<Dio>((ref) {
  final storage = ref.watch(secureStorageProvider);
  final version = ref.watch(appVersionProvider);

  final dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.defaultBaseUrl + AppConfig.apiPrefix,
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      headers: const {'Accept': 'application/json'},
      validateStatus: (_) => true,
    ),
  );

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        options.headers[AppConfig.versionHeader] = version;
        final token = await storage.readToken();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
          final tokoId = await storage.readActiveTokoId();
          if (tokoId != null &&
              tokoId.isNotEmpty &&
              !options.queryParameters.containsKey('toko_id')) {
            options.queryParameters['toko_id'] = tokoId;
          }
        }
        handler.next(options);
      },
      onResponse: (response, handler) {
        final code = response.statusCode ?? 0;
        if (code == 426) {
          ref.read(updateRequiredProvider.notifier).state = true;
        } else if (code == 401) {
          ref.read(sessionExpiredProvider.notifier).state = true;
        }
        handler.next(response);
      },
    ),
  );

  // Mode Demo dipasang SETELAH interceptor header/toko: `handler.resolve`
  // menghentikan rantai, jadi bila demo di depan, `toko_id` tidak pernah
  // ditambahkan dan semua data demo jatuh ke toko pertama apa pun toko yang
  // dipilih pengguna. Saat demo aktif, permintaan tetap tidak keluar ke jaringan.
  dio.interceptors.add(DemoInterceptor(ref.watch(demoSessionProvider)));

  return dio;
});
