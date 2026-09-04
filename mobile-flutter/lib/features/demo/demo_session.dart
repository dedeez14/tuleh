import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/demo_engine.dart';

/// Sesi Mode Demo — hidup selama aplikasi berjalan, tidak disimpan ke storage
/// (sama seperti desktop: data demo direset tiap aplikasi dibuka ulang).
class DemoSession {
  DemoEngine? _engine;

  bool get active => _engine != null;
  DemoEngine? get engine => _engine;

  /// Mulai demo dengan data segar.
  void start() => _engine = DemoEngine();

  void stop() => _engine = null;
}

final demoSessionProvider = Provider<DemoSession>((ref) => DemoSession());

/// Memotong permintaan jaringan saat Mode Demo aktif dan menjawabnya dari
/// [DemoEngine]. Dipasang paling depan pada Dio sehingga tidak ada lalu lintas
/// yang benar-benar keluar ke server saat demo.
class DemoInterceptor extends Interceptor {
  DemoInterceptor(this._session);

  final DemoSession _session;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final engine = _session.engine;
    if (engine == null) {
      handler.next(options);
      return;
    }

    // `options.path` relatif terhadap baseUrl (sudah tanpa /api/pos/v1).
    final path = Uri.parse(options.path).path;
    final res = engine.handle(
      method: options.method,
      path: path.startsWith('/') ? path : '/$path',
      query: Map<String, dynamic>.from(options.queryParameters),
      body: options.data,
    );

    handler.resolve(
      Response<dynamic>(
        requestOptions: options,
        statusCode: res.status,
        data: res.body,
      ),
    );
  }
}
