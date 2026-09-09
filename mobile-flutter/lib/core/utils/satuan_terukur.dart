/// Aturan barang yang dijual per ukuran (kilo, liter, meter) — bukan per potong.
///
/// Server hanya mengirim `satuan` sebagai teks bebas, jadi klien yang
/// menerjemahkannya. Satuan yang tidak dikenal sengaja dianggap TIDAK terukur
/// supaya perilaku lama (ketuk = tambah 1) tidak berubah diam-diam.
///
/// Padanan JavaScript: `frontend/src/renderer/js/lib/satuan-terukur.js` —
/// keduanya harus punya tabel dan pembulatan yang sama.
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

/// true bila barang dengan [satuan] ini dijual per ukuran.
bool apakahTerukur(String? satuan) => _langkah.containsKey(_kunci(satuan));

/// Langkah terkecil untuk [satuan] (1 = barang hitungan biasa).
double langkahSatuan(String? satuan) => _langkah[_kunci(satuan)] ?? 1;

/// Bulatkan [kuantitas] ke kelipatan langkah satuannya.
///
/// [keBawah] dipakai saat kuantitas berasal dari nominal: tagihan tidak boleh
/// melebihi uang yang diminta pelanggan.
double bulatkanKuantitas(double kuantitas, String? satuan, {bool keBawah = false}) {
  final langkah = langkahSatuan(satuan);
  if (langkah <= 0 || kuantitas <= 0) return 0;
  final kelipatan = kuantitas / langkah;
  final bulat = keBawah ? kelipatan.floorToDouble() : kelipatan.roundToDouble();
  // Kalikan balik lewat pembulatan 6 desimal agar 0.1*3 tidak jadi 0.30000000000000004.
  return double.parse((bulat * langkah).toStringAsFixed(6));
}

/// Kuantitas yang setara dengan [nominal] rupiah pada [harga] per satuan.
///
/// Mengembalikan 0 bila harga tidak sah atau nominalnya belum cukup untuk satu
/// langkah — pemanggil menampilkan pesan minimum belanja.
double kuantitasDariNominal(double nominal, double harga, String? satuan) {
  if (harga <= 0 || nominal <= 0) return 0;
  return bulatkanKuantitas(nominal / harga, satuan, keBawah: true);
}

/// Nominal terkecil yang bisa dilayani untuk [harga] per satuan (satu langkah).
double minimalNominal(double harga, String? satuan) =>
    (harga * langkahSatuan(satuan)).ceilToDouble();

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
