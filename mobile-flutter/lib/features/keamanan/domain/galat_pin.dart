import 'package:dio/dio.dart';

import '../../../core/network/api_error_mapper.dart';
import '../../../core/network/api_exception.dart';

/// Penolakan 429 "PIN terkunci" — sisa kuncian dari `data.terkunci_detik`.
///
/// [ApiException] biasa hanya membawa `message`, `errors`, dan `meta`; angka
/// hitung mundur server ada di `data`, jadi jalur PIN membungkusnya di sini.
/// Tetap [ApiException] supaya pemanggil lain tak perlu tahu bedanya.
class PinTerkunci extends ApiException {
  const PinTerkunci({
    required super.message,
    required this.detik,
    super.errors,
    super.meta,
    super.cobaLagiSetelah,
  }) : super(statusCode: 429);

  /// Sisa kuncian dalam detik; 0 bila server tidak menyebutkannya.
  final int detik;
}

/// Sisa detik kuncian PIN; 0 bila galatnya bukan kuncian atau tanpa angka.
int detikTerkunci(ApiException e) => e is PinTerkunci && e.detik > 0 ? e.detik : 0;

/// Kalimat hitung mundur kuncian PIN.
String kalimatTerkunci(int detik) => 'Terlalu banyak PIN salah. Coba lagi dalam $detik detik.';

/// Kalimat untuk penolakan 429 kuncian PIN; null bila galatnya bukan 429
/// (pemanggil memakai `firstError() ?? message`). Tanpa angka dari server,
/// kalimat server dipakai apa adanya — jangan mengarang durasi: kuncian itu
/// milik baris PIN di server, bukan timer lokal. Padanan `pesanTerkunci()` di
/// `lib/otorisasi.js` desktop.
String? pesanTerkunci(ApiException e) {
  if (e.statusCode != 429) return null;
  final detik = detikTerkunci(e);
  if (detik > 0) return kalimatTerkunci(detik);
  return e.message.trim().isNotEmpty ? e.message : 'Terlalu banyak PIN salah. Coba lagi sebentar.';
}

/// Jawaban gagal dari endpoint PIN → [ApiException], dengan 429 dibungkus
/// [PinTerkunci] agar layar bisa menghitung mundur.
ApiException galatPin(Response<dynamic> res) {
  final e = ApiErrorMapper.fromResponse(res);
  if (e.statusCode != 429) return e;
  final body = res.data;
  final data = body is Map ? body['data'] : null;
  final angka = data is Map ? num.tryParse('${data['terkunci_detik']}') : null;
  return PinTerkunci(
    message: e.message,
    detik: angka != null && angka > 0 ? angka.ceil() : 0,
    errors: e.errors,
    meta: e.meta,
    cobaLagiSetelah: e.cobaLagiSetelah,
  );
}
