import 'dart:convert';

import 'package:drift/drift.dart';

import 'salinan_db.dart';

/// Status satu pesan antrean.
enum StatusAntrean { menunggu, mengirim, terkirim, tinjau }

StatusAntrean statusDari(String s) => switch (s.toUpperCase()) {
  'MENGIRIM' => StatusAntrean.mengirim,
  'TERKIRIM' => StatusAntrean.terkirim,
  'TINJAU' => StatusAntrean.tinjau,
  _ => StatusAntrean.menunggu,
};

String statusKe(StatusAntrean s) => s.name.toUpperCase();

/// Satu permintaan tulis yang menunggu dikirim (baris `outbox`).
class PesanAntrean {
  const PesanAntrean({
    required this.urut,
    required this.clientRef,
    required this.jenis,
    required this.path,
    required this.body,
    required this.dibuat,
    this.tokoId,
    this.percobaan = 0,
    this.cobaLagiSetelah,
    this.status = StatusAntrean.menunggu,
    this.galatTerakhir,
    this.hasil,
  });

  final int urut;
  final String clientRef;

  /// CHECKOUT | PENGELUARAN | STOK_MASUK
  final String jenis;
  final String? tokoId;
  final String path;
  final Map<String, dynamic> body;
  final DateTime dibuat;
  final int percobaan;
  final DateTime? cobaLagiSetelah;
  final StatusAntrean status;
  final String? galatTerakhir;
  final Map<String, dynamic>? hasil;

  bool get perluPerhatian => status == StatusAntrean.tinjau;
  bool get belumTerkirim =>
      status == StatusAntrean.menunggu || status == StatusAntrean.mengirim;

  String get label => switch (jenis) {
    'CHECKOUT' => 'Transaksi',
    'PENGELUARAN' => 'Pengeluaran',
    'STOK_MASUK' => 'Stok masuk',
    'OPNAME' => 'Opname stok',
    'SESI_BUKA' => 'Buka sesi',
    'BILL_BUKA' => 'Buka bon',
    'BILL_RONDE' => 'Pesanan bon',
    'BILL_BAYAR' => 'Bayar bon',
    _ => jenis,
  };
}

/// Transaksi lokal (belum tersinkron) untuk riwayat & cetak ulang.
class TransaksiTertunda {
  const TransaksiTertunda({
    required this.clientRef,
    required this.nomorLokal,
    required this.tipePembayaran,
    required this.grandTotal,
    required this.dibayar,
    required this.waktuKlien,
    required this.strukJson,
    this.tokoId,
    this.nomorServer,
  });

  final String clientRef;
  final String? tokoId;
  final String nomorLokal;
  final String? nomorServer;
  final String tipePembayaran;
  final double grandTotal;
  final double dibayar;
  final DateTime waktuKlien;
  final String strukJson;
}

/// Ringkasan untuk pita status & layar Sinkronisasi.
class RingkasAntrean {
  const RingkasAntrean({this.menunggu = 0, this.tinjau = 0});
  final int menunggu;
  final int tinjau;
  int get total => menunggu + tinjau;
}

/// Penyimpanan antrean — antarmuka kecil (memori di test, SQLite di perangkat).
abstract interface class AntreanStore {
  /// Antrekan satu pesan beserta transaksi lokal & delta stok dalam SATU
  /// transaksi penyimpanan: tidak mungkin ada struk tanpa antrean.
  Future<void> antrekan(
    PesanAntrean pesan, {
    TransaksiTertunda? transaksi,
    Map<String, double> deltaStok = const {},
  });

  Future<List<PesanAntrean>> semua();

  /// Pesan MENUNGGU yang boleh dikirim sekarang, urut FIFO.
  Future<List<PesanAntrean>> siapKirim(DateTime sekarang);

  Future<PesanAntrean?> cari(String clientRef);

  Future<void> perbarui(
    String clientRef, {
    StatusAntrean? status,
    int? percobaan,
    DateTime? cobaLagiSetelah,
    bool hapusCobaLagi = false,
    String? galatTerakhir,
    Map<String, dynamic>? hasil,
  });

  /// Selesai terkirim: catat hasil, hapus transaksi lokal & delta stoknya.
  Future<void> selesai(String clientRef, {Map<String, dynamic>? hasil});

  /// Batalkan (pengguna): hapus pesan, transaksi lokal, dan delta stoknya.
  Future<void> batalkan(String clientRef);

  Future<RingkasAntrean> ringkas();

  Future<List<TransaksiTertunda>> transaksiTertunda({String? tokoId});

  Future<TransaksiTertunda?> transaksiLokal(String clientRef);

  /// Delta stok tertunda per id produk (dijumlahkan).
  Future<Map<String, double>> deltaStokTertunda({String? tokoId});
}

// ---------------------------------------------------------------- memori

class AntreanMemori implements AntreanStore {
  final List<PesanAntrean> _pesan = [];
  final Map<String, TransaksiTertunda> _trx = {};
  final List<(String clientRef, String idProduk, double delta)> _delta = [];
  int _urut = 0;

  @override
  Future<void> antrekan(
    PesanAntrean pesan, {
    TransaksiTertunda? transaksi,
    Map<String, double> deltaStok = const {},
  }) async {
    _pesan.add(_salin(pesan, urut: ++_urut));
    if (transaksi != null) _trx[pesan.clientRef] = transaksi;
    deltaStok.forEach((id, d) => _delta.add((pesan.clientRef, id, d)));
  }

  PesanAntrean _salin(
    PesanAntrean p, {
    int? urut,
    StatusAntrean? status,
    int? percobaan,
    DateTime? cobaLagiSetelah,
    bool hapusCobaLagi = false,
    String? galatTerakhir,
    Map<String, dynamic>? hasil,
  }) => PesanAntrean(
    urut: urut ?? p.urut,
    clientRef: p.clientRef,
    jenis: p.jenis,
    path: p.path,
    body: p.body,
    dibuat: p.dibuat,
    tokoId: p.tokoId,
    percobaan: percobaan ?? p.percobaan,
    cobaLagiSetelah: hapusCobaLagi ? null : (cobaLagiSetelah ?? p.cobaLagiSetelah),
    status: status ?? p.status,
    galatTerakhir: galatTerakhir ?? p.galatTerakhir,
    hasil: hasil ?? p.hasil,
  );

  @override
  Future<List<PesanAntrean>> semua() async =>
      List.unmodifiable(_pesan..sort((a, b) => a.urut.compareTo(b.urut)));

  @override
  Future<List<PesanAntrean>> siapKirim(DateTime sekarang) async => [
    for (final p in await semua())
      if (p.status == StatusAntrean.menunggu &&
          (p.cobaLagiSetelah == null || !p.cobaLagiSetelah!.isAfter(sekarang)))
        p,
  ];

  @override
  Future<PesanAntrean?> cari(String clientRef) async {
    for (final p in _pesan) {
      if (p.clientRef == clientRef) return p;
    }
    return null;
  }

  @override
  Future<void> perbarui(
    String clientRef, {
    StatusAntrean? status,
    int? percobaan,
    DateTime? cobaLagiSetelah,
    bool hapusCobaLagi = false,
    String? galatTerakhir,
    Map<String, dynamic>? hasil,
  }) async {
    final i = _pesan.indexWhere((p) => p.clientRef == clientRef);
    if (i < 0) return;
    _pesan[i] = _salin(
      _pesan[i],
      status: status,
      percobaan: percobaan,
      cobaLagiSetelah: cobaLagiSetelah,
      hapusCobaLagi: hapusCobaLagi,
      galatTerakhir: galatTerakhir,
      hasil: hasil,
    );
  }

  @override
  Future<void> selesai(String clientRef, {Map<String, dynamic>? hasil}) async {
    await perbarui(clientRef, status: StatusAntrean.terkirim, hasil: hasil, hapusCobaLagi: true);
    _trx.remove(clientRef);
    _delta.removeWhere((d) => d.$1 == clientRef);
  }

  @override
  Future<void> batalkan(String clientRef) async {
    _pesan.removeWhere((p) => p.clientRef == clientRef);
    _trx.remove(clientRef);
    _delta.removeWhere((d) => d.$1 == clientRef);
  }

  @override
  Future<RingkasAntrean> ringkas() async => RingkasAntrean(
    menunggu: _pesan.where((p) => p.belumTerkirim).length,
    tinjau: _pesan.where((p) => p.perluPerhatian).length,
  );

  @override
  Future<List<TransaksiTertunda>> transaksiTertunda({String? tokoId}) async => [
    for (final t in _trx.values)
      if (tokoId == null || t.tokoId == tokoId) t,
  ]..sort((a, b) => b.waktuKlien.compareTo(a.waktuKlien));

  @override
  Future<TransaksiTertunda?> transaksiLokal(String clientRef) async =>
      _trx[clientRef];

  @override
  Future<Map<String, double>> deltaStokTertunda({String? tokoId}) async {
    final out = <String, double>{};
    for (final d in _delta) {
      if (tokoId != null && _trx[d.$1]?.tokoId != tokoId) continue;
      out[d.$2] = (out[d.$2] ?? 0) + d.$3;
    }
    return out;
  }
}

// ----------------------------------------------------------------- drift

class AntreanDriftStore implements AntreanStore {
  AntreanDriftStore(this._db);
  final SalinanDb _db;

  PesanAntrean _dari(BarisOutbox b) => PesanAntrean(
    urut: b.urut,
    clientRef: b.clientRef,
    jenis: b.jenis,
    tokoId: b.tokoId,
    path: b.path,
    body: Map<String, dynamic>.from(jsonDecode(b.bodyJson) as Map),
    dibuat: b.dibuat,
    percobaan: b.percobaan,
    cobaLagiSetelah: b.cobaLagiSetelah,
    status: statusDari(b.status),
    galatTerakhir: b.galatTerakhir,
    hasil: b.hasilJson == null
        ? null
        : Map<String, dynamic>.from(jsonDecode(b.hasilJson!) as Map),
  );

  TransaksiTertunda _trxDari(BarisTransaksiLokal b) => TransaksiTertunda(
    clientRef: b.clientRef,
    tokoId: b.tokoId,
    nomorLokal: b.nomorLokal,
    nomorServer: b.nomorServer,
    tipePembayaran: b.tipePembayaran,
    grandTotal: b.grandTotal,
    dibayar: b.dibayar,
    waktuKlien: b.waktuKlien,
    strukJson: b.strukJson,
  );

  @override
  Future<void> antrekan(
    PesanAntrean pesan, {
    TransaksiTertunda? transaksi,
    Map<String, double> deltaStok = const {},
  }) => _db.transaction(() async {
    await _db
        .into(_db.outbox)
        .insert(
          OutboxCompanion.insert(
            clientRef: pesan.clientRef,
            jenis: pesan.jenis,
            tokoId: Value(pesan.tokoId),
            path: pesan.path,
            bodyJson: jsonEncode(pesan.body),
            status: Value(statusKe(pesan.status)),
            dibuat: pesan.dibuat,
          ),
        );
    if (transaksi != null) {
      await _db
          .into(_db.transaksiLokal)
          .insert(
            TransaksiLokalCompanion.insert(
              clientRef: transaksi.clientRef,
              tokoId: Value(transaksi.tokoId),
              nomorLokal: transaksi.nomorLokal,
              tipePembayaran: transaksi.tipePembayaran,
              grandTotal: transaksi.grandTotal,
              dibayar: transaksi.dibayar,
              waktuKlien: transaksi.waktuKlien,
              strukJson: transaksi.strukJson,
            ),
          );
    }
    for (final e in deltaStok.entries) {
      await _db
          .into(_db.stokDelta)
          .insert(
            StokDeltaCompanion.insert(
              clientRef: pesan.clientRef,
              idProduk: e.key,
              delta: e.value,
            ),
          );
    }
  });

  @override
  Future<List<PesanAntrean>> semua() async {
    final rows = await (_db.select(_db.outbox)..orderBy([(t) => OrderingTerm.asc(t.urut)])).get();
    return rows.map(_dari).toList();
  }

  @override
  Future<List<PesanAntrean>> siapKirim(DateTime sekarang) async => [
    for (final p in await semua())
      if (p.status == StatusAntrean.menunggu &&
          (p.cobaLagiSetelah == null || !p.cobaLagiSetelah!.isAfter(sekarang)))
        p,
  ];

  @override
  Future<PesanAntrean?> cari(String clientRef) async {
    final b = await (_db.select(_db.outbox)..where((t) => t.clientRef.equals(clientRef))).getSingleOrNull();
    return b == null ? null : _dari(b);
  }

  @override
  Future<void> perbarui(
    String clientRef, {
    StatusAntrean? status,
    int? percobaan,
    DateTime? cobaLagiSetelah,
    bool hapusCobaLagi = false,
    String? galatTerakhir,
    Map<String, dynamic>? hasil,
  }) async {
    await (_db.update(_db.outbox)..where((t) => t.clientRef.equals(clientRef))).write(
      OutboxCompanion(
        status: status == null ? const Value.absent() : Value(statusKe(status)),
        percobaan: percobaan == null ? const Value.absent() : Value(percobaan),
        cobaLagiSetelah: hapusCobaLagi
            ? const Value(null)
            : (cobaLagiSetelah == null ? const Value.absent() : Value(cobaLagiSetelah)),
        galatTerakhir: galatTerakhir == null ? const Value.absent() : Value(galatTerakhir),
        hasilJson: hasil == null ? const Value.absent() : Value(jsonEncode(hasil)),
      ),
    );
  }

  @override
  Future<void> selesai(String clientRef, {Map<String, dynamic>? hasil}) =>
      _db.transaction(() async {
        await perbarui(clientRef, status: StatusAntrean.terkirim, hasil: hasil, hapusCobaLagi: true);
        await (_db.delete(_db.transaksiLokal)..where((t) => t.clientRef.equals(clientRef))).go();
        await (_db.delete(_db.stokDelta)..where((t) => t.clientRef.equals(clientRef))).go();
      });

  @override
  Future<void> batalkan(String clientRef) => _db.transaction(() async {
    await (_db.delete(_db.outbox)..where((t) => t.clientRef.equals(clientRef))).go();
    await (_db.delete(_db.transaksiLokal)..where((t) => t.clientRef.equals(clientRef))).go();
    await (_db.delete(_db.stokDelta)..where((t) => t.clientRef.equals(clientRef))).go();
  });

  @override
  Future<RingkasAntrean> ringkas() async {
    final rows = await semua();
    return RingkasAntrean(
      menunggu: rows.where((p) => p.belumTerkirim).length,
      tinjau: rows.where((p) => p.perluPerhatian).length,
    );
  }

  @override
  Future<List<TransaksiTertunda>> transaksiTertunda({String? tokoId}) async {
    final q = _db.select(_db.transaksiLokal)..orderBy([(t) => OrderingTerm.desc(t.waktuKlien)]);
    if (tokoId != null) q.where((t) => t.tokoId.equals(tokoId));
    return (await q.get()).map(_trxDari).toList();
  }

  @override
  Future<TransaksiTertunda?> transaksiLokal(String clientRef) async {
    final b = await (_db.select(_db.transaksiLokal)..where((t) => t.clientRef.equals(clientRef))).getSingleOrNull();
    return b == null ? null : _trxDari(b);
  }

  @override
  Future<Map<String, double>> deltaStokTertunda({String? tokoId}) async {
    final rows = await _db.select(_db.stokDelta).get();
    final out = <String, double>{};
    Set<String>? refToko;
    if (tokoId != null) {
      refToko = (await transaksiTertunda(tokoId: tokoId)).map((t) => t.clientRef).toSet();
    }
    for (final r in rows) {
      if (refToko != null && !refToko.contains(r.clientRef)) continue;
      out[r.idProduk] = (out[r.idProduk] ?? 0) + r.delta;
    }
    return out;
  }
}
