import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/toko/presentation/providers/toko_providers.dart';
import '../network/api_exception.dart';
import 'antrean.dart';
import 'koneksi.dart';
import 'pengurai.dart';
import 'sinkron_latar.dart';
import 'waktu_klien.dart';

/// Hasil permintaan tulis lewat [AntreanTulis].
class HasilTulis {
  const HasilTulis({this.tertunda = false, this.clientRef});

  /// true = disimpan di antrean, dikirim saat online.
  final bool tertunda;

  /// client_ref baris antrean (hanya bila [tertunda]).
  final String? clientRef;

  static const langsung = HasilTulis();
}

/// Permintaan tulis sederhana (pengeluaran, stok masuk) dengan jalur offline:
/// coba kirim; GANGGUAN (jaringan putus, 408, 429, 5xx) → antrekan. Server
/// yang menolak (4xx lain, termasuk 402 langganan & 401 sesi) tetap dilempar
/// apa adanya agar pengguna melihat pesannya — tidak diantrekan.
class AntreanTulis {
  AntreanTulis({required this.antrean, this.koneksi, this.tokoId, this.pemilik, Random? acak})
    : _acak = acak ?? Random.secure();

  final AntreanStore antrean;
  final PenandaKoneksi? koneksi;
  final String? tokoId;

  /// Akun yang sedang masuk — dicatat sebagai pemilik baris antrean.
  final String? pemilik;
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
      'waktu_klien': waktuKlienIso(waktu),
    };
    Duration? cobaLagi;
    if (!langsungAntre && !(koneksi?.offline ?? false)) {
      try {
        await kirim(badan);
        return HasilTulis.langsung;
      } on ApiException catch (e) {
        if (!e.isGangguan) rethrow;
        // Timeout setelah data terkirim atau 5xx setelah server mencatatnya
        // pun cukup diantrekan biasa: server menolak duplikat lewat
        // `client_ref` yang ikut di badan permintaan.
        cobaLagi = e.cobaLagiSetelah;
      }
    }
    await antrean.antrekan(
      PesanAntrean(
        urut: 0,
        clientRef: clientRef,
        jenis: jenis,
        tokoId: tokoId ?? this.tokoId,
        pemilik: pemilik,
        path: path,
        body: badan,
        dibuat: waktu,
        status: StatusAntrean.menunggu,
        // Retry-After dari server dihormati sejak kiriman pertama.
        cobaLagiSetelah: cobaLagi == null ? null : waktu.add(cobaLagi),
      ),
      deltaStok: deltaStok,
    );
    unawaited(SinkronLatar.jadwalkanSekali());
    return HasilTulis(tertunda: true, clientRef: clientRef);
  }
}

final antreanTulisProvider = Provider<AntreanTulis>(
  (ref) => AntreanTulis(
    antrean: ref.watch(antreanStoreProvider),
    koneksi: ref.read(koneksiProvider.notifier),
    tokoId: ref.watch(activeTokoIdProvider).valueOrNull,
    pemilik: ref.watch(akunAktifProvider),
  ),
);
