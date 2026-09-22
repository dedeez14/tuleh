import 'dart:convert';

import '../entities/hasil_pesanan.dart';

/// `client_ref` nota pesanan beserta SIDIK muatan yang dikirim dengannya.
///
/// Server (`pos.idempoten`) memutar ulang jawaban pertama per (pengguna,
/// endpoint, `client_ref`) TANPA membaca isi permintaan. Ref yang sama pada
/// muatan yang sudah berubah karena itu memutar ulang pesanan LAMA — dan
/// aplikasi lalu mengosongkan keranjang pelanggan berikutnya seolah notanya
/// tersimpan. Ref hanya boleh dipakai ulang untuk muatan yang persis sama.
class RefNota {
  const RefNota({required this.ref, required this.sidik});

  final String ref;
  final String sidik;
}

/// Sidik stabil muatan `POST /orders`: cara bayar, item (id + kuantitas,
/// urut seperti dikirim), pelanggan, catatan, dan uang muka (jumlah + metode).
String sidikNota({
  required String bayar,
  required List<ItemNota> items,
  String? idPelanggan,
  String? catatan,
  num? uangMuka,
  String? metodeUangMuka,
}) => jsonEncode([
  bayar,
  [
    for (final i in items) [i.idProduk, i.kuantitas],
  ],
  idPelanggan,
  catatan,
  uangMuka,
  metodeUangMuka,
]);

/// Ref untuk kiriman nota bersidik [sidik]: sidik sama dengan [lama] → ref
/// lama (kirim ulang setelah gagal jaringan = pesanan yang SAMA); berbeda atau
/// belum ada → ref baru dari [buat]. Pemanggil membuang ref (null) setelah
/// kiriman apa pun sukses.
RefNota refNota(RefNota? lama, String sidik, String Function() buat) =>
    lama != null && lama.sidik == sidik
    ? lama
    : RefNota(ref: buat(), sidik: sidik);
