import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/offline/salinan_db.dart';
import 'package:tuleh_pos/core/offline/salinan_store.dart';

/// SalinanDriftStore di SQLite memori: tulis, timpa, baca, hapus.
void main() {
  test('tulis/timpa/baca/hapus salinan di SQLite', () async {
    final db = SalinanDb(NativeDatabase.memory());
    addTearDown(db.close);
    final store = SalinanDriftStore(db);

    expect(await store.baca('/produk?toko_id=T1'), isNull);
    final t1 = DateTime(2026, 9, 5, 14, 2);
    await store.tulis('/produk?toko_id=T1', '{"success":true}', t1);
    final s = await store.baca('/produk?toko_id=T1');
    expect(s!.json, '{"success":true}');
    expect(s.ditarikPada, t1);

    // Timpa dengan yang lebih baru (kunci sama → satu baris).
    final t2 = DateTime(2026, 9, 5, 15, 0);
    await store.tulis('/produk?toko_id=T1', '{"success":true,"data":[]}', t2);
    expect((await store.baca('/produk?toko_id=T1'))!.ditarikPada, t2);
    expect((await db.select(db.salinan).get()).length, 1);

    await store.hapusSemua();
    expect(await store.baca('/produk?toko_id=T1'), isNull);
  });
}
