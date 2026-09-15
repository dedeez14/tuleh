/// `waktu_klien` untuk badan permintaan tulis: ISO-8601 **waktu lokal kasir
/// beserta offset zonanya**, detik penuh, tanpa milidetik —
/// mis. `2026-09-12T14:25:41+07:00`.
///
/// Riwayat format:
/// - Dulu dikirim tanpa zona karena server menyisipkannya mentah ke kolom
///   MySQL `datetime`; `…Z` / milidetik ditolak (error 1292) dan checkout gagal.
/// - Sejak 12 Sep 2026 server menormalkannya (`Modules\POS\Support\WaktuKlien`:
///   Carbon::parse → zona toko `app.timezone` → `Y-m-d H:i:s`). Nilai TANPA
///   zona dianggap sudah dalam zona toko (WIB), sehingga kasir di WITA/WIT
///   tercatat bergeser 1–2 jam. Dengan offset eksplisit server mengonversi
///   dengan benar, dan nilainya tetap waktu lokal yang terbaca manusia.
String waktuKlienIso([DateTime? waktu]) {
  final d = (waktu ?? DateTime.now()).toLocal();
  String dua(int n) => n.toString().padLeft(2, '0');
  final offset = d.timeZoneOffset;
  final tanda = offset.isNegative ? '-' : '+';
  final menit = offset.inMinutes.abs();
  return '${d.year.toString().padLeft(4, '0')}-${dua(d.month)}-${dua(d.day)}'
      'T${dua(d.hour)}:${dua(d.minute)}:${dua(d.second)}'
      '$tanda${dua(menit ~/ 60)}:${dua(menit % 60)}';
}
