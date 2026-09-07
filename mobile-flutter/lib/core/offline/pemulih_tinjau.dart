import 'package:dio/dio.dart';

import 'antrean.dart';

/// Pemulihan otomatis baris CHECKOUT yang berstatus TINJAU karena server
/// tidak menjawab setelah data dikirim ("mungkin sudah sampai").
///
/// Selama server belum mengenali `client_ref`, satu-satunya cara memastikan
/// adalah mencocokkan ke daftar transaksi server pada hari itu:
/// - tepat SATU transaksi cocok (total sama, metode sama, waktu ±15 menit,
///   tidak dibatalkan, belum diklaim baris lain) → dianggap TERKIRIM dengan
///   nomor resminya;
/// - TIDAK ADA yang cocok padahal daftar berhasil ditarik → aman dikirim
///   ulang, baris kembali MENUNGGU;
/// - lebih dari satu kandidat → tetap TINJAU, pesannya menyebut kandidatnya
///   agar kasir yang memutuskan.
class PemulihTinjau {
  PemulihTinjau({
    required this.store,
    required this.dio,
    this.jendela = const Duration(minutes: 15),
  });

  final AntreanStore store;
  final Dio dio;
  final Duration jendela;

  /// Penanda TINJAU yang layak dipulihkan otomatis (bukan penolakan server).
  static bool layakDipulihkan(PesanAntrean p) =>
      p.status == StatusAntrean.tinjau &&
      p.jenis == 'CHECKOUT' &&
      (p.galatTerakhir ?? '').contains('setelah data dikirim');

  /// Mengembalikan jumlah baris yang berubah status. Aman dipanggil berulang.
  Future<int> jalankan() async {
    final calon = (await store.semua()).where(layakDipulihkan).toList();
    if (calon.isEmpty) return 0;

    var berubah = 0;
    final daftarCache = <String, List<_TrxServer>?>{};
    final diklaim = <String>{};

    for (final p in calon) {
      final waktu = DateTime.tryParse('${p.body['waktu_klien'] ?? ''}') ?? p.dibuat;
      final kunci = '${p.tokoId ?? ''}|${_tgl(waktu)}';
      daftarCache[kunci] ??= await _tarik(p.tokoId, waktu);
      final daftar = daftarCache[kunci];
      if (daftar == null) continue; // daftar gagal ditarik → jangan memutuskan

      final total = await _totalLokal(p);
      final tipe = '${p.body['tipe_pembayaran'] ?? ''}'.toUpperCase();
      final kandidat = [
        for (final t in daftar)
          if (!diklaim.contains(t.id) &&
              !t.dibatalkan &&
              (t.total - total).abs() < 1 &&
              (tipe.isEmpty || t.metode.isEmpty || t.metode == tipe) &&
              t.waktu != null &&
              t.waktu!.difference(waktu.toUtc()).abs() <= jendela)
            t,
      ];

      if (kandidat.length == 1) {
        final t = kandidat.single;
        diklaim.add(t.id);
        await store.selesai(p.clientRef, hasil: {'nomor': t.nomor, 'id': t.id, 'dipulihkan': true});
        berubah++;
      } else if (kandidat.isEmpty) {
        await store.perbarui(
          p.clientRef,
          status: StatusAntrean.menunggu,
          percobaan: 0,
          hapusCobaLagi: true,
          galatTerakhir: 'Dipastikan belum tercatat di server; dikirim ulang otomatis.',
        );
        berubah++;
      } else {
        final nomor = kandidat.map((t) => t.nomor).take(3).join(', ');
        await store.perbarui(
          p.clientRef,
          galatTerakhir:
              'Kemungkinan sudah tercatat sebagai $nomor. Periksa Riwayat, lalu '
              'Batalkan bila sudah ada atau Kirim ulang bila belum.',
        );
      }
    }
    return berubah;
  }

  Future<double> _totalLokal(PesanAntrean p) async {
    final lokal = await store.transaksiLokal(p.clientRef);
    if (lokal != null) return lokal.grandTotal;
    var total = 0.0;
    final items = p.body['items'];
    if (items is List) {
      for (final it in items) {
        if (it is! Map) continue;
        final harga = (it['harga'] as num?)?.toDouble() ?? 0;
        final qty = (it['kuantitas'] as num?)?.toDouble() ?? 0;
        final diskon = (it['diskon_persen'] as num?)?.toDouble() ?? 0;
        total += harga * qty * (1 - diskon / 100);
      }
    }
    return total;
  }

  /// Tarik transaksi server sekitar tanggal [waktu] (H-1 s.d. H+1, zona
  /// perangkat) untuk toko [tokoId]. null bila gagal.
  Future<List<_TrxServer>?> _tarik(String? tokoId, DateTime waktu) async {
    final dari = _tgl(waktu.subtract(const Duration(days: 1)));
    final sampai = _tgl(waktu.add(const Duration(days: 1)));
    try {
      final res = await dio.get<dynamic>(
        '/transaksi',
        queryParameters: {
          'dari': dari,
          'sampai': sampai,
          'tanggal_dari': dari,
          'tanggal_sampai': sampai,
          'toko_id': ?tokoId,
        },
      );
      final code = res.statusCode ?? 0;
      final body = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : null;
      if (code < 200 || code >= 300 || body == null || body['success'] != true) return null;
      final data = body['data'];
      final rows = data is List ? data : (data is Map && data['rows'] is List ? data['rows'] as List : const []);
      return [
        for (final e in rows)
          if (e is Map) _TrxServer.dari(Map<String, dynamic>.from(e)),
      ];
    } catch (_) {
      return null;
    }
  }

  static String _tgl(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class _TrxServer {
  _TrxServer({required this.id, required this.nomor, required this.total, required this.metode, required this.status, this.waktu});

  final String id;
  final String nomor;
  final double total;
  final String metode;
  final String status;
  final DateTime? waktu; // UTC

  bool get dibatalkan => status.toUpperCase().contains('BATAL');

  static _TrxServer dari(Map<String, dynamic> m) {
    final raw = (m['tanggal'] ?? m['created_at'])?.toString();
    final dt = raw == null ? null : DateTime.tryParse(raw);
    return _TrxServer(
      id: '${m['id'] ?? ''}',
      nomor: (m['nomor'] ?? m['no'] ?? '-').toString(),
      total: _angka(m['grand_total'] ?? m['total']),
      metode: (m['tipe_pembayaran'] ?? m['metode_bayar'] ?? '').toString().toUpperCase(),
      status: (m['status'] ?? '').toString(),
      waktu: dt?.toUtc(),
    );
  }

  static double _angka(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
}
