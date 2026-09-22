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

  final baris = <StrukBaris>[
    for (final e in (m['items'] is List ? m['items'] as List : const []))
      if (e is Map)
        StrukBaris(
          nama: (e['nama'] ?? '').toString(),
          kuantitas: angka(e['kuantitas']) ?? 0,
          harga: angka(e['harga']) ?? 0,
          satuan: e['satuan']?.toString(),
        ),
  ];

  return Struk(
    namaToko: namaToko,
    alamat: alamat,
    telepon: telepon,
    catatanKaki: catatanKaki,
    logoUrl: logoUrl,
    demo: demo,
    nomor: (m['nomor'] ?? '').toString(),
    waktu:
        DateTime.tryParse((m['tanggal'] ?? '').toString())?.toLocal() ??
        DateTime.now(),
    kasir: m['kasir']?.toString(),
    pelanggan: m['pelanggan']?.toString(),
    baris: baris,
    total: total,
    // Nota bayar nanti tak punya metode (bukan "BAYAR SAAT AMBIL"); nota DP = metode uang muka.
    metode: nota ? (status == 'UANG MUKA' ? metode : null) : metode,
    uangMuka: uangMuka > 0 ? uangMuka : null,
    sisa: nota
        ? (angka(m['sisa']) ?? (total - uangMuka))
        : (uangMuka > 0 ? total - uangMuka : null),
    labelSisa: nota ? 'Sisa' : 'Dibayar saat serah',
    // Baris "Tunai" hanya untuk transaksi tunai tanpa uang muka (sama dengan checkout kasir).
    dibayar: (!nota && uangMuka == 0 && metode == 'TUNAI')
        ? angka(m['dibayar'])
        : null,
    kembalian: nota ? null : angka(m['kembalian']),
  );
}
