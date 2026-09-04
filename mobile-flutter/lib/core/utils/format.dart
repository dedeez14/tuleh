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
