import 'package:flutter/services.dart';

/// Pemformat kolom uang: yang diketik `50000` tampil `50.000` seketika, seperti
/// kalkulator kasir — kasir tak perlu menghitung nol. Hanya angka yang
/// diterima; pemisah ribuan titik (konvensi Indonesia); tanpa desimal karena
/// rupiah di kasir selalu bulat.
///
/// Nilai angka dibaca lagi dengan [parseRupiah] — JANGAN `double.parse` teks
/// kolom langsung, karena titiknya akan dibaca sebagai desimal.
class RupiahInputFormatter extends TextInputFormatter {
  const RupiahInputFormatter({this.maksDigit = 12});

  /// Batas digit agar angka tak meledak (Rp 999 miliar cukup untuk kasir).
  final int maksDigit;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digit = _hanyaDigit(newValue.text);
    if (digit.isEmpty) return const TextEditingValue();
    if (digit.length > maksDigit) return oldValue;

    // Nol di depan dibuang ("0" lalu ketik 5 → "5", bukan "05").
    final bersih = digit.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    final teks = formatRupiahDigit(bersih);

    // Kursor: pertahankan jumlah digit di kiri kursor, lalu petakan ke posisi
    // dalam teks berformat — agar mengedit di tengah tidak melompat ke akhir.
    final digitKiri = _hanyaDigit(
      newValue.text.substring(
        0,
        newValue.selection.baseOffset.clamp(0, newValue.text.length),
      ),
    ).length;
    final digitKiriBersih =
        (digitKiri - (digit.length - bersih.length)).clamp(0, bersih.length);
    var posisi = 0;
    var terlihat = 0;
    while (posisi < teks.length && terlihat < digitKiriBersih) {
      if (teks[posisi] != '.') terlihat++;
      posisi++;
    }

    return TextEditingValue(
      text: teks,
      selection: TextSelection.collapsed(offset: posisi),
    );
  }

  static String _hanyaDigit(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');
}

/// "50000" → "50.000". Input harus digit saja.
String formatRupiahDigit(String digit) {
  final b = StringBuffer();
  for (var i = 0; i < digit.length; i++) {
    final sisa = digit.length - i;
    b.write(digit[i]);
    if (sisa > 1 && sisa % 3 == 1) b.write('.');
  }
  return b.toString();
}

/// Teks kolom berformat → nilai. "50.000" → 50000; kosong → 0.
double parseRupiah(String? teks) {
  if (teks == null) return 0;
  final digit = teks.replaceAll(RegExp(r'[^0-9]'), '');
  if (digit.isEmpty) return 0;
  return double.tryParse(digit) ?? 0;
}

/// Nilai → teks kolom ("50.000"), untuk mengisi controller dari kode
/// (mis. chip saran nominal).
String teksRupiah(num nilai) => formatRupiahDigit(nilai.round().toString());
