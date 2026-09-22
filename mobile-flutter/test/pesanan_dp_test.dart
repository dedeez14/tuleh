// Fase 3 (2.33.0): nota bayar-nanti & uang muka lewat POST /orders; transisi pelunasan membawa struk.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/features/pesanan/data/datasources/pesanan_remote_datasource.dart';
import 'package:tuleh_pos/features/pesanan/domain/entities/hasil_pesanan.dart';
import 'package:tuleh_pos/features/pesanan/domain/entities/pesanan.dart';

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

Map<String, dynamic> _order({String bayar = 'DP', num dibayar = 10000, num sisa = 18000}) => {
      'id': 'O1', 'stage': 'ANTRIAN', 'nomor': 'ORD/1', 'bayar': bayar, 'total': 28000,
      'dibayar': dibayar, 'sisa': sisa,
      'pembayaran': [
        if (bayar == 'DP') {'id': 'B1', 'jenis': 'DP', 'jumlah': 10000, 'tipe_pembayaran': 'TUNAI', 'waktu': '2026-09-22T10:00:00+07:00', 'kasir': 'Kasir Demo'},
      ],
      'items': [{'nama': 'Cuci Kering', 'kuantitas': 1}],
    };

void main() {
  test('buatNota DP → POST /orders {bayar, items, dp, client_ref}; nota & pesanan terurai', () async {
    final s = _Server((o) => _json({'success': true, 'data': {'order': _order(), 'nota': {'status': 'UANG MUKA', 'uang_muka': 10000, 'sisa': 18000}}}, 201));
    final hasil = await PesananRemoteDataSource(_dio(s)).buatNota(
      bayar: 'DP',
      items: const [ItemNota(idProduk: 'P1', kuantitas: 1, harga: 28000)],
      uangMuka: 10000,
      metodeUangMuka: 'TUNAI',
      clientRef: 'dp-1',
    );
    final o = s.permintaan.single;
    expect(o.method, 'POST');
    expect(o.path, '/orders');
    expect(o.data, {
      'bayar': 'DP',
      'items': [{'id_produk': 'P1', 'kuantitas': 1}],
      'dp': {'jumlah': 10000, 'tipe_pembayaran': 'TUNAI'},
      'client_ref': 'dp-1',
    });
    expect(hasil.pesanan.adalahDp, isTrue);
    expect(hasil.pesanan.dibayar, 10000);
    expect(hasil.pesanan.sisa, 18000);
    expect(hasil.pesanan.pembayaran.single.jenis, 'DP');
    expect(hasil.nota['status'], 'UANG MUKA');
  });

  test('buatNota NANTI tidak mengirim dp', () async {
    final s = _Server((o) => _json({'success': true, 'data': {'order': _order(bayar: 'BELUM', dibayar: 0, sisa: 28000), 'nota': {'status': 'BELUM LUNAS'}}}, 201));
    await PesananRemoteDataSource(_dio(s)).buatNota(
      bayar: 'NANTI', items: const [ItemNota(idProduk: 'P1', kuantitas: 2, harga: 5000)], clientRef: 'n-1',
    );
    expect((s.permintaan.single.data as Map).containsKey('dp'), isFalse);
  });

  test('transisi pelunasan: data = field pesanan + struk; bentuk lama {order, struk} tetap terurai', () async {
    final flat = _Server((o) => _json({'success': true, 'data': {..._order(bayar: 'LUNAS', dibayar: 28000, sisa: 0), 'struk': {'nomor': 'POS-1', 'uang_muka': 10000}}}));
    final a = await PesananRemoteDataSource(_dio(flat)).transition('O1', to: 'SELESAI', tipePembayaran: 'TUNAI');
    expect(a.pesanan.bayar, 'LUNAS');
    expect(a.pesanan.id, 'O1');
    expect(a.struk?['nomor'], 'POS-1');

    final lama = _Server((o) => _json({'success': true, 'data': {'order': _order(bayar: 'LUNAS', dibayar: 28000, sisa: 0), 'struk': {'nomor': 'POS-2'}}}));
    final b = await PesananRemoteDataSource(_dio(lama)).transition('O1', to: 'SELESAI');
    expect(b.pesanan.id, 'O1');
    expect(b.struk?['nomor'], 'POS-2');

    final biasa = _Server((o) => _json({'success': true, 'data': _order()}));
    expect((await PesananRemoteDataSource(_dio(biasa)).transition('O1', to: 'DIPROSES')).struk, isNull);
  });

  test('list meneruskan saringan bayar', () async {
    final s = _Server((o) => _json({'success': true, 'data': [_order()]}));
    await PesananRemoteDataSource(_dio(s)).list(bayar: 'BELUM,DP');
    expect(s.permintaan.single.queryParameters['bayar'], 'BELUM,DP');
  });

  test('perluDilunasi: BELUM & DP; LUNAS & BON tidak; server lama tanpa sisa → sisa = total untuk BELUM', () {
    expect(Pesanan.fromJson(_order()).perluDilunasi, isTrue);
    expect(Pesanan.fromJson({'id': 'x', 'stage': 'A', 'bayar': 'BELUM', 'total': 28000}).sisa, 28000);
    expect(Pesanan.fromJson({'id': 'x', 'stage': 'A', 'bayar': 'BON', 'total': 28000}).perluDilunasi, isFalse);
    expect(Pesanan.fromJson({'id': 'x', 'stage': 'A', 'bayar': 'LUNAS', 'total': 28000}).sisa, 0);
  });
}
