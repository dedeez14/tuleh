// Fase 4: operasi /sync/v2/batch dari baris antrean Android — pemetaan per
// jenis (paritas desktop operasi-batch.js), client_ref batch deterministik yang
// ikut generasi kirim ulang, hasil item, kode di galat, rujukan baris refund.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/offline/antrean.dart';
import 'package:tuleh_pos/core/offline/operasi_batch.dart';

PesanAntrean _p(
  String ref,
  String jenis,
  String path,
  Map<String, dynamic> body, {
  int urut = 1,
  String? tokoId = 'T-enc',
  DateTime? dibuat,
}) => PesanAntrean(
  urut: urut, clientRef: ref, jenis: jenis, path: path, body: body,
  dibuat: dibuat ?? DateTime(2026, 9, 24, 10, 15, 2), tokoId: tokoId,
);

final _zona = RegExp(r'[+-]\d{2}:\d{2}$');

class _Server implements HttpClientAdapter {
  _Server(this.jawab);
  final Object Function(RequestOptions o) jawab;
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? s, Future<void>? c) async {
    final r = jawab(o);
    if (r is DioExceptionType) throw DioException(requestOptions: o, type: r);
    final (int code, Object body) = r as (int, Object);
    return ResponseBody.fromString(jsonEncode(body), code, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('jalur & jenis batch: rute v2, lima jenis antrean, segmen 25', () {
    expect(jalurSyncBatch, '/sync/v2/batch');
    expect(jenisBatch, {'CHECKOUT': 'checkout', 'REFUND': 'refund', 'BATAL': 'batal', 'BILL_BAYAR': 'bills.settle', 'ORDER_TRANSISI': 'orders.transition'});
    expect(batasOpSegmen, 25);
  });

  test('CHECKOUT: badan utuh tanpa kunci _, offline:true, toko & nomor lokal, waktu ber-zona, device_seq = urut, umur_detik', () {
    final p = _p('c1', 'CHECKOUT', '/transaksi/checkout', {
      'items': [{'id_produk': 'P1', 'harga': 12000, 'kuantitas': 5}],
      'tipe_pembayaran': 'TUNAI', 'dibayar': 70000, 'client_ref': 'c1',
      'waktu_klien': '2026-09-24T10:15:02+07:00', '_kirim_ulang': 2,
    }, urut: 41);
    final op = opDariBaris(p, deviceId: 'dev-1', kini: DateTime(2026, 9, 24, 10, 17, 7), nomorLokal: 'L-DEV1-260924-0007');
    expect(op['idempotency_key'], 'c1');
    expect(op['device_id'], 'dev-1');
    expect(op['device_seq'], 41);
    expect(op['umur_detik'], 125);
    expect(op['type'], 'checkout');
    final payload = op['payload'] as Map<String, dynamic>;
    expect(payload['offline'], isTrue);
    expect(payload['toko_id'], 'T-enc');
    expect(payload['nomor_lokal'], 'L-DEV1-260924-0007');
    expect(payload['client_ref'], 'c1');
    expect(payload['waktu_klien'], '2026-09-24T10:15:02+07:00');
    expect(payload.containsKey('_kirim_ulang'), isFalse, reason: 'data bantu tidak dikirim');
    expect(p.body.containsKey('offline'), isFalse, reason: 'baris antrean tidak diubah');
    final diBadan = opDariBaris(_p('c2', 'CHECKOUT', '/transaksi/checkout', {'nomor_lokal': 'L-X-1'}), deviceId: 'd', kini: DateTime(2026, 9, 24, 11), nomorLokal: 'L-LAIN');
    expect((diBadan['payload'] as Map)['nomor_lokal'], 'L-X-1', reason: 'nomor di badan diutamakan');
  });

  test('tanpa waktu_klien di badan → waktu baris dibuat, ber-offset', () {
    final op = opDariBaris(_p('b1', 'BATAL', '/transaksi/eyJpdiI6%3D%3D/batal', {'alasan': 'Salah input'}), deviceId: 'd', kini: DateTime(2026, 9, 24, 11));
    expect((op['payload'] as Map)['waktu_klien'], matches(_zona));
  });

  test('REFUND/BATAL: transaksi lokal → transaksi_ref; tersinkron → transaksi_id (di-decode)', () {
    final lokal = opDariBaris(_p('rf-1', 'REFUND', '/transaksi/lokal:c1/refund', {
      'items': [{'baris': 1, 'kuantitas': 1}], 'metode': 'TUNAI', 'alasan': 'Rusak', 'kembali_stok': true,
    }), deviceId: 'd', kini: DateTime(2026, 9, 24, 11));
    final pl = lokal['payload'] as Map<String, dynamic>;
    expect(lokal['type'], 'refund');
    expect(pl['transaksi_ref'], 'c1');
    expect(pl.containsKey('transaksi_id'), isFalse);
    expect(pl['items'], [{'baris': 1, 'kuantitas': 1}]);
    final batal = opDariBaris(_p('b-1', 'BATAL', '/transaksi/eyJpdiI6%3D%3D/batal', {'alasan': 'Salah input'}), deviceId: 'd', kini: DateTime(2026, 9, 24, 11));
    final pb = batal['payload'] as Map<String, dynamic>;
    expect(batal['type'], 'batal');
    expect(pb['transaksi_id'], 'eyJpdiI6==');
    expect(pb.containsKey('transaksi_ref'), isFalse);
    expect(pb['alasan'], 'Salah input');
  });

  test('BILL_BAYAR / ORDER_TRANSISI: id dari jalur (jalur tergantikan diutamakan); toko untuk semua tipe', () {
    final bon = opDariBaris(_p('s-1', 'BILL_BAYAR', '/bills/lokal:b1/settle', {'tipe_pembayaran': 'QRIS', 'dibayar': null}, tokoId: 'T2'),
        deviceId: 'd', kini: DateTime(2026, 9, 24, 11), path: '/bills/B%2F7/settle');
    final pb = bon['payload'] as Map<String, dynamic>;
    expect(bon['type'], 'bills.settle');
    expect(pb['bon_id'], 'B/7');
    expect(pb['toko_id'], 'T2');
    expect(pb['client_ref'], 's-1', reason: 'client_ref payload selalu = idempotency_key');
    final psn = opDariBaris(_p('o-1', 'ORDER_TRANSISI', '/orders/O9/transition', {'to': 'SELESAI', 'tipe_pembayaran': 'TUNAI'}, tokoId: null),
        deviceId: 'd', kini: DateTime(2026, 9, 24, 11));
    final po = psn['payload'] as Map<String, dynamic>;
    expect(psn['type'], 'orders.transition');
    expect(po['order_id'], 'O9');
    expect(po['to'], 'SELESAI');
    expect(po.containsKey('toko_id'), isFalse, reason: 'baris tanpa toko → server memakai toko cadangan/sesi');
  });

  test('jenis non-batch ditolak; urut 0 (belum tersimpan) tanpa device_seq', () {
    expect(() => opDariBaris(_p('x', 'PENGELUARAN', '/pengeluaran', const {}), deviceId: 'd', kini: DateTime(2026)), throwsArgumentError);
    final op = opDariBaris(_p('y', 'CHECKOUT', '/transaksi/checkout', const {}, urut: 0), deviceId: 'd', kini: DateTime(2026, 9, 24, 11));
    expect(op.containsKey('device_seq'), isFalse);
  });

  test('clientRefBatch: rumus tetap (= desktop), generasi kirim ulang & garam & urutan & perangkat mengubah ref', () {
    final a = _p('a', 'CHECKOUT', '/transaksi/checkout', const {});
    final b = _p('b', 'REFUND', '/transaksi/T1/refund', const {'_kirim_ulang': 0});
    expect(sidikKomposisi([a, b]), 'checkout:a:0\nrefund:b:0');
    final r1 = clientRefBatch('dev', [a, b]);
    expect(r1, 'fe481eea9f58de368b53f096384781ea43950b643012811349ddede35f5cf3cd');
    expect(clientRefBatch('dev', [a, b], garam: 1), '0e60b3cd99e807769359fd279851932cb17696d348ebb4b85781b8ccc777d2a5');
    final bUlang = _p('b', 'REFUND', '/transaksi/T1/refund', const {'_kirim_ulang': 1});
    expect(clientRefBatch('dev', [a, bUlang]), isNot(r1));
    expect(clientRefBatch('dev', [b, a]), isNot(r1));
    expect(clientRefBatch('dev-lain', [a, b]), isNot(r1));
    expect(kirimUlangKe(bUlang), 1);
  });

  test('ukuranJson = byte UTF-8', () {
    expect(ukuranJson({'a': 'é'}), utf8.encode('{"a":"é"}').length);
  });

  test('HasilItemBatch: bentuk hasil TERKIRIM; kode & pesan cadangan', () {
    final h = HasilItemBatch.dariJson({
      'idempotency_key': 'k', 'type': 'checkout', 'accepted': true, 'server_id': 'enc-1', 'nomor': 'POS/1', 'kode': 'OK',
      'retriable': false, 'message': 'Transaksi berhasil.', 'reason': null, 'idempoten': true, 'peringatan': ['SELISIH_STOK'],
      'data': {'grand_total': 1},
    })!;
    expect(h.keHasil(nomorLokal: 'L-1'), {
      'id': 'enc-1', 'nomor': 'POS/1', 'kode': 'OK', 'tipe': 'checkout', 'peringatan': ['SELISIH_STOK'],
      'idempoten': true, '_idempoten': true, 'data': {'grand_total': 1}, 'nomor_lokal': 'L-1',
    });
    final tolak = HasilItemBatch.dariJson({'idempotency_key': 'x', 'accepted': false})!;
    expect(tolak.kode, 'GALAT_SERVER');
    expect(tolak.message, 'Galat server');
    expect(HasilItemBatch.dariJson({'accepted': true}), isNull, reason: 'tanpa kunci tak bisa dicocokkan');
  });

  test('galat berkode: awalan [KODE] terurai; galat lama tanpa kode', () {
    final g = galatBerkode('SESI_TIDAK_ADA', 'Belum ada sesi kasir untuk toko ini.');
    expect(g, '[SESI_TIDAK_ADA] Belum ada sesi kasir untuk toko ini.');
    expect(kodeGalat(g), 'SESI_TIDAK_ADA');
    expect(pesanGalat(g), 'Belum ada sesi kasir untuk toko ini.');
    expect(kodeGalat('Tidak dapat terhubung ke server.'), isNull);
    expect(kodeGalat(null), isNull);
  });

  test('label kode & peringatan (sama dengan desktop); kode asing apa adanya', () {
    expect(labelKode('OTORISASI_WAJIB'), 'Butuh persetujuan atasan — ulangi saat online');
    expect(labelKode('PELUNASAN_HARUS_REFUND'), 'Transaksi pelunasan — gunakan Refund');
    expect(labelKode('KODE_BARU'), 'KODE_BARU');
    expect(labelPeringatan(['SELISIH_STOK', 'SESI_TUTUP', 'BARU']), ['Selisih stok', 'Masuk sesi yang sudah ditutup', 'BARU']);
    expect(labelPeringatan(null), isEmpty);
  });

  test('idItemDariHasil & barisKeIdItem: ringkasan batch atau struk per baris; tak dikenal → null', () {
    final batch = {'id': 'SRV/1', 'data': {'items': [{'baris': 0, 'id': 'I-a'}, {'baris': 1, 'id': 'I-b'}]}};
    final perBaris = {'id': 'S2', 'items': [{'id': 'J-a'}, {'id': 'J-b'}]};
    expect(idItemDariHasil(batch, 1), 'I-b');
    expect(idItemDariHasil(perBaris, 1), 'J-b');
    expect(idItemDariHasil(perBaris, 5), isNull);
    final body = {'items': [{'baris': 1, 'kuantitas': 2}], 'metode': 'TUNAI', 'alasan': 'Rusak'};
    expect(barisKeIdItem(body, batch), {'items': [{'id': 'I-b', 'kuantitas': 2}], 'metode': 'TUNAI', 'alasan': 'Rusak'});
    expect(barisKeIdItem(body, {'id': 'S3', 'dipulihkan': true}), isNull);
    expect(barisKeIdItem({'alasan': 'x'}, null), {'alasan': 'x'}, reason: 'batal tanpa items apa adanya');
  });

  test('KonfigSyncBatch dari /config: versi & batas; tanpa blok = versi 0; gagal baca = null', () async {
    final k = KonfigSyncBatch.dariConfig({'sync_batch': {'versi': 2, 'path': '/sync/v2/batch', 'maks_operasi': 200, 'maks_byte': 2097152, 'saran_operasi_per_segmen': 25}});
    expect(k.aktif, isTrue);
    expect(k.batasOp(25), 25);
    expect(k.batasOp(4), 4, reason: 'adaptif setelah 413');
    expect(k.batasByte, 1468006);
    expect(const KonfigSyncBatch(versi: 2, maksOperasi: 5).batasOp(25), 5);
    expect(KonfigSyncBatch.dariConfig({'antrean_maks_umur_jam': 48}).aktif, isFalse);
    expect(KonfigSyncBatch.dariConfig(null).versi, 0);
    expect(const KonfigSyncBatch(versi: 1).aktif, isFalse);

    final dio = Dio(BaseOptions(validateStatus: (_) => true))
      ..httpClientAdapter = _Server((o) => (200, {'success': true, 'data': {'sync_batch': {'versi': 2}}}));
    expect((await ambilKonfigSyncBatch(dio))!.versi, 2);
    final rusak = Dio(BaseOptions(validateStatus: (_) => true))..httpClientAdapter = _Server((o) => (503, {'success': false}));
    expect(await ambilKonfigSyncBatch(rusak), isNull);
    final daftar = Dio(BaseOptions(validateStatus: (_) => true))..httpClientAdapter = _Server((o) => (200, {'success': true, 'data': <Object>[]}));
    expect((await ambilKonfigSyncBatch(daftar))!.aktif, isFalse, reason: 'server menjawab tanpa blok');
  });
}
