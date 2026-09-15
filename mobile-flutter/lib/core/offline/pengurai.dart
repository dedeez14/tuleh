import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../diagnostik/log_cincin.dart';
import '../network/api_client.dart';
import '../network/api_error_mapper.dart';
import '../network/api_exception.dart';
import 'antrean.dart';
import 'koneksi.dart';
import 'pemulih_tinjau.dart';
import 'rujukan_lokal.dart';
import 'sinkron_latar.dart' show KunciPengurai;

/// Penyiap badan per jenis pesan, dijalankan tepat sebelum kirim (fase 3):
/// mis. SESI_BUKA mengisi `gudang_id` yang belum sempat diambil saat offline.
/// Boleh melempar [DioException] (diperlakukan seperti gagal jaringan).
typedef PenyiapBadan =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> body);

/// Pengurai antrean kirim: mengirim pesan `outbox` sesuai urutan dibuat.
///
/// Keputusan per jawaban (rancangan "Tuléh Offline-First" + kontrak kesiapan
/// produksi 2026-09-15, sama dengan desktop):
/// - 2xx + success:true → TERKIRIM; transaksi lokal & delta stok dihapus.
/// - JARINGAN putus / timeout → baris mundur (5s, 15s, 45s, 2m, maks 10m),
///   putaran BERHENTI (server tak terjangkau — yang lain pun akan gagal), dan
///   koneksi ditandai offline. Selama offline antrean berjalan FIFO ketat.
/// - GANGGUAN SERVER per baris — 5xx (termasuk 502/503/504), 408, 429 → baris
///   itu saja yang mundur (menghormati `Retry-After`), pengurai LANJUT ke baris
///   lain yang layak (tanpa head-of-line blocking; aman karena server
///   mengenali `client_ref`). Setelah batas dari server
///   (`antrean_maks_percobaan_galat_server` / `antrean_maks_umur_jam` di
///   `/config`) baris pindah ke TINJAU dengan pesan server terakhir; tanpa
///   batas dari server baris tidak pernah dipindah sendiri.
/// - 401 (sesi berakhir), 402 (langganan berakhir), 426 (wajib perbarui) →
///   berhenti TANPA menjadwalkan ulang; baris tetap MENUNGGU dan dilanjutkan
///   setelah pengguna masuk lagi / memperpanjang / memperbarui aplikasi.
/// - 4xx lain (409 sesi/cakupan, 422 validasi, …) → TINJAU dengan pesan server.
/// - Ketergantungan tetap dijaga walau tanpa FIFO ketat: baris yang merujuk
///   `lokal:<ref>` menunggu induknya terkirim (induk ditolak → TINJAU), dan
///   SESI_BUKA yang belum terkirim menahan baris toko yang sama di belakangnya.
/// - Baris milik akun lain (lihat [PesanAntrean.pemilik]) dilewati.
class PenguraiAntrean {
  PenguraiAntrean({
    required this.store,
    required this.dio,
    required this.koneksi,
    this.setelahBerubah,
    this.penyiap = const {},
    this.kunci,
    this.pemulihDiberikan,
    this.tanpaPemulih = false,
    this.pemilik,
    this.batas,
    DateTime Function()? sekarang,
  }) : _sekarang = sekarang ?? DateTime.now;

  /// Akun pemilik token yang dipakai [dio]; hanya baris dengan
  /// [PesanAntrean.pemilik] yang SAMA yang dikirim. null callback = tanpa
  /// saringan (uji). Akun null = belum ada akun tercatat → hanya baris versi
  /// lama tanpa pemilik (perilaku sebelum penanda pemilik ada).
  final String? Function()? pemilik;

  /// Kebijakan batas dari server (`/config`); null / gagal = tanpa batas.
  final Future<BatasAntrean?> Function()? batas;

  /// Kunci bersama dengan isolate latar (WorkManager); null di test.
  final KunciPengurai? kunci;

  /// Pemulih baris TINJAU "mungkin sudah sampai" (dicocokkan ke daftar
  /// transaksi server); dijalankan setelah putaran kirim yang tidak gagal
  /// jaringan. Default dibuat dari [dio]; null = tidak ada pemulihan.
  PemulihTinjau? get pemulih => pemulihDiberikan ?? (_pemulihDefault ??= PemulihTinjau(store: store, dio: dio));
  final PemulihTinjau? pemulihDiberikan;
  PemulihTinjau? _pemulihDefault;

  /// true = lewati pemulihan (test pengurai murni).
  final bool tanpaPemulih;

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

  /// Jeda sebelum mencoba lagi: mundur eksponensial, atau `Retry-After` dari
  /// server bila lebih lama.
  static Duration jedaCobaLagi(int percobaan, Duration? retryAfter) {
    final m = mundur(percobaan);
    return retryAfter != null && retryAfter > m ? retryAfter : m;
  }

  /// Baris yang boleh dikirim dengan token saat ini.
  bool Function(PesanAntrean) _saringPemilik() {
    final ambil = pemilik;
    if (ambil == null) return (_) => true;
    final akun = ambil();
    return (p) => p.pemilik == akun;
  }

  /// Pesan yang siap diproses: MENUNGGU, dan MENGIRIM yang tertinggal karena
  /// aplikasi mati di tengah pengiriman (tanpa ini baris itu tersangkut
  /// selamanya; kiriman ulang aman berkat `client_ref`).
  static bool _antre(PesanAntrean p) =>
      p.status == StatusAntrean.menunggu || p.status == StatusAntrean.mengirim;

  Future<BatasAntrean> _ambilBatas() async {
    try {
      return await batas?.call() ?? BatasAntrean.tanpaBatas;
    } catch (_) {
      return BatasAntrean.tanpaBatas;
    }
  }

  /// Kirim semua pesan yang siap. Aman dipanggil berulang (dikunci).
  /// Mengembalikan jumlah pesan yang berhasil terkirim.
  Future<int> jalankan() async {
    if (_berjalan) return 0;
    final saring = _saringPemilik();
    _berjalan = true;
    var sukses = 0;
    await kunci?.kunci();
    try {
      // Kebijakan batas hanya diambil bila ada gangguan server (sekali per
      // putaran) — jalur normal tidak menambah permintaan.
      Future<BatasAntrean>? batasPutaran;
      Future<BatasAntrean> aturan() => batasPutaran ??= _ambilBatas();
      var hasil = await _putaran(saring, aturan);
      sukses += hasil.terkirim;
      // Baris "mungkin sudah sampai": pastikan ke server, lalu (bila ternyata
      // belum tercatat) kirim ulang di putaran ini juga.
      if (hasil.akhir == _Hasil.lanjut && !tanpaPemulih && pemulih != null) {
        final dipulihkan = await pemulih!.jalankan();
        if (dipulihkan > 0) {
          setelahBerubah?.call();
          hasil = await _putaran(saring, aturan);
          sukses += hasil.terkirim;
        }
      }
      // Sesi/langganan/versi ditolak: jangan memukul server tiap detik.
      // Dilanjutkan oleh pemicu berikutnya (masuk lagi, kembali ke depan,
      // koneksi pulih, "Sinkron sekarang").
      if (hasil.akhir == _Hasil.henti) {
        _jadwal?.cancel();
      } else {
        await _jadwalkanUlang(saring);
      }
    } finally {
      _berjalan = false;
      await kunci?.buka();
    }
    return sukses;
  }

  /// Satu putaran atas baris yang layak, urut dibuat.
  Future<({int terkirim, _Hasil akhir})> _putaran(
    bool Function(PesanAntrean) saring,
    Future<BatasAntrean> Function() aturan,
  ) async {
    final kini = _sekarang();
    // Offline diketahui = server tak terjangkau → FIFO ketat (baris dalam
    // jeda menahan yang di belakangnya); selain itu tiap baris berjeda sendiri.
    final ketat = koneksi?.offline ?? false;
    final baris = (await store.semua()).where(_antre).where(saring).toList();
    final tokoSesiTertunda = <String?>{};
    var terkirim = 0;
    for (final p in baris) {
      if (tokoSesiTertunda.contains(p.tokoId)) continue; // sesi toko ini belum terbuka di server
      final dalamJeda = p.cobaLagiSetelah != null && p.cobaLagiSetelah!.isAfter(kini);
      if (dalamJeda) {
        if (ketat) break;
        if (p.jenis == 'SESI_BUKA') tokoSesiTertunda.add(p.tokoId);
        continue;
      }
      final hasil = await _kirim(p, aturan);
      switch (hasil) {
        case _Hasil.terkirim:
          terkirim++;
        case _Hasil.gangguanServer || _Hasil.lewati:
          if (p.jenis == 'SESI_BUKA') tokoSesiTertunda.add(p.tokoId);
        case _Hasil.berhenti || _Hasil.henti:
          return (terkirim: terkirim, akhir: hasil);
        case _Hasil.lanjut:
          break;
      }
    }
    return (terkirim: terkirim, akhir: _Hasil.lanjut);
  }

  Future<_Hasil> _kirim(PesanAntrean p, Future<BatasAntrean> Function() aturan) async {
    // Rujukan lokal di path → id server dari hasil induk (harus sudah TERKIRIM).
    var path = p.path;
    final refInduk = rujukanDalamPath(path);
    if (refInduk != null) {
      final induk = await store.cari(refInduk);
      // Induk masih antre (mis. sedang mundur karena gangguan server) → tunggu
      // tanpa mengubah apa pun; bukan alasan untuk ditinjau manusia.
      if (induk != null && _antre(induk)) return _Hasil.lewati;
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
      // Sejak server MOVERA mengenal `client_ref` (9 Sep 2026), kiriman ulang
      // dengan ref yang sama TIDAK membuat baris baru — jawabannya yang sama
      // diulang. Jadi timeout "mungkin sudah sampai" cukup dikirim ulang.
      final jawaban = e.response;
      if (e.type == DioExceptionType.badResponse && jawaban != null) {
        res = jawaban; // Dio ber-validateStatus ketat: klasifikasikan dari status
      } else {
        return _gagalJaringan(p);
      }
    }

    final code = res.statusCode ?? 0;
    final body = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : const <String, dynamic>{};
    if (code >= 200 && code < 300 && body['success'] == true) {
      final data = body['data'] is Map ? Map<String, dynamic>.from(body['data'] as Map) : <String, dynamic>{};
      // 200 + meta.idempoten = server mengulang jawaban lama: baris ini sudah
      // tercatat pada percobaan sebelumnya, bukan penjualan kedua.
      final meta = body['meta'] is Map ? Map<String, dynamic>.from(body['meta'] as Map) : const {};
      if (meta['idempoten'] == true) data['_idempoten'] = true;
      await store.selesai(p.clientRef, hasil: data);
      koneksi?.tandaiOnline();
      setelahBerubah?.call();
      return _Hasil.terkirim;
    }
    if (code > 0 && statusGangguan(code)) {
      return _gangguanServer(p, body, code, ApiErrorMapper.retryAfter(res.headers), await aturan());
    }
    if (code == 0) return _gagalJaringan(p);
    if (code == 401 || code == 402 || code == 426) {
      final pesan = switch (code) {
        401 => 'Sesi berakhir — dikirim setelah Anda masuk kembali dengan akun yang sama.',
        426 => 'Aplikasi perlu diperbarui — dikirim setelah pembaruan dipasang.',
        // 402: kalimat server untuk manusia (errors berisi kode mesin BERAKHIR).
        _ => _pesanServer(body, code, bawaan: ApiErrorMapper.statusMessage(code), utamakanPesan: true),
      };
      await store.perbarui(p.clientRef, status: StatusAntrean.menunggu, galatTerakhir: pesan);
      LogCincin.global.catat('Antrean ${p.jenis} ${p.clientRef}: berhenti HTTP $code');
      setelahBerubah?.call();
      return _Hasil.henti;
    }
    // Ditolak server (409 sesi/cakupan, 422 validasi, …) → tinjau manusia.
    LogCincin.global.catat('Antrean ${p.jenis} ${p.clientRef}: ditolak HTTP $code');
    await store.perbarui(
      p.clientRef,
      status: StatusAntrean.tinjau,
      galatTerakhir: _pesanServer(body, code),
    );
    setelahBerubah?.call();
    return _Hasil.lanjut;
  }

  /// Server tak terjangkau: baris mundur, koneksi offline, putaran berhenti.
  Future<_Hasil> _gagalJaringan(PesanAntrean p) async {
    final percobaan = p.percobaan + 1;
    await store.perbarui(
      p.clientRef,
      status: StatusAntrean.menunggu,
      percobaan: percobaan,
      cobaLagiSetelah: _sekarang().add(mundur(percobaan)),
      galatTerakhir: 'Tidak dapat terhubung ke server.',
    );
    LogCincin.global.catat('Antrean ${p.jenis} ${p.clientRef}: jaringan gagal, percobaan $percobaan');
    koneksi?.tandaiOffline();
    setelahBerubah?.call();
    return _Hasil.berhenti;
  }

  /// Gangguan server untuk baris ini (5xx/408/429): mundur sendiri lalu lanjut
  /// ke baris lain; lewat batas dari server → TINJAU dengan pesan terakhir.
  Future<_Hasil> _gangguanServer(
    PesanAntrean p,
    Map<String, dynamic> body,
    int code,
    Duration? retryAfter,
    BatasAntrean aturan,
  ) async {
    final percobaan = p.percobaan + 1;
    final galatServer = p.galatServer + 1;
    final pesanServer = _pesanServer(body, code, bawaan: ApiErrorMapper.statusMessage(code));
    final kini = _sekarang();
    if (aturan.terlampaui(galatServer: galatServer, dibuat: p.dibuat, sekarang: kini)) {
      await store.perbarui(
        p.clientRef,
        status: StatusAntrean.tinjau,
        percobaan: percobaan,
        galatServer: galatServer,
        hapusCobaLagi: true,
        galatTerakhir: '$pesanServer (HTTP $code, $galatServer kali)',
      );
      LogCincin.global.catat('Antrean ${p.jenis} ${p.clientRef}: HTTP $code melewati batas server → TINJAU', tingkat: 'W');
      setelahBerubah?.call();
      return _Hasil.lanjut;
    }
    await store.perbarui(
      p.clientRef,
      status: StatusAntrean.menunggu,
      percobaan: percobaan,
      galatServer: galatServer,
      cobaLagiSetelah: kini.add(jedaCobaLagi(percobaan, retryAfter)),
      galatTerakhir: '$pesanServer (HTTP $code) — dikirim ulang otomatis.',
    );
    LogCincin.global.catat('Antrean ${p.jenis} ${p.clientRef}: HTTP $code, percobaan $percobaan');
    setelahBerubah?.call();
    return _Hasil.gangguanServer;
  }

  static String _pesanServer(Map<String, dynamic> body, int code, {String? bawaan, bool utamakanPesan = false}) {
    if (utamakanPesan) {
      final msg = body['message']?.toString().trim();
      if (msg != null && msg.isNotEmpty) return msg;
    }
    final errors = body['errors'];
    if (errors is Map && errors.isNotEmpty) {
      final first = errors.values.first;
      if (first is List && first.isNotEmpty) return first.first.toString();
    }
    final msg = body['message']?.toString();
    if (msg != null && msg.isNotEmpty) return msg;
    return bawaan ?? 'Ditolak server (HTTP $code).';
  }

  /// Jadwalkan putaran berikutnya pada waktu coba-lagi terdekat dari baris
  /// yang layak (aturan sama dengan [_putaran]; baris yang tertahan induk /
  /// sesi tidak memicu putaran setiap detik).
  Future<void> _jadwalkanUlang(bool Function(PesanAntrean) saring) async {
    _jadwal?.cancel();
    final kini = _sekarang();
    final ketat = koneksi?.offline ?? false;
    final semua = await store.semua();
    final status = {for (final p in semua) p.clientRef: p.status};
    final tokoSesiTertunda = <String?>{};
    DateTime? terdekat;
    for (final p in semua.where(_antre).where(saring)) {
      if (tokoSesiTertunda.contains(p.tokoId)) continue;
      final induk = rujukanDalamPath(p.path);
      final indukAntre = induk != null && (status[induk] == StatusAntrean.menunggu || status[induk] == StatusAntrean.mengirim);
      if (p.jenis == 'SESI_BUKA') tokoSesiTertunda.add(p.tokoId);
      if (indukAntre) continue; // ikut jadwal induknya
      final t = p.cobaLagiSetelah != null && p.cobaLagiSetelah!.isAfter(kini) ? p.cobaLagiSetelah! : kini;
      if (terdekat == null || t.isBefore(terdekat)) terdekat = t;
      if (ketat && p.cobaLagiSetelah != null) break;
    }
    if (terdekat == null) return;
    var jeda = terdekat.difference(kini);
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
      galatServer: 0,
      hapusCobaLagi: true,
    );
    final rujukan = rujukanLokal(clientRef);
    for (final t in await store.semua()) {
      if (t.status == StatusAntrean.tinjau &&
          t.galatTerakhir == pesanIndukBelumTerkirim &&
          t.path.contains(rujukan)) {
        await store.perbarui(t.clientRef, status: StatusAntrean.menunggu, percobaan: 0, galatServer: 0, hapusCobaLagi: true);
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

/// terkirim; lanjut (baris ini selesai diputuskan, lanjut ke berikutnya);
/// lewati (menunggu induk yang masih antre, tanpa perubahan);
/// gangguanServer (baris ini mundur sendiri, lanjut ke berikutnya);
/// berhenti (jaringan — jadwalkan ulang); henti (401/402/426 — tunggu pemicu).
enum _Hasil { terkirim, lanjut, lewati, gangguanServer, berhenti, henti }

/// Penyimpanan antrean (SQLite di perangkat; test meng-override).
final antreanStoreProvider = Provider<AntreanStore>(
  (ref) => AntreanDriftStore(ref.watch(salinanDbProvider)),
);

/// Naik setiap antrean berubah; provider ringkasan/daftar mengawasinya.
final antreanVersiProvider = StateProvider<int>((_) => 0);

/// Kebijakan batas antrean dari `GET /config` (null = tanpa batas) untuk
/// layar Sinkronisasi. Salinan baca membuatnya tetap tersedia saat offline.
final batasAntreanProvider = FutureProvider<BatasAntrean?>((ref) async {
  ref.watch(akunAktifProvider);
  ref.watch(antreanVersiProvider);
  return ambilBatasAntrean(ref.watch(dioProvider));
});

/// `GET /config` → [BatasAntrean]; gagal apa pun → null (tanpa batas).
Future<BatasAntrean?> ambilBatasAntrean(Dio dio) async {
  try {
    final res = await dio.get<dynamic>('/config');
    final code = res.statusCode ?? 0;
    final body = res.data;
    if (code < 200 || code >= 300 || body is! Map || body['success'] != true) return null;
    final data = body['data'];
    return BatasAntrean.dariConfig(data is Map ? Map<String, dynamic>.from(data) : null);
  } catch (_) {
    return null;
  }
}

final penguraiProvider = Provider<PenguraiAntrean>((ref) {
  final dio = ref.watch(dioProvider);
  final p = PenguraiAntrean(
    store: ref.watch(antreanStoreProvider),
    dio: dio,
    koneksi: ref.read(koneksiProvider.notifier),
    setelahBerubah: () => ref.read(antreanVersiProvider.notifier).state++,
    penyiap: {'SESI_BUKA': (body) => isiGudangId(dio, body)},
    kunci: Platform.isAndroid ? KunciPengurai() : null,
    pemilik: () => ref.read(akunAktifProvider),
    batas: () => ambilBatasAntrean(dio),
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

/// Id akun yang sedang masuk — diisi [AuthController] (masuk, masuk otomatis,
/// keluar, sesi berakhir). Menandai pemilik baris antrean baru dan menyaring
/// baris yang boleh dikirim dengan token saat ini.
final akunAktifProvider = StateProvider<String?>((_) => null);

/// Ringkasan antrean untuk pita status & layar Sinkronisasi (dari sudut
/// pandang akun yang sedang masuk; baris akun lain dihitung terpisah).
final ringkasAntreanProvider = FutureProvider<RingkasAntrean>((ref) async {
  ref.watch(antreanVersiProvider);
  final akun = ref.watch(akunAktifProvider);
  return ringkasUntuk(await ref.watch(antreanStoreProvider).semua(), akun);
});

final daftarAntreanProvider = FutureProvider<List<PesanAntrean>>((ref) {
  ref.watch(antreanVersiProvider);
  return ref.watch(antreanStoreProvider).semua();
});
