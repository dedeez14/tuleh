import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/storage/secure_storage.dart';
import 'package:tuleh_pos/features/demo/data/masa_coba_remote.dart';
import 'package:tuleh_pos/features/demo/data/masa_coba_service.dart';
import 'package:tuleh_pos/features/demo/domain/masa_coba.dart';

/// Lapis 2/3 masa coba: pendaftaran perangkat & OTP terhadap server tiruan
/// yang mengikuti "Kontrak Masa Coba Tuléh". Server yang belum memasang
/// endpoint (404) harus membuat aplikasi berperilaku seperti lapis 1 saja.

final t0 = DateTime.utc(2026, 9, 5, 3);
DateTime hari(num n) => t0.add(Duration(minutes: (n * 24 * 60).round()));

class StorageUji extends SecureStorage {
  StorageUji() : super(const FlutterSecureStorage());
  final Map<String, String> m = {};
  @override
  Future<String?> bacaNilai(String k) async => m[k];
  @override
  Future<void> tulisNilai(String k, String? v) async =>
      v == null ? m.remove(k) : m[k] = v;
}

/// Server tiruan: /app/versi memberi Date; /demo/* dijawab lewat [handler].
Dio serverTiruan(
  DateTime waktu,
  Response<dynamic> Function(RequestOptions o) handler,
) {
  final dio = Dio(BaseOptions(validateStatus: (_) => true));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (o, h) {
        if (o.path.contains('/app/versi')) {
          h.resolve(
            Response(
              requestOptions: o,
              statusCode: 200,
              data: const {'success': true, 'data': {}},
              headers: Headers.fromMap({
                'date': [_rfc1123(waktu)],
              }),
            ),
          );
          return;
        }
        h.resolve(handler(o));
      },
    ),
  );
  return dio;
}

String _rfc1123(DateTime t) {
  const hari = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const bulan = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final u = t.toUtc();
  String dua(int n) => n.toString().padLeft(2, '0');
  return '${hari[u.weekday - 1]}, ${dua(u.day)} ${bulan[u.month - 1]} ${u.year} '
      '${dua(u.hour)}:${dua(u.minute)}:${dua(u.second)} GMT';
}

Response<dynamic> ok(RequestOptions o, Map<String, dynamic> data) => Response(
  requestOptions: o,
  statusCode: 200,
  data: {'success': true, 'data': data},
);

Response<dynamic> gagal(RequestOptions o, int code, [Map<String, dynamic>? body]) =>
    Response(requestOptions: o, statusCode: code, data: body ?? {'success': false});

MasaCobaService layanan(Dio dio, StorageUji st) => MasaCobaService(
  st,
  dio: dio,
  versi: '2.6.0',
  perangkat: IdentitasPerangkat(bacaAndroidId: () async => 'android-uji'),
);

void main() {
  group('gabungkan (murni)', () {
    test('server mengenal perangkat dengan mulai lebih awal: pasang ulang tidak mengulang', () {
      final lokal = MasaCoba.periksa(
        catatan: null,
        waktuServer: hari(6),
        perangkat: hari(6),
        mulaiBaru: true,
      );
      expect(lokal.sisaHari, 7, reason: 'lokal mengira baru mulai');
      final g = MasaCoba.gabungkan(
        lokal,
        StatusServer(status: 'AKTIF', mulai: t0, waktuServer: hari(6)),
        perangkat: hari(6),
      );
      expect(g.kode, KodeMasaCoba.aktif);
      expect(g.sisaHari, 1);
      expect(g.catatan!.mulai, t0);
    });

    test('BERAKHIR / DIBLOKIR / butuh identitas dari server menang', () {
      final lokal = MasaCoba.periksa(
        catatan: null,
        waktuServer: t0,
        perangkat: t0,
        mulaiBaru: true,
      );
      expect(
        MasaCoba.gabungkan(lokal, const StatusServer(status: 'BERAKHIR'), perangkat: t0).kode,
        KodeMasaCoba.berakhir,
      );
      expect(
        MasaCoba.gabungkan(lokal, const StatusServer(status: 'DIBLOKIR'), perangkat: t0).kode,
        KodeMasaCoba.diblokir,
      );
      expect(
        MasaCoba.gabungkan(
          lokal,
          const StatusServer(status: 'BELUM_VERIFIKASI', butuhIdentitas: true),
          perangkat: t0,
        ).kode,
        KodeMasaCoba.butuhIdentitas,
      );
    });

    test('mulai lokal lebih awal dari server: lokal dipakai', () {
      final lokal = MasaCoba.periksa(
        catatan: CatatanMasaCoba(mulai: hari(-3), serverTerakhir: hari(-3)),
        waktuServer: t0,
        perangkat: t0,
      );
      final g = MasaCoba.gabungkan(
        lokal,
        StatusServer(status: 'AKTIF', mulai: t0, waktuServer: t0),
        perangkat: t0,
      );
      expect(g.sisaHari, 4);
      expect(g.catatan!.mulai, hari(-3));
    });

    test('StatusServer.dariJson toleran', () {
      expect(StatusServer.dariJson(null), isNull);
      expect(StatusServer.dariJson({'status': ''}), isNull);
      final s = StatusServer.dariJson({
        'status': 'aktif',
        'butuh_identitas': false,
        'mulai': '2026-09-05T03:00:00Z',
        'waktu_server': '2026-09-06T03:00:00Z',
        'sisa_hari': 6,
      })!;
      expect(s.status, 'AKTIF');
      expect(s.mulai, t0);
      expect(s.sisaHari, 6);
    });
  });

  group('layanan dengan server tiruan', () {
    test('endpoint belum ada (404): perilaku lapis 1 saja', () async {
      final st = StorageUji();
      final svc = layanan(serverTiruan(t0, (o) => gagal(o, 404)), st);
      final r = await svc.periksa(mulaiBaru: true);
      expect(r.kode, KodeMasaCoba.aktif);
      expect(r.sisaHari, 7);
      expect(r.sumberWaktu, 'server'); // dari header Date, bukan /demo
    });

    test('server sudah mencatat perangkat 6 hari lalu: sisa 1 hari walau aplikasi baru dipasang', () async {
      final st = StorageUji();
      final svc = layanan(
        serverTiruan(hari(6), (o) {
          expect(o.path, '/demo/perangkat');
          expect(o.data['platform'], 'android');
          expect((o.data['perangkat_id'] as String).length, 64);
          return ok(o, {
            'status': 'AKTIF',
            'butuh_identitas': false,
            'mulai': t0.toIso8601String(),
            'waktu_server': hari(6).toIso8601String(),
            'sisa_hari': 1,
          });
        }),
        st,
      );
      final r = await svc.periksa(mulaiBaru: true);
      expect(r.kode, KodeMasaCoba.aktif);
      expect(r.sisaHari, 1);
      expect(st.m['demo_mulai'], t0.toIso8601String(), reason: 'catatan lokal ditulis ulang');
    });

    test('server minta identitas, lalu OTP: token ikut dikirim', () async {
      final st = StorageUji();
      var kirim = 0;
      final svc = layanan(
        serverTiruan(t0, (o) {
          if (o.path == '/demo/perangkat') {
            final token = (o.data as Map)['identitas_token'];
            return ok(
              o,
              token == 'tok-123'
                  ? {'status': 'AKTIF', 'mulai': t0.toIso8601String(), 'waktu_server': t0.toIso8601String()}
                  : {'status': 'BELUM_VERIFIKASI', 'butuh_identitas': true, 'waktu_server': t0.toIso8601String()},
            );
          }
          if (o.path == '/demo/otp/kirim') {
            kirim++;
            return ok(o, {'kadaluarsa_detik': 300});
          }
          if (o.path == '/demo/otp/verifikasi') {
            final kode = (o.data as Map)['kode'];
            return kode == '482913'
                ? ok(o, {'identitas_token': 'tok-123', 'status': 'AKTIF', 'mulai': t0.toIso8601String()})
                : gagal(o, 422, {
                    'success': false,
                    'errors': {
                      'kode': ['Kode tidak cocok atau sudah kedaluwarsa.'],
                    },
                  });
          }
          return gagal(o, 404);
        }),
        st,
      );

      final awal = await svc.periksa(mulaiBaru: true);
      expect(awal.kode, KodeMasaCoba.butuhIdentitas);

      expect(await svc.remote.otpKirim(jenis: 'wa', tujuan: '081234567890'), isNull);
      expect(kirim, 1);
      final salah = await svc.remote.otpVerifikasi(jenis: 'wa', tujuan: '081234567890', kode: '000000');
      expect(salah.galat, 'Kode tidak cocok atau sudah kedaluwarsa.');
      final benar = await svc.remote.otpVerifikasi(jenis: 'wa', tujuan: '081234567890', kode: '482913');
      expect(benar.token, 'tok-123');
      await svc.simpanIdentitasToken(benar.token);

      final lagi = await svc.periksa(mulaiBaru: true);
      expect(lagi.kode, KodeMasaCoba.aktif);
      expect(lagi.sisaHari, 7);
    });

    test('pemeriksaan berkala: GET 404 (belum terdaftar) lalu daftar lewat POST', () async {
      final st = StorageUji();
      final panggilan = <String>[];
      final svc = layanan(
        serverTiruan(t0, (o) {
          panggilan.add('${o.method} ${o.path}');
          if (o.method == 'GET') return gagal(o, 404);
          return ok(o, {'status': 'AKTIF', 'mulai': t0.toIso8601String(), 'waktu_server': t0.toIso8601String()});
        }),
        st,
      );
      await svc.periksa(mulaiBaru: true); // POST
      await svc.periksa(); // GET 404 -> POST
      expect(panggilan.where((p) => p.startsWith('GET')).length, 1);
      expect(panggilan.where((p) => p.startsWith('POST')).length, 2);
    });

    test('server DIBLOKIR: diblokir, sisa 0', () async {
      final st = StorageUji();
      final svc = layanan(
        serverTiruan(t0, (o) => ok(o, {'status': 'DIBLOKIR', 'waktu_server': t0.toIso8601String()})),
        st,
      );
      final r = await svc.periksa(mulaiBaru: true);
      expect(r.kode, KodeMasaCoba.diblokir);
      expect(r.sisaHari, 0);
    });
  });
}
