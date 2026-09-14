/// Pilihan formulir Produk & Jasa yang datang dari master server (2026-09-14):
/// satuan, cara input jumlah di kasir, dan toko yang menjual produk.
library;

/// Satuan master (`GET /satuan`).
class SatuanPilihan {
  const SatuanPilihan({required this.id, required this.nama, this.kode});

  final String id;
  final String nama;
  final String? kode;
}

/// Mode jual master (`GET /mode-jual`) — SATUAN | UKUR | UKUR_NOMINAL.
class ModeJualPilihan {
  const ModeJualPilihan({
    required this.kode,
    required this.nama,
    this.keterangan,
    this.desimal = false,
    this.bolehNominal = false,
  });

  final String kode;
  final String nama;
  final String? keterangan;
  final bool desimal;
  final bool bolehNominal;
}

/// Satu toko pada formulir produk (`GET /produk-toko/{id}`). Id toko
/// terenkripsi tidak deterministik, jadi tanda [dijual] wajib dari server —
/// aplikasi tidak bisa mencocokkan `toko_ids` produk dengan daftar `/tokos`.
class TokoProduk {
  const TokoProduk({required this.id, required this.nama, this.dijual = false});

  final String id;
  final String nama;
  final bool dijual;
}

/// Toko yang menjual produk; [semuaToko] = belum ditugaskan ke toko mana pun.
typedef TokoProdukDaftar = ({bool semuaToko, List<TokoProduk> tokos});
