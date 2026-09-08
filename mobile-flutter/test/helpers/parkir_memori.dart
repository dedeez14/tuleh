import 'dart:io';
import 'dart:math';

import 'package:tuleh_pos/features/kasir/data/parkir_store.dart';
import 'package:tuleh_pos/features/kasir/domain/entities/cart_item.dart';
import 'package:tuleh_pos/features/kasir/presentation/controllers/keranjang_meta.dart';

/// Parkir in-memory dengan aturan yang sama (nomor urut, batas, per toko).
///
/// Dipakai tes widget: di dalam `testWidgets`, Future dari I/O berkas nyata
/// tidak pernah selesai (zona async palsu). Perilaku berkasnya diuji terpisah
/// di `kasir_parkir_batal_opname_test.dart`.
class ParkirMemori extends ParkirStore {
  ParkirMemori({DateTime? jam})
    : _jam = jam ?? DateTime(2026, 9, 8, 10, 30),
      super(dir: () async => Directory.systemTemp);

  final DateTime _jam;
  final Map<String, List<KeranjangParkir>> _data = {};
  int _urut = 0;

  List<KeranjangParkir> _bucket(String? tokoId) =>
      _data.putIfAbsent(tokoId ?? '', () => []);

  @override
  Future<List<KeranjangParkir>> daftar(String? tokoId) async =>
      List.of(_bucket(tokoId));

  @override
  Future<KeranjangParkir> simpan(
    String? tokoId, {
    required List<CartItem> items,
    KeranjangMeta meta = const KeranjangMeta(),
  }) async {
    if (items.isEmpty) throw ArgumentError('Keranjang kosong.');
    final bucket = _bucket(tokoId);
    if (bucket.length >= maksParkir) throw const ParkirPenuh();
    final entri = KeranjangParkir(
      id: 'p${++_urut}',
      nomor: (bucket.fold<int>(0, (m, p) => max(m, p.nomor)) % 999) + 1,
      waktu: _jam,
      items: List.of(items),
      meta: meta,
    );
    bucket.add(entri);
    return entri;
  }

  @override
  Future<KeranjangParkir?> ambil(String? tokoId, String id) async {
    final bucket = _bucket(tokoId);
    final i = bucket.indexWhere((p) => p.id == id);
    if (i < 0) return null;
    return bucket.removeAt(i);
  }

  @override
  Future<void> hapus(String? tokoId, String id) async =>
      _bucket(tokoId).removeWhere((p) => p.id == id);
}
