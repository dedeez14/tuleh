import 'package:drift/drift.dart';

import 'salinan_db.dart';

/// Satu salinan jawaban server.
class Salinan {
  const Salinan({required this.json, required this.ditarikPada});
  final String json;
  final DateTime ditarikPada;
}

/// Penyimpanan salinan — antarmuka kecil agar test memakai memori dan
/// perangkat memakai SQLite (drift).
abstract interface class SalinanStore {
  Future<Salinan?> baca(String kunci);
  Future<void> tulis(String kunci, String json, DateTime ditarikPada);
  Future<void> hapusSemua();
}

/// Implementasi SQLite lewat [SalinanDb].
class SalinanDriftStore implements SalinanStore {
  SalinanDriftStore(this._db);
  final SalinanDb _db;

  @override
  Future<Salinan?> baca(String kunci) async {
    final baris = await (_db.select(
      _db.salinan,
    )..where((t) => t.kunci.equals(kunci))).getSingleOrNull();
    if (baris == null) return null;
    return Salinan(json: baris.json, ditarikPada: baris.ditarikPada);
  }

  @override
  Future<void> tulis(String kunci, String json, DateTime ditarikPada) =>
      _db
          .into(_db.salinan)
          .insertOnConflictUpdate(
            SalinanCompanion(
              kunci: Value(kunci),
              json: Value(json),
              ditarikPada: Value(ditarikPada),
            ),
          );

  @override
  Future<void> hapusSemua() => _db.delete(_db.salinan).go();
}

/// Implementasi memori untuk test (dan cadangan bila SQLite gagal dibuka).
class SalinanMemori implements SalinanStore {
  final Map<String, Salinan> _m = {};

  @override
  Future<Salinan?> baca(String kunci) async => _m[kunci];

  @override
  Future<void> tulis(String kunci, String json, DateTime ditarikPada) async =>
      _m[kunci] = Salinan(json: json, ditarikPada: ditarikPada);

  @override
  Future<void> hapusSemua() async => _m.clear();

  int get jumlah => _m.length;
}
