import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'salinan_db.g.dart';

/// Salinan jawaban server untuk permintaan baca (GET), dikunci per toko +
/// jalur + query. Dipakai [SalinanInterceptor] agar aplikasi tetap bisa
/// menampilkan data terakhir saat internet mati (mode offline fase 1).
@DataClassName('BarisSalinan')
class Salinan extends Table {
  TextColumn get kunci => text()();
  TextColumn get json => text()();
  DateTimeColumn get ditarikPada => dateTime()();

  @override
  Set<Column> get primaryKey => {kunci};
}

/// Antrean kirim (fase 2): satu baris = satu permintaan tulis yang belum /
/// sudah dikirim. `urut` = urutan kirim (FIFO ketat).
@DataClassName('BarisOutbox')
class Outbox extends Table {
  IntColumn get urut => integer().autoIncrement()();
  TextColumn get clientRef => text().unique()();
  TextColumn get jenis => text()(); // CHECKOUT | PENGELUARAN | STOK_MASUK
  TextColumn get tokoId => text().nullable()();
  TextColumn get path => text()();
  TextColumn get bodyJson => text()();
  IntColumn get percobaan => integer().withDefault(const Constant(0))();
  DateTimeColumn get cobaLagiSetelah => dateTime().nullable()();
  TextColumn get status => text().withDefault(const Constant('MENUNGGU'))();
  TextColumn get galatTerakhir => text().nullable()();
  TextColumn get hasilJson => text().nullable()();
  DateTimeColumn get dibuat => dateTime()();
}

/// Transaksi yang lahir di perangkat saat offline; dihapus setelah terkirim.
@DataClassName('BarisTransaksiLokal')
class TransaksiLokal extends Table {
  TextColumn get clientRef => text()();
  TextColumn get tokoId => text().nullable()();
  TextColumn get nomorLokal => text()();
  TextColumn get nomorServer => text().nullable()();
  TextColumn get tipePembayaran => text()();
  RealColumn get grandTotal => real()();
  RealColumn get dibayar => real()();
  DateTimeColumn get waktuKlien => dateTime()();
  TextColumn get strukJson => text()(); // snapshot Struk untuk cetak ulang

  @override
  Set<Column> get primaryKey => {clientRef};
}

/// Koreksi stok yang belum sampai server: stok tampil = stok server + delta.
@DataClassName('BarisStokDelta')
class StokDelta extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get clientRef => text()();
  TextColumn get idProduk => text()();
  RealColumn get delta => real()(); // negatif = terjual
}

@DriftDatabase(tables: [Salinan, Outbox, TransaksiLokal, StokDelta])
class SalinanDb extends _$SalinanDb {
  SalinanDb(super.e);

  /// Basis data di penyimpanan privat aplikasi (`tuleh_salinan.sqlite`).
  SalinanDb.buka() : super(driftDatabase(name: 'tuleh_salinan'));

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(outbox);
        await m.createTable(transaksiLokal);
        await m.createTable(stokDelta);
      }
    },
  );
}
