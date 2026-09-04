const _bulanId = [
  '', 'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
  'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
];

/// ISO/tanggal → "2 Agu 2026" (Bahasa Indonesia). '-' bila kosong/invalid.
String fmtTanggal(String? iso) {
  if (iso == null || iso.isEmpty) return '-';
  final dt = DateTime.tryParse(iso);
  if (dt == null) return iso;
  return '${dt.day} ${_bulanId[dt.month]} ${dt.year}';
}

/// Rupiah ringkas untuk label sumbu grafik (mis. 1250000 → "1,2 jt").
/// Angka penuh tetap dipakai di tabel & tooltip; ini hanya untuk sumbu yang
/// ruangnya sempit.
String fmtIDRSingkat(num value) {
  final n = value.abs();
  final tanda = value < 0 ? '-' : '';
  if (n >= 1000000000) return '$tanda${_satuDesimal(n / 1000000000)} M';
  if (n >= 1000000) return '$tanda${_satuDesimal(n / 1000000)} jt';
  if (n >= 1000) return '$tanda${_satuDesimal(n / 1000)} rb';
  return '$tanda${n.round()}';
}

String _satuDesimal(double v) {
  final bulat = v.roundToDouble() == v || v >= 100;
  return bulat ? v.round().toString() : v.toStringAsFixed(1).replaceAll('.', ',');
}

/// Tanggal pendek untuk label sumbu (mis. "2024-09-04" → "4 Sep").
String fmtTanggalPendek(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  final dt = DateTime.tryParse(iso);
  if (dt == null) return iso;
  return '${dt.day} ${_bulanId[dt.month]}';
}

/// Kuantitas item: bilangan bulat tanpa desimal, pecahan sampai 2 angka
/// (mis. 2 → "2", 4.5 → "4,5" untuk layanan kiloan).
String fmtQty(num value) {
  if (value == value.roundToDouble()) return value.round().toString();
  return value
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '')
      .replaceAll('.', ',');
}

/// Format Rupiah tanpa dependensi eksternal (mis. 51000 → "Rp 51.000").
String fmtIDR(num value) {
  final n = value.round();
  final digits = n.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write('.');
    buf.write(digits[i]);
  }
  return '${n < 0 ? '-' : ''}Rp ${buf.toString()}';
}
