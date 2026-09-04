import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Penyimpanan aman (Keystore Android) untuk token & preferensi sensitif.
/// Token TIDAK PERNAH disimpan di SharedPreferences biasa (high-secure).
///
/// Semua pembacaan di-cache di memori. Interceptor Dio membaca token dan id
/// toko pada SETIAP permintaan; tanpa cache itu berarti dua operasi Keystore
/// per permintaan, dan pada banyak ponsel Android 10 satu operasi Keystore
/// memakan ratusan milidetik — beranda yang memicu belasan permintaan jadi
/// terasa "memuat toko" berdetik-detik. Tulis/hapus memperbarui cache.
class SecureStorage {
  SecureStorage(this._storage);

  final FlutterSecureStorage _storage;
  final Map<String, String?> _cache = {};

  Future<String?> _read(String key) async {
    if (_cache.containsKey(key)) return _cache[key];
    final v = await _storage.read(key: key);
    _cache[key] = v;
    return v;
  }

  Future<void> _write(String key, String? value) async {
    if (value == null || value.isEmpty) {
      _cache[key] = null;
      await _storage.delete(key: key);
    } else {
      _cache[key] = value;
      await _storage.write(key: key, value: value);
    }
  }

  static const _kToken = 'tuleh_token';
  static const _kBaseUrl = 'tuleh_base_url';
  static const _kActiveToko = 'tuleh_active_toko';
  static const _kUpdateSnooze = 'tuleh_update_snooze';
  static const _kRestokAmbang = 'tuleh_restok_ambang';

  Future<String?> readToken() => _read(_kToken);
  Future<void> writeToken(String? value) => _write(_kToken, value);

  Future<String?> readBaseUrl() => _read(_kBaseUrl);
  Future<void> writeBaseUrl(String value) => _write(_kBaseUrl, value);

  Future<String?> readActiveTokoId() => _read(_kActiveToko);
  Future<void> writeActiveTokoId(String? value) => _write(_kActiveToko, value);

  /// Tanggal terakhir banner update opsional ditutup (format YYYY-MM-DD).
  /// Dipakai agar banner muncul maksimal 1× per hari.
  Future<String?> readUpdateSnooze() => _read(_kUpdateSnooze);
  Future<void> writeUpdateSnooze(String yyyymmdd) =>
      _write(_kUpdateSnooze, yyyymmdd);

  /// Ambang stok "perlu restok" (dipakai layar Stok). Default 5.
  Future<int> readRestokAmbang() async {
    final v = await _read(_kRestokAmbang);
    return int.tryParse(v ?? '') ?? 5;
  }

  Future<void> writeRestokAmbang(int value) =>
      _write(_kRestokAmbang, value.toString());

  /// Nilai preferensi bebas (mis. printer terpilih). Dipisah dari kunci sesi
  /// agar tidak ikut terhapus saat pengguna keluar.
  Future<String?> bacaNilai(String kunci) => _read('tuleh_$kunci');

  Future<void> tulisNilai(String kunci, String? nilai) =>
      _write('tuleh_$kunci', nilai);

  Future<void> clearSession() async {
    await _write(_kToken, null);
    await _write(_kActiveToko, null);
  }
}

/// Provider — instance tunggal. flutter_secure_storage v11 di Android memakai
/// EncryptedSharedPreferences (Android Keystore) secara bawaan.
final secureStorageProvider = Provider<SecureStorage>((ref) {
  return SecureStorage(const FlutterSecureStorage());
});
