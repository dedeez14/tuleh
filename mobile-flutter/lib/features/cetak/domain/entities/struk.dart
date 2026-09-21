import '../../../../core/utils/satuan_terukur.dart' as ukur;

/// Isi struk yang akan dicetak ke printer thermal.
/// Sengaja bebas dari detail transport (ESC/POS) agar bisa diuji sebagai data.
class StrukBaris {
  const StrukBaris({
    required this.nama,
    required this.kuantitas,
    required this.harga,
    this.satuan,
    this.nominalDiminta,
    this.dijualPerUkuran,
  });

  final String nama;
  final num kuantitas;
  final double harga;

  /// Satuan ukur (Kg, liter, meter). Dicetak di struk supaya pelanggan tahu
  /// "0,74 Kg", bukan "0,74" yang menggantung. Null untuk barang hitungan.
  final String? satuan;

  /// Rupiah yang diminta pelanggan (baris per nominal) — dicetak
  /// "(diminta Rp 20.000)" di bawah barisnya. Null untuk baris biasa.
  final double? nominalDiminta;

  /// Penanda terukur dari mode jual produk (server 2026-09-14): satuan yang
  /// tak ada di tabel ("Karung") tetap dicetak sebagai ukuran. Null = tebak
  /// dari [satuan].
  final bool? dijualPerUkuran;

  /// Baris yang dijual per ukuran (satuannya ikut dicetak).
  bool get terukur => dijualPerUkuran ?? ukur.apakahTerukur(satuan);

  /// "0,74 Kg" atau "2" — dipakai struk teks & ESC/POS.
  String get labelKuantitas => ukur.PerilakuJual(
    terukur: terukur,
    bolehNominal: false,
    langkah: 1,
    satuan: satuan ?? '',
  ).label(kuantitas);

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
    this.pelanggan,
    this.diskon,
    this.judul,
    this.rujukan,
    this.alasan,
    this.labelTotal = 'TOTAL',
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

  /// Nama pelanggan (bila transaksi dikaitkan ke pelanggan).
  final String? pelanggan;

  /// Potongan diskon transaksi (rupiah); [total] sudah setelah potongan.
  final double? diskon;

  /// Judul di bawah kepala toko (mis. "NOTA REFUND"); null = struk transaksi biasa.
  final String? judul;

  /// Nomor dokumen yang dirujuk (nota refund → nomor transaksi asal).
  final String? rujukan;

  /// Alasan (refund) — dicetak di bawah total, dibungkus per kata.
  final String? alasan;

  /// Label baris total: "TOTAL" untuk transaksi, "TOTAL REFUND" untuk nota refund.
  final String labelTotal;

  /// Baris terukur dihitung satu item: "0,74 kg" bukan nol item (0,4 kg
  /// membulat ke nol) dan bukan pula 0,74 item.
  int get jumlahItem =>
      baris.fold<int>(0, (s, b) => s + (b.terukur ? 1 : b.kuantitas.round()));

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
        {
          'nama': b.nama,
          'kuantitas': b.kuantitas,
          'harga': b.harga,
          'satuan': ?b.satuan,
          'terukur': ?b.dijualPerUkuran,
          'nominal_diminta': ?b.nominalDiminta,
        },
    ],
    'total': total,
    'metode': metode,
    'dibayar': dibayar,
    'kembalian': kembalian,
    'catatan_kaki': catatanKaki,
    'barcode': barcode,
    'logo_url': logoUrl,
    'demo': demo,
    'pelanggan': pelanggan,
    'diskon': diskon,
    'judul': judul,
    'rujukan': rujukan,
    'alasan': alasan,
    'label_total': labelTotal,
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
                satuan: b['satuan']?.toString(),
                nominalDiminta: d(b['nominal_diminta']),
                dijualPerUkuran: b['terukur'] is bool ? b['terukur'] as bool : null,
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
      pelanggan: j['pelanggan']?.toString(),
      diskon: d(j['diskon']),
      judul: j['judul']?.toString(),
      rujukan: j['rujukan']?.toString(),
      alasan: j['alasan']?.toString(),
      labelTotal: (j['label_total'] ?? 'TOTAL').toString(),
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
    pelanggan: pelanggan,
    diskon: diskon,
    judul: judul,
    rujukan: rujukan,
    alasan: alasan,
    labelTotal: labelTotal,
  );
}
