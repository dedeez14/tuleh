import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Penyimpanan aman (Keystore Android) untuk token & preferensi sensitif.
/// Token TIDAK PERNAH disimpan di SharedPreferences biasa (high-secure).
class SecureStorage {
  SecureStorage(this._storage);

  final FlutterSecureStorage _storage;

  static const _kToken = 'tuleh_token';
  static const _kBaseUrl = 'tuleh_base_url';
  static const _kActiveToko = 'tuleh_active_toko';
  static const _kUpdateSnooze = 'tuleh_update_snooze';
  static const _kRestokAmbang = 'tuleh_restok_ambang';

  Future<String?> readToken() => _storage.read(key: _kToken);
  Future<void> writeToken(String? value) => value == null || value.isEmpty
      ? _storage.delete(key: _kToken)
      : _storage.write(key: _kToken, value: value);

  Future<String?> readBaseUrl() => _storage.read(key: _kBaseUrl);
  Future<void> writeBaseUrl(String value) =>
      _storage.write(key: _kBaseUrl, value: value);

  Future<String?> readActiveTokoId() => _storage.read(key: _kActiveToko);
  Future<void> writeActiveTokoId(String? value) => value == null || value.isEmpty
      ? _storage.delete(key: _kActiveToko)
      : _storage.write(key: _kActiveToko, value: value);

  /// Tanggal terakhir banner update opsional ditutup (format YYYY-MM-DD).
  /// Dipakai agar banner muncul maksimal 1× per hari.
  Future<String?> readUpdateSnooze() => _storage.read(key: _kUpdateSnooze);
  Future<void> writeUpdateSnooze(String yyyymmdd) =>
      _storage.write(key: _kUpdateSnooze, value: yyyymmdd);

  /// Ambang stok "perlu restok" (dipakai layar Stok). Default 5.
  Future<int> readRestokAmbang() async {
    final v = await _storage.read(key: _kRestokAmbang);
    return int.tryParse(v ?? '') ?? 5;
  }

  Future<void> writeRestokAmbang(int value) =>
      _storage.write(key: _kRestokAmbang, value: value.toString());

  Future<void> clearSession() async {
    await _storage.delete(key: _kToken);
    await _storage.delete(key: _kActiveToko);
  }
}

/// Provider — instance tunggal. flutter_secure_storage v11 di Android memakai
/// EncryptedSharedPreferences (Android Keystore) secara bawaan.
final secureStorageProvider = Provider<SecureStorage>((ref) {
  return SecureStorage(const FlutterSecureStorage());
});
