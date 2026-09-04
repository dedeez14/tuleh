import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/utils/format.dart';
import 'package:tuleh_pos/features/pesanan/data/datasources/pesanan_remote_datasource.dart';
import 'package:tuleh_pos/features/pesanan/domain/entities/pesanan.dart';
import 'package:tuleh_pos/features/pesanan/domain/logic/papan_logic.dart';
import 'package:tuleh_pos/features/toko/domain/entities/toko_manifest.dart';

/// Papan pesanan Flutter — kolom & aksi kartu berasal dari manifest toko,
/// sehingga satu layar melayani bakso, laundry, bengkel, doorsmeer, salon,
/// dan bidang usaha baru yang belum dikenal aplikasi.

// Lifecycle nyata dari manifest server / Mode Demo desktop.
const _bakso = ['ANTRIAN', 'DIPROSES', 'READY', 'SELESAI'];
const _laundry = [
  'ANTRIAN',
  'DIPROSES',
  'PENCUCIAN',
  'PENGERINGAN',
  'LIPAT',
  'SIAP_AMBIL',
  'SELESAI',
];
const _bengkel = [
  'ANTRIAN',
  'PEMERIKSAAN',
  'PENGERJAAN',
  'SIAP_AMBIL',
  'SELESAI',
];
const _doorsmeer = [
  'ANTRIAN',
  'PENCUCIAN',
  'PENGERINGAN',
  'FINISHING',
  'SIAP_AMBIL',
  'SELESAI',
];
const _salon = ['ANTRIAN', 'DILAYANI', 'SELESAI'];

Pesanan _order({
  String id = 'ORD-1',
  required String stage,
  String? bayar = 'LUNAS',
  String? noAntrian = 'B-001',
  String? meja,
}) => Pesanan(
  id: id,
  stage: stage,
  bayar: bayar,
  noAntrian: noAntrian,
  meja: meja,
  total: 50000,
);

void main() {
  group('stageLabel', () {
    test('tahap jasa kendaraan & salon punya label manusiawi', () {
      expect(stageLabel('PEMERIKSAAN'), 'Pemeriksaan');
      expect(stageLabel('PENGERJAAN'), 'Pengerjaan');
      expect(stageLabel('DILAYANI'), 'Dilayani');
      expect(stageLabel('FINISHING'), 'Finishing & Poles');
    });

    test('label lama tetap; tahap tak dikenal → Title Case; kosong aman', () {
      expect(stageLabel('SIAP_AMBIL'), 'Siap Diambil');
      expect(stageLabel('MENUNGGU_BAYAR'), 'Menunggu Bayar');
      expect(stageLabel('READY'), 'Siap');
      expect(stageLabel('TAHAP_BARU_X'), 'Tahap Baru X');
      expect(stageLabel(''), '');
      expect(stageLabel(null), '');
    });
  });

  group('kolom papan', () {
    test('tahap terminal tidak jadi kolom', () {
      expect(kolomPapan(_bakso), ['ANTRIAN', 'DIPROSES', 'READY']);
      expect(kolomPapan(_salon), ['ANTRIAN', 'DILAYANI']);
      expect(kolomPapan(_doorsmeer), [
        'ANTRIAN',
        'PENCUCIAN',
        'PENGERINGAN',
        'FINISHING',
        'SIAP_AMBIL',
      ]);
    });

    test('MENUNGGU_BAYAR hanya muncul bila ada order QR meja belum bayar', () {
      expect(kolomPapan(_bakso, adaMenungguBayar: true).first, 'MENUNGGU_BAYAR');
      expect(kolomPapan(_bakso).contains('MENUNGGU_BAYAR'), isFalse);
    });

    test('toko tanpa alur bertahap tidak punya kolom', () {
      expect(kolomPapan(const ['SELESAI']), isEmpty);
      expect(kolomPapan(const []), isEmpty);
    });

    test('alur panjang (>4 tahap) memakai ambang umur jam, bukan menit', () {
      expect(ambangUmur(_bakso), umurCepat);
      expect(ambangUmur(_salon), umurCepat);
      expect(ambangUmur(_laundry), umurPanjang);
      expect(ambangUmur(_doorsmeer), umurPanjang);
    });
  });

  group('tahapBerikut', () {
    test('mengikuti urutan manifest tiap bidang usaha', () {
      expect(tahapBerikut('ANTRIAN', _bengkel), 'PEMERIKSAAN');
      expect(tahapBerikut('PEMERIKSAAN', _bengkel), 'PENGERJAAN');
      expect(tahapBerikut('PENGERINGAN', _doorsmeer), 'FINISHING');
      expect(tahapBerikut('ANTRIAN', _salon), 'DILAYANI');
    });

    test('order QR meja belum bayar masuk ke tahap pertama', () {
      expect(tahapBerikut('MENUNGGU_BAYAR', _bakso), 'ANTRIAN');
    });

    test('tahap terminal / tak dikenal tidak punya lanjutan', () {
      expect(tahapBerikut('SELESAI', _bakso), isNull);
      expect(tahapBerikut('ENTAH', _bakso), isNull);
      expect(tahapBerikut('ANTRIAN', const []), isNull);
    });
  });

  group('aksi kartu', () {
    test('order QR meja belum bayar → Konfirmasi Bayar', () {
      final o = _order(stage: 'MENUNGGU_BAYAR', bayar: 'BELUM');
      expect(aksiKartu(o, _bakso), AksiKartu.konfirmasiBayar);
      expect(
        labelAksi(AksiKartu.konfirmasiBayar, o.stage, _bakso),
        'Konfirmasi Bayar',
      );
    });

    test('kolom terakhir + nota belum lunas → Lunasi & Serahkan', () {
      final o = _order(stage: 'SIAP_AMBIL', bayar: 'BELUM');
      expect(aksiKartu(o, _bengkel), AksiKartu.lunasi);
      expect(
        labelAksi(AksiKartu.lunasi, o.stage, _bengkel),
        'Lunasi & Serahkan',
      );
    });

    test('kolom terakhir + sudah lunas → tandai selesai', () {
      final o = _order(stage: 'SIAP_AMBIL');
      expect(aksiKartu(o, _bengkel), AksiKartu.selesai);
      expect(labelAksi(AksiKartu.selesai, o.stage, _bengkel), 'Selesai ✓');
    });

    test('tahap tengah → maju ke tahap berikutnya', () {
      final o = _order(stage: 'PENCUCIAN');
      expect(aksiKartu(o, _doorsmeer), AksiKartu.maju);
      expect(labelAksi(AksiKartu.maju, o.stage, _doorsmeer), '→ Pengeringan');
    });

    test('salon: nota belum bayar di DILAYANI → Lunasi (tahap terakhir)', () {
      final o = _order(stage: 'DILAYANI', bayar: 'BELUM');
      expect(aksiKartu(o, _salon), AksiKartu.lunasi);
    });

    test('pesanan yang sudah terminal tidak punya aksi', () {
      expect(aksiKartu(_order(stage: 'SELESAI'), _bakso), isNull);
    });
  });

  group('umur pesanan', () {
    test('dihitung dari created_at, tidak pernah negatif', () {
      final now = DateTime(2026, 9, 4, 12, 0);
      final o = Pesanan(
        id: 'x',
        stage: 'ANTRIAN',
        createdAt: now.subtract(const Duration(minutes: 25)),
      );
      expect(umurMenit(o, now: now), 25);

      final masaDepan = Pesanan(
        id: 'y',
        stage: 'ANTRIAN',
        createdAt: now.add(const Duration(minutes: 5)),
      );
      expect(umurMenit(masaDepan, now: now), 0);
      expect(umurMenit(const Pesanan(id: 'z', stage: 'ANTRIAN')), 0);
    });

    test('fmtUmur: menit lalu jam+menit', () {
      expect(fmtUmur(25), '25 mnt');
      expect(fmtUmur(60), '1 j 0 mnt');
      expect(fmtUmur(135), '2 j 15 mnt');
    });
  });

  group('parsing pesanan dari server', () {
    test('bentuk /orders → entitas, termasuk tiket bon meja', () {
      final rows = PesananRemoteDataSource.parseRows([
        {
          'id': 'ORD-9',
          'stage': 'PENGERJAAN',
          'no_antrian': 'B-003',
          'bayar': 'BELUM',
          'total': 100000,
          'pelanggan': 'Siti Aminah (D 1290 ABC)',
          'created_at': '2026-09-04T03:00:00.000Z',
          'items': [
            {'nama': 'Servis Ringan Motor', 'kuantitas': 1},
            {'nama': 'Oli Mesin 1 L', 'kuantitas': 2},
          ],
        },
        {'id': 'ORD-10', 'stage': 'ANTRIAN', 'meja': 'Meja 3', 'ronde': 2},
      ]);

      expect(rows.length, 2);
      final a = rows.first;
      expect(a.stage, 'PENGERJAAN');
      expect(a.label, 'B-003');
      expect(a.belumBayar, isTrue);
      expect(a.items.length, 2);
      expect(a.items[1].kuantitas, 2);
      expect(a.createdAt, isNotNull);

      final b = rows[1];
      expect(b.dariMeja, isTrue);
      expect(b.label, 'Meja 3'); // identitas tiket bon = meja
      expect(b.ronde, 2);
      expect(b.belumBayar, isFalse);
    });

    test('data terbungkus {rows: []} (paginasi) ikut terbaca', () {
      final rows = PesananRemoteDataSource.parseRows({
        'rows': [
          {'id': 'ORD-1', 'stage': 'ANTRIAN'},
        ],
      });
      expect(rows.single.id, 'ORD-1');
    });

    test('bentuk tak terduga → daftar kosong, bukan crash', () {
      expect(PesananRemoteDataSource.parseRows(null), isEmpty);
      expect(PesananRemoteDataSource.parseRows('bukan list'), isEmpty);
    });
  });

  group('manifest toko', () {
    test('normalisasi bentuk server: menus, lifecycle, stasiun', () {
      final m = TokoManifest.fromJson({
        'vertical_code': 'doorsmeer',
        'menus': [
          {'id': 'kasir', 'label': 'Kasir / Penerimaan', 'order': 2},
          {
            'id': 'proses',
            'label': 'Papan Cuci',
            'route_key': 'proses',
            'order': 3,
          },
        ],
        'capabilities': ['stages', 'queue'],
        'transaction_flow': ['INTAKE', 'PAYMENT_OR_LATER'],
        'lifecycle': {
          'states': _doorsmeer,
          'transitions': [
            {'from': 'ANTRIAN', 'to': 'PENCUCIAN'},
          ],
        },
        'station_types': [
          {'type': 'cashier', 'label': 'Kasir', 'min': 1},
          {'type': 'washing', 'label': 'Pencucian', 'min': 1},
        ],
        'payment_modes': ['TUNAI', 'QRIS'],
      });

      expect(m.verticalCode, 'doorsmeer');
      expect(m.lifecycleStates, _doorsmeer);
      expect(m.punyaPapanPesanan, isTrue);
      expect(m.bolehBayarNanti, isTrue);
      expect(m.menuPapan?.label, 'Papan Cuci'); // label ikut bidang usaha
      expect(m.stationTypes.map((s) => s.type), ['cashier', 'washing']);
      expect(m.paymentModes, ['TUNAI', 'QRIS']);
    });

    test('route_key kosong → jatuh ke id menu', () {
      final m = TokoManifest.fromJson({
        'menus': [
          {'id': 'antrian', 'label': 'Antrian Cukur'},
        ],
        'lifecycle': {'states': _salon},
      });
      expect(m.menuPapan?.routeKey, 'antrian');
      expect(m.menuPapan?.label, 'Antrian Cukur');
    });

    test('toko tanpa alur bertahap tidak menampilkan papan', () {
      final m = TokoManifest.fromJson({
        'vertical_code': 'minimarket',
        'menus': [
          {'id': 'kasir', 'label': 'Kasir'},
        ],
        'lifecycle': {'states': ['SELESAI']},
      });
      expect(m.punyaPapanPesanan, isFalse);
      expect(m.menuPapan, isNull);
    });

    test('manifest kosong (server lama / 404) aman dipakai', () {
      const m = TokoManifest();
      expect(m.punyaPapanPesanan, isFalse);
      expect(m.bolehBayarNanti, isFalse);
      expect(m.menus, isEmpty);
      expect(TokoManifest.fromJson(const {}).lifecycleStates, isEmpty);
    });
  });

  group('fmtQty', () {
    test('bulat tanpa desimal; pecahan pakai koma (layanan kiloan)', () {
      expect(fmtQty(2), '2');
      expect(fmtQty(2.0), '2');
      expect(fmtQty(4.5), '4,5');
      expect(fmtQty(0.25), '0,25');
    });
  });
}
