import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../../core/utils/satuan_terukur.dart';

part 'product.freezed.dart';

/// Entitas produk katalog. `harga` = harga yang DITAGIH kasir: harga promo bila
/// promo sedang aktif (server: `harga_efektif`), selain itu harga jual.
@freezed
abstract class Product with _$Product {
  const factory Product({
    required String id,
    required String nama,
    required double harga,
    String? tipe, // PRODUK | JASA
    double? hargaBeli,
    String? satuan,
    String? kategori,
    String? barcode,
    double? stok,
    /// Harga jual normal saat [promo] aktif (untuk dicoret di kartu).
    double? hargaNormal,
    @Default(false) bool promo,
    /// URL foto produk (server: `gambar`); null = tanpa foto.
    String? gambar,
    /// Cara input jumlah di kasir (server 2026-09-14): SATUAN | UKUR |
    /// UKUR_NOMINAL. null = server lama → ditebak dari nama [satuan].
    String? modeJual,
    /// Nama mode jual dari master server ("Per ukuran atau per rupiah").
    String? modeJualNama,
    /// "PRODUK" = dipilih eksplisit di produk; "SATUAN" = otomatis ikut satuan.
    String? modeJualAsal,
    /// Jumlah boleh pecahan (mode UKUR / UKUR_NOMINAL).
    bool? desimal,
    /// Kasir boleh mengisi nominal rupiah (mode UKUR_NOMINAL).
    bool? bolehNominal,
    /// Langkah terkecil jumlah (1 untuk SATUAN, mis. 0,01 untuk Kg).
    double? langkah,
  }) = _Product;
}

/// Perilaku jual produk di kasir — dari server bila ada, selain itu dari satuan.
extension PerilakuProduk on Product {
  PerilakuJual get perilaku => PerilakuJual.dari(
    satuan: satuan,
    modeJual: modeJual,
    desimal: desimal,
    bolehNominal: bolehNominal,
    langkah: langkah,
  );
}
