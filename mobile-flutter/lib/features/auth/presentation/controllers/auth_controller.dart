import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/akses/identitas_segar.dart';
import '../../../../core/diagnostik/log_cincin.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/offline/pengurai.dart';
import '../../../../core/storage/secure_storage.dart';
import '../../../demo/data/masa_coba_service.dart';
import '../../../demo/demo_session.dart';
import '../../../demo/domain/masa_coba.dart';
import '../../domain/entities/user.dart';
import '../providers/auth_providers.dart';

/// Pesan untuk layar masuk (mis. "Sesi Anda berakhir…") — dihapus setelah
/// berhasil masuk.
final pesanMasukProvider = StateProvider<String?>((_) => null);

/// State autentikasi sesi: `AsyncData(user)` = masuk, `AsyncData(null)` = keluar,
/// `AsyncLoading` = proses, `AsyncError` = gagal (pesan ditampilkan layar).
class AuthController extends AsyncNotifier<User?> {
  static const pesanSesiBerakhir = 'Sesi Anda telah berakhir. Silakan masuk kembali.';

  @override
  Future<User?> build() async {
    // Auto-login: bila token tersimpan & valid, langsung masuk.
    final result = await ref.read(authRepositoryProvider).currentUser();
    final user = result.when(ok: (user) => user, err: (_) => null);
    if (user != null) {
      await _setelahMasuk(user, lanjutkanSesi: true);
    } else {
      _tandaiAkun(null);
    }
    return user;
  }

  void _tandaiAkun(String? id) {
    try {
      ref.read(akunAktifProvider.notifier).state = id;
    } catch (_) {
      // Wadah provider sudah dibuang (mis. uji selesai lebih dulu).
    }
  }

  /// Setelah akun dikenali (masuk / masuk otomatis):
  /// - catat akun aktif (pemilik antrean baru, saringan pengurai);
  /// - baris antrean versi lama tanpa pemilik diklaim HANYA bila akun ini sama
  ///   dengan akun terakhir di perangkat (atau belum pernah tercatat);
  /// - akun BERBEDA dari akun terakhir → salinan offline akun sebelumnya
  ///   dihapus agar datanya tidak tampil untuk akun ini.
  Future<void> _setelahMasuk(User user, {bool lanjutkanSesi = false}) async {
    // Mode Demo tidak punya akun server: antreannya dijawab mesin demo di
    // perangkat, jadi tanpa pemilik (null) — tidak ada yang disaring.
    final demo = ref.read(demoSessionProvider).active;
    _tandaiAkun(demo || user.id.isEmpty ? null : user.id);
    // Kunci langganan (402) milik sesi/akun sebelumnya tidak boleh terbawa;
    // bila masih berlaku, penulisan berikutnya menjawab 402 lagi.
    if (!lanjutkanSesi) _lepasKunciLangganan();
    if (demo || user.id.isEmpty) return;
    final storage = ref.read(secureStorageProvider);
    try {
      final terakhir = await storage.readAkunTerakhir();
      if (terakhir == null || terakhir == user.id) {
        await ref.read(antreanStoreProvider).klaimTanpaPemilik(user.id);
      } else if (!lanjutkanSesi) {
        LogCincin.global.catat('Akun berganti di perangkat ini; salinan offline akun sebelumnya dihapus.');
        await ref.read(salinanStoreProvider).hapusSemua();
      }
      if (terakhir != user.id) await storage.writeAkunTerakhir(user.id);
    } catch (_) {
      // Penyimpanan bermasalah tidak boleh menghalangi masuk.
    }
  }

  void _lepasKunciLangganan() {
    try {
      ref.read(langgananTerkunciProvider.notifier).state = null;
    } catch (_) {}
  }

  /// Token ditolak server (401): bersihkan sesi dari Keystore dan kembali ke
  /// layar masuk dengan pesan. Antrean offline TIDAK dihapus — dikirim lagi
  /// setelah akun yang sama masuk; akun lain tidak akan mengirimnya.
  Future<void> sesiBerakhir() async {
    if (ref.read(demoSessionProvider).active) return; // demo tak pernah 401
    LogCincin.global.catat('Sesi berakhir (401) — kembali ke layar masuk.', tingkat: 'W');
    ref.read(pesanMasukProvider.notifier).state = pesanSesiBerakhir;
    try {
      await ref.read(secureStorageProvider).clearSession();
    } catch (_) {}
    ref.read(akunAktifProvider.notifier).state = null;
    _lepasKunciLangganan();
    state = const AsyncData(null);
  }

  Future<void> login({
    required String login,
    required String password,
    required String deviceName,
  }) async {
    state = const AsyncLoading();
    final result = await ref.read(loginUseCaseProvider).call(
          login: login,
          password: password,
          deviceName: deviceName,
        );
    final user = result.valueOrNull;
    if (user != null) {
      await _setelahMasuk(user);
      ref.read(pesanMasukProvider.notifier).state = null;
      ref.read(sessionExpiredProvider.notifier).state = false;
    }
    state = result.when(
      ok: (user) => AsyncData(user),
      err: (e) => AsyncError(e, StackTrace.current),
    );
  }

  /// Masuk Mode Demo — tanpa akun, tanpa jaringan. Mesin demo menjawab semua
  /// permintaan API di perangkat ini; token demo disimpan agar alur yang
  /// memeriksa token (mis. auto-login & interceptor toko) tetap berjalan.
  Future<void> startDemo() async {
    state = const AsyncLoading();
    // Masa coba 7 hari (waktu server). Berakhir/rusak → layar kunci;
    // belum pernah mulai tanpa koneksi → pesan di layar masuk.
    final masaCoba = await ref
        .read(masaCobaServiceProvider)
        .periksa(mulaiBaru: true);
    if (!masaCoba.aktif) {
      state = AsyncError(MasaCobaException(masaCoba), StackTrace.current);
      return;
    }
    ref.read(demoSessionProvider).start();
    final storage = ref.read(secureStorageProvider);
    await storage.writeToken('demo-token');
    await storage.writeActiveTokoId(null); // mulai dari pemilihan toko
    final result = await ref.read(authRepositoryProvider).currentUser();
    final user = result.valueOrNull;
    if (user != null) await _setelahMasuk(user);
    state = result.when(
      ok: (user) => AsyncData(user),
      err: (e) => AsyncError(e, StackTrace.current),
    );
  }

  bool get isDemo => ref.read(demoSessionProvider).active;

  /// Jeda minimum antar-muat identitas saat aplikasi kembali ke depan.
  static const jedaIdentitas = Duration(seconds: 60);

  /// Jeda TERSENDIRI untuk [segarkanIdentitas] dengan `paksa` (sesudah 403).
  /// Layar yang polling — papan pesanan 4 dtk, meja 5 dtk, stok 10 dtk — kena
  /// 403 setiap putaran bila haknya dicabut, dan tanpa jeda ini setiap
  /// penolakan memanggil `/auth/me` lagi. Lebih panjang dari polling tercepat,
  /// tetapi jauh lebih pendek dari [jedaIdentitas]: 403 PERTAMA harus langsung
  /// menyegarkan.
  static const jedaIdentitasPaksa = Duration(seconds: 30);

  DateTime? _identitasTerakhir;
  DateTime? _identitasPaksaTerakhir;
  bool _identitasBerjalan = false;

  bool _perluMuatIdentitas({required bool paksa, required DateTime kini}) {
    final terakhir = paksa ? _identitasPaksaTerakhir : _identitasTerakhir;
    if (terakhir == null) return true; // jalur ini belum pernah dipakai
    return kini.difference(terakhir) >= (paksa ? jedaIdentitasPaksa : jedaIdentitas);
  }

  /// Muat ulang identitas dari `/auth/me` (hak akses, peran, nama). Dipanggil
  /// tiap aplikasi kembali ke depan — dengan jeda agar berpindah aplikasi
  /// bolak-balik tak membanjiri server — dan dengan [paksa] sesudah 403 (hak
  /// mungkin baru saja dicabut atau ditambah pemilik).
  ///
  /// Gagal (jaringan/gangguan) sengaja diabaikan: identitas lama tetap dipakai
  /// dan sesi TIDAK dibersihkan — amplop kosong bukan bukti hak dicabut, dan
  /// server tetap penentu lewat 403. Token yang benar-benar mati menjawab 401
  /// dan ditangani `SesiBerakhirGate`.
  ///
  /// Mengembalikan true bila daftar hak BERUBAH: pemanggil (`IdentitasGate`)
  /// memuat ulang manifest sebelum menilai menu, karena server menyaring menu
  /// per hak akses sedangkan `manifest_version` tidak bergerak.
  Future<bool> segarkanIdentitas({bool paksa = false, DateTime? sekarang}) async {
    // Potret SEBELUM menunggu jawaban; dibandingkan lagi sesudahnya.
    final sebelum = state.valueOrNull;
    // Sedang berjalan → jangan menumpuk: 403 beruntun dari beberapa layar
    // sekaligus cukup menghasilkan satu panggilan (sekaligus penjaga rekursi).
    if (sebelum == null || isDemo || _identitasBerjalan) return false;
    final kini = sekarang ?? DateTime.now();
    if (!_perluMuatIdentitas(paksa: paksa, kini: kini)) return false;
    _identitasBerjalan = true;
    if (paksa) _identitasPaksaTerakhir = kini;
    try {
      final hasil = await ref.read(authRepositoryProvider).currentUser();
      // Distempel juga saat gagal: perangkat tanpa sinyal tak perlu mencoba
      // lagi setiap kembali ke depan.
      _identitasTerakhir = kini;
      final user = hasil.valueOrNull;
      if (user == null) return false;
      // Pengguna keluar akun / sesi berakhir selagi jawaban ditunggu → jangan
      // menghidupkan identitas lama lagi.
      if (!identical(state.valueOrNull, sebelum)) return false;
      state = AsyncData(user);
      return kunciAkses(sebelum.akses) != kunciAkses(user.akses);
    } finally {
      _identitasBerjalan = false;
    }
  }

  Future<void> logout() async {
    ref.read(demoSessionProvider).stop();
    await ref.read(authRepositoryProvider).logout();
    // Salinan offline milik akun ini — jangan tersisa untuk akun berikutnya.
    try {
      await ref.read(salinanStoreProvider).hapusSemua();
    } catch (_) {
      // Penyimpanan salinan bermasalah tidak boleh menghalangi keluar.
    }
    ref.read(akunAktifProvider.notifier).state = null;
    _lepasKunciLangganan();
    state = const AsyncData(null);
  }
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, User?>(AuthController.new);
