// Fase 4: rujukan transaksi lokal & urutan kausal di pengurai (rancangan §C.7 +
// kritik B-2/B-7/B-8/B-14) — refund/pembatalan atas checkout yang belum
// terkirim, penahan stok masuk → penjualan per toko, kaskade TINJAU induk→anak.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/offline/antrean.dart';
import 'package:tuleh_pos/core/offline/koneksi.dart';
import 'package:tuleh_pos/core/offline/operasi_batch.dart';
import 'package:tuleh_pos/core/offline/pemulih_tinjau.dart';
import 'package:tuleh_pos/core/offline/pengurai.dart';
import 'package:tuleh_pos/core/offline/rujukan_lokal.dart';

class _Penanda implements PenandaKoneksi {
  bool offlineNilai = false;
  @override
  bool get offline => offlineNilai;
  @override
  void tandaiOffline({DateTime? ditarikPada}) => offlineNilai = true;
  @override
  void tandaiOnline() => offlineNilai = false;
}

class _Server implements HttpClientAdapter {
  _Server(this.jawab);
  final Object Function(RequestOptions o) jawab;
  final List<RequestOptions> diminta = [];

  List<RequestOptions> get kiriman => [for (final o in diminta) if (o.method == 'POST') o];
  List<List<String>> get batch => [
    for (final o in kiriman)
      if (o.path == jalurSyncBatch) [for (final op in (o.data as Map)['operations'] as List) '${(op as Map)['idempotency_key']}'],
  ];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? s, Future<void>? c) async {
    diminta.add(o);
    final r = jawab(o);
    if (r is DioExceptionType) throw DioException(requestOptions: o, type: r);
    final (int code, Object body) = r as (int, Object);
    return ResponseBody.fromString(jsonEncode(body), code, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }

  @override
  void close({bool force = false}) {}
}

List<Map<String, dynamic>> _ops(RequestOptions o) => [
  for (final x in (o.data as Map)['operations'] as List) Map<String, dynamic>.from(x as Map),
];

/// Jawaban batch: semua diterima kecuali yang ada di [tolak] (key → {kode, retriable, message}).
(int, Object) _hasilBatch(RequestOptions o, [Map<String, Map<String, Object>> tolak = const {}]) => (200, {
  'success': true,
  'data': {
    'versi': 2,
    'results': [
      for (final op in _ops(o))
        if (tolak[op['idempotency_key']] case final t?)
          {'idempotency_key': op['idempotency_key'], 'type': op['type'], 'accepted': false, ...t}
        else
          {
            'idempotency_key': op['idempotency_key'], 'type': op['type'], 'accepted': true, 'server_id': 'srv-${op['idempotency_key']}',
            'nomor': 'N-${op['idempotency_key']}', 'kode': 'OK', 'peringatan': <String>[], 'data': null,
          },
    ],
  },
});

Dio _dio(_Server s) => Dio(BaseOptions(validateStatus: (_) => true))..httpClientAdapter = s;

Future<void> _induk(AntreanStore a, [String ref = 'induk', String toko = 'T1']) => a.antrekan(PesanAntrean(
  urut: 0, clientRef: ref, jenis: 'CHECKOUT', path: '/transaksi/checkout', tokoId: toko, dibuat: DateTime(2026, 9, 24, 9),
  body: {'client_ref': ref, 'items': [{'id_produk': 'P1', 'kuantitas': 1}, {'id_produk': 'P2', 'kuantitas': 2}]},
));

Future<void> _anakRefund(AntreanStore a, [String ref = 'anak', String induk = 'induk']) => a.antrekan(PesanAntrean(
  urut: 0, clientRef: ref, jenis: 'REFUND', path: '/transaksi/lokal:$induk/refund', tokoId: 'T1', dibuat: DateTime(2026, 9, 24, 9, 5),
  body: {'client_ref': ref, 'items': [{'baris': 1, 'kuantitas': 1}], 'metode': 'TUNAI', 'alasan': 'Rusak', 'kembali_stok': true},
));

Future<void> _anakBatal(AntreanStore a, [String ref = 'anak', String induk = 'induk']) => a.antrekan(PesanAntrean(
  urut: 0, clientRef: ref, jenis: 'BATAL', path: '/transaksi/lokal:$induk/batal', tokoId: 'T1', dibuat: DateTime(2026, 9, 24, 9, 5),
  body: {'client_ref': ref, 'alasan': 'Salah input'},
));

PenguraiAntrean _pengurai(
  AntreanStore a,
  _Server s, {
  bool batch = false,
  KonfigSyncBatch konfig = const KonfigSyncBatch(versi: 2),
  DateTime Function()? sekarang,
  Future<BatasAntrean?> Function()? batas,
  bool pemulih = false,
  _Penanda? penanda,
}) {
  final p = PenguraiAntrean(
    store: a,
    dio: _dio(s),
    koneksi: penanda ?? _Penanda(),
    tanpaPemulih: !pemulih,
    konfigBatch: batch ? () async => konfig : null,
    idPerangkat: () async => 'dev-uji',
    sekarang: sekarang ?? () => DateTime(2026, 9, 24, 10),
    batas: batas,
  );
  addTearDown(p.hentikan);
  return p;
}

void main() {
  test('per baris: anak ditahan tanpa penalti selama induk menunggu; induk terkirim → jalur & baris ditulis ulang ke id server', () async {
    final a = AntreanMemori();
    await _induk(a);
    await _anakRefund(a);
    var kini = DateTime(2026, 9, 24, 10);
    await a.perbarui('induk', cobaLagiSetelah: kini.add(const Duration(seconds: 60)));
    final s = _Server((o) => o.path == '/transaksi/checkout'
        ? (201, {'success': true, 'data': {'id': 'SRV1', 'nomor': 'POS-1', 'items': [{'id': 'I-a'}, {'id': 'I-b'}]}})
        : (201, {'success': true, 'data': {'id': 'RF1', 'nomor': 'RFD-1'}}));
    final p = _pengurai(a, s, sekarang: () => kini);
    await p.jalankan();
    expect(s.kiriman, isEmpty, reason: 'induk belum waktunya, anak tertahan');
    expect((await a.cari('anak'))!.percobaan, 0);
    expect((await a.cari('anak'))!.status, StatusAntrean.menunggu);

    kini = kini.add(const Duration(seconds: 60));
    expect(await p.jalankan(), 2);
    expect([for (final o in s.kiriman) o.path], ['/transaksi/checkout', '/transaksi/SRV1/refund']);
    expect((s.kiriman[1].data as Map)['items'], [{'id': 'I-b', 'kuantitas': 1}]);
    expect((await a.cari('anak'))!.hasil!['nomor'], 'RFD-1');
  });

  test('per baris: induk terkirim tanpa rincian item (dipulihkan) → anak TINJAU INDUK_TIDAK_DIKENAL, tidak dikirim', () async {
    final a = AntreanMemori();
    await _induk(a);
    await _anakRefund(a);
    await a.selesai('induk', hasil: {'id': 'SRV2', 'nomor': 'POS-2', 'dipulihkan': true});
    final s = _Server((o) => (201, {'success': true, 'data': <String, dynamic>{}}));
    await _pengurai(a, s).jalankan();
    expect(s.kiriman, isEmpty);
    final anak = (await a.cari('anak'))!;
    expect(anak.status, StatusAntrean.tinjau);
    expect(kodeGalat(anak.galatTerakhir), 'INDUK_TIDAK_DIKENAL');
  });

  test('batch: induk & anak satu segmen → anak merujuk transaksi_ref induk dengan item "baris"', () async {
    final a = AntreanMemori();
    await _induk(a);
    await _anakRefund(a);
    final s = _Server((o) => _hasilBatch(o));
    expect(await _pengurai(a, s, batch: true).jalankan(), 2);
    expect(s.batch, [['induk', 'anak']]);
    final opAnak = _ops(s.kiriman.single)[1];
    expect(opAnak['payload']['transaksi_ref'], 'induk');
    expect(opAnak['payload']['items'], [{'baris': 1, 'kuantitas': 1}]);
  });

  test('batch: induk sedang mundur galat server → anak tidak ikut segmen (tidak memancing PRASYARAT)', () async {
    final a = AntreanMemori();
    await _induk(a);
    await _anakRefund(a);
    await a.perbarui('induk', cobaLagiSetelah: DateTime(2026, 9, 24, 11));
    final s = _Server((o) => _hasilBatch(o));
    await _pengurai(a, s, batch: true).jalankan();
    expect(s.kiriman, isEmpty);
    final anak = (await a.cari('anak'))!;
    expect(anak.percobaan, 0);
    expect(anak.cobaLagiSetelah, isNull);
  });

  test('batch: induk di segmen yang terkirim karena batas segmen → anak dinilai ulang setelah induk dijawab', () async {
    // Batas 1 op per segmen: induk pergi sendirian; anak (yang tadi melihat
    // induknya di segmen) diputuskan ulang menurut jawaban induk.
    final kasus = <(Map<String, Map<String, Object>>, List<List<String>>, Future<void> Function(AntreanStore))>[
      (const {}, [['induk'], ['anak']], (a) async {
        final anak = (await a.cari('anak'))!;
        expect(anak.status, StatusAntrean.terkirim);
      }),
      (const {'induk': {'kode': 'VALIDASI', 'retriable': false, 'message': 'Produk belum punya satuan.'}}, [['induk']], (a) async {
        final anak = (await a.cari('anak'))!;
        expect(anak.status, StatusAntrean.tinjau);
        expect(kodeGalat(anak.galatTerakhir), 'INDUK_TINJAU');
      }),
      (const {'induk': {'kode': 'GALAT_SERVER', 'retriable': true, 'message': 'Galat.'}}, [['induk']], (a) async {
        final anak = (await a.cari('anak'))!;
        expect(anak.status, StatusAntrean.menunggu);
        expect(anak.percobaan, 0, reason: 'menunggu induk tanpa penalti');
        expect(anak.cobaLagiSetelah, isNull);
        expect(anak.galatTerakhir, isNull);
      }),
    ];
    for (final (tolak, harap, cek) in kasus) {
      final a = AntreanMemori();
      await _induk(a);
      await _anakRefund(a);
      final s = _Server((o) => _hasilBatch(o, tolak));
      await _pengurai(a, s, batch: true, konfig: const KonfigSyncBatch(versi: 2, maksOperasi: 1)).jalankan();
      expect(s.batch, harap, reason: '$tolak');
      if (harap.length == 2) expect(_ops(s.kiriman[1]).single['payload']['transaksi_ref'], 'induk');
      await cek(a);
    }
  });

  test('kaskade: induk ditolak (VALIDASI) → anak TINJAU INDUK_TINJAU; kirim ulang induk memulihkan anak & keduanya terkirim', () async {
    final a = AntreanMemori();
    await _induk(a);
    await _anakRefund(a);
    var tolakInduk = true;
    final s = _Server((o) => _hasilBatch(o, tolakInduk
        ? {
            'induk': {'kode': 'VALIDASI', 'retriable': false, 'message': 'Produk belum punya satuan.'},
            'anak': {'kode': 'PRASYARAT', 'retriable': true, 'message': 'Transaksi asal belum tercatat.'},
          }
        : const {}));
    final p = _pengurai(a, s, batch: true);
    await p.jalankan();
    expect((await a.cari('induk'))!.status, StatusAntrean.tinjau);
    final anak = (await a.cari('anak'))!;
    expect(anak.status, StatusAntrean.tinjau);
    expect(kodeGalat(anak.galatTerakhir), 'INDUK_TINJAU');

    tolakInduk = false;
    await p.kirimUlang('induk');
    expect(s.batch[1], ['induk', 'anak']);
    expect((await a.cari('induk'))!.status, StatusAntrean.terkirim);
    expect((await a.cari('anak'))!.status, StatusAntrean.terkirim);
  });

  test('kirim ulang induk hanya memulihkan anak berujukan PERSIS induk itu (bukan awalan ref yang sama)', () async {
    final a = AntreanMemori();
    await _induk(a);
    await _induk(a, 'induk2');
    await _anakRefund(a, 'anak2', 'induk2');
    for (final r in ['induk', 'induk2', 'anak2']) {
      await a.perbarui(r, status: StatusAntrean.tinjau, percobaan: 3, galatTerakhir: galatBerkode('INDUK_TINJAU', PenguraiAntrean.pesanIndukTinjau));
    }
    final s = _Server((o) => _hasilBatch(o));
    await _pengurai(a, s, batch: true).kirimUlang('induk');
    expect(s.batch, [['induk']]);
    final anak2 = (await a.cari('anak2'))!;
    expect(anak2.status, StatusAntrean.tinjau);
    expect(anak2.percobaan, 3, reason: 'tidak ikut dikembalikan ke antrean');
  });

  test('kaskade per baris: induk ditolak 422 → anak yang menunggu ikut TINJAU INDUK_TINJAU', () async {
    final a = AntreanMemori();
    await _induk(a);
    await _anakRefund(a);
    await a.perbarui('anak', cobaLagiSetelah: DateTime(2026, 9, 24, 12));
    final s = _Server((o) => (422, {'success': false, 'message': 'Data tidak valid.'}));
    await _pengurai(a, s).jalankan();
    expect((await a.cari('induk'))!.status, StatusAntrean.tinjau);
    expect(kodeGalat((await a.cari('anak'))!.galatTerakhir), 'INDUK_TINJAU');
    expect(s.kiriman, hasLength(1), reason: 'anak tidak dikirim');
  });

  test('anak PRASYARAT dibebaskan dari jeda panjang begitu induk diterima', () async {
    final a = AntreanMemori();
    await _induk(a);
    await _anakRefund(a);
    var kini = DateTime(2026, 9, 24, 10);
    var putaran = 0;
    final s = _Server((o) {
      putaran++;
      return putaran == 1
          ? _hasilBatch(o, {
              'induk': {'kode': 'GALAT_SERVER', 'retriable': true, 'message': 'Galat.'},
              'anak': {'kode': 'PRASYARAT', 'retriable': true, 'message': 'Belum.'},
            })
          : _hasilBatch(o);
    });
    final p = _pengurai(a, s, batch: true, sekarang: () => kini);
    await p.jalankan();
    expect((await a.cari('anak'))!.cobaLagiSetelah, kini.add(PenguraiAntrean.mundurLama(1)));
    kini = kini.add(PenguraiAntrean.mundur(1));
    await p.jalankan();
    expect(s.batch[1], ['induk'], reason: 'anak masih dalam jeda saat induk dikirim');
    expect((await a.cari('anak'))!.cobaLagiSetelah, isNull, reason: 'dibebaskan setelah induk diterima');
    await p.jalankan();
    expect(s.batch[2], ['anak']);
    expect((await a.cari('anak'))!.status, StatusAntrean.terkirim);
  });

  test('anak satu segmen yang dijawab PRASYARAT padahal induknya diterima di segmen itu → dibebaskan', () async {
    final a = AntreanMemori();
    await _induk(a);
    await _anakRefund(a);
    final s = _Server((o) => _hasilBatch(o, {'anak': {'kode': 'PRASYARAT', 'retriable': true, 'message': 'Belum.'}}));
    await _pengurai(a, s, batch: true).jalankan();
    final anak = (await a.cari('anak'))!;
    expect(anak.status, StatusAntrean.menunggu);
    expect(anak.cobaLagiSetelah, isNull);
  });

  test('penahan kausal: stok masuk toko T yang mundur menahan penjualan toko T sesudahnya, toko lain jalan', () async {
    final a = AntreanMemori();
    await a.antrekan(PesanAntrean(urut: 0, clientRef: 'stok', jenis: 'STOK_MASUK', path: '/inventory/stok-masuk', tokoId: 'T1', body: const {'client_ref': 'stok'}, dibuat: DateTime(2026, 9, 24, 8)));
    await _induk(a, 'jual-t1', 'T1');
    await _induk(a, 'jual-t2', 'T2');
    await a.perbarui('stok', cobaLagiSetelah: DateTime(2026, 9, 24, 11));
    final s = _Server((o) => o.path == jalurSyncBatch ? _hasilBatch(o) : (201, {'success': true, 'data': <String, dynamic>{}}));
    final p = _pengurai(a, s, batch: true);
    await p.jalankan();
    expect(s.batch, [['jual-t2']]);
    await a.perbarui('stok', status: StatusAntrean.tinjau);
    await p.jalankan();
    expect(s.batch[1], ['jual-t1'], reason: 'penahan gugur saat stok masuk ditinjau');
  });

  test('penahan kausal: stok masuk yang terkirim di putaran yang sama langsung melepas penjualan toko itu', () async {
    final a = AntreanMemori();
    await a.antrekan(PesanAntrean(urut: 0, clientRef: 'stok', jenis: 'STOK_MASUK', path: '/inventory/stok-masuk', tokoId: 'T1', body: const {'client_ref': 'stok'}, dibuat: DateTime(2026, 9, 24, 8)));
    await _induk(a, 'jual', 'T1');
    final s = _Server((o) => o.path == jalurSyncBatch ? _hasilBatch(o) : (201, {'success': true, 'data': {'id': 'SM1'}}));
    expect(await _pengurai(a, s, batch: true).jalankan(), 2);
    expect([for (final o in s.kiriman) o.path], ['/inventory/stok-masuk', jalurSyncBatch]);
  });

  test('penahan kausal berlaku juga di mode per baris', () async {
    final a = AntreanMemori();
    await a.antrekan(PesanAntrean(urut: 0, clientRef: 'stok', jenis: 'STOK_MASUK', path: '/inventory/stok-masuk', tokoId: 'T1', body: const {'client_ref': 'stok'}, dibuat: DateTime(2026, 9, 24, 8)));
    await _induk(a, 'jual', 'T1');
    await a.perbarui('stok', cobaLagiSetelah: DateTime(2026, 9, 24, 11));
    final s = _Server((o) => (201, {'success': true, 'data': <String, dynamic>{}}));
    await _pengurai(a, s).jalankan();
    expect(s.kiriman, isEmpty);
  });

  test('anak BATAL: per baris jalur ditulis ulang ke id server (badan apa adanya); batch merujuk transaksi_ref', () async {
    final a = AntreanMemori();
    await _induk(a);
    await _anakBatal(a);
    await a.selesai('induk', hasil: {'id': 'SRV3', 'nomor': 'POS-3'});
    final s = _Server((o) => (201, {'success': true, 'data': {'id': 'BT1', 'nomor': 'BTL-1'}}));
    await _pengurai(a, s).jalankan();
    expect([for (final o in s.kiriman) o.path], ['/transaksi/SRV3/batal']);
    expect(s.kiriman.single.data, {'client_ref': 'anak', 'alasan': 'Salah input'});
    expect((await a.cari('anak'))!.status, StatusAntrean.terkirim);

    final b = AntreanMemori();
    await _induk(b);
    await _anakBatal(b);
    final s2 = _Server((o) => _hasilBatch(o));
    await _pengurai(b, s2, batch: true).jalankan();
    expect(s2.batch, [['induk', 'anak']]);
    final op = _ops(s2.kiriman.single)[1];
    expect(op['type'], 'batal');
    expect(op['payload']['transaksi_ref'], 'induk');
  });

  test('induk sudah dibatalkan dari antrean → anak TINJAU INDUK_TIDAK_DIKENAL (pesanIndukDibatalkan), kedua mode', () async {
    for (final batch in [false, true]) {
      final a = AntreanMemori();
      await _anakRefund(a, 'anak', 'hilang');
      final s = _Server((o) => _hasilBatch(o));
      await _pengurai(a, s, batch: batch).jalankan();
      expect(s.kiriman, isEmpty, reason: 'batch=$batch');
      final anak = (await a.cari('anak'))!;
      expect(anak.status, StatusAntrean.tinjau);
      expect(anak.galatTerakhir, galatBerkode('INDUK_TIDAK_DIKENAL', PenguraiAntrean.pesanIndukDibatalkan), reason: 'batch=$batch');
    }
  });

  test('kaskade dari batas galat server (per baris 503 → TINJAU) → anak INDUK_TINJAU', () async {
    final a = AntreanMemori();
    await _induk(a);
    await _anakRefund(a);
    final s = _Server((o) => (503, {'success': false, 'message': 'Pemeliharaan'}));
    await _pengurai(a, s, batas: () async => const BatasAntrean(maksPercobaanGalatServer: 1)).jalankan();
    expect((await a.cari('induk'))!.status, StatusAntrean.tinjau);
    expect(kodeGalat((await a.cari('anak'))!.galatTerakhir), 'INDUK_TINJAU');
    expect(s.kiriman, hasLength(1));
  });

  test('kaskade dari timeout lewat umur: batch (anak satu segmen yang juga tua) & per baris → anak INDUK_TINJAU; kirim ulang induk memulihkan', () async {
    for (final batch in [true, false]) {
      final a = AntreanMemori();
      await _induk(a);
      await _anakRefund(a);
      var putus = true;
      final penanda = _Penanda();
      final s = _Server((o) => putus
          ? DioExceptionType.receiveTimeout
          : (o.path == jalurSyncBatch
              ? _hasilBatch(o)
              : (201, {'success': true, 'data': {'id': 'S-${(o.data as Map)['client_ref']}', 'items': [{'id': 'I-a'}, {'id': 'I-b'}]}})));
      final p = _pengurai(
        a, s, batch: batch, penanda: penanda,
        sekarang: () => DateTime(2026, 9, 24, 12), batas: () async => const BatasAntrean(maksUmurJam: 2),
      );
      await p.jalankan();
      final induk = (await a.cari('induk'))!;
      expect(induk.status, StatusAntrean.tinjau, reason: 'batch=$batch');
      expect(induk.galatTerakhir, contains('setelah data dikirim'));
      final anak = (await a.cari('anak'))!;
      expect(anak.status, StatusAntrean.tinjau, reason: 'batch=$batch');
      expect(kodeGalat(anak.galatTerakhir), 'INDUK_TINJAU', reason: 'batch=$batch');
      expect(penanda.offline, isFalse, reason: 'timeout bukan offline (batch=$batch)');

      putus = false;
      await p.kirimUlang('induk');
      expect((await a.cari('induk'))!.status, StatusAntrean.terkirim, reason: 'batch=$batch');
      expect((await a.cari('anak'))!.status, StatusAntrean.terkirim, reason: 'batch=$batch');
    }
  });

  test('pemulih asli: induk "mungkin sudah sampai" dipulihkan → anak INDUK_TINJAU ikut kembali & terkirim (per baris/batch × cocok/belum tercatat)', () async {
    for (final batch in [false, true]) {
      for (final cocok in [true, false]) {
        final alasan = 'batch=$batch cocok=$cocok';
        final a = AntreanMemori();
        await _induk(a);
        await _anakBatal(a);
        await a.perbarui('induk', status: StatusAntrean.tinjau, galatTerakhir: '${PenguraiAntrean.pesanTimeoutSetelahKirim} (tertunda lebih dari 2 jam; perlu ditinjau)');
        await a.perbarui('anak', status: StatusAntrean.tinjau, galatTerakhir: galatBerkode('INDUK_TINJAU', PenguraiAntrean.pesanIndukTinjau));
        final s = _Server((o) {
          if (o.method == 'GET' && o.path == '/transaksi') {
            return (200, {
              'success': true,
              'data': [
                if (cocok)
                  {
                    'id': 'SRV-P', 'nomor': 'POS-P', 'grand_total': 0, 'tipe_pembayaran': 'TUNAI', 'status': 'SELESAI',
                    'tanggal': DateTime(2026, 9, 24, 9, 2).toUtc().toIso8601String(),
                  },
              ],
            });
          }
          if (o.path == jalurSyncBatch) return _hasilBatch(o);
          if (o.path == '/transaksi/checkout') return (201, {'success': true, 'data': {'id': 'SRV1', 'nomor': 'POS-1'}});
          return (201, {'success': true, 'data': {'id': 'BT1', 'nomor': 'BTL-1'}});
        });
        await _pengurai(a, s, batch: batch, pemulih: true).jalankan();
        expect((await a.cari('induk'))!.status, StatusAntrean.terkirim, reason: alasan);
        expect((await a.cari('anak'))!.status, StatusAntrean.terkirim, reason: alasan);
        final harap = switch ((batch, cocok)) {
          (false, true) => ['/transaksi/SRV-P/batal'],
          (false, false) => ['/transaksi/checkout', '/transaksi/SRV1/batal'],
          _ => [jalurSyncBatch],
        };
        expect([for (final o in s.kiriman) o.path], harap, reason: alasan);
        if (batch) expect(s.batch.single, cocok ? ['anak'] : ['induk', 'anak'], reason: alasan);
      }
    }
  });

  test('awal putaran: anak INDUK_TINJAU yang induknya kini MENUNGGU pulih; anak PRASYARAT dari induk TERKIRIM lepas jeda & galat', () async {
    final a = AntreanMemori();
    await _induk(a);
    await _anakRefund(a);
    // Induk dikembalikan ke antrean di luar pengurai (mis. pemulih pada isolate lain).
    await a.perbarui('anak', status: StatusAntrean.tinjau, galatTerakhir: galatBerkode('INDUK_TINJAU', PenguraiAntrean.pesanIndukTinjau));
    final s = _Server((o) => _hasilBatch(o));
    await _pengurai(a, s, batch: true).jalankan();
    expect(s.batch, [['induk', 'anak']]);

    final b = AntreanMemori();
    await _induk(b);
    await _anakRefund(b);
    await b.selesai('induk', hasil: {'id': 'SRV1', 'items': [{'id': 'I-a'}, {'id': 'I-b'}]});
    await b.perbarui('anak', percobaan: 1, cobaLagiSetelah: DateTime(2026, 9, 24, 11), galatTerakhir: galatBerkode('PRASYARAT', 'Belum.'));
    final s2 = _Server((o) => (201, {'success': true, 'data': {'id': 'RF1'}}));
    await _pengurai(b, s2).jalankan();
    expect([for (final o in s2.kiriman) o.path], ['/transaksi/SRV1/refund']);
    expect((await b.cari('anak'))!.status, StatusAntrean.terkirim);
  });

  test('awal putaran (paritas desktop): anak INDUK_TINJAU pulih HANYA bila induk MENUNGGU/TERKIRIM — induk MENGIRIM belum diputuskan', () async {
    // Induk MENGIRIM (tertinggal dari putaran yang terputus) → anak tetap TINJAU.
    final a = AntreanMemori();
    await _induk(a);
    await _anakRefund(a);
    await a.perbarui('induk', status: StatusAntrean.mengirim);
    await a.perbarui('anak', status: StatusAntrean.tinjau, galatTerakhir: galatBerkode('INDUK_TINJAU', PenguraiAntrean.pesanIndukTinjau));
    final s = _Server((o) => DioExceptionType.connectionError);
    await _pengurai(a, s).jalankan();
    expect([for (final o in s.kiriman) o.path], ['/transaksi/checkout'], reason: 'induk MENGIRIM tetap dikirim ulang');
    final anak = (await a.cari('anak'))!;
    expect(anak.status, StatusAntrean.tinjau);
    expect(kodeGalat(anak.galatTerakhir), 'INDUK_TINJAU');

    // Induk TERKIRIM → anak pulih dan langsung terkirim atas id server induk.
    final b = AntreanMemori();
    await _induk(b);
    await _anakRefund(b);
    await b.selesai('induk', hasil: {'id': 'SRV1', 'items': [{'id': 'I-a'}, {'id': 'I-b'}]});
    await b.perbarui('anak', status: StatusAntrean.tinjau, galatTerakhir: galatBerkode('INDUK_TINJAU', PenguraiAntrean.pesanIndukTinjau));
    final s2 = _Server((o) => (201, {'success': true, 'data': {'id': 'RF1'}}));
    await _pengurai(b, s2).jalankan();
    expect([for (final o in s2.kiriman) o.path], ['/transaksi/SRV1/refund']);
    expect((await b.cari('anak'))!.status, StatusAntrean.terkirim);
  });

  test('anak PRASYARAT yang dibebaskan: jeda & galat basi dibersihkan', () async {
    final a = AntreanMemori();
    await _induk(a);
    await _anakRefund(a);
    await a.perbarui('anak', percobaan: 1, cobaLagiSetelah: DateTime(2026, 9, 24, 11), galatTerakhir: galatBerkode('PRASYARAT', 'Belum.'));
    final s = _Server((o) => _hasilBatch(o));
    await _pengurai(a, s, batch: true).jalankan();
    expect(s.batch, [['induk']]);
    final anak = (await a.cari('anak'))!;
    expect(anak.cobaLagiSetelah, isNull);
    expect(anak.galatTerakhir, isNull);
  });

  test('baris tertahan penahan kausal tidak memasang timer sendiri: jadwal = jeda penahannya', () async {
    final a = AntreanMemori();
    await a.antrekan(PesanAntrean(urut: 0, clientRef: 'stok', jenis: 'STOK_MASUK', path: '/inventory/stok-masuk', tokoId: 'T1', body: const {'client_ref': 'stok'}, dibuat: DateTime(2026, 9, 24, 8)));
    await _induk(a, 'jual', 'T1');
    await a.perbarui('stok', cobaLagiSetelah: DateTime(2026, 9, 24, 11));
    final s = _Server((o) => (201, {'success': true, 'data': <String, dynamic>{}}));
    final p = _pengurai(a, s);
    await p.jalankan();
    expect(s.kiriman, isEmpty);
    expect(p.jadwalBerikutnya, DateTime(2026, 9, 24, 11));
  });

  test('pulihkanTurunan: hanya TINJAU menunggu induk itu (bon lama & INDUK_TINJAU); PemulihTinjau mengenali TINJAU timeout', () async {
    final a = AntreanMemori();
    await _induk(a);
    await _anakRefund(a, 'r1');
    await _anakBatal(a, 'b1');
    await a.antrekan(PesanAntrean(urut: 0, clientRef: 'bon', jenis: 'BILL_BAYAR', path: '/bills/lokal:induk/settle', body: const {}, dibuat: DateTime(2026, 9, 24, 9)));
    await _anakRefund(a, 'lain', 'induk2');
    await a.perbarui('r1', status: StatusAntrean.tinjau, galatTerakhir: galatBerkode('INDUK_TINJAU', PenguraiAntrean.pesanIndukTinjau));
    await a.perbarui('b1', status: StatusAntrean.tinjau, galatTerakhir: galatBerkode('VALIDASI', 'Ditolak.'));
    await a.perbarui('bon', status: StatusAntrean.tinjau, galatTerakhir: PenguraiAntrean.pesanIndukBelumTerkirim);
    await a.perbarui('lain', status: StatusAntrean.tinjau, galatTerakhir: galatBerkode('INDUK_TINJAU', PenguraiAntrean.pesanIndukTinjau));
    expect(await pulihkanTurunan(a, 'induk'), 2);
    expect([for (final r in ['r1', 'b1', 'bon', 'lain']) (await a.cari(r))!.status],
        [StatusAntrean.menunggu, StatusAntrean.tinjau, StatusAntrean.menunggu, StatusAntrean.tinjau]);
    expect((await a.cari('r1'))!.galatTerakhir, isNull);

    await a.perbarui('induk', status: StatusAntrean.tinjau, galatTerakhir: '${PenguraiAntrean.pesanTimeoutSetelahKirim} (tertunda lebih dari 2 jam; perlu ditinjau)');
    expect(PemulihTinjau.layakDipulihkan((await a.cari('induk'))!), isTrue);
  });
}
