import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/api_client.dart';
import 'antrean.dart';
import 'koneksi.dart';
import 'rujukan_lokal.dart';
import 'sinkron_latar.dart' show KunciPengurai;

/// Penyiap badan per jenis pesan, dijalankan tepat sebelum kirim (fase 3):
/// mis. SESI_BUKA mengisi `gudang_id` yang belum sempat diambil saat offline.
/// Boleh melempar [DioException] (diperlakukan seperti gagal jaringan).
typedef PenyiapBadan =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> body);

/// Pengurai antrean kirim (fase 2): mengirim pesan `outbox` satu per satu
/// sesuai urutan, dengan mundur eksponensial saat jaringan gagal.
///
/// Keputusan per jawaban (lihat rancangan "Tuléh Offline-First"):
/// - 2xx + success:true → TERKIRIM; transaksi lokal & delta stok dihapus.
/// - 409/422 (ditolak server) → TINJAU dengan pesan server.
/// - gagal jaringan sebelum sampai → coba lagi setelah 5s, 15s, 45s, 2m,
///   maks 10m (status tetap MENUNGGU).
/// - timeout SETELAH terkirim (mungkin sudah diterima) → TINJAU: mengulang
///   bisa menggandakan transaksi sampai server mengenali `client_ref`.
/// - 401 → berhenti (sesi berakhir; antrean dijaga sampai masuk lagi).
/// - Fase 3: path berisi rujukan `lokal:<ref>` (bon dibuka offline) diganti
///   id server dari hasil induknya; induk yang belum terkirim → TINJAU.
class PenguraiAntrean {
  PenguraiAntrean({
    required this.store,
    required this.dio,
    required this.koneksi,
    this.setelahBerubah,
    this.penyiap = const {},
    this.kunci,
    DateTime Function()? sekarang,
  }) : _sekarang = sekarang ?? DateTime.now;

  /// Kunci bersama dengan isolate latar (WorkManager); null di test.
  final KunciPengurai? kunci;

  final AntreanStore store;
  final Dio dio;
  final PenandaKoneksi? koneksi;

  /// Penyiap badan per `jenis` (lihat [PenyiapBadan]).
  final Map<String, PenyiapBadan> penyiap;

  static const pesanIndukBelumTerkirim =
      'Menunggu bon induknya terkirim. Selesaikan baris bon tersebut dulu, '
      'lalu tekan Kirim ulang di sini.';

  /// Dipanggil setiap ada perubahan status (UI menyegarkan diri).
  final void Function()? setelahBerubah;
  final DateTime Function() _sekarang;

  bool _berjalan = false;
  Timer? _jadwal;

  static const jedaMundur = [
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 45),
    Duration(minutes: 2),
    Duration(minutes: 10),
  ];

  static Duration mundur(int percobaan) =>
      jedaMundur[percobaan.clamp(1, jedaMundur.length) - 1];

  /// Kirim semua pesan yang siap. Aman dipanggil berulang (dikunci).
  /// Mengembalikan jumlah pesan yang berhasil terkirim.
  Future<int> jalankan() async {
    if (_berjalan) return 0;
    _berjalan = true;
    var sukses = 0;
    await kunci?.kunci();
    try {
      // FIFO ketat: pesan MENUNGGU diproses sesuai urutan; bila yang paling
      // depan masih menunggu jadwal coba-lagi, yang di belakangnya ikut
      // menunggu (transaksi tidak boleh saling mendahului). TINJAU dilewati.
      final kini = _sekarang();
      final menunggu = (await store.semua())
          .where((p) => p.status == StatusAntrean.menunggu)
          .toList();
      for (final p in menunggu) {
        if (p.cobaLagiSetelah != null && p.cobaLagiSetelah!.isAfter(kini)) break;
        final lanjut = await _kirim(p);
        if (lanjut == _Hasil.terkirim) sukses++;
        if (lanjut == _Hasil.berhenti) break;
      }
      await _jadwalkanUlang();
    } finally {
      _berjalan = false;
      await kunci?.buka();
    }
    return sukses;
  }

  Future<_Hasil> _kirim(PesanAntrean p) async {
    // Rujukan lokal di path → id server dari hasil induk (harus sudah TERKIRIM).
    var path = p.path;
    final refInduk = rujukanDalamPath(path);
    if (refInduk != null) {
      final induk = await store.cari(refInduk);
      final idInduk = induk?.hasil?['id']?.toString();
      if (induk == null || induk.status != StatusAntrean.terkirim || idInduk == null || idInduk.isEmpty) {
        await store.perbarui(
          p.clientRef,
          status: StatusAntrean.tinjau,
          galatTerakhir: induk == null
              ? 'Bon induknya sudah dibatalkan; baris ini tidak bisa dikirim.'
              : pesanIndukBelumTerkirim,
        );
        setelahBerubah?.call();
        return _Hasil.lanjut;
      }
      path = path.replaceAll(rujukanLokal(refInduk), Uri.encodeComponent(idInduk));
    }

    await store.perbarui(p.clientRef, status: StatusAntrean.mengirim);
    Response<dynamic> res;
    try {
      var body = badanKirim(p.body);
      final siapkan = penyiap[p.jenis];
      if (siapkan != null) body = await siapkan(body);
      // Atas nama toko saat pesan dibuat (pencegat app melewati bila sudah ada).
      res = await dio.post<dynamic>(
        path,
        data: body,
        queryParameters: p.tokoId == null ? null : {'toko_id': p.tokoId},
      );
    } on DioException catch (e) {
      final mungkinSampai =
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout;
      if (mungkinSampai) {
        await store.perbarui(
          p.clientRef,
          status: StatusAntrean.tinjau,
          galatTerakhir:
              'Server tidak menjawab setelah data dikirim. Periksa di Riwayat '
              'apakah sudah tercatat sebelum mengirim ulang.',
        );
        setelahBerubah?.call();
        return _Hasil.lanjut;
      }
      // Belum sampai → mundur lalu coba lagi; hentikan putaran ini.
      final percobaan = p.percobaan + 1;
      await store.perbarui(
        p.clientRef,
        status: StatusAntrean.menunggu,
        percobaan: percobaan,
        cobaLagiSetelah: _sekarang().add(mundur(percobaan)),
        galatTerakhir: 'Tidak dapat terhubung ke server.',
      );
      koneksi?.tandaiOffline();
      setelahBerubah?.call();
      return _Hasil.berhenti;
    }

    final code = res.statusCode ?? 0;
    final body = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : const <String, dynamic>{};
    if (code >= 200 && code < 300 && body['success'] == true) {
      final data = body['data'] is Map ? Map<String, dynamic>.from(body['data'] as Map) : <String, dynamic>{};
      await store.selesai(p.clientRef, hasil: data);
      koneksi?.tandaiOnline();
      setelahBerubah?.call();
      return _Hasil.terkirim;
    }
    if (code == 401) {
      await store.perbarui(p.clientRef, status: StatusAntrean.menunggu);
      setelahBerubah?.call();
      return _Hasil.berhenti;
    }
    // Ditolak server (409 sesi/cakupan, 422 validasi, 5xx) → tinjau manusia.
    await store.perbarui(
      p.clientRef,
      status: StatusAntrean.tinjau,
      galatTerakhir: _pesanServer(body, code),
    );
    setelahBerubah?.call();
    return _Hasil.lanjut;
  }

  static String _pesanServer(Map<String, dynamic> body, int code) {
    final errors = body['errors'];
    if (errors is Map && errors.isNotEmpty) {
      final first = errors.values.first;
      if (first is List && first.isNotEmpty) return first.first.toString();
    }
    final msg = body['message']?.toString();
    if (msg != null && msg.isNotEmpty) return msg;
    return 'Ditolak server (HTTP $code).';
  }

  /// Bila masih ada yang menunggu, jadwalkan putaran berikutnya pada waktu
  /// coba-lagi terdekat.
  Future<void> _jadwalkanUlang() async {
    _jadwal?.cancel();
    final semua = await store.semua();
    DateTime? terdekat;
    for (final p in semua) {
      if (p.status != StatusAntrean.menunggu) continue;
      final t = p.cobaLagiSetelah ?? _sekarang();
      if (terdekat == null || t.isBefore(terdekat)) terdekat = t;
    }
    if (terdekat == null) return;
    var jeda = terdekat.difference(_sekarang());
    if (jeda < const Duration(seconds: 1)) jeda = const Duration(seconds: 1);
    _jadwal = Timer(jeda, jalankan);
  }

  /// Pengguna menekan "Kirim ulang" pada pesan TINJAU. Baris turunan yang
  /// tadi TINJAU karena menunggu induk ini ikut dikembalikan ke antrean.
  Future<void> kirimUlang(String clientRef) async {
    await store.perbarui(
      clientRef,
      status: StatusAntrean.menunggu,
      percobaan: 0,
      hapusCobaLagi: true,
    );
    final rujukan = rujukanLokal(clientRef);
    for (final t in await store.semua()) {
      if (t.status == StatusAntrean.tinjau &&
          t.galatTerakhir == pesanIndukBelumTerkirim &&
          t.path.contains(rujukan)) {
        await store.perbarui(t.clientRef, status: StatusAntrean.menunggu, percobaan: 0, hapusCobaLagi: true);
      }
    }
    setelahBerubah?.call();
    await jalankan();
  }

  void hentikan() {
    _jadwal?.cancel();
    _jadwal = null;
  }
}

enum _Hasil { terkirim, lanjut, berhenti }

/// Penyimpanan antrean (SQLite di perangkat; test meng-override).
final antreanStoreProvider = Provider<AntreanStore>(
  (ref) => AntreanDriftStore(ref.watch(salinanDbProvider)),
);

/// Naik setiap antrean berubah; provider ringkasan/daftar mengawasinya.
final antreanVersiProvider = StateProvider<int>((_) => 0);

final penguraiProvider = Provider<PenguraiAntrean>((ref) {
  final dio = ref.watch(dioProvider);
  final p = PenguraiAntrean(
    store: ref.watch(antreanStoreProvider),
    dio: dio,
    koneksi: ref.read(koneksiProvider.notifier),
    setelahBerubah: () => ref.read(antreanVersiProvider.notifier).state++,
    penyiap: {'SESI_BUKA': (body) => isiGudangId(dio, body)},
    kunci: Platform.isAndroid ? KunciPengurai() : null,
  );
  ref.onDispose(p.hentikan);
  return p;
});

/// SESI_BUKA yang diantrekan saat `/gudang` belum pernah tersalin: ambil id
/// gudang pertama tepat sebelum kirim. Gagal jaringan dilempar apa adanya.
Future<Map<String, dynamic>> isiGudangId(Dio dio, Map<String, dynamic> body) async {
  final ada = body['gudang_id']?.toString() ?? '';
  if (ada.isNotEmpty) return body;
  final res = await dio.get<dynamic>('/gudang');
  final data = res.data is Map ? (res.data as Map)['data'] : null;
  final rows = data is List ? data : (data is Map && data['rows'] is List ? data['rows'] as List : const []);
  for (final e in rows) {
    if (e is Map && e['id'] != null) return {...body, 'gudang_id': e['id'].toString()};
  }
  return body; // biar server yang menjawab (422) → TINJAU dengan pesannya
}

/// Ringkasan antrean untuk pita status & layar Sinkronisasi.
final ringkasAntreanProvider = FutureProvider<RingkasAntrean>((ref) {
  ref.watch(antreanVersiProvider);
  return ref.watch(antreanStoreProvider).ringkas();
});

final daftarAntreanProvider = FutureProvider<List<PesanAntrean>>((ref) {
  ref.watch(antreanVersiProvider);
  return ref.watch(antreanStoreProvider).semua();
});
