import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../diagnostik/log_cincin.dart';
import '../network/api_client.dart';
import '../network/api_error_mapper.dart';
import '../network/api_exception.dart';
import 'antrean.dart';
import 'koneksi.dart';
import 'operasi_batch.dart';
import 'pemulih_tinjau.dart';
import 'rujukan_lokal.dart';
import 'sinkron_latar.dart' show KunciPengurai;

/// Penyiap badan per jenis pesan, dijalankan tepat sebelum kirim (fase 3):
/// mis. SESI_BUKA mengisi `gudang_id` yang belum sempat diambil saat offline.
/// Boleh melempar [DioException] (diperlakukan seperti gagal jaringan).
typedef PenyiapBadan =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> body);

/// Satu baris di segmen batch beserta operasinya.
typedef _BarisSegmen = ({PesanAntrean p, Map<String, dynamic> op});

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
///
/// Mode BATCH v2 (Fase 4; aktif bila `GET /config` `sync_batch.versi ≥ 2`,
/// [konfigBatch] & [idPerangkat] disuntik): baris berjenis [jenisBatch]
/// dikumpulkan ke SEGMEN BERURUTAN (≤25 op, ≤1,5 MB) dan dikirim satu
/// `POST /sync/v2/batch`; baris jenis lain memotong segmen dan dikirim per
/// baris di posisinya. Hasil dipetakan per `client_ref` (= idempotency_key):
///   OK → TERKIRIM (hasil: id, nomor, kode, peringatan, data);
///   retriable:false → TINJAU `[KODE] pesan`;
///   DITUNDA → dikirim lagi ±3 dtk tanpa menaikkan percobaan;
///   GALAT_SERVER / hasil hilang → mundur galat server (batas `/config`);
///   LANGGANAN → henti seperti 402;
///   retriable:true lain (PRASYARAT, SESI_TIDAK_ADA, SESI_BEDA_TOKO, kode baru)
///   → jeda panjang 1–60 menit, umur lewat batas `/config` → TINJAU.
/// Jawaban batch non-200: 401/402/426 henti; jaringan putus & 429 tanpa kode
/// → jeda jaringan, berhenti; timeout setelah terkirim → mundur per baris
/// tanpa menandai offline (paritas desktop TIMEOUT); 404 atau 503
/// BATCH_TIDAK_TERSEDIA (dan 200 tanpa `data.versi = 2`) → per baris sampai
/// `/config` berikutnya; 409 BATCH_REF_BENTROK → ref bergaram sekali; 413 →
/// segmen dibelah; 429 BATCH_BERJALAN → tunda 3 dtk; 5xx/408/422/4xx lain →
/// mundur per baris sebagai galat server.
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
    this.konfigBatch,
    this.idPerangkat,
    DateTime Function()? sekarang,
  }) : _sekarang = sekarang ?? DateTime.now;

  /// Akun pemilik token yang dipakai [dio]; hanya baris dengan
  /// [PesanAntrean.pemilik] yang SAMA yang dikirim. null callback = tanpa
  /// saringan (uji). Akun null = belum ada akun tercatat → hanya baris versi
  /// lama tanpa pemilik (perilaku sebelum penanda pemilik ada).
  final String? Function()? pemilik;

  /// Kebijakan batas dari server (`/config`); null / gagal = tanpa batas.
  final Future<BatasAntrean?> Function()? batas;

  /// Blok `sync_batch` dari `GET /config` (Fase 4). null = hanya kiriman per
  /// baris (uji lama). Jawaban null (gagal baca) tidak dimemo.
  final Future<KonfigSyncBatch?> Function()? konfigBatch;

  /// `device_id` batch (secure storage `tuleh_perangkat_sinkron`). null / gagal
  /// = hanya kiriman per baris.
  final Future<String> Function()? idPerangkat;

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

  /// Konfigurasi batch terakhir yang terbaca & kapan; `_batchMati` = server
  /// menjawab 404/503/v1 → per baris sampai `/config` dibaca ulang.
  KonfigSyncBatch? _konfig;
  DateTime? _konfigPada;
  bool _batchMati = false;

  /// Batas operasi per segmen setelah 413 (pulih ×2 tiap segmen sukses).
  int _batasOpAdaptif = batasOpSegmen;

  static const jedaMundur = [
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 45),
    Duration(minutes: 2),
    Duration(minutes: 10),
  ];

  static Duration mundur(int percobaan) =>
      jedaMundur[percobaan.clamp(1, jedaMundur.length) - 1];

  /// Jeda item batch yang BELUM bisa dijalankan (menunggu sesi dibuka /
  /// transaksi asal tercatat): bukan galat server, tak dihitung ke batas galat.
  static const jedaLama = [
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 15),
    Duration(minutes: 30),
    Duration(minutes: 60),
  ];

  static Duration mundurLama(int percobaan) =>
      jedaLama[percobaan.clamp(1, jedaLama.length) - 1];

  /// DITUNDA / BATCH_BERJALAN: dikirim lagi sebentar lagi tanpa menaikkan
  /// percobaan, tetapi tidak "segera" — server yang padat tak dihantam ulang.
  static const jedaTunda = Duration(seconds: 3);

  /// Umur memo `sync_batch` dari `/config`.
  static const umurKonfig = Duration(minutes: 5);

  /// Batas tunggu jawaban `POST /sync/v2/batch` (server berhenti mengambil
  /// item baru di ±20 dtk; sisanya DITUNDA).
  static const batasTungguBatch = Duration(seconds: 60);

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

  /// Satu putaran: mode batch bila server mendukungnya dan ada baris
  /// berjenis batch; server yang ternyata tak mendukung (404/503/v1) →
  /// lanjut per baris di putaran yang sama.
  Future<({int terkirim, _Hasil akhir})> _putaran(
    bool Function(PesanAntrean) saring,
    Future<BatasAntrean> Function() aturan,
  ) async {
    final adaBatch = (await store.semua()).where(_antre).where(saring).any((p) => jenisBatch.containsKey(p.jenis));
    if (adaBatch) {
      final konfig = await _konfigAktif();
      final deviceId = konfig == null ? null : await _deviceId();
      if (konfig != null && deviceId != null) {
        final b = await _putaranBatch(saring, aturan, konfig, deviceId);
        if (b.akhir != _Hasil.perBaris) return b;
        final lanjut = await _putaranPerBaris(saring, aturan);
        return (terkirim: b.terkirim + lanjut.terkirim, akhir: lanjut.akhir);
      }
    }
    return _putaranPerBaris(saring, aturan);
  }

  /// `sync_batch` aktif untuk putaran ini (memo [umurKonfig]); null = per baris.
  Future<KonfigSyncBatch?> _konfigAktif() async {
    final ambil = konfigBatch;
    if (ambil == null || idPerangkat == null) return null;
    final kini = _sekarang();
    final pada = _konfigPada;
    if (pada == null || kini.isBefore(pada) || kini.difference(pada) >= umurKonfig) {
      KonfigSyncBatch? k;
      try {
        k = await ambil();
      } catch (_) {
        k = null;
      }
      // Gagal baca (offline, 5xx) tidak dimemo: salinan lama tetap dipakai.
      if (k != null) {
        _konfig = k;
        _konfigPada = kini;
        _batchMati = false;
      }
    }
    final k = _konfig;
    return k != null && k.aktif && !_batchMati ? k : null;
  }

  Future<String?> _deviceId() async {
    try {
      final id = await idPerangkat!();
      return id.isEmpty ? null : id;
    } catch (_) {
      return null;
    }
  }

  /// Satu putaran per baris atas baris yang layak, urut dibuat.
  Future<({int terkirim, _Hasil akhir})> _putaranPerBaris(
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
        case _Hasil.lanjut || _Hasil.perBaris:
          break;
      }
    }
    return (terkirim: terkirim, akhir: _Hasil.lanjut);
  }

  /// Satu putaran mode batch: segmen berurutan, baris non-batch di posisinya.
  Future<({int terkirim, _Hasil akhir})> _putaranBatch(
    bool Function(PesanAntrean) saring,
    Future<BatasAntrean> Function() aturan,
    KonfigSyncBatch konfig,
    String deviceId,
  ) async {
    final kini = _sekarang();
    final ketat = koneksi?.offline ?? false;
    final baris = (await store.semua()).where(_antre).where(saring).toList();
    final batasByte = konfig.batasByte;
    final tokoSesiTertunda = <String?>{};
    var segmen = <_BarisSegmen>[];
    var ukuran = 0;
    var terkirim = 0;

    Future<_Hasil> kirimSegmen() async {
      if (segmen.isEmpty) return _Hasil.lanjut;
      final isi = segmen;
      segmen = <_BarisSegmen>[];
      ukuran = 0;
      final r = await _kirimSegmen(isi, deviceId, aturan);
      terkirim += r.terkirim;
      // Detak kunci bersama: putaran berisi beberapa segmen × 60 dtk tidak
      // boleh membuat isolate latar menganggap kunci basi (3 menit).
      await kunci?.kunci();
      return r.akhir;
    }

    for (final awal in baris) {
      // Status terkini: segmen sebelumnya bisa sudah memutuskan baris ini.
      final p = await store.cari(awal.clientRef);
      if (p == null || !_antre(p)) continue;
      if (tokoSesiTertunda.contains(p.tokoId)) continue;
      final dalamJeda = p.cobaLagiSetelah != null && p.cobaLagiSetelah!.isAfter(kini);
      if (dalamJeda) {
        if (ketat) break;
        if (p.jenis == 'SESI_BUKA') tokoSesiTertunda.add(p.tokoId);
        continue;
      }
      if (jenisBatch.containsKey(p.jenis)) {
        final jalur = await _jalurBatch(p, segmen);
        if (jalur == null) continue;
        final nomorLokal = p.jenis == 'CHECKOUT' ? (await store.transaksiLokal(p.clientRef))?.nomorLokal : null;
        var op = opDariBaris(p, deviceId: deviceId, kini: kini, path: jalur, nomorLokal: nomorLokal);
        var n = ukuranJson(op);
        if (segmen.isNotEmpty && (segmen.length >= konfig.batasOp(_batasOpAdaptif) || ukuran + n > batasByte)) {
          final h = await kirimSegmen();
          if (h != _Hasil.lanjut) return (terkirim: terkirim, akhir: h);
          // Induk yang tadi satu segmen kini sudah dijawab: nilai ulang.
          final ulang = await _jalurBatch(p, segmen);
          if (ulang == null) continue;
          op = opDariBaris(p, deviceId: deviceId, kini: kini, path: ulang, nomorLokal: nomorLokal);
          n = ukuranJson(op);
        }
        segmen.add((p: p, op: op));
        ukuran += n;
        continue;
      }
      // Jenis di luar batch: segmen sebelumnya dikirim dulu (urutan kausal).
      final h = await kirimSegmen();
      if (h != _Hasil.lanjut) return (terkirim: terkirim, akhir: h);
      final hasil = await _kirim(p, aturan);
      switch (hasil) {
        case _Hasil.terkirim:
          terkirim++;
        case _Hasil.gangguanServer || _Hasil.lewati:
          if (p.jenis == 'SESI_BUKA') tokoSesiTertunda.add(p.tokoId);
        case _Hasil.berhenti || _Hasil.henti:
          return (terkirim: terkirim, akhir: hasil);
        case _Hasil.lanjut || _Hasil.perBaris:
          break;
      }
    }
    final h = await kirimSegmen();
    return (terkirim: terkirim, akhir: h);
  }

  /// Jalur siap kirim untuk baris batch, atau null bila baris ditahan / sudah
  /// diputuskan (rujukan `lokal:` induk yang belum / tidak akan terkirim).
  /// REFUND/BATAL atas transaksi lokal merujuk `transaksi_ref` (jalur apa
  /// adanya); BILL_BAYAR atas bon lokal memakai id bon server induk.
  Future<String?> _jalurBatch(PesanAntrean p, List<_BarisSegmen> segmen) async {
    final refInduk = rujukanDalamPath(p.path);
    if (refInduk == null) return p.path;
    final induk = await store.cari(refInduk);
    if (induk != null && _antre(induk)) return null; // tunggu induk tanpa penalti
    final idInduk = induk?.hasil?['id']?.toString();
    final terkirim = induk != null && induk.status == StatusAntrean.terkirim;
    if (terkirim && (p.jenis == 'REFUND' || p.jenis == 'BATAL')) return p.path;
    if (!terkirim || idInduk == null || idInduk.isEmpty) {
      await _tinjauInduk(p, induk);
      return null;
    }
    return p.path.replaceAll(rujukanLokal(refInduk), Uri.encodeComponent(idInduk));
  }

  /// Baris yang induk lokalnya dibatalkan / ditolak.
  Future<void> _tinjauInduk(PesanAntrean p, PesanAntrean? induk) async {
    await store.perbarui(
      p.clientRef,
      status: StatusAntrean.tinjau,
      galatTerakhir: induk == null
          ? 'Bon induknya sudah dibatalkan; baris ini tidak bisa dikirim.'
          : pesanIndukBelumTerkirim,
    );
    setelahBerubah?.call();
  }

  Future<({int terkirim, _Hasil akhir})> _kirimSegmen(
    List<_BarisSegmen> isi,
    String deviceId,
    Future<BatasAntrean> Function() aturan,
  ) async {
    final baris = [for (final x in isi) x.p];
    for (final p in baris) {
      await store.perbarui(p.clientRef, status: StatusAntrean.mengirim);
    }
    Map<String, dynamic> badan(int garam) => {
      'client_ref': clientRefBatch(deviceId, baris, garam: garam),
      'device_id': deviceId,
      'operations': [for (final x in isi) x.op],
    };
    var res = await _postBatch(badan(0));
    // Ref sama dengan isi berbeda (antrean dipulihkan): ref bergaram, sekali saja.
    if (res != null && res.statusCode == 409 && _kodeAmplop(res) == 'BATCH_REF_BENTROK') {
      res = await _postBatch(badan(1));
    }
    return _olahJawabanBatch(isi, res, aturan);
  }

  /// Batas tunggu habis SETELAH permintaan batch terkirim (send/receive
  /// timeout — server mungkin sudah memproses), dibedakan dari jaringan putus.
  /// Diisi [_postBatch], dibaca [_olahJawabanBatch] (paritas desktop TIMEOUT).
  bool _batchTimeout = false;

  /// null = tidak ada jawaban HTTP (jaringan putus / timeout — lihat
  /// [_batchTimeout]). `toko_id: null` menekan toko AKTIF yang disisipkan
  /// pencegat Dio aplikasi (`api_client.dart` hanya menambah bila kuncinya
  /// belum ada): toko tiap op ada di `payload.toko_id` (kritik B-17, paritas
  /// desktop `query: {toko_id: undefined}`); server membaca `?toko_id` kosong
  /// sebagai "tidak dikirim".
  Future<Response<dynamic>?> _postBatch(Map<String, dynamic> badan) async {
    _batchTimeout = false;
    try {
      return await dio.post<dynamic>(
        jalurSyncBatch,
        data: badan,
        queryParameters: const {'toko_id': null},
        options: Options(receiveTimeout: batasTungguBatch),
      );
    } on DioException catch (e) {
      final jawaban = e.response;
      if (e.type == DioExceptionType.badResponse && jawaban != null) return jawaban;
      _batchTimeout = e.type == DioExceptionType.receiveTimeout || e.type == DioExceptionType.sendTimeout;
      return null;
    }
  }

  static Map<String, dynamic> _badanJson(Response<dynamic> res) =>
      res.data is Map ? Map<String, dynamic>.from(res.data as Map) : <String, dynamic>{};

  /// `errors.kode[0]` amplop gagal (mis. BATCH_REF_BENTROK); null bila tak ada.
  static String? _kodeAmplop(Response<dynamic> res) {
    final errors = _badanJson(res)['errors'];
    final k = errors is Map ? errors['kode'] : null;
    return k is List && k.isNotEmpty ? '${k.first}' : null;
  }

  /// Jawaban satu POST batch → status semua baris segmen.
  Future<({int terkirim, _Hasil akhir})> _olahJawabanBatch(
    List<_BarisSegmen> isi,
    Response<dynamic>? res,
    Future<BatasAntrean> Function() aturan,
  ) async {
    final baris = [for (final x in isi) x.p];
    if (res == null && _batchTimeout) {
      // Batas tunggu habis setelah data terkirim (kontrak §13.5, paritas desktop
      // TIMEOUT): server mungkin sudah memproses — tiap baris mundur sendiri
      // TANPA menandai offline & tanpa menaikkan galat server; kiriman ulang aman
      // (idempoten per op). Putaran lanjut ke baris lain yang siap.
      for (final p in baris) {
        await _timeoutBatch(p);
      }
      setelahBerubah?.call();
      return (terkirim: 0, akhir: _Hasil.lanjut);
    }
    if (res == null) {
      for (final p in baris) {
        await _gagalJaringan(p);
      }
      return (terkirim: 0, akhir: _Hasil.berhenti);
    }
    final code = res.statusCode ?? 0;
    final body = _badanJson(res);
    final kode = _kodeAmplop(res);
    if (code >= 200 && code < 300 && body['success'] == true) {
      final data = body['data'];
      if (data is! Map || data['versi'] != 2 || data['results'] is! List) {
        return _jawabanServerLama(isi, data);
      }
      return _petakanHasil(isi, data['results'] as List, aturan);
    }
    // Server belum mengenal batch v2 di koneksi ini: per baris tanpa menghukum baris.
    if (code == 404 || (code == 503 && kode == 'BATCH_TIDAK_TERSEDIA')) {
      _batchMati = true;
      for (final p in baris) {
        await store.perbarui(p.clientRef, status: StatusAntrean.menunggu);
      }
      LogCincin.global.catat('Sinkron batch HTTP $code → per baris sampai /config berikutnya', tingkat: 'W');
      setelahBerubah?.call();
      return (terkirim: 0, akhir: _Hasil.perBaris);
    }
    if (code == 429 && kode == 'BATCH_BERJALAN') {
      final nanti = _sekarang().add(jedaTunda);
      for (final p in baris) {
        await store.perbarui(
          p.clientRef,
          status: StatusAntrean.menunggu,
          cobaLagiSetelah: nanti,
          galatTerakhir: galatBerkode('BATCH_BERJALAN', 'Server masih memproses kiriman sebelumnya; dikirim lagi sebentar.'),
        );
      }
      setelahBerubah?.call();
      return (terkirim: 0, akhir: _Hasil.berhenti);
    }
    // 429 tanpa kode = batas laju (`pos_sync_batas_per_menit_*`): jeda JARINGAN
    // seperti desktop & kontrak §13.5 — semua baris segmen menunggu, putaran
    // berhenti (bukan gangguan per baris yang melanjutkan ke segmen berikutnya).
    if (code == 429) {
      for (final p in baris) {
        await _gagalJaringan(p, pesan: 'Server membatasi permintaan; dicoba lagi otomatis.');
      }
      return (terkirim: 0, akhir: _Hasil.berhenti);
    }
    if (code == 413 || kode == 'BATCH_TERLALU_BESAR') {
      if (baris.length == 1) {
        await _tinjau(
          baris.single,
          galatBerkode(
            'BATCH_TERLALU_BESAR',
            'Data ini terlalu besar untuk dikirim ke server. Batalkan lalu catat ulang '
                'dalam beberapa transaksi, atau hubungi dukungan.',
          ),
        );
      } else {
        _batasOpAdaptif = max(1, baris.length ~/ 2);
        for (final p in baris) {
          await store.perbarui(p.clientRef, status: StatusAntrean.menunggu);
        }
      }
      setelahBerubah?.call();
      return (terkirim: 0, akhir: _Hasil.lanjut);
    }
    if (code == 401 || code == 402 || code == 426) {
      final pesan = _pesanHenti(code, body);
      for (final p in baris) {
        await store.perbarui(p.clientRef, status: StatusAntrean.menunggu, galatTerakhir: pesan);
      }
      LogCincin.global.catat('Sinkron batch: berhenti HTTP $code');
      setelahBerubah?.call();
      return (terkirim: 0, akhir: _Hasil.henti);
    }
    // 5xx/408 dan 409/422/4xx lain: jawaban tidak menilai baris satu per
    // satu → mundur per baris sebagai galat server (batas /config berlaku).
    if (code == 422) {
      LogCincin.global.catat('Sinkron batch: amplop ditolak 422 — ${_pesanServer(body, code)}', tingkat: 'W');
    }
    final batasPutaran = await aturan();
    final retryAfter = ApiErrorMapper.retryAfter(res.headers);
    for (final p in baris) {
      await _gangguanServer(p, body, code, retryAfter, batasPutaran);
    }
    return (terkirim: 0, akhir: _Hasil.lanjut);
  }

  /// Hasil per item, dicocokkan lewat idempotency_key (bukan indeks).
  Future<({int terkirim, _Hasil akhir})> _petakanHasil(
    List<_BarisSegmen> isi,
    List<dynamic> results,
    Future<BatasAntrean> Function() aturan,
  ) async {
    final peta = <String, HasilItemBatch>{};
    for (final r in results) {
      final h = HasilItemBatch.dariJson(r);
      if (h != null) peta[h.idempotencyKey] = h;
    }
    final kini = _sekarang();
    var terkirim = 0;
    var langganan = false;
    for (final x in isi) {
      final p = x.p;
      final it = peta[p.clientRef];
      if (it == null) {
        await _tundaGalatServer(p, 'GALAT_SERVER', 'Server tidak mengembalikan hasil untuk data ini', await aturan());
        continue;
      }
      if (it.accepted) {
        final nomorLokal = (x.op['payload'] as Map)['nomor_lokal']?.toString();
        await store.selesai(p.clientRef, hasil: it.keHasil(nomorLokal: nomorLokal));
        terkirim++;
        continue;
      }
      switch (it.kode) {
        case 'DITUNDA':
          await store.perbarui(
            p.clientRef,
            status: StatusAntrean.menunggu,
            cobaLagiSetelah: kini.add(jedaTunda),
            galatTerakhir: galatBerkode('DITUNDA', 'Ditunda server (batas waktu kiriman); dikirim lagi sebentar.'),
          );
        case 'GALAT_SERVER':
          await _tundaGalatServer(p, it.kode, it.message, await aturan());
        case 'LANGGANAN':
          langganan = true;
          await store.perbarui(p.clientRef, status: StatusAntrean.menunggu, galatTerakhir: galatBerkode(it.kode, it.message));
        default:
          if (it.retriable) {
            await _tundaLama(p, it.kode, it.message, aturan);
          } else {
            await _tinjau(p, galatBerkode(it.kode, it.message));
          }
      }
    }
    koneksi?.tandaiOnline();
    if (terkirim > 0) _batasOpAdaptif = min(batasOpSegmen, _batasOpAdaptif * 2);
    setelahBerubah?.call();
    return (terkirim: terkirim, akhir: langganan ? _Hasil.henti : _Hasil.lanjut);
  }

  /// 200 tanpa `data.versi = 2` = server v1 menjawab (rollback / salinan
  /// `/config` basi): yang diterima dicatat, sisanya kembali ke antrean dan
  /// kiriman pindah ke per baris.
  Future<({int terkirim, _Hasil akhir})> _jawabanServerLama(List<_BarisSegmen> isi, Object? data) async {
    final results = data is Map && data['results'] is List ? data['results'] as List : const <dynamic>[];
    final peta = <String, HasilItemBatch>{};
    for (final r in results) {
      final h = HasilItemBatch.dariJson(r);
      if (h != null) peta[h.idempotencyKey] = h;
    }
    var terkirim = 0;
    for (final x in isi) {
      final it = peta[x.p.clientRef];
      if (it != null && it.accepted) {
        await store.selesai(x.p.clientRef, hasil: it.keHasil());
        terkirim++;
      } else {
        await store.perbarui(x.p.clientRef, status: StatusAntrean.menunggu);
      }
    }
    _batchMati = true;
    LogCincin.global.catat('Sinkron batch: jawaban tanpa versi 2 → per baris', tingkat: 'W');
    setelahBerubah?.call();
    return (terkirim: terkirim, akhir: _Hasil.perBaris);
  }

  /// Item belum bisa dijalankan (retriable, bukan galat server): jeda panjang
  /// bertingkat; umur baris lewat batas `/config` → TINJAU.
  Future<void> _tundaLama(PesanAntrean p, String kode, String pesan, Future<BatasAntrean> Function() aturan) async {
    final percobaan = p.percobaan + 1;
    final kini = _sekarang();
    final umurJam = (await aturan()).maksUmurJam;
    if (umurJam != null && kini.difference(p.dibuat) >= Duration(hours: umurJam)) {
      await _tinjau(p, galatBerkode(kode, '$pesan (tertunda lebih dari $umurJam jam; perlu ditinjau)'), percobaan: percobaan);
      return;
    }
    await store.perbarui(
      p.clientRef,
      status: StatusAntrean.menunggu,
      percobaan: percobaan,
      cobaLagiSetelah: kini.add(mundurLama(percobaan)),
      galatTerakhir: galatBerkode(kode, pesan),
    );
  }

  /// Galat server untuk item INI: mundur per baris; lewat batas → TINJAU.
  Future<void> _tundaGalatServer(PesanAntrean p, String kode, String pesan, BatasAntrean aturan) async {
    final percobaan = p.percobaan + 1;
    final galatServer = p.galatServer + 1;
    final kini = _sekarang();
    if (aturan.terlampaui(galatServer: galatServer, dibuat: p.dibuat, sekarang: kini)) {
      await _tinjau(p, galatBerkode(kode, '$pesan ($galatServer kali)'), percobaan: percobaan, galatServer: galatServer);
      return;
    }
    await store.perbarui(
      p.clientRef,
      status: StatusAntrean.menunggu,
      percobaan: percobaan,
      galatServer: galatServer,
      // Jeda menurut jumlah galat server baris ini (paritas desktop `mundur(galatServer)`).
      cobaLagiSetelah: kini.add(mundur(galatServer)),
      galatTerakhir: galatBerkode(kode, '$pesan — dikirim ulang otomatis.'),
    );
  }

  /// Pindahkan baris ke TINJAU dengan galat berkode.
  Future<void> _tinjau(PesanAntrean p, String galat, {int? percobaan, int? galatServer}) async {
    await store.perbarui(
      p.clientRef,
      status: StatusAntrean.tinjau,
      percobaan: percobaan,
      galatServer: galatServer,
      hapusCobaLagi: true,
      galatTerakhir: galat,
    );
    LogCincin.global.catat('Antrean ${p.jenis} ${p.clientRef}: TINJAU ${kodeGalat(galat) ?? ''}');
  }

  static String _pesanHenti(int code, Map<String, dynamic> body) => switch (code) {
    401 => 'Sesi berakhir — dikirim setelah Anda masuk kembali dengan akun yang sama.',
    426 => 'Aplikasi perlu diperbarui — dikirim setelah pembaruan dipasang.',
    // 402: kalimat server untuk manusia (errors berisi kode mesin BERAKHIR).
    _ => _pesanServer(body, code, bawaan: ApiErrorMapper.statusMessage(code), utamakanPesan: true),
  };

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
        await _tinjauInduk(p, induk);
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
      // Nomor lokal struk offline ikut hasil: layar Sinkronisasi menampilkan "L-… → POS/…".
      final nomorLokal = p.body['nomor_lokal'];
      if (nomorLokal is String && nomorLokal.isNotEmpty) data.putIfAbsent('nomor_lokal', () => nomorLokal);
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
      await store.perbarui(p.clientRef, status: StatusAntrean.menunggu, galatTerakhir: _pesanHenti(code, body));
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

  /// Server tak terjangkau (atau batas laju 429 batch — [pesan]): baris mundur,
  /// koneksi offline, putaran berhenti.
  Future<_Hasil> _gagalJaringan(PesanAntrean p, {String pesan = 'Tidak dapat terhubung ke server.'}) async {
    final percobaan = p.percobaan + 1;
    await store.perbarui(
      p.clientRef,
      status: StatusAntrean.menunggu,
      percobaan: percobaan,
      cobaLagiSetelah: _sekarang().add(mundur(percobaan)),
      galatTerakhir: pesan,
    );
    LogCincin.global.catat('Antrean ${p.jenis} ${p.clientRef}: jaringan gagal, percobaan $percobaan');
    koneksi?.tandaiOffline();
    setelahBerubah?.call();
    return _Hasil.berhenti;
  }

  /// Batas tunggu jawaban batch habis setelah terkirim: baris mundur sendiri
  /// (5s, 15s, …) tanpa menaikkan galat server dan tanpa menandai offline
  /// (paritas desktop TIMEOUT; kontrak §13.5).
  Future<void> _timeoutBatch(PesanAntrean p) async {
    final percobaan = p.percobaan + 1;
    await store.perbarui(
      p.clientRef,
      status: StatusAntrean.menunggu,
      percobaan: percobaan,
      cobaLagiSetelah: _sekarang().add(mundur(percobaan)),
      galatTerakhir: 'Server tidak menjawab tepat waktu; dicoba lagi otomatis.',
    );
    LogCincin.global.catat('Antrean ${p.jenis} ${p.clientRef}: batas tunggu batch habis, percobaan $percobaan', tingkat: 'W');
  }

  /// Gangguan server untuk baris ini (5xx/408/429 per baris): mundur sendiri lalu lanjut
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

  /// Pengguna menekan "Kirim ulang" pada pesan TINJAU. Generasi kirim ulang
  /// (`_kirim_ulang` di badan) naik sehingga `client_ref` batch berganti dan
  /// server menilai ulang — bukan memutar jawaban batch lama. Baris turunan
  /// yang tadi TINJAU karena menunggu induk ini ikut dikembalikan ke antrean.
  Future<void> kirimUlang(String clientRef) async {
    final p = await store.cari(clientRef);
    await store.perbarui(
      clientRef,
      status: StatusAntrean.menunggu,
      percobaan: 0,
      galatServer: 0,
      hapusCobaLagi: true,
      hapusGalat: true,
      body: p == null ? null : {...p.body, kunciKirimUlang: kirimUlangKe(p) + 1},
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
/// berhenti (jaringan — jadwalkan ulang); henti (401/402/426 — tunggu pemicu);
/// perBaris (hanya di dalam [PenguraiAntrean._putaran]: server tak mendukung
/// batch v2 → sisa putaran per baris).
enum _Hasil { terkirim, lanjut, lewati, gangguanServer, berhenti, henti, perBaris }

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
