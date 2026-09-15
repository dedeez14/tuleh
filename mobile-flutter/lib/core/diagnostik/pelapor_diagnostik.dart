import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../constants/app_config.dart';
import '../network/api_exception.dart';
import '../offline/waktu_klien.dart';
import 'log_cincin.dart';
import 'penyamar.dart';

/// Jenis laporan kontrak `POST /diagnostik`.
abstract final class JenisDiagnostik {
  static const crash = 'crash';
  static const error = 'error';
  static const log = 'log';
}

/// Batas ukuran kontrak `/diagnostik` (server menolak yang melebihi).
abstract final class BatasDiagnostik {
  static const pesan = 2000;
  static const stack = 20000;
  static const konteksByte = 10 * 1024;
}

String _potong(String s, int maks) => s.length <= maks ? s : '${s.substring(0, maks - 1)}…';

/// Penyimpanan antrean laporan (berkas JSON kecil — sengaja TIDAK memakai
/// SQLite antrean transaksi: crash bisa berasal dari basis data itu sendiri,
/// dan laporan tidak boleh ikut antre FIFO di belakang penjualan).
abstract interface class PenyimpanDiagnostik {
  Future<List<Map<String, dynamic>>> baca();
  Future<void> tulis(List<Map<String, dynamic>> isi);
}

class PenyimpanDiagnostikMemori implements PenyimpanDiagnostik {
  List<Map<String, dynamic>> isi = [];
  @override
  Future<List<Map<String, dynamic>>> baca() async => [for (final m in isi) Map.of(m)];
  @override
  Future<void> tulis(List<Map<String, dynamic>> baru) async => isi = [for (final m in baru) Map.of(m)];
}

class PenyimpanDiagnostikBerkas implements PenyimpanDiagnostik {
  PenyimpanDiagnostikBerkas({this.dir});
  final Directory? dir;

  Future<File> _berkas() async {
    final d = dir ?? await getApplicationSupportDirectory();
    return File('${d.path}/antrean_diagnostik.json');
  }

  @override
  Future<List<Map<String, dynamic>>> baca() async {
    try {
      final f = await _berkas();
      if (!await f.exists()) return [];
      final data = jsonDecode(await f.readAsString());
      return [
        if (data is List)
          for (final e in data)
            if (e is Map) Map<String, dynamic>.from(e),
      ];
    } catch (_) {
      return []; // berkas rusak: laporan lama dikorbankan, aplikasi jalan terus
    }
  }

  @override
  Future<void> tulis(List<Map<String, dynamic>> isi) async {
    try {
      final f = await _berkas();
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode(isi), flush: true);
      await tmp.rename(f.path);
    } catch (_) {}
  }
}

/// Hasil kirim laporan yang diminta pengguna.
class HasilLaporan {
  const HasilLaporan({required this.clientRef, this.idServer});
  final String clientRef;

  /// Id laporan dari server (202) — disebutkan ke CS. null = masih antre.
  final String? idServer;
  bool get terkirim => idServer != null;
}

/// Pelapor galat/crash ke `POST /api/pos/v1/diagnostik`:
/// - setiap laporan punya `client_ref` (server menolak kiriman ganda);
/// - pesan, stack, dan konteks disamarkan ([samarkan]) & dipotong sesuai batas;
/// - galat identik dalam satu sesi aplikasi hanya dilaporkan sekali;
/// - disimpan dulu ke berkas lalu dikirim — gangguan (jaringan/408/429/5xx)
///   membiarkannya antre untuk percobaan berikutnya; penolakan 4xx lain
///   membuangnya (tidak akan pernah diterima);
/// - pelaporan TIDAK PERNAH melempar: gagal melapor tidak boleh menambah crash.
class PelaporDiagnostik {
  PelaporDiagnostik({
    required this.dio,
    required this.simpan,
    required this.versi,
    this.token,
    this.konteksDasar,
    this.maksAntrean = 30,
    DateTime Function()? sekarang,
    Random? acak,
  }) : _sekarang = sekarang ?? DateTime.now,
       _acak = acak ?? Random.secure();

  /// Dio ke server POS (baseUrl `…/api/pos/v1`). Header versi & platform
  /// ditambahkan per permintaan.
  final Dio dio;
  final PenyimpanDiagnostik simpan;
  final String versi;

  /// Token sesi (opsional) — hanya dipakai sebagai header Authorization agar
  /// server menautkan laporan ke perusahaan/pengguna; tidak pernah di badan.
  final Future<String?> Function()? token;

  /// Konteks tetap (os, perangkat, locale, layar terakhir).
  final Map<String, dynamic> Function()? konteksDasar;
  final int maksAntrean;
  final DateTime Function() _sekarang;
  final Random _acak;

  final Set<String> _sidikSesi = {};
  Future<Map<String, String>>? _kiriman;

  /// Mutasi penyimpanan dijalankan bergiliran: kiriman yang sedang berjalan
  /// tidak boleh menimpa laporan yang baru diantrekan di tengahnya.
  Future<void> _giliran = Future.value();
  Future<T> _eksklusif<T>(Future<T> Function() kerja) {
    final hasil = _giliran.then((_) => kerja());
    _giliran = hasil.then((_) {}, onError: (Object _) {});
    return hasil;
  }

  String _uuid() {
    const hex = '0123456789abcdef';
    final b = List<int>.generate(16, (_) => _acak.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => hex[x >> 4] + hex[x & 0x0f]).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }

  static Map<String, dynamic> _konteksAman(Map<String, dynamic> konteks) {
    // Nilai disamarkan & dipendekkan; bila tetap > 10 KB, kunci terakhir dibuang.
    final out = <String, dynamic>{};
    konteks.forEach((k, v) {
      if (v == null) return;
      out[k] = v is num || v is bool ? v : _potong(samarkan('$v'), 1000);
    });
    while (out.isNotEmpty && utf8.encode(jsonEncode(out)).length > BatasDiagnostik.konteksByte) {
      out.remove(out.keys.last);
    }
    return out;
  }

  /// Bangun badan laporan (tanpa mengirim).
  Map<String, dynamic> buatLaporan({
    required String jenis,
    required String pesan,
    String? stack,
    Map<String, dynamic> konteks = const {},
  }) {
    Map<String, dynamic> dasar;
    try {
      dasar = konteksDasar?.call() ?? const {};
    } catch (_) {
      dasar = const {};
    }
    return {
      'platform': AppConfig.platform,
      'versi': versi,
      'jenis': jenis,
      'pesan': _potong(samarkan(pesan.trim().isEmpty ? '(tanpa pesan)' : pesan), BatasDiagnostik.pesan),
      if (stack != null && stack.trim().isNotEmpty)
        'stack': _potong(samarkan(stack), BatasDiagnostik.stack),
      'konteks': _konteksAman({...dasar, ...konteks}),
      'terjadi_pada': waktuKlienIso(_sekarang()),
      'client_ref': _uuid(),
    };
  }

  static String _sidik(String jenis, String pesan, String? stack) => sha1
      .convert(utf8.encode('$jenis|$pesan|${(stack ?? '').length > 600 ? stack!.substring(0, 600) : stack ?? ''}'))
      .toString();

  /// Laporkan galat tak tertangani. Aman dipanggil dari penangan galat global.
  Future<void> laporkanGalat(
    Object galat,
    StackTrace? stack, {
    String jenis = JenisDiagnostik.error,
    Map<String, dynamic> konteks = const {},
  }) async {
    try {
      final pesan = '$galat';
      final teksStack = stack?.toString();
      final sidik = _sidik(jenis, pesan, teksStack);
      if (!_sidikSesi.add(sidik)) return; // sudah dilaporkan di sesi ini
      LogCincin.global.catat('Galat ($jenis): $pesan', tingkat: 'E');
      await _antrekan(buatLaporan(jenis: jenis, pesan: pesan, stack: teksStack, konteks: konteks));
      unawaited(kirimTertunda());
    } catch (_) {}
  }

  /// "Kirim laporan ke dukungan": catatan pengguna + ekor log dalam aplikasi.
  /// Mencoba kirim segera; bila gangguan, tetap antre & dikirim nanti.
  Future<HasilLaporan> kirimLaporanPengguna({String? catatan, String? ekorLog}) async {
    final laporan = buatLaporan(
      jenis: JenisDiagnostik.log,
      pesan: (catatan ?? '').trim().isEmpty ? 'Laporan dari pengguna' : catatan!.trim(),
      stack: ekorLog ?? LogCincin.global.ekor(maksKarakter: BatasDiagnostik.stack),
      konteks: const {'sumber': 'pengaturan'},
    );
    final ref = laporan['client_ref'] as String;
    await _antrekan(laporan);
    final hasil = await kirimTertunda();
    return HasilLaporan(clientRef: ref, idServer: hasil[ref]);
  }

  Future<void> _antrekan(Map<String, dynamic> laporan) => _eksklusif(() async {
    final isi = await simpan.baca();
    if (isi.any((m) => m['client_ref'] == laporan['client_ref'])) return;
    isi.add(laporan);
    // Banjir galat tidak boleh memenuhi penyimpanan: yang tertua dibuang.
    while (isi.length > maksAntrean) {
      isi.removeAt(0);
    }
    await simpan.tulis(isi);
  });

  Future<int> jumlahTertunda() async => (await simpan.baca()).length;

  /// Kirim semua laporan antre (urut lama → baru). Mengembalikan peta
  /// client_ref → id server untuk yang diterima. Bila putaran lain sedang
  /// berjalan, ditunggu dulu lalu dijalankan lagi (laporan yang baru masuk
  /// di tengahnya ikut terkirim).
  Future<Map<String, String>> kirimTertunda() async {
    final berjalan = _kiriman;
    final hasilSebelumnya = berjalan == null ? const <String, String>{} : await berjalan;
    final lain = _kiriman;
    if (lain != null) return {...hasilSebelumnya, ...await lain};
    final putaran = _kirimPutaran();
    _kiriman = putaran;
    try {
      return {...hasilSebelumnya, ...await putaran};
    } finally {
      if (identical(_kiriman, putaran)) _kiriman = null;
    }
  }

  Future<Map<String, String>> _kirimPutaran() async {
    final diterima = <String, String>{};
    try {
      final isi = await _eksklusif(simpan.baca);
      if (isi.isEmpty) return diterima;
      final selesai = <Object?>{};
      String? tok;
      try {
        tok = await token?.call();
      } catch (_) {}
      for (final laporan in isi) {
        final kode = await _kirimSatu(laporan, tok, diterima);
        // Gangguan: sisanya dicoba lagi nanti (urutan dijaga).
        if (kode == null || statusGangguan(kode)) break;
        // 2xx diterima; 4xx lain ditolak permanen → sama-sama dibuang.
        selesai.add(laporan['client_ref']);
      }
      if (selesai.isNotEmpty) {
        await _eksklusif(() async {
          final kini = await simpan.baca();
          await simpan.tulis([
            for (final m in kini)
              if (!selesai.contains(m['client_ref'])) m,
          ]);
        });
      }
    } catch (_) {}
    return diterima;
  }

  Future<int?> _kirimSatu(Map<String, dynamic> laporan, String? tok, Map<String, String> diterima) async {
    try {
      final res = await dio.post<dynamic>(
        '/diagnostik',
        data: laporan,
        options: Options(
          headers: {
            AppConfig.versionHeader: versi,
            AppConfig.platformHeader: AppConfig.platform,
            if (tok != null && tok.isNotEmpty) 'Authorization': 'Bearer $tok',
          },
          validateStatus: (_) => true,
        ),
      );
      final kode = res.statusCode ?? 0;
      if (kode >= 200 && kode < 300) {
        final data = res.data is Map ? (res.data as Map)['data'] : null;
        final id = data is Map ? data['id']?.toString() : null;
        diterima[laporan['client_ref'] as String] = id ?? '';
      }
      return kode;
    } on DioException {
      return null;
    }
  }
}
