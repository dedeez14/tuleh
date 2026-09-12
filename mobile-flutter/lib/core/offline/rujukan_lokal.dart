import 'waktu_klien.dart';

/// Rujukan lokal (fase 3): entitas yang lahir saat offline (bon meja, sesi)
/// belum punya id server. Baris antrean yang bergantung padanya memakai
/// rujukan `lokal:<client_ref>` di path; pengurai menggantinya dengan id dari
/// hasil kiriman induknya sebelum mengirim (FIFO menjamin induk lebih dulu).
const awalanRujukanLokal = 'lokal:';

String rujukanLokal(String clientRef) => '$awalanRujukanLokal$clientRef';

bool adalahRujukanLokal(String? id) =>
    id != null && id.startsWith(awalanRujukanLokal);

String? clientRefDariRujukan(String? id) =>
    adalahRujukanLokal(id) ? id!.substring(awalanRujukanLokal.length) : null;

final _polaRujukan = RegExp('$awalanRujukanLokal([A-Za-z0-9_-]+)');

/// client_ref induk yang dirujuk di [path], atau null.
String? rujukanDalamPath(String path) => _polaRujukan.firstMatch(path)?.group(1);

/// Kunci badan yang diawali `_` hanya untuk tampilan lokal (nama & harga item
/// bon saat offline) dan tidak dikirim ke server.
///
/// `waktu_klien` sekalian dirapikan: baris yang diantrekan versi lama membawa
/// format yang ditolak MySQL, dan tanpa ini transaksi lama akan terus gagal
/// walau aplikasinya sudah diperbarui.
Map<String, dynamic> badanKirim(Map<String, dynamic> body) => {
  for (final e in body.entries)
    if (!e.key.startsWith('_'))
      e.key: e.key == 'waktu_klien' ? _waktuRapi(e.value) : e.value,
};

Object? _waktuRapi(Object? nilai) {
  if (nilai is! String || nilai.isEmpty) return nilai;
  final t = DateTime.tryParse(nilai);
  return t == null ? nilai : waktuKlienIso(t);
}
