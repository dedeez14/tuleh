import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/toko/presentation/providers/toko_providers.dart';
import '../network/api_exception.dart';
import 'antrean.dart';
import 'koneksi.dart';
import 'pengurai.dart';
import 'sinkron_latar.dart';

/// Hasil permintaan tulis lewat [AntreanTulis].
class HasilTulis {
  const HasilTulis({this.tertunda = false, this.perluTinjau = false, this.clientRef});

  /// true = disimpan di antrean, dikirim saat online.
  final bool tertunda;
  final bool perluTinjau;

  /// client_ref baris antrean (hanya bila [tertunda]).
  final String? clientRef;

  static const langsung = HasilTulis();
}

/// Permintaan tulis sederhana (pengeluaran, stok masuk) dengan jalur offline:
/// coba kirim; gagal jaringan → antrekan. Server yang menolak (4xx) tetap
/// dilempar apa adanya agar pengguna melihat pesannya.
class AntreanTulis {
  AntreanTulis({required this.antrean, this.koneksi, this.tokoId, Random? acak})
    : _acak = acak ?? Random.secure();

  final AntreanStore antrean;
  final PenandaKoneksi? koneksi;
  final String? tokoId;
  final Random _acak;

  String _clientRef() {
    const hex = '0123456789abcdef';
    final b = List<int>.generate(16, (_) => _acak.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => hex[x >> 4] + hex[x & 0x0f]).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }

  /// [langsungAntre] = jangan coba ke server (mis. path merujuk bon lokal
  /// yang id servernya belum ada). [tokoId] menimpa toko default.
  /// Petunjuk untuk baris "perlu ditinjau": tunjukkan tempat yang benar untuk
  /// memeriksa, karena hanya CHECKOUT yang muncul di Riwayat. Opname/stok masuk
  /// dicek di layar Produk, bon di peta meja.
  static String _pesanTinjau(String jenis) {
    const awal = 'Server tidak menjawab setelah data dikirim. ';
    return awal + switch (jenis) {
      'OPNAME' || 'STOK_MASUK' =>
        'Periksa stok produknya di layar Produk sebelum mengirim ulang — '
            'mengirim dua kali akan mengubah stok dua kali.',
      'BILL_BUKA' || 'BILL_RONDE' || 'BILL_BAYAR' =>
        'Periksa bon meja itu lebih dulu sebelum mengirim ulang.',
      'PENGELUARAN' =>
        'Periksa daftar Pengeluaran lebih dulu sebelum mengirim ulang.',
      'SESI_BUKA' =>
        'Periksa apakah sesi kasir sudah terbuka sebelum mengirim ulang.',
      _ =>
        'Periksa dulu apakah sudah tercatat sebelum mengirim ulang.',
    };
  }

  Future<HasilTulis> jalankan({
    required String jenis,
    required String path,
    required Map<String, dynamic> body,
    required Future<void> Function(Map<String, dynamic> body) kirim,
    Map<String, double> deltaStok = const {},
    bool langsungAntre = false,
    String? tokoId,
  }) async {
    final clientRef = _clientRef();
    final waktu = DateTime.now();
    final badan = {
      ...body,
      'client_ref': clientRef,
      'waktu_klien': waktu.toIso8601String(),
    };
    var tinjau = false;
    if (!langsungAntre && !(koneksi?.offline ?? false)) {
      try {
        await kirim(badan);
        return HasilTulis.langsung;
      } on ApiException catch (e) {
        if (!e.isJaringan) rethrow;
        tinjau = e.mungkinSampai;
      }
    }
    await antrean.antrekan(
      PesanAntrean(
        urut: 0,
        clientRef: clientRef,
        jenis: jenis,
        tokoId: tokoId ?? this.tokoId,
        path: path,
        body: badan,
        dibuat: waktu,
        status: tinjau ? StatusAntrean.tinjau : StatusAntrean.menunggu,
        galatTerakhir: tinjau ? _pesanTinjau(jenis) : null,
      ),
      deltaStok: deltaStok,
    );
    if (!tinjau) unawaited(SinkronLatar.jadwalkanSekali());
    return HasilTulis(tertunda: true, perluTinjau: tinjau, clientRef: clientRef);
  }
}

final antreanTulisProvider = Provider<AntreanTulis>(
  (ref) => AntreanTulis(
    antrean: ref.watch(antreanStoreProvider),
    koneksi: ref.read(koneksiProvider.notifier),
    tokoId: ref.watch(activeTokoIdProvider).valueOrNull,
  ),
);
