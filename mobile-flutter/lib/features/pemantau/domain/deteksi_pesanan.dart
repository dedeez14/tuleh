import '../../../core/utils/format.dart';

/// Jenis kejadian yang layak dinotifikasikan ke kasir.
enum JenisKejadian { pesananBaru, tambahPesanan, mintaBayar }

/// Satu kejadian → satu notifikasi.
class KejadianPesanan {
  const KejadianPesanan({
    required this.jenis,
    required this.judul,
    required this.isi,
    required this.tujuan,
  });

  final JenisKejadian jenis;
  final String judul;
  final String isi;

  /// Rute aplikasi yang dibuka saat notifikasi diketuk: '/meja' atau
  /// '/aktivitas' (papan pesanan).
  final String tujuan;

  @override
  String toString() => '$jenis: $judul — $isi';
}

/// Potret keadaan terakhir yang sudah dilihat pemantau. Disimpan di memori
/// isolate layanan; hilang saat layanan berhenti (poll pertama setelah start
/// hanya membuat potret, tidak menotifikasi apa pun — mencegah banjir).
class PotretPesanan {
  const PotretPesanan({this.pesanan = const {}, this.meja = const {}});

  /// id pesanan (/orders) → stage.
  final Map<String, String> pesanan;

  /// id meja → potret bon di meja itu (null bila kosong).
  final Map<String, PotretMeja?> meja;
}

class PotretMeja {
  const PotretMeja({
    required this.billId,
    required this.total,
    required this.jumlahItem,
    required this.status,
  });

  final String billId;
  final double total;
  final int jumlahItem;
  final String status;

  bool get mintaBayar => status.toUpperCase() == 'BILL';
}

/// Hasil satu putaran deteksi.
class HasilDeteksi {
  const HasilDeteksi({required this.potret, required this.kejadian});
  final PotretPesanan potret;
  final List<KejadianPesanan> kejadian;
}

/// Membandingkan data terbaru server dengan potret sebelumnya.
///
/// Sumber "pesanan dari meja" di MOVERA ada dua, dipantau keduanya:
/// - `/orders` (toko bertahap: pesanan QR meja masuk sebagai order dengan
///   label meja dan `bayar: BELUM`) → id baru = pesanan baru;
/// - `/bills` (toko bermeja): bon muncul atau totalnya bertambah = pelanggan
///   memesan/menambah dari QR meja; status `BILL` = pelanggan minta bayar.
///
/// Logika ini murni (tanpa I/O) agar mudah diuji.
class DeteksiPesanan {
  const DeteksiPesanan();

  HasilDeteksi bandingkan({
    required PotretPesanan? sebelum,
    required List<dynamic> orders,
    required List<dynamic> tables,
  }) {
    final pesananBaru = <String, String>{};
    final mejaBaru = <String, PotretMeja?>{};
    final kejadian = <KejadianPesanan>[];
    final pertama = sebelum == null;

    for (final o in orders) {
      if (o is! Map) continue;
      final id = o['id']?.toString();
      if (id == null || id.isEmpty) continue;
      final stage = (o['stage'] ?? '').toString();
      pesananBaru[id] = stage;
      if (pertama || sebelum.pesanan.containsKey(id)) continue;
      kejadian.add(
        KejadianPesanan(
          jenis: JenisKejadian.pesananBaru,
          judul: 'Pesanan baru ${_labelOrder(o)}'.trim(),
          isi: _isiOrder(o),
          tujuan: '/aktivitas',
        ),
      );
    }

    for (final t in tables) {
      if (t is! Map) continue;
      final id = t['id']?.toString();
      if (id == null || id.isEmpty) continue;
      final nomor = (t['nomor'] ?? t['kode'] ?? '?').toString();
      final bill = t['bill'];
      final kini = bill is Map ? _potretBill(bill) : null;
      mejaBaru[id] = kini;
      if (pertama) continue;

      final lalu = sebelum.meja[id];
      if (kini == null) continue; // meja kosong / bon selesai
      final bonBaru = lalu == null || lalu.billId != kini.billId;
      if (bonBaru && (kini.jumlahItem > 0 || kini.total > 0)) {
        kejadian.add(
          KejadianPesanan(
            jenis: JenisKejadian.pesananBaru,
            judul: 'Meja $nomor: pesanan baru',
            isi: _isiMeja(kini),
            tujuan: '/meja',
          ),
        );
      } else if (!bonBaru &&
          (kini.jumlahItem > lalu.jumlahItem || kini.total > lalu.total)) {
        final tambah = kini.total - lalu.total;
        kejadian.add(
          KejadianPesanan(
            jenis: JenisKejadian.tambahPesanan,
            judul: 'Meja $nomor: tambah pesanan',
            isi: tambah > 0
                ? '+${fmtIDR(tambah)} · total ${fmtIDR(kini.total)}'
                : _isiMeja(kini),
            tujuan: '/meja',
          ),
        );
      }
      final baruMintaBayar = kini.mintaBayar && !(lalu?.mintaBayar ?? false);
      if (baruMintaBayar) {
        kejadian.add(
          KejadianPesanan(
            jenis: JenisKejadian.mintaBayar,
            judul: 'Meja $nomor minta bayar',
            isi: 'Total ${fmtIDR(kini.total)}',
            tujuan: '/meja',
          ),
        );
      }
    }

    return HasilDeteksi(
      potret: PotretPesanan(pesanan: pesananBaru, meja: mejaBaru),
      kejadian: kejadian,
    );
  }

  static PotretMeja _potretBill(Map<dynamic, dynamic> b) {
    final total = b['total'] ?? b['grand_total'];
    final item = b['jumlah_item'] ?? b['items_count'];
    return PotretMeja(
      billId: (b['id'] ?? '').toString(),
      total: total is num ? total.toDouble() : double.tryParse('$total') ?? 0,
      jumlahItem: item is num ? item.toInt() : int.tryParse('$item') ?? 0,
      status: (b['status'] ?? '').toString(),
    );
  }

  static String _labelOrder(Map<dynamic, dynamic> o) {
    final antrian = o['no_antrian'] ?? o['nomor_antrian'] ?? o['nomor'];
    return antrian == null ? '' : '$antrian';
  }

  static String _isiOrder(Map<dynamic, dynamic> o) {
    final meja = o['meja'] ?? o['meja_label'];
    final pelanggan = o['pelanggan'] is Map
        ? (o['pelanggan'] as Map)['nama']
        : o['pelanggan'];
    final total = o['total'] ?? o['grand_total'];
    final bagian = <String>[
      if (meja != null && '$meja'.isNotEmpty) '$meja',
      if (pelanggan != null && '$pelanggan'.isNotEmpty) '$pelanggan',
      if (total is num && total > 0) fmtIDR(total.toDouble()),
    ];
    return bagian.isEmpty ? 'Ketuk untuk membuka papan pesanan' : bagian.join(' · ');
  }

  static String _isiMeja(PotretMeja m) => [
    if (m.jumlahItem > 0) '${m.jumlahItem} item',
    if (m.total > 0) fmtIDR(m.total),
  ].join(' · ');
}
