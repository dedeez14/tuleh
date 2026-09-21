// Refund di Android (2.30.0): struk membawa sisa refund per baris & dokumen refund;
// POST /transaksi/{id}/refund mengirim kontrak server (items id+kuantitas, metode,
// alasan, kembali_stok, client_ref idempoten).

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/network/api_exception.dart';
import 'package:tuleh_pos/features/riwayat/data/datasources/riwayat_remote_datasource.dart';
import 'package:tuleh_pos/features/riwayat/domain/entities/refund.dart';

class _Server implements HttpClientAdapter {
  _Server(this.jawab);
  final ResponseBody Function(RequestOptions o) jawab;
  final permintaan = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? s, Future<void>? c) async {
    permintaan.add(o);
    return jawab(o);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Map<String, dynamic> body, [int status = 200]) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
);

Dio _dio(_Server s) =>
    Dio(BaseOptions(baseUrl: 'https://x.test/api', validateStatus: (_) => true))..httpClientAdapter = s;

final _struk = {
  'id': 'T1', 'nomor': 'POS-000051', 'tanggal': '2026-09-20T09:00:00+07:00', 'status': 'SELESAI',
  'tipe_pembayaran': 'TUNAI', 'subtotal': 51000, 'total_diskon': 0, 'total_pajak': 0, 'grand_total': 51000,
  'dibayar': 100000, 'kembalian': 49000, 'total_refund': 18000, 'nilai_bersih': 33000,
  'items': [
    {'id': 'I1', 'nama': 'Kopi Susu', 'satuan': 'cup', 'kuantitas': 2, 'harga': 18000, 'subtotal': 36000, 'qty_refund': 1, 'qty_bisa_refund': 1},
    {'id': 'I2', 'nama': 'Roti Bakar', 'kuantitas': 1, 'harga': 15000, 'subtotal': 15000, 'qty_refund': 0, 'qty_bisa_refund': 1},
  ],
  'refunds': [
    {
      'id': 'R1', 'nomor': 'RF-000003', 'tanggal': '2026-09-20T10:15:00+07:00', 'metode': 'TUNAI', 'metode_nama': 'Tunai',
      'alasan': 'Tumpah', 'oleh': 'Manager Toko', 'subtotal': 18000, 'total_pajak': 0, 'total': 18000,
      'items': [{'item_id': 'I1', 'nama': 'Kopi Susu', 'satuan': 'cup', 'kuantitas': 1, 'total': 18000, 'kembali_stok': false}],
    },
  ],
};

void main() {
  group('RiwayatRemoteDataSource.detail', () {
    test('memetakan id/qty_refund/qty_bisa_refund per baris, total_refund, nilai_bersih, refunds[] dengan item_id', () async {
      final ds = RiwayatRemoteDataSource(_dio(_Server((_) => _json({'success': true, 'data': _struk}))));
      final d = await ds.detail('T1');
      expect(d.items.map((i) => i.id), ['I1', 'I2']);
      expect(d.items[0].qtyRefund, 1);
      expect(d.items[0].qtyBisaRefund, 1);
      expect(d.items[1].qtyBisaRefund, 1);
      expect(d.totalRefund, 18000);
      expect(d.nilaiBersih, 33000);
      expect(d.adaSisaRefund, isTrue);
      final r = d.refunds.single;
      expect(r.nomor, 'RF-000003');
      expect(r.metodeNama, 'Tunai');
      expect(r.oleh, 'Manager Toko');
      expect(r.total, 18000);
      expect(r.items.single.itemId, 'I1');
      expect(r.items.single.kembaliStok, isFalse);
    });

    test('server lama tanpa bidang refund: nol, kosong, adaSisaRefund false', () async {
      final tanpa = Map<String, dynamic>.from(_struk)
        ..remove('total_refund')
        ..remove('nilai_bersih')
        ..remove('refunds')
        ..['items'] = [{'nama': 'Kopi', 'kuantitas': 1, 'harga': 1000, 'subtotal': 1000}];
      final d = await RiwayatRemoteDataSource(_dio(_Server((_) => _json({'success': true, 'data': tanpa})))).detail('T1');
      expect(d.totalRefund, 0);
      expect(d.nilaiBersih, isNull);
      expect(d.refunds, isEmpty);
      expect(d.items.single.id, isNull);
      expect(d.adaSisaRefund, isFalse);
    });
  });

  group('RiwayatRemoteDataSource.list', () {
    test('total_refund per baris riwayat', () async {
      final ds = RiwayatRemoteDataSource(_dio(_Server((_) => _json({'success': true, 'data': [
        {'id': 'T1', 'nomor': 'A', 'grand_total': 51000, 'total_refund': 18000},
        {'id': 'T2', 'nomor': 'B', 'grand_total': 20000},
      ]}))));
      final l = await ds.list();
      expect(l[0].totalRefund, 18000);
      expect(l[1].totalRefund, 0);
    });
  });

  group('RiwayatRemoteDataSource.refund', () {
    final permintaan = PermintaanRefund(
      baris: const [BarisRefund(id: 'I1', kuantitas: 1), BarisRefund(id: 'I2', kuantitas: 0.5)],
      metode: 'TUNAI',
      alasan: 'Tumpah',
      kembaliStok: false,
      clientRef: 'rf-1',
      waktuKlien: DateTime(2026, 9, 20, 10, 15),
    );

    test('POST /transaksi/{id}/refund (id di-encode) dengan body kontrak; 201 → Refund', () async {
      final server = _Server((o) => _json({'success': true, 'data': _struk['refunds']![0]}, 201));
      final r = await RiwayatRemoteDataSource(_dio(server)).refund('abc/def==', permintaan);
      final o = server.permintaan.single;
      expect(o.method, 'POST');
      expect(o.path, '/transaksi/abc%2Fdef%3D%3D/refund');
      expect(o.data, {
        'items': [{'id': 'I1', 'kuantitas': 1.0}, {'id': 'I2', 'kuantitas': 0.5}],
        'metode': 'TUNAI',
        'alasan': 'Tumpah',
        'kembali_stok': false,
        'client_ref': 'rf-1',
        'waktu_klien': '2026-09-20T10:15:00.000',
      });
      expect(r.nomor, 'RF-000003');
      expect(r.items.single.itemId, 'I1');
    });

    test('403 tanpa hak & 422 melebihi sisa → ApiException dengan pesan server', () async {
      final tolak = _Server((_) => _json({'success': false, 'message': 'Anda tidak memiliki hak Refund transaksi.'}, 403));
      await expectLater(
        RiwayatRemoteDataSource(_dio(tolak)).refund('T1', permintaan),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 403).having((e) => e.message, 'pesan', contains('tidak memiliki hak'))),
      );
      final lebih = _Server((_) => _json({
        'success': false, 'message': 'Data tidak valid.',
        'errors': {'items.0.kuantitas': ['Jumlah refund Kopi Susu melebihi sisa (1).']},
      }, 422));
      await expectLater(
        RiwayatRemoteDataSource(_dio(lebih)).refund('T1', permintaan),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 422).having((e) => e.firstError(), 'galat pertama', contains('melebihi sisa'))),
      );
    });
  });
}
