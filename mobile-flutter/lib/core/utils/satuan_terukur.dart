/// Aturan barang yang dijual per ukuran (kilo, liter, meter) — bukan per potong.
///
/// Server sejak 2026-09-14 mengirim perilaku jual PER PRODUK: `mode_jual`
/// (SATUAN | UKUR | UKUR_NOMINAL, dari master server), `desimal`,
/// `boleh_nominal`, `langkah` — hasil pilihan produk, satuan terukur, dan
/// bidang usaha toko. Bila ada, itu yang dipakai ([PerilakuJual.dari]). Tabel
/// satuan di bawah hanya cadangan untuk server lama yang cuma mengirim `satuan`
/// sebagai teks bebas; satuan yang tidak dikenal sengaja dianggap TIDAK terukur
/// supaya perilaku lama (ketuk = tambah 1) tidak berubah diam-diam.
///
/// Produk memakai [PerilakuJual] (lihat `Product.perilaku`); fungsi tingkat
/// atas menerima teks satuan untuk pemanggil yang hanya punya satuan (struk,
/// bon meja, detail transaksi).
///
/// Padanan JavaScript: `frontend/src/renderer/js/lib/satuan-terukur.js` dan
/// server `Modules/POS/app/Support/PosModeJualProduk.php` — tabel dan
/// pembulatannya harus sama persis.
library;

/// Satuan terukur → langkah terkecil yang masuk akal ditimbang/diukur.
const _langkah = <String, double>{
  'kg': 0.01,
  'kilo': 0.01,
  'kilogram': 0.01,
  'gram': 10,
  'gr': 10,
  'g': 10,
  'ons': 0.1,
  'liter': 0.01,
  'ltr': 0.01,
  'l': 0.01,
  'ml': 10,
  'meter': 0.1,
  'mtr': 0.1,
  'm': 0.1,
};

String _kunci(String? satuan) => (satuan ?? '').trim().toLowerCase();

/// Cara satu barang dijual di kasir: per jumlah bulat, per ukuran, atau per
/// ukuran sekaligus per rupiah ("beli Rp 20.000").
class PerilakuJual {
  const PerilakuJual({
    required this.terukur,
    required this.bolehNominal,
    required this.langkah,
    this.satuan = '',
  });

  /// Tebakan dari nama satuan saja (server lama).
  factory PerilakuJual.dariSatuan(String? satuan) {
    final langkah = _langkah[_kunci(satuan)];
    return PerilakuJual(
      terukur: langkah != null,
      bolehNominal: langkah != null,
      langkah: langkah ?? 1,
      satuan: satuan ?? '',
    );
  }

  /// Dari bidang produk server. [modeJual] kosong = server lama → tabel satuan.
  factory PerilakuJual.dari({
    String? satuan,
    String? modeJual,
    bool? desimal,
    bool? bolehNominal,
    double? langkah,
  }) {
    if (modeJual == null || modeJual.trim().isEmpty) {
      return PerilakuJual.dariSatuan(satuan);
    }
    final terukur = desimal == true;
    final l = langkah ?? 0;
    return PerilakuJual(
      terukur: terukur,
      bolehNominal: terukur && bolehNominal == true,
      langkah: terukur && l > 0 ? l : 1,
      satuan: satuan ?? '',
    );
  }

  /// true = dijual per ukuran (ketuk membuka lembar ukuran, bukan +1).
  final bool terukur;

  /// true = kasir boleh mengisi nominal rupiah yang diminta pelanggan.
  final bool bolehNominal;

  /// Langkah terkecil (1 = barang hitungan biasa).
  final double langkah;

  /// Teks satuan untuk label ("Kg", "Karung").
  final String satuan;

  /// Bulatkan [kuantitas] ke kelipatan [langkah].
  ///
  /// [keBawah] dipakai saat kuantitas berasal dari nominal: tagihan tidak boleh
  /// melebihi uang yang diminta pelanggan.
  double bulatkan(double kuantitas, {bool keBawah = false}) {
    if (langkah <= 0 || kuantitas <= 0) return 0;
    // Lewat 6 desimal dulu (sama dengan server): 0.3 / 0.1 = 2.9999999999999996 harus tetap 3.
    final kelipatan = double.parse((kuantitas / langkah).toStringAsFixed(6));
    final bulat = keBawah ? kelipatan.floorToDouble() : kelipatan.roundToDouble();
    // Kalikan balik lewat pembulatan 6 desimal agar 0.1*3 tidak jadi 0.30000000000000004.
    return double.parse((bulat * langkah).toStringAsFixed(6));
  }

  /// Kuantitas yang setara dengan [nominal] rupiah pada [harga] per satuan.
  ///
  /// Mengembalikan 0 bila harga tidak sah atau nominalnya belum cukup untuk
  /// satu langkah — pemanggil menampilkan pesan minimum belanja.
  double dariNominal(double nominal, double harga) {
    if (harga <= 0 || nominal <= 0) return 0;
    return bulatkan(nominal / harga, keBawah: true);
  }

  /// Nominal terkecil yang bisa dilayani untuk [harga] per satuan (satu langkah).
  double minimalNominal(double harga) => (harga * langkah).ceilToDouble();

  /// "0,74 kg" untuk barang terukur, "2" untuk barang hitungan.
  ///
  /// Satuan hanya ikut bila barangnya memang dijual per ukuran: pada barang
  /// hitungan "2 pcs" tidak menambah informasi apa pun.
  String label(num kuantitas) {
    final teks = satuan.trim();
    return terukur && teks.isNotEmpty
        ? '${fmtQtyRingkas(kuantitas)} $teks'
        : fmtQtyRingkas(kuantitas);
  }
}

/// true bila barang dengan [satuan] ini dijual per ukuran (server lama).
bool apakahTerukur(String? satuan) => PerilakuJual.dariSatuan(satuan).terukur;

/// Langkah terkecil untuk [satuan] (1 = barang hitungan biasa).
double langkahSatuan(String? satuan) => PerilakuJual.dariSatuan(satuan).langkah;

/// Bulatkan [kuantitas] ke kelipatan langkah satuannya — lihat [PerilakuJual.bulatkan].
double bulatkanKuantitas(double kuantitas, String? satuan, {bool keBawah = false}) =>
    PerilakuJual.dariSatuan(satuan).bulatkan(kuantitas, keBawah: keBawah);

/// Kuantitas yang setara dengan [nominal] rupiah — lihat [PerilakuJual.dariNominal].
double kuantitasDariNominal(double nominal, double harga, String? satuan) =>
    PerilakuJual.dariSatuan(satuan).dariNominal(nominal, harga);

/// Nominal terkecil yang bisa dilayani untuk [harga] per satuan (satu langkah).
double minimalNominal(double harga, String? satuan) =>
    PerilakuJual.dariSatuan(satuan).minimalNominal(harga);

/// Kuantitas ringkas untuk label: bilangan bulat tanpa koma, pecahan sampai
/// tiga angka di belakang koma (0,74 / 0,005 kg) memakai koma Indonesia.
String fmtQtyRingkas(num nilai) {
  if (nilai == nilai.roundToDouble()) return nilai.round().toString();
  return nilai
      .toStringAsFixed(3)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '')
      .replaceAll('.', ',');
}

/// Uang untuk [kuantitas] pada [harga] — dibulatkan ke rupiah penuh, sama
/// dengan cara seluruh aplikasi menghitung uang.
double totalBaris(double kuantitas, double harga) => (kuantitas * harga).roundToDouble();

/// "0,74 kg" untuk barang terukur, "2" untuk barang hitungan — lihat [PerilakuJual.label].
String labelKuantitas(num kuantitas, String? satuan) =>
    PerilakuJual.dariSatuan(satuan).label(kuantitas);
