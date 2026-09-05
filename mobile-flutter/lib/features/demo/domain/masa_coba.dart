/// Masa coba Mode Demo — 7 hari sejak pertama kali demo dibuka di perangkat
/// ini, dihitung dengan WAKTU SERVER, bukan jam perangkat.
///
/// Prinsip (sama dengan desktop, frontend/src/main/lib/masa-coba.js):
/// - Mulai masa coba hanya bisa dengan waktu server (header `Date` dari
///   /app/versi). Tanpa koneksi saat pertama kali → demo belum bisa dibuka.
/// - Saat memeriksa, pakai waktu server bila terjangkau. Bila tidak, pakai
///   yang TERBESAR antara jam perangkat dan waktu server yang terakhir
///   terlihat — memundurkan jam tidak pernah memperpanjang masa coba.
/// - Catatan disimpan di SecureStorage (Keystore); hilang bila aplikasi
///   dihapus. Menutup celah itu butuh pendaftaran perangkat di server.
///
/// Murni (tanpa I/O) agar mudah diuji.
library;

enum KodeMasaCoba { aktif, berakhir, butuhKoneksi, butuhIdentitas, diblokir, rusak }

class CatatanMasaCoba {
  const CatatanMasaCoba({required this.mulai, required this.serverTerakhir});
  final DateTime mulai;
  final DateTime serverTerakhir;
}

class StatusMasaCoba {
  const StatusMasaCoba({
    required this.kode,
    required this.sisaHari,
    this.berakhirPada,
    this.catatan,
    this.belumMulai = false,
    this.sumberWaktu,
    this.kini,
  });

  final KodeMasaCoba kode;
  final int sisaHari;
  final DateTime? berakhirPada;

  /// Catatan yang harus disimpan (null = jangan ubah apa pun).
  final CatatanMasaCoba? catatan;
  final bool belumMulai;
  final String? sumberWaktu;

  /// "Sekarang" yang dipakai saat memutuskan (UTC); null bila belum mulai.
  final DateTime? kini;

  bool get aktif => kode == KodeMasaCoba.aktif;

  StatusMasaCoba salin({
    KodeMasaCoba? kode,
    int? sisaHari,
    DateTime? berakhirPada,
    CatatanMasaCoba? catatan,
    String? sumberWaktu,
  }) => StatusMasaCoba(
    kode: kode ?? this.kode,
    sisaHari: sisaHari ?? this.sisaHari,
    berakhirPada: berakhirPada ?? this.berakhirPada,
    catatan: catatan ?? this.catatan,
    belumMulai: belumMulai,
    sumberWaktu: sumberWaktu ?? this.sumberWaktu,
    kini: kini,
  );
}

/// Jawaban server `/demo/perangkat` (lapis 2/3) — sudah diparse.
class StatusServer {
  const StatusServer({
    required this.status,
    this.butuhIdentitas = false,
    this.mulai,
    this.waktuServer,
    this.sisaHari,
  });

  /// AKTIF | BELUM_VERIFIKASI | BERAKHIR | DIBLOKIR
  final String status;
  final bool butuhIdentitas;
  final DateTime? mulai;
  final DateTime? waktuServer;
  final int? sisaHari;

  static StatusServer? dariJson(dynamic d) {
    if (d is! Map) return null;
    final m = Map<String, dynamic>.from(d);
    final status = (m['status'] ?? '').toString().toUpperCase();
    if (status.isEmpty) return null;
    return StatusServer(
      status: status,
      butuhIdentitas: m['butuh_identitas'] == true,
      mulai: DateTime.tryParse('${m['mulai'] ?? ''}')?.toUtc(),
      waktuServer: DateTime.tryParse('${m['waktu_server'] ?? ''}')?.toUtc(),
      sisaHari: m['sisa_hari'] is num ? (m['sisa_hari'] as num).toInt() : null,
    );
  }
}

abstract final class MasaCoba {
  static const Duration durasi = Duration(days: 7);

  /// Waktu "sekarang" yang dipercaya: server > server terakhir > perangkat.
  static (DateTime, String) tentukanKini({
    DateTime? waktuServer,
    DateTime? serverTerakhir,
    required DateTime perangkat,
  }) {
    if (waktuServer != null) return (waktuServer.toUtc(), 'server');
    final p = perangkat.toUtc();
    if (serverTerakhir != null && serverTerakhir.toUtc().isAfter(p)) {
      return (serverTerakhir.toUtc(), 'server_terakhir');
    }
    return (p, 'perangkat');
  }

  static int sisaHari(DateTime mulai, DateTime kini) {
    final akhir = mulai.toUtc().add(durasi);
    final sisa = akhir.difference(kini.toUtc());
    if (sisa <= Duration.zero) return 0;
    return (sisa.inSeconds / Duration.secondsPerDay).ceil();
  }

  static StatusMasaCoba periksa({
    required CatatanMasaCoba? catatan,
    required DateTime? waktuServer,
    required DateTime perangkat,
    bool mulaiBaru = false,
  }) {
    if (catatan == null) {
      if (!mulaiBaru) {
        return const StatusMasaCoba(
          kode: KodeMasaCoba.aktif,
          sisaHari: 7,
          belumMulai: true,
        );
      }
      if (waktuServer == null) {
        return const StatusMasaCoba(
          kode: KodeMasaCoba.butuhKoneksi,
          sisaHari: 7,
        );
      }
      final s = waktuServer.toUtc();
      return StatusMasaCoba(
        kode: KodeMasaCoba.aktif,
        sisaHari: 7,
        berakhirPada: s.add(durasi),
        catatan: CatatanMasaCoba(mulai: s, serverTerakhir: s),
        sumberWaktu: 'server',
        kini: s,
      );
    }

    final (kini, sumber) = tentukanKini(
      waktuServer: waktuServer,
      serverTerakhir: catatan.serverTerakhir,
      perangkat: perangkat,
    );
    final sisa = sisaHari(catatan.mulai, kini);
    final majuServer =
        waktuServer != null &&
        waktuServer.toUtc().isAfter(catatan.serverTerakhir.toUtc());
    return StatusMasaCoba(
      kode: sisa <= 0 ? KodeMasaCoba.berakhir : KodeMasaCoba.aktif,
      sisaHari: sisa,
      berakhirPada: catatan.mulai.toUtc().add(durasi),
      catatan: majuServer
          ? CatatanMasaCoba(
              mulai: catatan.mulai,
              serverTerakhir: waktuServer.toUtc(),
            )
          : null,
      sumberWaktu: sumber,
      kini: kini,
    );
  }

  /// Gabungkan hasil lokal (lapis 1) dengan jawaban server (lapis 2/3).
  /// Aturan sama dengan desktop `gabungkan()`: server menentukan "sekarang";
  /// `mulai` paling awal menang; siapa pun yang menyatakan berakhir/diblokir
  /// menang; server yang minta identitas → [KodeMasaCoba.butuhIdentitas].
  /// [server] null → hasil lokal apa adanya (endpoint belum ada / offline).
  static StatusMasaCoba gabungkan(
    StatusMasaCoba lokal,
    StatusServer? server, {
    required DateTime perangkat,
  }) {
    if (server == null) return lokal;
    if (server.status == 'DIBLOKIR') {
      return lokal.salin(kode: KodeMasaCoba.diblokir, sisaHari: 0);
    }
    if (server.butuhIdentitas || server.status == 'BELUM_VERIFIKASI') {
      return lokal.salin(kode: KodeMasaCoba.butuhIdentitas);
    }
    final mulaiLokal = lokal.catatan?.mulai;
    var mulai = server.mulai;
    if (mulaiLokal != null &&
        (mulai == null || mulaiLokal.toUtc().isBefore(mulai))) {
      mulai = mulaiLokal.toUtc();
    }
    if (mulai == null) return lokal;

    final kini = server.waktuServer ?? lokal.kini ?? perangkat.toUtc();
    final sisa = sisaHari(mulai, kini);
    final berakhir =
        server.status == 'BERAKHIR' ||
        sisa <= 0 ||
        lokal.kode == KodeMasaCoba.berakhir ||
        lokal.kode == KodeMasaCoba.rusak;
    return lokal.salin(
      kode: berakhir ? KodeMasaCoba.berakhir : KodeMasaCoba.aktif,
      sisaHari: berakhir ? 0 : sisa,
      berakhirPada: mulai.add(durasi),
      catatan: CatatanMasaCoba(
        mulai: mulai,
        serverTerakhir:
            server.waktuServer ?? lokal.catatan?.serverTerakhir ?? mulai,
      ),
      sumberWaktu: 'server',
    );
  }
}

/// Dilempar AuthController.startDemo bila demo tidak boleh dibuka.
class MasaCobaException implements Exception {
  const MasaCobaException(this.status);
  final StatusMasaCoba status;

  String get pesan => switch (status.kode) {
    KodeMasaCoba.butuhKoneksi =>
      'Mode Demo perlu koneksi internet saat pertama kali dibuka '
          '(untuk mencatat waktu mulai masa coba).',
    KodeMasaCoba.berakhir =>
      'Masa coba Mode Demo 7 hari sudah berakhir. Masuk dengan akun '
          'berlangganan untuk melanjutkan.',
    KodeMasaCoba.rusak =>
      'Catatan masa coba tidak sah. Masuk dengan akun berlangganan.',
    KodeMasaCoba.butuhIdentitas =>
      'Verifikasi nomor WhatsApp atau email dulu untuk memulai masa coba.',
    KodeMasaCoba.diblokir =>
      'Mode Demo di perangkat ini tidak tersedia. Hubungi Tuléh atau masuk '
          'dengan akun berlangganan.',
    KodeMasaCoba.aktif => '',
  };

  @override
  String toString() => pesan;
}
