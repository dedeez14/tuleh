// Fase 4 (sinkron batch v2) — fondasi antrean TANPA perubahan skema drift:
// badan & galat bisa diperbarui lewat kolom lama, delta stok per baris,
// label jenis baru, id perangkat sinkron sekali per instalasi, dan nomor lokal
// berawalan perangkat.

import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/offline/antrean.dart';
import 'package:tuleh_pos/core/offline/nomor_lokal.dart';
import 'package:tuleh_pos/core/offline/perangkat_sinkron.dart';
import 'package:tuleh_pos/core/offline/salinan_db.dart';
import 'package:tuleh_pos/core/storage/secure_storage.dart';

class _Storage extends SecureStorage {
  _Storage([Map<String, String>? isi]) : m = isi ?? {}, super(const FlutterSecureStorage());
  final Map<String, String> m;
  int tulis = 0;
  @override
  Future<String?> bacaNilai(String k) async => m[k];
  @override
  Future<void> tulisNilai(String k, String? v) async {
    tulis++;
    v == null ? m.remove(k) : m[k] = v;
  }
}

PesanAntrean _p(String ref, {String jenis = 'CHECKOUT', Map<String, dynamic> body = const {'a': 1}}) => PesanAntrean(
  urut: 0, clientRef: ref, jenis: jenis, path: '/transaksi/checkout', body: body,
  dibuat: DateTime(2026, 9, 24, 10), tokoId: 'T1',
);

void main() {
  group('AntreanStore fase 4 (memori & drift sama)', () {
    for (final (nama, buat) in <(String, AntreanStore Function())>[
      ('memori', AntreanMemori.new),
      ('drift', () => AntreanDriftStore(SalinanDb(NativeDatabase.memory()))),
    ]) {
      test('$nama: perbarui(body:) menimpa badan; hapusGalat mengosongkan galat', () async {
        final st = buat();
        await st.antrekan(_p('c1'));
        await st.perbarui('c1', galatTerakhir: '[VALIDASI] Produk belum punya satuan.');
        expect((await st.cari('c1'))!.galatTerakhir, '[VALIDASI] Produk belum punya satuan.');
        await st.perbarui('c1', body: {'a': 1, '_kirim_ulang': 1}, hapusGalat: true);
        final p = (await st.cari('c1'))!;
        expect(p.body, {'a': 1, '_kirim_ulang': 1});
        expect(p.galatTerakhir, isNull);
        await st.perbarui('c1', status: StatusAntrean.tinjau);
        expect((await st.cari('c1'))!.body['_kirim_ulang'], 1, reason: 'body tidak disentuh bila null');
      });

      test('$nama: deltaStokUntuk hanya milik satu baris', () async {
        final st = buat();
        await st.antrekan(_p('c1'), deltaStok: {'P1': -2, 'P2': -1});
        await st.antrekan(_p('c2'), deltaStok: {'P1': -5});
        expect(await st.deltaStokUntuk('c1'), {'P1': -2.0, 'P2': -1.0});
        expect(await st.deltaStokUntuk('c2'), {'P1': -5.0});
        expect(await st.deltaStokUntuk('tidak-ada'), isEmpty);
      });
    }
  });

  test('label jenis antrean Fase 4', () {
    expect(_p('r', jenis: 'REFUND').label, 'Refund');
    expect(_p('b', jenis: 'BATAL').label, 'Pembatalan');
    expect(_p('o', jenis: 'ORDER_TRANSISI').label, 'Pesanan');
    expect(_p('y', jenis: 'BILL_BAYAR').label, 'Bayar bon');
  });

  group('id perangkat sinkron', () {
    test('UUID v4 dibuat sekali, disimpan, dan dipakai ulang (juga oleh instans penyimpanan lain)', () async {
      final isi = <String, String>{};
      final s1 = _Storage(isi);
      final id = await idPerangkatSinkron(s1, acak: Random(7));
      expect(id, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
      expect(isi[kunciPerangkatSinkron], id);
      expect(await idPerangkatSinkron(s1), id);
      expect(s1.tulis, 1, reason: 'tidak ditulis ulang');
      final s2 = _Storage(isi); // isolate latar: instans lain, penyimpanan sama
      expect(await idPerangkatSinkron(s2), id);
      expect(s2.tulis, 0);
    });

    test('pemanggil serentak mendapat id yang sama', () async {
      final s = _Storage();
      final hasil = await Future.wait([idPerangkatSinkron(s), idPerangkatSinkron(s), idPerangkatSinkron(s)]);
      expect(hasil.toSet(), hasLength(1));
      expect(s.tulis, 1);
    });

    test('awalan perangkat = 4 huruf/angka pertama, huruf besar', () {
      expect(awalanDariIdPerangkat('3b9d6c1e-6a0f-4a55'), '3B9D');
      expect(awalanDariIdPerangkat('a-b'), 'AB');
      expect(awalanDariIdPerangkat('--'), '');
    });
  });

  group('nomor lokal', () {
    test('tanpa awalan = format lama', () async {
      final n = NomorLokal(_Storage());
      expect(await n.berikutnya(sekarang: DateTime(2026, 9, 24)), 'L-260924-0001');
    });

    test('awalanPerangkat: L-<4 karakter perangkat>-yyMMdd-NNNN (≤ 30 karakter)', () async {
      final s = _Storage({kunciPerangkatSinkron: '3b9d6c1e-6a0f-4a55-9f7e-2c7f0d6e8a11'});
      final n = NomorLokal(s, awalanPerangkat: true);
      expect(await n.berikutnya(sekarang: DateTime(2026, 9, 24)), 'L-3B9D-260924-0001');
      final kedua = await n.berikutnya(sekarang: DateTime(2026, 9, 24));
      expect(kedua, 'L-3B9D-260924-0002');
      expect(kedua.length, lessThanOrEqualTo(30));
    });
  });
}
