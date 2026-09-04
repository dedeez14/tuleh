import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/features/pemantau/domain/deteksi_pesanan.dart';

/// Pemantau pesanan meja (layanan latar depan). Logika deteksinya murni:
/// bandingkan potret sebelumnya dengan data /orders & /bills terbaru.

Map<String, dynamic> meja(String id, String nomor, {Map<String, dynamic>? bill}) =>
    {'id': id, 'nomor': nomor, 'kode': 'M$nomor', 'bill': bill};

Map<String, dynamic> bill(String id, {double total = 0, int item = 0, String status = 'BUKA'}) =>
    {'id': id, 'total': total, 'jumlah_item': item, 'status': status, 'pax': 2};

void main() {
  const d = DeteksiPesanan();

  test('poll pertama hanya membuat potret — tidak ada notifikasi', () {
    final h = d.bandingkan(
      sebelum: null,
      orders: [
        {'id': 'O1', 'stage': 'MENUNGGU_BAYAR', 'meja': 'Meja 3', 'total': 25000},
      ],
      tables: [meja('T1', '1', bill: bill('B1', total: 40000, item: 3))],
    );
    expect(h.kejadian, isEmpty);
    expect(h.potret.pesanan, {'O1': 'MENUNGGU_BAYAR'});
    expect(h.potret.meja['T1']!.total, 40000);
  });

  test('pesanan QR meja baru di /orders → "Pesanan baru" menuju papan pesanan', () {
    final awal = d.bandingkan(sebelum: null, orders: const [], tables: const []).potret;
    final h = d.bandingkan(
      sebelum: awal,
      orders: [
        {
          'id': 'O7',
          'stage': 'MENUNGGU_BAYAR',
          'no_antrian': 'A-007',
          'meja': 'Meja 5',
          'bayar': 'BELUM',
          'total': 52000,
        },
      ],
      tables: const [],
    );
    expect(h.kejadian, hasLength(1));
    final k = h.kejadian.single;
    expect(k.jenis, JenisKejadian.pesananBaru);
    expect(k.judul, 'Pesanan baru A-007');
    expect(k.isi, 'Meja 5 · Rp 52.000');
    expect(k.tujuan, '/aktivitas');
  });

  test('bon meja muncul, bertambah, lalu minta bayar', () {
    var potret = d.bandingkan(
      sebelum: null,
      orders: const [],
      tables: [meja('T1', '1'), meja('T2', '2')],
    ).potret;

    // Pelanggan memesan dari QR → bon baru dengan item.
    var h = d.bandingkan(
      sebelum: potret,
      orders: const [],
      tables: [meja('T1', '1', bill: bill('B1', total: 30000, item: 2)), meja('T2', '2')],
    );
    expect(h.kejadian.map((k) => k.jenis), [JenisKejadian.pesananBaru]);
    expect(h.kejadian.single.judul, 'Meja 1: pesanan baru');
    expect(h.kejadian.single.isi, '2 item · Rp 30.000');
    expect(h.kejadian.single.tujuan, '/meja');
    potret = h.potret;

    // Tidak berubah → diam.
    h = d.bandingkan(
      sebelum: potret,
      orders: const [],
      tables: [meja('T1', '1', bill: bill('B1', total: 30000, item: 2)), meja('T2', '2')],
    );
    expect(h.kejadian, isEmpty);

    // Tambah pesanan → total naik.
    h = d.bandingkan(
      sebelum: potret,
      orders: const [],
      tables: [meja('T1', '1', bill: bill('B1', total: 45000, item: 3)), meja('T2', '2')],
    );
    expect(h.kejadian.single.jenis, JenisKejadian.tambahPesanan);
    expect(h.kejadian.single.isi, '+Rp 15.000 · total Rp 45.000');
    potret = h.potret;

    // Minta bayar (status BILL) tanpa item baru.
    h = d.bandingkan(
      sebelum: potret,
      orders: const [],
      tables: [meja('T1', '1', bill: bill('B1', total: 45000, item: 3, status: 'BILL')), meja('T2', '2')],
    );
    expect(h.kejadian.single.jenis, JenisKejadian.mintaBayar);
    expect(h.kejadian.single.judul, 'Meja 1 minta bayar');
    potret = h.potret;

    // Masih BILL pada poll berikutnya → tidak diulang.
    h = d.bandingkan(
      sebelum: potret,
      orders: const [],
      tables: [meja('T1', '1', bill: bill('B1', total: 45000, item: 3, status: 'BILL')), meja('T2', '2')],
    );
    expect(h.kejadian, isEmpty);

    // Bon selesai (meja kosong) → diam, potret dibersihkan.
    h = d.bandingkan(sebelum: h.potret, orders: const [], tables: [meja('T1', '1'), meja('T2', '2')]);
    expect(h.kejadian, isEmpty);
    expect(h.potret.meja['T1'], isNull);
  });

  test('bon baru tanpa item (kasir membuka meja sendiri) tidak dinotifikasi', () {
    final potret = d.bandingkan(sebelum: null, orders: const [], tables: [meja('T1', '1')]).potret;
    final h = d.bandingkan(
      sebelum: potret,
      orders: const [],
      tables: [meja('T1', '1', bill: bill('B9'))],
    );
    expect(h.kejadian, isEmpty);
  });

  test('baris rusak diabaikan, tidak melempar', () {
    final h = d.bandingkan(
      sebelum: const PotretPesanan(),
      orders: ['x', 1, null, {'stage': 'A'}, {'id': '', 'stage': 'B'}],
      tables: [null, 'y', {'nomor': '3'}, {'id': 'T', 'bill': 'bukan map'}],
    );
    expect(h.kejadian, isEmpty);
    expect(h.potret.pesanan, isEmpty);
    expect(h.potret.meja, {'T': null});
  });
}
