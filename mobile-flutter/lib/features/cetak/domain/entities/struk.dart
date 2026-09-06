/// Isi struk yang akan dicetak ke printer thermal.
/// Sengaja bebas dari detail transport (ESC/POS) agar bisa diuji sebagai data.
class StrukBaris {
  const StrukBaris({
    required this.nama,
    required this.kuantitas,
    required this.harga,
  });

  final String nama;
  final num kuantitas;
  final double harga;

  double get subtotal => harga * kuantitas;
}

class Struk {
  const Struk({
    required this.namaToko,
    required this.nomor,
    required this.waktu,
    required this.baris,
    required this.total,
    this.alamat,
    this.telepon,
    this.kasir,
    this.metode,
    this.dibayar,
    this.kembalian,
    this.catatanKaki,
    this.barcode,
    this.logoUrl,
    this.demo = false,
  });

  final String namaToko;
  final String? alamat;
  final String? telepon;
  final String nomor;
  final DateTime waktu;
  final String? kasir;
  final List<StrukBaris> baris;
  final double total;
  final String? metode;
  final double? dibayar;
  final double? kembalian;
  final String? catatanKaki;

  /// Isi barcode/QR di kaki struk (mis. nomor nota untuk pelacakan).
  final String? barcode;

  /// URL logo toko untuk kepala struk (null = tanpa logo).
  final String? logoUrl;

  /// Dibuat di Mode Demo: struk bertanda "MODE DEMO — bukan bukti pembayaran".
  final bool demo;

  int get jumlahItem =>
      baris.fold<int>(0, (s, b) => s + b.kuantitas.round());

  /// Transaksi offline menyimpan struk apa adanya untuk cetak ulang.
  Map<String, dynamic> toJson() => {
    'nama_toko': namaToko,
    'alamat': alamat,
    'telepon': telepon,
    'nomor': nomor,
    'waktu': waktu.toIso8601String(),
    'kasir': kasir,
    'baris': [
      for (final b in baris)
        {'nama': b.nama, 'kuantitas': b.kuantitas, 'harga': b.harga},
    ],
    'total': total,
    'metode': metode,
    'dibayar': dibayar,
    'kembalian': kembalian,
    'catatan_kaki': catatanKaki,
    'barcode': barcode,
    'logo_url': logoUrl,
    'demo': demo,
  };

  factory Struk.fromJson(Map<String, dynamic> j) {
    double? d(dynamic v) => v == null ? null : (v as num).toDouble();
    return Struk(
      namaToko: (j['nama_toko'] ?? '').toString(),
      alamat: j['alamat']?.toString(),
      telepon: j['telepon']?.toString(),
      nomor: (j['nomor'] ?? '-').toString(),
      waktu: DateTime.tryParse('${j['waktu'] ?? ''}') ?? DateTime.now(),
      kasir: j['kasir']?.toString(),
      baris: [
        if (j['baris'] is List)
          for (final b in j['baris'] as List)
            if (b is Map)
              StrukBaris(
                nama: (b['nama'] ?? '-').toString(),
                kuantitas: (b['kuantitas'] as num?) ?? 0,
                harga: d(b['harga']) ?? 0,
              ),
      ],
      total: d(j['total']) ?? 0,
      metode: j['metode']?.toString(),
      dibayar: d(j['dibayar']),
      kembalian: d(j['kembalian']),
      catatanKaki: j['catatan_kaki']?.toString(),
      barcode: j['barcode']?.toString(),
      logoUrl: j['logo_url']?.toString(),
      demo: j['demo'] == true,
    );
  }

  Struk salinDengan({String? nomor, String? barcode, String? catatanKaki}) => Struk(
    namaToko: namaToko,
    alamat: alamat,
    telepon: telepon,
    nomor: nomor ?? this.nomor,
    waktu: waktu,
    kasir: kasir,
    baris: baris,
    total: total,
    metode: metode,
    dibayar: dibayar,
    kembalian: kembalian,
    catatanKaki: catatanKaki ?? this.catatanKaki,
    barcode: barcode ?? this.barcode,
    logoUrl: logoUrl,
    demo: demo,
  );
}
