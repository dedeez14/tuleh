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

@DriftDatabase(tables: [Salinan])
class SalinanDb extends _$SalinanDb {
  SalinanDb(super.e);

  /// Basis data di penyimpanan privat aplikasi (`tuleh_salinan.sqlite`).
  SalinanDb.buka() : super(driftDatabase(name: 'tuleh_salinan'));

  @override
  int get schemaVersion => 1;
}
