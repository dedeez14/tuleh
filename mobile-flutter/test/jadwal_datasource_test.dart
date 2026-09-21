// Modul Jadwal di Android (2.32.0): slot per hari + peserta. Penolakan 409
// (KUOTA_PENUH dsb.) sampai ke layar sebagai ApiException berstatus 409 dengan
// kalimat server apa adanya; kode mesinnya sendiri tidak diteruskan.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/network/api_exception.dart';
import 'package:tuleh_pos/features/jadwal/data/datasources/jadwal_remote_datasource.dart';
import 'package:tuleh_pos/features/jadwal/domain/entities/jadwal.dart';

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

final _slot = {
  'id': 'J1', 'toko_id': 'T1', 'nama': 'Yoga Pagi', 'tanggal': '2026-09-21',
  'jam_mulai': '07:00', 'jam_selesai': '08:00', 'kuota': 2, 'peserta_count': 1, 'sisa_kuota': 1,
  'pengajar': 'Sari', 'catatan': 'Studio B', 'status': 'AKTIF',
  'peserta': [
    {'id': 'P1', 'pelanggan_id': 'C1', 'nama': 'Budi', 'telepon': '628123', 'status': 'TERDAFTAR'},
  ],
};

void main() {
  test('daftar: GET /jadwal?tanggal=… dan memetakan kuota/sisa/peserta_count', () async {
    final server = _Server((_) => _json({'success': true, 'data': [_slot]}));
    final rows = await JadwalRemoteDataSource(_dio(server)).daftar('2026-09-21');
    expect(server.permintaan.single.path, '/jadwal');
    expect(server.permintaan.single.queryParameters['tanggal'], '2026-09-21');
    expect(rows.single.nama, 'Yoga Pagi');
    expect(rows.single.kuota, 2);
    expect(rows.single.pesertaCount, 1);
    expect(rows.single.sisaKuota, 1);
    expect(rows.single.penuh, isFalse);
    expect(rows.single.aktif, isTrue);
    expect(rows.single.peserta, isEmpty, reason: 'daftar ringkas tidak membawa peserta');
  });

  test('tanpa kuota: sisa null dan tidak pernah penuh', () async {
    final tanpa = Map<String, dynamic>.from(_slot)
      ..['kuota'] = null
      ..['sisa_kuota'] = null
      ..['peserta_count'] = 9;
    final rows = await JadwalRemoteDataSource(_dio(_Server((_) => _json({'success': true, 'data': [tanpa]})))).daftar('2026-09-21');
    expect(rows.single.kuota, isNull);
    expect(rows.single.sisaKuota, isNull);
    expect(rows.single.penuh, isFalse);
  });

  test('detail membawa peserta; simpan & ubah mengirim bentuk server', () async {
    final server = _Server((_) => _json({'success': true, 'data': _slot}));
    final ds = JadwalRemoteDataSource(_dio(server));

    final d = await ds.detail('J1');
    expect(server.permintaan.last.path, '/jadwal/J1');
    expect(d.peserta.single.nama, 'Budi');
    expect(d.peserta.single.id, 'P1');
    expect(d.peserta.single.pelangganId, 'C1');

    const isian = IsianJadwal(
      nama: 'Yoga Pagi', tanggal: '2026-09-21', jamMulai: '07:00', jamSelesai: '08:00',
      kuota: 2, pengajar: 'Sari', catatan: 'Studio B',
    );
    await ds.simpan(isian);
    expect(server.permintaan.last.method, 'POST');
    expect(server.permintaan.last.data, {
      'nama': 'Yoga Pagi', 'tanggal': '2026-09-21', 'jam_mulai': '07:00', 'jam_selesai': '08:00',
      'kuota': 2, 'pengajar': 'Sari', 'catatan': 'Studio B',
    });

    await ds.ubah('a/b', const IsianJadwal(nama: 'X', tanggal: '2026-09-21', jamMulai: '07:00'));
    expect(server.permintaan.last.method, 'PUT');
    expect(server.permintaan.last.path, '/jadwal/a%2Fb');
    expect(server.permintaan.last.data, {
      'nama': 'X', 'tanggal': '2026-09-21', 'jam_mulai': '07:00',
      'jam_selesai': null, 'kuota': null, 'pengajar': null, 'catatan': null,
    });

    await ds.batal('J1');
    expect(server.permintaan.last.method, 'DELETE');
  });

  test('peserta: daftarkan, ubah status, lepas', () async {
    final server = _Server((_) => _json({'success': true, 'data': (_slot['peserta'] as List).first}, 201));
    final ds = JadwalRemoteDataSource(_dio(server));

    final p = await ds.tambahPeserta('J1', 'C1');
    expect(server.permintaan.last.path, '/jadwal/J1/peserta');
    expect(server.permintaan.last.data, {'pelanggan_id': 'C1'});
    expect(p.nama, 'Budi');

    await ds.ubahStatusPeserta('J1', 'P1', 'HADIR');
    expect(server.permintaan.last.method, 'PATCH');
    expect(server.permintaan.last.path, '/jadwal/J1/peserta/P1');
    expect(server.permintaan.last.data, {'status': 'HADIR'});

    await ds.lepasPeserta('J1', 'P1');
    expect(server.permintaan.last.method, 'DELETE');
  });

  test('409 KUOTA_PENUH & 403 tanpa hak → ApiException berpesan server', () async {
    final penuh = _Server((_) => _json({
      'success': false, 'kode': 'KUOTA_PENUH', 'message': 'Kuota jadwal "Yoga Pagi" sudah penuh (2 peserta).',
    }, 409));
    await expectLater(
      JadwalRemoteDataSource(_dio(penuh)).tambahPeserta('J1', 'C9'),
      throwsA(isA<ApiException>()
          .having((e) => e.statusCode, 'status', 409)
          .having((e) => e.message, 'pesan', contains('sudah penuh'))),
    );

    final tolak = _Server((_) => _json({'success': false, 'message': 'Anda tidak memiliki hak akses "Kelola jadwal".'}, 403));
    await expectLater(
      JadwalRemoteDataSource(_dio(tolak)).simpan(const IsianJadwal(nama: 'X', tanggal: '2026-09-21', jamMulai: '07:00')),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 403)),
    );
  });
}
