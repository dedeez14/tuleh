// Fase 4: pengurai mode batch v2 (rancangan §B.4/§B.6/§I.2 + kritik A-02/A-03/
// A-11/B-1/B-3/B-16) — segmen berurutan dengan baris per baris di tengah,
// pemetaan semua kode dari fikstur kontrak bersama server↔app, jawaban batch
// non-200, jalan kembali ke per baris, kirim ulang, detak kunci.

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/network/api_client.dart' show ekstraTanpaTokoAktif;
import 'package:tuleh_pos/core/offline/antrean.dart';
import 'package:tuleh_pos/core/offline/koneksi.dart';
import 'package:tuleh_pos/core/offline/operasi_batch.dart';
import 'package:tuleh_pos/core/offline/pemulih_tinjau.dart';
import 'package:tuleh_pos/core/offline/pengurai.dart';
import 'package:tuleh_pos/core/offline/salinan_interceptor.dart';
import 'package:tuleh_pos/core/offline/sinkron_latar.dart';

class _Penanda implements PenandaKoneksi {
  bool offlineNilai = false;
  @override
  bool get offline => offlineNilai;
  @override
  void tandaiOffline({DateTime? ditarikPada}) => offlineNilai = true;
  @override
  void tandaiOnline() => offlineNilai = false;
}

/// Jawaban server tiruan: (status, badan) atau DioExceptionType.
class _Server implements HttpClientAdapter {
  _Server([Object Function(RequestOptions o)? jawab]) : jawab = jawab ?? _terimaSemua;
  Object Function(RequestOptions o) jawab;
  final List<RequestOptions> diminta = [];

  List<Map<String, dynamic>> get batch => [
    for (final o in diminta)
      if (o.path == jalurSyncBatch) Map<String, dynamic>.from(o.data as Map),
  ];

  int get bacaConfig => diminta.where((o) => o.method == 'GET' && o.path == '/config').length;

  List<String> get log => [
    for (final o in diminta)
      if (o.method == 'POST')
        o.path == jalurSyncBatch
            ? 'batch:${((o.data as Map)['operations'] as List).map((x) => (x as Map)['idempotency_key']).join(',')}'
            : 'baris:${(o.data as Map)['client_ref']}',
  ];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? s, Future<void>? c) async {
    diminta.add(o);
    final r = jawab(o);
    if (r is DioExceptionType) throw DioException(requestOptions: o, type: r);
    // (status, badan) atau (status, badan, header tambahan) — mis. Retry-After.
    final (int code, Object body, Map<String, List<String>> kepala) = switch (r) {
      (final int c, final Object b, final Map<String, List<String>> h) => (c, b, h),
      (final int c, final Object b) => (c, b, const <String, List<String>>{}),
      _ => throw StateError('Jawaban tiruan tidak dikenal: $r'),
    };
    return ResponseBody.fromString(
      jsonEncode(body),
      code,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType], ...kepala},
    );
  }

  @override
  void close({bool force = false}) {}
}

List<Map<String, dynamic>> _ops(RequestOptions o) => [
  for (final x in (o.data as Map)['operations'] as List) Map<String, dynamic>.from(x as Map),
];

Map<String, dynamic> _item(Map<String, dynamic> op, {String kode = 'OK', bool? retriable, String? message, List<String> peringatan = const []}) {
  final diterima = kode == 'OK';
  final pesan = message ?? (diterima ? 'Sinkronisasi diterima.' : 'Ditolak ($kode).');
  return {
    'idempotency_key': op['idempotency_key'], 'device_id': op['device_id'], 'device_seq': op['device_seq'], 'type': op['type'],
    'accepted': diterima, 'server_id': diterima ? 'srv-${op['idempotency_key']}' : null, 'nomor': diterima ? 'N-${op['idempotency_key']}' : null,
    'kode': kode, 'retriable': retriable ?? false, 'message': pesan, 'reason': diterima ? null : pesan,
    'idempoten': false, 'peringatan': peringatan, 'data': null,
  };
}

(int, Object) _jawabBatch(List<Map<String, dynamic>> results) => (200, {
  'success': true, 'message': 'Sinkronisasi selesai.', 'meta': {'sidik': 'x'}, 'errors': null,
  'data': {'versi': 2, 'accepted': results.where((r) => r['accepted'] == true).length, 'rejected': 0, 'ditunda': 0, 'results': results},
});

Object _terimaSemua(RequestOptions o) {
  if (o.path == jalurSyncBatch) return _jawabBatch([for (final op in _ops(o)) _item(op)]);
  if (o.method == 'GET') return (200, {'success': true, 'data': {'sync_batch': {'versi': 2}}});
  final ref = (o.data as Map?)?['client_ref'];
  return (201, {'success': true, 'data': {'id': 'S-$ref', 'nomor': 'B-$ref'}});
}

Dio _dio(_Server s) => Dio(BaseOptions(validateStatus: (_) => true))..httpClientAdapter = s;

String _jalur(String jenis, String ref) => switch (jenis) {
  'CHECKOUT' => '/transaksi/checkout',
  'REFUND' => '/transaksi/T-$ref/refund',
  'BATAL' => '/transaksi/T-$ref/batal',
  'BILL_BAYAR' => '/bills/B-$ref/settle',
  'ORDER_TRANSISI' => '/orders/O-$ref/transition',
  'PENGELUARAN' => '/pengeluaran',
  _ => '/inventory/stok-masuk',
};

Future<void> _baris(AntreanStore a, String ref, {String jenis = 'CHECKOUT', String? pemilik, String? path, Map<String, dynamic>? body}) =>
    a.antrekan(PesanAntrean(
      urut: 0, clientRef: ref, jenis: jenis, path: path ?? _jalur(jenis, ref),
      body: body ?? {'client_ref': ref}, dibuat: DateTime(2026, 9, 24, 9), tokoId: 'T1', pemilik: pemilik,
    ));

final _kini = DateTime(2026, 9, 24, 10);

PenguraiAntrean _pengurai(
  AntreanStore a,
  _Server s, {
  KonfigSyncBatch? konfig = const KonfigSyncBatch(versi: 2),
  bool konfigDariServer = false,
  DateTime Function()? sekarang,
  Future<BatasAntrean?> Function()? batas,
  KunciPengurai? kunci,
  String? Function()? pemilik,
  _Penanda? penanda,
}) {
  final dio = _dio(s);
  final p = PenguraiAntrean(
    store: a,
    dio: dio,
    koneksi: penanda ?? _Penanda(),
    tanpaPemulih: true,
    konfigBatch: konfigDariServer ? () => ambilKonfigSyncBatch(dio) : (konfig == null ? null : () async => konfig),
    idPerangkat: () async => 'dev-uji',
    sekarang: sekarang ?? () => _kini,
    batas: batas,
    kunci: kunci,
    pemilik: pemilik,
  );
  addTearDown(p.hentikan);
  return p;
}

/// Sikap app per kode (rancangan §B.4) — dipakai tes fikstur & tes semua kode.
void _cekPemetaan(PesanAntrean p, Map<String, dynamic> r, DateTime kini) {
  final kode = r['kode'] as String;
  final alasan = '${r['idempotency_key']} ($kode)';
  if (r['accepted'] == true) {
    expect(p.status, StatusAntrean.terkirim, reason: alasan);
    expect(p.hasil!['id'], r['server_id'], reason: alasan);
    expect(p.hasil!['nomor'], r['nomor'], reason: alasan);
    expect(p.hasil!['peringatan'], r['peringatan'], reason: alasan);
    expect(p.hasil!['idempoten'], r['idempoten'], reason: alasan);
  } else if (kode == 'DITUNDA') {
    expect(p.status, StatusAntrean.menunggu, reason: alasan);
    expect(p.cobaLagiSetelah, kini.add(PenguraiAntrean.jedaTunda), reason: alasan);
    expect(p.percobaan, 0, reason: '$alasan: tidak menaikkan percobaan');
    expect(kodeGalat(p.galatTerakhir), 'DITUNDA', reason: alasan);
  } else if (kode == 'GALAT_SERVER') {
    expect(p.status, StatusAntrean.menunggu, reason: alasan);
    expect(p.galatServer, 1, reason: alasan);
    expect(p.cobaLagiSetelah, kini.add(PenguraiAntrean.mundur(1)), reason: alasan);
    expect(kodeGalat(p.galatTerakhir), 'GALAT_SERVER', reason: alasan);
  } else if (kode == 'LANGGANAN') {
    expect(p.status, StatusAntrean.menunggu, reason: alasan);
    expect(p.percobaan, 0, reason: alasan);
    expect(kodeGalat(p.galatTerakhir), 'LANGGANAN', reason: alasan);
  } else if (r['retriable'] == true) {
    expect(p.status, StatusAntrean.menunggu, reason: alasan);
    expect(p.percobaan, 1, reason: alasan);
    expect(p.cobaLagiSetelah, kini.add(PenguraiAntrean.mundurLama(1)), reason: alasan);
    expect(kodeGalat(p.galatTerakhir), kode, reason: alasan);
  } else {
    expect(p.status, StatusAntrean.tinjau, reason: alasan);
    expect(kodeGalat(p.galatTerakhir), kode, reason: alasan);
    expect(pesanGalat(p.galatTerakhir!), contains(r['message'] as String), reason: alasan);
  }
}

Map<String, dynamic> _fikstur() => jsonDecode(File('test/fikstur/sync-batch-v2.json').readAsStringSync()) as Map<String, dynamic>;

const _jenisDari = {'checkout': 'CHECKOUT', 'refund': 'REFUND', 'batal': 'BATAL', 'bills.settle': 'BILL_BAYAR', 'orders.transition': 'ORDER_TRANSISI'};

void main() {
  test('tanpa konfigBatch → jalur per baris lama, tanpa GET /config', () async {
    final a = AntreanMemori();
    await _baris(a, 'c1');
    await _baris(a, 'c2');
    final s = _Server();
    expect(await _pengurai(a, s, konfig: null).jalankan(), 2);
    expect(s.log, ['baris:c1', 'baris:c2']);
    expect(s.bacaConfig, 0);
  });

  test('/config tanpa sync_batch → per baris; /config dibaca sekali per 5 menit', () async {
    final a = AntreanMemori();
    await _baris(a, 'c1');
    final s = _Server((o) => o.method == 'GET' ? (200, {'success': true, 'data': {'antrean_maks_umur_jam': null}}) : _terimaSemua(o));
    final p = _pengurai(a, s, konfigDariServer: true);
    await p.jalankan();
    await _baris(a, 'c2');
    await p.jalankan();
    expect(s.log, ['baris:c1', 'baris:c2']);
    expect(s.bacaConfig, 1);
  });

  test('segmen berurutan: baris non-batch memotong segmen dan dikirim per baris di posisinya', () async {
    final a = AntreanMemori();
    await _baris(a, 'c1');
    await _baris(a, 'r1', jenis: 'REFUND');
    await _baris(a, 'x1', jenis: 'PENGELUARAN');
    await _baris(a, 'c2');
    final s = _Server();
    expect(await _pengurai(a, s).jalankan(), 4);
    expect(s.log, ['batch:c1,r1', 'baris:x1', 'batch:c2']);
    final b = s.batch.first;
    expect(b['client_ref'], clientRefBatch('dev-uji', [(await a.cari('c1'))!, (await a.cari('r1'))!]));
    expect(b['client_ref'], matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(b['device_id'], 'dev-uji');
    final ops = (b['operations'] as List).cast<Map>();
    expect([for (final op in ops) [op['idempotency_key'], op['type'], op['device_seq']]], [['c1', 'checkout', 1], ['r1', 'refund', 2]]);
    expect(ops[0]['payload']['offline'], isTrue);
    expect(ops[0]['payload']['toko_id'], 'T1');
    expect(ops[1]['payload']['transaksi_id'], 'T-r1');
    expect((await a.cari('c1'))!.status, StatusAntrean.terkirim);
    expect((await a.cari('c1'))!.hasil!['id'], 'srv-c1');
    expect((await a.cari('x1'))!.hasil!['nomor'], 'B-x1');
  });

  test('pemetaan hasil fikstur kontrak bersama (POS_DOCS/fikstur/sync-batch-v2.json)', () async {
    final respons = _fikstur()['respons'] as Map<String, dynamic>;
    final results = [for (final r in (respons['data'] as Map)['results'] as List) Map<String, dynamic>.from(r as Map)];
    final dipakai = results.where((r) => _jenisDari.containsKey(r['type'])).toList();
    expect(dipakai, isNotEmpty);
    final a = AntreanMemori();
    for (final r in dipakai) {
      await _baris(a, r['idempotency_key'] as String, jenis: _jenisDari[r['type']]!);
    }
    final s = _Server((o) => o.path == jalurSyncBatch ? (200, respons) : _terimaSemua(o));
    await _pengurai(a, s).jalankan();
    for (final r in dipakai) {
      _cekPemetaan((await a.cari(r['idempotency_key'] as String))!, r, _kini);
    }
  });

  test('semua kode kontrak (tabel kode fikstur) + hasil hilang dipetakan sesuai sikap app', () async {
    final kode = Map<String, dynamic>.from(_fikstur()['kode'] as Map);
    expect(kode.keys, containsAll(['OK', 'VALIDASI', 'OTORISASI_WAJIB', 'PRASYARAT', 'DITUNDA', 'LANGGANAN', 'GALAT_SERVER', 'PELUNASAN_HARUS_REFUND']));
    final a = AntreanMemori();
    for (final k in kode.keys) {
      await _baris(a, 'k-$k');
    }
    await _baris(a, 'k-hilang');
    final hasil = <String, Map<String, dynamic>>{};
    final s = _Server((o) {
      if (o.path != jalurSyncBatch) return _terimaSemua(o);
      final results = <Map<String, dynamic>>[];
      for (final op in _ops(o)) {
        final k = (op['idempotency_key'] as String).substring(2);
        if (k == 'hilang') continue;
        final r = _item(op, kode: k, retriable: kode[k] as bool);
        hasil[op['idempotency_key'] as String] = r;
        results.add(r);
      }
      return _jawabBatch(results);
    });
    await _pengurai(a, s).jalankan();
    for (final e in hasil.entries) {
      _cekPemetaan((await a.cari(e.key))!, e.value, _kini);
    }
    final hilang = (await a.cari('k-hilang'))!;
    expect(hilang.status, StatusAntrean.menunggu);
    expect(hilang.galatServer, 1);
    expect(kodeGalat(hilang.galatTerakhir), 'GALAT_SERVER');
  });

  test('jeda panjang naik bertingkat untuk kode retriable berulang; umur lewat batas /config → TINJAU', () async {
    final a = AntreanMemori();
    await _baris(a, 'k');
    var kini = _kini;
    final s = _Server((o) => o.path == jalurSyncBatch
        ? _jawabBatch([for (final op in _ops(o)) _item(op, kode: 'PRASYARAT', retriable: true, message: 'Transaksi asal belum tercatat.')])
        : _terimaSemua(o));
    final p = _pengurai(a, s, sekarang: () => kini, batas: () async => const BatasAntrean(maksUmurJam: 2));
    await p.jalankan();
    expect((await a.cari('k'))!.cobaLagiSetelah, kini.add(const Duration(minutes: 1)));
    kini = kini.add(const Duration(minutes: 1));
    await p.jalankan();
    expect((await a.cari('k'))!.cobaLagiSetelah, kini.add(const Duration(minutes: 5)));
    expect((await a.cari('k'))!.percobaan, 2);
    kini = DateTime(2026, 9, 24, 11, 0, 1); // baris dibuat 09:00 → umur > 2 jam
    await p.jalankan();
    final k = (await a.cari('k'))!;
    expect(k.status, StatusAntrean.tinjau);
    expect(kodeGalat(k.galatTerakhir), 'PRASYARAT');
    expect(k.galatTerakhir, contains('lebih dari 2 jam'));
  });

  test('HTTP batch 401/402/426/jaringan/timeout/429/5xx: semua baris segmen diperlakukan sama, satu kiriman, tanpa TINJAU', () async {
    final kasus = <(Object, void Function(PesanAntrean, _Penanda))>[
      ((401, {'success': false, 'message': 'Unauthenticated.'}), (p, _) {
        expect(p.status, StatusAntrean.menunggu);
        expect(p.percobaan, 0);
        expect(p.galatTerakhir, contains('Sesi berakhir'));
      }),
      ((402, {'success': false, 'message': 'Langganan usaha Anda berakhir.', 'errors': {'langganan': ['BERAKHIR']}}), (p, _) {
        expect(p.galatTerakhir, 'Langganan usaha Anda berakhir.');
        expect(p.percobaan, 0);
      }),
      ((426, {'success': false, 'message': 'Perbarui'}), (p, _) => expect(p.galatTerakhir, contains('perlu diperbarui'))),
      (DioExceptionType.connectionError, (p, k) {
        expect(p.status, StatusAntrean.menunggu);
        expect(p.percobaan, 1);
        expect(p.cobaLagiSetelah, _kini.add(PenguraiAntrean.mundur(1)));
        expect(k.offline, isTrue);
      }),
      // Timeout setelah terkirim: mundur per baris TANPA menandai offline & tanpa galat server (paritas desktop TIMEOUT).
      (DioExceptionType.receiveTimeout, (p, k) {
        expect(p.status, StatusAntrean.menunggu);
        expect(p.percobaan, 1);
        expect(p.galatServer, 0);
        expect(p.cobaLagiSetelah, _kini.add(PenguraiAntrean.mundur(1)));
        expect(p.galatTerakhir, contains('tidak menjawab tepat waktu'));
        expect(k.offline, isFalse);
      }),
      // 429 tanpa kode = batas laju: jeda jaringan untuk seluruh segmen (paritas desktop & kontrak §13.5).
      ((429, {'success': false, 'message': 'Too Many Attempts.'}), (p, k) {
        expect(p.status, StatusAntrean.menunggu);
        expect(p.percobaan, 1);
        expect(p.galatServer, 0);
        expect(p.galatTerakhir, contains('membatasi permintaan'));
        expect(k.offline, isTrue);
      }),
      ((503, {'success': false, 'message': 'Pemeliharaan'}), (p, _) {
        expect(p.galatServer, 1);
        expect(p.galatTerakhir, contains('HTTP 503'));
      }),
    ];
    for (final (jawab, cek) in kasus) {
      final a = AntreanMemori();
      await _baris(a, 'c1');
      await _baris(a, 'c2');
      final penanda = _Penanda();
      final s = _Server((o) => o.path == jalurSyncBatch ? jawab : _terimaSemua(o));
      expect(await _pengurai(a, s, penanda: penanda).jalankan(), 0, reason: '$jawab');
      expect(s.log, ['batch:c1,c2'], reason: '$jawab: satu kiriman');
      for (final r in ['c1', 'c2']) {
        final p = (await a.cari(r))!;
        expect(p.status, isNot(StatusAntrean.tinjau), reason: '$jawab');
        cek(p, penanda);
      }
    }
  });

  test('422 amplop cacat → mundur per baris sebagai galat server (bukan TINJAU)', () async {
    final a = AntreanMemori();
    await _baris(a, 'c1');
    final s = _Server((o) => o.path == jalurSyncBatch ? (422, {'success': false, 'message': 'Data tidak valid.', 'errors': {'operations': ['Wajib.']}}) : _terimaSemua(o));
    await _pengurai(a, s).jalankan();
    final c1 = (await a.cari('c1'))!;
    expect(c1.status, StatusAntrean.menunggu);
    expect(c1.galatServer, 1);
  });

  test('413 → segmen dibelah dua; satu baris yang tetap terlalu besar → TINJAU BATCH_TERLALU_BESAR', () async {
    final a = AntreanMemori();
    for (final r in ['a', 'b', 'c', 'd']) {
      await _baris(a, r);
    }
    final ukuran = <int>[];
    final s = _Server((o) {
      if (o.path != jalurSyncBatch) return _terimaSemua(o);
      ukuran.add(_ops(o).length);
      return _ops(o).length > 2
          ? (413, {'success': false, 'message': 'Terlalu besar', 'errors': {'kode': ['BATCH_TERLALU_BESAR']}})
          : _terimaSemua(o);
    });
    final p = _pengurai(a, s);
    await p.jalankan();
    expect([for (final x in await a.semua()) x.status], List.filled(4, StatusAntrean.menunggu));
    await p.jalankan();
    expect(ukuran, [4, 2, 2]);
    expect((await a.semua()).every((x) => x.status == StatusAntrean.terkirim), isTrue);

    final b = AntreanMemori();
    await _baris(b, 'raksasa');
    final s2 = _Server((o) => o.path == jalurSyncBatch ? (413, {'success': false, 'message': 'Payload Too Large'}) : _terimaSemua(o));
    await _pengurai(b, s2).jalankan();
    final r = (await b.cari('raksasa'))!;
    expect(r.status, StatusAntrean.tinjau);
    expect(kodeGalat(r.galatTerakhir), 'BATCH_TERLALU_BESAR');
  });

  test('409 BATCH_REF_BENTROK → kirim ulang SEKALI dengan ref bergaram', () async {
    final a = AntreanMemori();
    await _baris(a, 'c1');
    final s = _Server();
    s.jawab = (o) => o.path == jalurSyncBatch && s.batch.length == 1
        ? (409, {'success': false, 'message': 'Bentrok', 'errors': {'kode': ['BATCH_REF_BENTROK']}})
        : _terimaSemua(o);
    await _pengurai(a, s).jalankan();
    expect(s.batch, hasLength(2));
    final baris = [(await a.cari('c1'))!];
    expect(s.batch[0]['client_ref'], clientRefBatch('dev-uji', baris));
    expect(s.batch[1]['client_ref'], clientRefBatch('dev-uji', baris, garam: 1));
    expect(baris.single.status, StatusAntrean.terkirim);
  });

  test('429 BATCH_BERJALAN → tunggu Retry-After (bawaan 5 dtk) tanpa menaikkan percobaan; baris sesudahnya tidak dikirim putaran ini', () async {
    // Kontrak §13.5 / K-7: server mengirim `Retry-After: 5`; tanpa header = 5 dtk (paritas desktop).
    expect(PenguraiAntrean.jedaBatchBerjalan, const Duration(seconds: 5));
    for (final (kepala, jeda) in <(Map<String, List<String>>, Duration)>[
      (const {}, PenguraiAntrean.jedaBatchBerjalan),
      (const {'retry-after': ['12']}, const Duration(seconds: 12)),
    ]) {
      final a = AntreanMemori();
      await _baris(a, 'c1');
      await _baris(a, 'x1', jenis: 'PENGELUARAN');
      final s = _Server((o) => o.path == jalurSyncBatch
          ? (429, {'success': false, 'message': 'Masih diproses', 'errors': {'kode': ['BATCH_BERJALAN']}}, kepala)
          : _terimaSemua(o));
      await _pengurai(a, s).jalankan();
      expect(s.log, ['batch:c1'], reason: '$kepala');
      final c1 = (await a.cari('c1'))!;
      expect(c1.status, StatusAntrean.menunggu);
      expect(c1.cobaLagiSetelah, _kini.add(jeda), reason: '$kepala');
      expect(c1.percobaan, 0);
      expect(kodeGalat(c1.galatTerakhir), 'BATCH_BERJALAN');
      expect((await a.cari('x1'))!.status, StatusAntrean.menunggu);
    }
  });

  test('timeout batch menghormati batas umur /config: baris yang terlalu lama → TINJAU, baris muda tetap mundur', () async {
    final a = AntreanMemori();
    await _baris(a, 'tua'); // dibuat 09:00
    await a.antrekan(PesanAntrean(
      urut: 0, clientRef: 'muda', jenis: 'CHECKOUT', path: '/transaksi/checkout',
      body: const {'client_ref': 'muda'}, dibuat: DateTime(2026, 9, 24, 11, 30), tokoId: 'T1',
    ));
    final kini = DateTime(2026, 9, 24, 12);
    final penanda = _Penanda();
    final s = _Server((o) => o.path == jalurSyncBatch ? DioExceptionType.receiveTimeout : _terimaSemua(o));
    await _pengurai(a, s, penanda: penanda, sekarang: () => kini, batas: () async => const BatasAntrean(maksUmurJam: 2)).jalankan();
    expect(s.log, ['batch:tua,muda']);
    final tua = (await a.cari('tua'))!;
    expect(tua.status, StatusAntrean.tinjau);
    expect(tua.percobaan, 1);
    expect(tua.galatServer, 0, reason: 'timeout bukan galat server');
    expect(tua.galatTerakhir, '${PenguraiAntrean.pesanTimeoutSetelahKirim} (tertunda lebih dari 2 jam; perlu ditinjau)');
    expect(tua.galatTerakhir, contains('setelah data dikirim'));
    expect(PemulihTinjau.layakDipulihkan(tua), isTrue, reason: 'pemulih memeriksanya ke daftar transaksi server');
    expect(tua.cobaLagiSetelah, isNull);
    final muda = (await a.cari('muda'))!;
    expect(muda.status, StatusAntrean.menunggu);
    expect(muda.percobaan, 1);
    expect(muda.cobaLagiSetelah, kini.add(PenguraiAntrean.mundur(1)));
    expect(penanda.offline, isFalse);
  });

  test('umur_detik dihitung per operasi saat benar-benar dikirim, bukan dari awal putaran', () async {
    final a = AntreanMemori();
    await _baris(a, 'c1'); // dibuat 09:00
    await _baris(a, 'c2');
    var kini = _kini; // 10:00
    final s = _Server();
    s.jawab = (o) {
      if (o.path != jalurSyncBatch) return _terimaSemua(o);
      kini = kini.add(const Duration(seconds: 30)); // server lambat menjawab
      return s.batch.length == 1
          ? (409, {'success': false, 'message': 'Bentrok', 'errors': {'kode': ['BATCH_REF_BENTROK']}})
          : _terimaSemua(o);
    };
    await _pengurai(a, s, konfig: const KonfigSyncBatch(versi: 2, maksOperasi: 1), sekarang: () => kini).jalankan();
    expect(
      [for (final b in s.batch) for (final op in b['operations'] as List) [(op as Map)['idempotency_key'], op['umur_detik']]],
      [['c1', 3600], ['c1', 3630], ['c2', 3660]],
    );
  });

  test('jalur non-item (413 dibelah, timeout, jaringan) tidak meninggalkan kode lama di galat (paritas desktop kode:null)', () async {
    for (final jawab in <Object>[
      (413, {'success': false, 'message': 'Terlalu besar', 'errors': {'kode': ['BATCH_TERLALU_BESAR']}}),
      DioExceptionType.receiveTimeout,
      DioExceptionType.connectionError,
    ]) {
      final a = AntreanMemori();
      await _baris(a, 'c1');
      await _baris(a, 'c2');
      for (final r in ['c1', 'c2']) {
        await a.perbarui(r, galatTerakhir: galatBerkode('DITUNDA', 'Ditunda server (batas waktu kiriman); dikirim lagi sebentar.'));
      }
      final s = _Server((o) => o.path == jalurSyncBatch ? jawab : _terimaSemua(o));
      await _pengurai(a, s).jalankan();
      for (final r in ['c1', 'c2']) {
        final p = (await a.cari(r))!;
        expect(p.status, StatusAntrean.menunggu, reason: '$jawab');
        expect(p.galatTerakhir, isNotNull, reason: '$jawab');
        expect(kodeGalat(p.galatTerakhir), isNull, reason: '$jawab: kode lama dibersihkan');
      }
    }
  });

  test('batch sama sekali tanpa ?toko_id (bukan ?toko_id kosong): tanda untuk pencegat app & SalinanInterceptor, toko tiap op di payload (paritas desktop)', () async {
    final a = AntreanMemori();
    await _baris(a, 'c1');
    final s = _Server();
    await _pengurai(a, s).jalankan();
    final o = s.diminta.firstWhere((x) => x.path == jalurSyncBatch);
    expect(o.uri.query, isEmpty, reason: '${o.uri}');
    // Rantai dioProvider asli (toko aktif tidak disisipkan): offline_batch_wiring_test.
    expect(o.extra[ekstraTanpaTokoAktif], isTrue);
    expect(o.extra[SalinanInterceptor.tandaAntreanBatch], isTrue);
    expect((_ops(o).single['payload'] as Map)['toko_id'], 'T1');
  });

  test('404 / 503 BATCH_TIDAK_TERSEDIA → per baris di putaran yang sama; batch dicoba lagi setelah memo /config habis', () async {
    for (final tolak in <Object>[
      (404, {'success': false, 'message': 'Not Found'}),
      (503, {'success': false, 'message': 'Tidak tersedia', 'errors': {'kode': ['BATCH_TIDAK_TERSEDIA']}}),
    ]) {
      final a = AntreanMemori();
      await _baris(a, 'c1');
      await _baris(a, 'c2');
      var kini = _kini;
      final s = _Server((o) => o.path == jalurSyncBatch ? tolak : _terimaSemua(o));
      final p = _pengurai(a, s, konfigDariServer: true, sekarang: () => kini);
      expect(await p.jalankan(), 2, reason: '$tolak');
      expect(s.log, ['batch:c1,c2', 'baris:c1', 'baris:c2'], reason: '$tolak');
      await _baris(a, 'c3');
      await p.jalankan();
      expect(s.log.last, 'baris:c3', reason: 'server tanpa batch: per baris sampai /config dibaca ulang');
      expect(s.bacaConfig, 1);
      kini = kini.add(PenguraiAntrean.umurKonfig);
      await _baris(a, 'c4');
      await p.jalankan();
      expect(s.bacaConfig, 2);
      expect(s.log, containsAllInOrder(['batch:c4', 'baris:c4']));
    }
  });

  test('jawaban 200 tanpa data.versi = server lama: yang diterima dicatat, sisanya per baris', () async {
    final a = AntreanMemori();
    await _baris(a, 'c1');
    await _baris(a, 'c2');
    final s = _Server((o) => o.path == jalurSyncBatch
        ? (200, {'success': true, 'data': {'results': [{'idempotency_key': 'c1', 'accepted': true, 'server_id': 'v1-1', 'nomor': 'N1'}]}})
        : _terimaSemua(o));
    await _pengurai(a, s).jalankan();
    expect(s.log, ['batch:c1,c2', 'baris:c2']);
    expect((await a.cari('c1'))!.hasil!['nomor'], 'N1');
    expect((await a.cari('c2'))!.status, StatusAntrean.terkirim);
  });

  test('kirim ulang dari TINJAU: _kirim_ulang naik → client_ref batch berbeda → dinilai ulang server', () async {
    final a = AntreanMemori();
    await _baris(a, 'k');
    var tolak = true;
    final s = _Server((o) => o.path == jalurSyncBatch && tolak
        ? _jawabBatch([for (final op in _ops(o)) _item(op, kode: 'VALIDASI', message: 'Produk belum punya satuan.')])
        : _terimaSemua(o));
    final p = _pengurai(a, s);
    await p.jalankan();
    expect((await a.cari('k'))!.status, StatusAntrean.tinjau);
    tolak = false;
    await p.kirimUlang('k');
    final k = (await a.cari('k'))!;
    expect(k.body[kunciKirimUlang], 1);
    expect(k.status, StatusAntrean.terkirim);
    expect(s.batch[0]['client_ref'], isNot(s.batch[1]['client_ref']));
    expect(s.batch[1]['client_ref'], clientRefBatch('dev-uji', [k]));
    expect(((s.batch[1]['operations'] as List).single as Map)['payload'].containsKey(kunciKirimUlang), isFalse);
  });

  test('batas segmen: 25 bawaan; maks_operasi /config yang lebih kecil dipakai', () async {
    final a = AntreanMemori();
    for (var i = 0; i < 30; i++) {
      await _baris(a, 'c$i');
    }
    final s = _Server();
    await _pengurai(a, s).jalankan();
    expect([for (final b in s.batch) (b['operations'] as List).length], [25, 5]);

    final b = AntreanMemori();
    for (var i = 0; i < 12; i++) {
      await _baris(b, 'd$i');
    }
    final s2 = _Server();
    await _pengurai(b, s2, konfig: const KonfigSyncBatch(versi: 2, maksOperasi: 5)).jalankan();
    expect([for (final x in s2.batch) (x['operations'] as List).length], [5, 5, 2]);
  });

  test('kunci pengurai diperbarui setelah tiap segmen (isolate latar tak menganggapnya basi)', () async {
    final a = AntreanMemori();
    for (var i = 0; i < 30; i++) {
      await _baris(a, 'c$i');
    }
    final kunci = _KunciHitung();
    await _pengurai(a, _Server(), kunci: kunci).jalankan();
    expect(kunci.kunciDipanggil, 3, reason: 'awal putaran + sebelum POST tiap segmen (dua segmen)');
  });

  test('pemilik: hanya baris akun token yang masuk segmen', () async {
    final a = AntreanMemori();
    await _baris(a, 'milik', pemilik: 'a@t');
    await _baris(a, 'lain', pemilik: 'b@t');
    final s = _Server();
    await _pengurai(a, s, pemilik: () => 'a@t').jalankan();
    expect(s.log, ['batch:milik']);
    expect((await a.cari('lain'))!.status, StatusAntrean.menunggu);
  });

  test('bayar bon atas bon lokal: buka bon per baris dulu, lalu bon_id = id server induk', () async {
    final a = AntreanMemori();
    await _baris(a, 'b1', jenis: 'BILL_BUKA', path: '/bills');
    await _baris(a, 'y1', jenis: 'BILL_BAYAR', path: '/bills/lokal:b1/settle', body: {'tipe_pembayaran': 'TUNAI', 'dibayar': 10000});
    final s = _Server();
    expect(await _pengurai(a, s).jalankan(), 2);
    expect(s.log, ['baris:b1', 'batch:y1']);
    final op = (s.batch.single['operations'] as List).single as Map;
    expect(op['payload']['bon_id'], 'S-b1');
  });

  test('per baris: nomor_lokal badan checkout ikut hasil (untuk "L-… → nomor server")', () async {
    final a = AntreanMemori();
    await _baris(a, 'c1', body: {'client_ref': 'c1', 'nomor_lokal': 'L-3B9D-260924-0001'});
    await _pengurai(a, _Server(), konfig: null).jalankan();
    expect((await a.cari('c1'))!.hasil!['nomor_lokal'], 'L-3B9D-260924-0001');
  });

  test('429 BATCH_BERJALAN = jeda batch tingkat perangkat: tidak ada POST batch lain selama Retry-After, baris endpoint tunggal tetap jalan', () async {
    final a = AntreanMemori();
    for (var i = 0; i < 30; i++) {
      await _baris(a, 'c$i');
    }
    await _baris(a, 'x1', jenis: 'PENGELUARAN');
    var kini = _kini;
    var berjalan = true;
    final s = _Server((o) => o.path == jalurSyncBatch && berjalan
        ? (429, {'success': false, 'message': 'Masih diproses', 'errors': {'kode': ['BATCH_BERJALAN']}})
        : _terimaSemua(o));
    final p = _pengurai(a, s, sekarang: () => kini);
    await p.jalankan();
    expect(s.batch, hasLength(1), reason: 'segmen kedua tidak dikirim setelah 429');
    expect((s.batch.single['operations'] as List).length, 25);

    // Putaran lain di dalam jendela: baris batch (termasuk 5 yang belum pernah dikirim) menunggu.
    kini = kini.add(const Duration(seconds: 2));
    await p.jalankan();
    expect(s.batch, hasLength(1), reason: 'masih dalam jeda batch perangkat');
    expect(s.log.last, 'baris:x1', reason: 'endpoint tunggal tetap jalan');
    expect(p.jadwalBerikutnya, isNotNull);
    expect(p.jadwalBerikutnya!.isBefore(_kini.add(PenguraiAntrean.jedaBatchBerjalan)), isFalse, reason: 'timer ≥ 5 dtk sejak 429');

    berjalan = false;
    kini = _kini.add(PenguraiAntrean.jedaBatchBerjalan);
    await p.jalankan();
    expect([for (final b in s.batch) (b['operations'] as List).length], [25, 25, 5]);
  });

  test('Retry-After batch: detik desimal diterima, tanggal HTTP diterima, dijepit ≤ 10 menit, tak sah → null', () {
    Headers h(String v) => Headers.fromMap({'retry-after': [v]});
    expect(PenguraiAntrean.jedaRetryAfter(h('5')), const Duration(seconds: 5));
    expect(PenguraiAntrean.jedaRetryAfter(h('5.5')), const Duration(milliseconds: 5500));
    expect(PenguraiAntrean.jedaRetryAfter(h('99999')), const Duration(minutes: 10));
    final kini = DateTime.utc(2026, 9, 24, 3);
    expect(PenguraiAntrean.jedaRetryAfter(h(HttpDate.format(kini.add(const Duration(seconds: 30)))), sekarang: kini), const Duration(seconds: 30));
    for (final salah in ['0', '-3', 'NaN', 'Infinity', 'nanti']) {
      expect(PenguraiAntrean.jedaRetryAfter(h(salah)), isNull, reason: salah);
    }
    expect(PenguraiAntrean.jedaRetryAfter(Headers()), isNull);
    // Nilai absurd dijepit ke 600 dtk SEBELUM dikali ke mikrodetik (tanpa luapan / lemparan).
    for (final absurd in ['1e308', '1e18', '1e12', '600.0000001']) {
      expect(PenguraiAntrean.jedaRetryAfter(h(absurd)), const Duration(minutes: 10), reason: absurd);
    }
    // Tanggal HTTP tepat sekarang / sudah lewat → null (pemanggil memakai jeda cadangan).
    expect(PenguraiAntrean.jedaRetryAfter(h(HttpDate.format(kini)), sekarang: kini), isNull);
    expect(PenguraiAntrean.jedaRetryAfter(h(HttpDate.format(kini.subtract(const Duration(minutes: 1)))), sekarang: kini), isNull);
  });

  test('429 BATCH_BERJALAN dengan Retry-After tanggal HTTP yang ≤ sekarang → jeda cadangan 5 dtk (paritas desktop), dihitung dari jam pengurai', () async {
    // Jam pengurai sengaja di masa depan terhadap jam dinding: tanggal harus
    // dibandingkan dengan jam pengurai, bukan DateTime.now().
    final kini = DateTime.utc(2030, 1, 2, 3, 4, 5);
    for (final tanggal in [kini, kini.subtract(const Duration(seconds: 30))]) {
      final a = AntreanMemori();
      await _baris(a, 'c1');
      final s = _Server((o) => o.path == jalurSyncBatch
          ? (429, {'success': false, 'message': 'Masih diproses', 'errors': {'kode': ['BATCH_BERJALAN']}}, {'retry-after': [HttpDate.format(tanggal)]})
          : _terimaSemua(o));
      await _pengurai(a, s, sekarang: () => kini).jalankan();
      final c1 = (await a.cari('c1'))!;
      expect(c1.cobaLagiSetelah, kini.add(PenguraiAntrean.jedaBatchBerjalan), reason: '$tanggal');
    }
  });

  test('per baris: timeout setelah POST terkirim → mundur baris itu saja tanpa menandai offline, lanjut ke baris lain; lewat umur → TINJAU "setelah data dikirim"', () async {
    final a = AntreanMemori();
    await _baris(a, 'c1'); // dibuat 09:00
    await _baris(a, 'c2');
    final penanda = _Penanda();
    final s = _Server((o) => (o.data as Map?)?['client_ref'] == 'c1' ? DioExceptionType.receiveTimeout : _terimaSemua(o));
    await _pengurai(a, s, konfig: null, penanda: penanda).jalankan();
    expect(s.log, ['baris:c1', 'baris:c2']);
    final c1 = (await a.cari('c1'))!;
    expect(c1.status, StatusAntrean.menunggu);
    expect(c1.percobaan, 1);
    expect(c1.galatServer, 0);
    expect(c1.cobaLagiSetelah, _kini.add(PenguraiAntrean.mundur(1)));
    expect(c1.galatTerakhir, contains('tidak menjawab tepat waktu'));
    expect(penanda.offline, isFalse);
    expect((await a.cari('c2'))!.status, StatusAntrean.terkirim);

    final b = AntreanMemori();
    await _baris(b, 'tua');
    final s2 = _Server((o) => DioExceptionType.receiveTimeout);
    await _pengurai(b, s2, konfig: null, sekarang: () => DateTime(2026, 9, 24, 12), batas: () async => const BatasAntrean(maksUmurJam: 2)).jalankan();
    final tua = (await b.cari('tua'))!;
    expect(tua.status, StatusAntrean.tinjau);
    expect(tua.galatTerakhir, '${PenguraiAntrean.pesanTimeoutSetelahKirim} (tertunda lebih dari 2 jam; perlu ditinjau)');
    expect(PemulihTinjau.layakDipulihkan(tua), isTrue);

    // Gagal tersambung (belum terkirim) tetap jaringan: offline & putaran berhenti.
    final c = AntreanMemori();
    await _baris(c, 'c1');
    await _baris(c, 'c2');
    final penanda3 = _Penanda();
    final s3 = _Server((o) => DioExceptionType.connectionTimeout);
    await _pengurai(c, s3, konfig: null, penanda: penanda3).jalankan();
    expect(s3.log, ['baris:c1']);
    expect(penanda3.offline, isTrue);
  });

  test('404 / 503 BATCH_TIDAK_TERSEDIA / server lama: baris kembali per baris tanpa kode lama di galat', () async {
    for (final jawab in <Object>[
      (404, {'success': false, 'message': 'Not Found'}),
      (503, {'success': false, 'message': 'Tidak tersedia', 'errors': {'kode': ['BATCH_TIDAK_TERSEDIA']}}),
      (200, {'success': true, 'data': {'results': <Object>[]}}),
    ]) {
      final a = AntreanMemori();
      await _baris(a, 'c1');
      await a.perbarui('c1', galatTerakhir: galatBerkode('DITUNDA', 'Ditunda server (batas waktu kiriman); dikirim lagi sebentar.'));
      final s = _Server((o) => o.path == jalurSyncBatch ? jawab : _terimaSemua(o));
      await _pengurai(a, s).jalankan();
      expect(s.log, ['batch:c1', 'baris:c1'], reason: '$jawab');
      final c1 = (await a.cari('c1'))!;
      expect(c1.status, StatusAntrean.terkirim, reason: '$jawab');
      // Galat lama tetap tersimpan pada baris terkirim, tetapi kodenya sudah dibersihkan saat kembali ke antrean.
      expect(c1.galatTerakhir, isNotNull, reason: '$jawab');
      expect(kodeGalat(c1.galatTerakhir), isNull, reason: '$jawab');
    }
  });
}

class _KunciHitung extends KunciPengurai {
  int kunciDipanggil = 0;
  @override
  Future<bool> terkunci() async => false;
  @override
  Future<void> kunci() async {
    kunciDipanggil++;
  }

  @override
  Future<void> buka() async {}
}
