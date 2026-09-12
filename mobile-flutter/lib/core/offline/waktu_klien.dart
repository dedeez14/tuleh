/// `waktu_klien` untuk badan permintaan tulis: ISO-8601 **waktu lokal kasir**,
/// detik penuh, tanpa akhiran zona dan tanpa milidetik.
///
/// Server menyimpan nilai ini apa adanya ke kolom MySQL `datetime`
/// (`client_created_at`). Format lain ditolak MySQL dengan error 1292
/// "Incorrect datetime value" dan transaksi gagal — itulah yang terjadi saat
/// desktop mengirim `toISOString()` ("…T07:25:40.635Z").
///
/// Waktu lokal memang yang dimaksud kolom itu: kapan kasir menekan Bayar
/// menurut jam tokonya, bukan menurut UTC.
String waktuKlienIso([DateTime? waktu]) {
  final d = (waktu ?? DateTime.now()).toLocal();
  String dua(int n) => n.toString().padLeft(2, '0');
  return '${d.year.toString().padLeft(4, '0')}-${dua(d.month)}-${dua(d.day)}'
      'T${dua(d.hour)}:${dua(d.minute)}:${dua(d.second)}';
}
