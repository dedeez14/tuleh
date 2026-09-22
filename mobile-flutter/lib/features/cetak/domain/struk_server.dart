import 'dart:math' as math;

import 'entities/struk.dart';

/// Nota pesanan & struk transaksi dari server → [Struk] siap cetak (Fase 3).
/// Identitas toko datang dari pemanggil (profil usaha yang sudah dimuat app),
/// karena nota server hanya membawa isi dokumen.
///
/// Nominal server bisa berupa angka atau teks desimal ("50000.00"); keduanya
/// dibaca sebagai angka, nilai kosong dianggap nol.
Struk strukDariServer(
  Map<String, dynamic> m, {
  required String namaToko,
  String? alamat,
  String? telepon,
  String? catatanKaki,
  String? logoUrl,
  bool demo = false,
}) {
  double? angka(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v');
  final status = (m['status'] ?? '').toString().toUpperCase();
  final nota = status == 'BELUM LUNAS' || status == 'UANG MUKA';
  final total = angka(m['grand_total']) ?? 0;
  final uangMuka = angka(m['uang_muka']) ?? 0;
  final metode = m['tipe_pembayaran']?.toString();
  // Server boleh mengirim kode metode huruf kecil — jangan bandingkan mentah.
  final tunai = (metode ?? '').toUpperCase() == 'TUNAI';
  final diskon = angka(m['total_diskon']) ?? 0;
  final nomor = (m['nomor'] ?? '').toString();

  final baris = <StrukBaris>[
    for (final e in (m['items'] is List ? m['items'] as List : const []))
      if (e is Map)
        StrukBaris(
          nama: (e['nama'] ?? '-').toString(),
          kuantitas: angka(e['kuantitas']) ?? 0,
          harga: angka(e['harga']) ?? 0,
          satuan: e['satuan']?.toString(),
          nominalDiminta: angka(e['nominal_diminta']),
        ),
  ];

  return Struk(
    namaToko: namaToko,
    alamat: alamat,
    telepon: telepon,
    catatanKaki: catatanKaki,
    logoUrl: logoUrl,
    demo: demo,
    nomor: nomor,
    // QR kaki struk memakai nomor nota, sama dengan struk checkout kasir —
    // tanpa ini nota pesanan tercetak tanpa kode yang bisa dipindai.
    barcode: nomor.isEmpty ? null : nomor,
    // Untuk laundry/bengkel inilah alasan utama nota dicetak.
    noAntrian: m['no_antrian']?.toString(),
    waktu:
        DateTime.tryParse((m['tanggal'] ?? '').toString())?.toLocal() ??
        DateTime.now(),
    kasir: m['kasir']?.toString(),
    pelanggan: m['pelanggan']?.toString(),
    baris: baris,
    total: total,
    diskon: diskon > 0 ? diskon : null,
    // Nota BELUM lunas tidak pernah mencetak baris "Bayar <metode>" (terbaca
    // seolah sudah dibayar penuh); pada nota DP metodenya menempel di label
    // uang muka — cermin `barisPembayaran()` desktop.
    metode: nota ? null : metode,
    labelUangMuka: (status == 'UANG MUKA' && (metode ?? '').isNotEmpty)
        ? 'Uang muka ($metode)'
        : 'Uang muka',
    uangMuka: uangMuka > 0 ? uangMuka : null,
    // Data yang melenceng (DP > grand_total) tak boleh mencetak sisa negatif.
    sisa: nota
        ? math.max(0, angka(m['sisa']) ?? (total - uangMuka))
        : (uangMuka > 0 ? math.max(0, total - uangMuka) : null),
    labelSisa: nota ? 'Sisa' : 'Dibayar saat serah',
    // Baris "Tunai" hanya untuk transaksi tunai tanpa uang muka (sama dengan checkout kasir).
    dibayar: (!nota && uangMuka == 0 && tunai) ? angka(m['dibayar']) : null,
    kembalian: nota ? null : angka(m['kembalian']),
  );
}
