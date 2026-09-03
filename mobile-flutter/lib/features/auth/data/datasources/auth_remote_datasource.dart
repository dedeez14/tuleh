import 'package:dio/dio.dart';

import '../../../../core/network/api_error_mapper.dart';
import '../../../../core/network/api_exception.dart';
import '../../domain/entities/user.dart';

/// Sumber data jaringan untuk autentikasi (MOVERA POS API).
/// Parsing envelope defensif — bentuk server bervariasi (id int/string).
class AuthRemoteDataSource {
  AuthRemoteDataSource(this._dio);

  final Dio _dio;

  /// POST /auth/login → { token, user }. Body: login + password + device_name.
  Future<({String token, User user})> login({
    required String login,
    required String password,
    required String deviceName,
  }) async {
    final body = await _send(
      () => _dio.post<dynamic>('/auth/login', data: {
        'login': login,
        'password': password,
        'device_name': deviceName,
      }),
    );
    final data = _map(body['data']);
    final token = (data['token'] ?? data['access_token'])?.toString();
    if (token == null || token.isEmpty) {
      throw const ApiException(message: 'Token tidak diterima dari server.', statusCode: 200);
    }
    return (token: token, user: _userFrom(data));
  }

  /// GET /auth/me → user sesi berjalan (untuk auto-login).
  Future<User> me() async {
    final body = await _send(() => _dio.get<dynamic>('/auth/me'));
    return _userFrom(_map(body['data']));
  }

  // ---- helper ----

  /// Kirim request (validateStatus longgar) → kembalikan body envelope sukses,
  /// atau lempar [ApiException] untuk 4xx/5xx/jaringan.
  Future<Map<String, dynamic>> _send(Future<Response<dynamic>> Function() call) async {
    late final Response<dynamic> res;
    try {
      res = await call();
    } on DioException catch (e) {
      throw ApiErrorMapper.fromDio(e);
    }
    final code = res.statusCode ?? 0;
    final body = _map(res.data);
    final ok = code >= 200 && code < 300 && body['success'] == true;
    if (!ok) {
      throw ApiException(
        message: (body['message'] as String?) ?? ApiErrorMapper.statusMessage(code),
        statusCode: code,
        errors: ApiErrorMapper.parseErrors(body['errors']),
      );
    }
    return body;
  }

  Map<String, dynamic> _map(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};

  User _userFrom(Map<String, dynamic> data) {
    final userMap = _map(data['user']);
    final companyMap = _map(data['company']);
    return User(
      id: (userMap['id'] ?? '').toString(),
      name: (userMap['name'] ?? userMap['nama'] ?? 'Pengguna').toString(),
      email: userMap['email']?.toString(),
      role: (data['pos_role'] ?? userMap['role'])?.toString(),
      companyName: (companyMap['nama'] ?? companyMap['name'])?.toString(),
    );
  }
}
