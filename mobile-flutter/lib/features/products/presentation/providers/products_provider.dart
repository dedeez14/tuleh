import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/offline/pengurai.dart';
import '../../../toko/domain/entities/toko.dart';
import '../../../toko/domain/entities/toko_manifest.dart';
import '../../../toko/presentation/providers/toko_providers.dart';
import '../../data/datasources/product_remote_datasource.dart';
import '../../data/repositories/product_repository_impl.dart';
import '../../domain/entities/product.dart';
import '../../domain/repositories/product_repository.dart';

final productRepositoryProvider = Provider<ProductRepository>(
  (ref) => ProductRepositoryImpl(ProductRemoteDataSource(ref.watch(dioProvider))),
);

/// Kata kunci pencarian katalog (diikat ke kolom cari Kasir).
final productQueryProvider = StateProvider<String>((ref) => '');

/// `?tipe` katalog kasir dari jenis item bidang usaha toko (manifest
/// `item_config.jenis_item`): jasa + barang → SEMUA, hanya jasa → JASA, hanya
/// barang → null (bawaan server). Cermin `loadProduk` di pos.js desktop.
///
/// [jenisItem] null = server lama belum mengirimnya → tebakan dari [sinyalBidang]
/// (nama/kategori/kode bidang usaha) seperti desktop dulu.
String? tipeKatalogKasir(List<String>? jenisItem, {String sinyalBidang = ''}) {
  if (jenisItem != null) {
    final adaJasa = jenisItem.contains('JASA');
    final adaProduk = jenisItem.contains('PRODUK');
    if (adaJasa && adaProduk) return 'SEMUA';
    return adaJasa ? 'JASA' : null;
  }
  final jasa = RegExp(
    r'jasa|service|laundry|salon|bengkel|konter|barber|doorsmeer|car.?wash|petshop|cuci',
  ).hasMatch(sinyalBidang.toLowerCase());
  return jasa ? 'SEMUA' : null;
}

/// Tipe katalog kasir toko aktif — lihat [tipeKatalogKasir]. Manifest atau
/// daftar toko yang gagal dimuat (offline tanpa salinan) tidak menghalangi
/// katalog: jatuh ke bawaan server.
final tipeKatalogKasirProvider = FutureProvider<String?>((ref) async {
  final tokoId = ref.watch(activeTokoIdProvider).valueOrNull;
  TokoManifest? manifest;
  try {
    manifest = await ref.watch(activeManifestProvider.future);
  } catch (_) {
    manifest = null;
  }
  if (manifest?.jenisItem != null) return tipeKatalogKasir(manifest!.jenisItem);
  Toko? toko;
  try {
    for (final t in await ref.watch(tokoListProvider.future)) {
      if (t.id == tokoId) toko = t;
    }
  } catch (_) {
    toko = null;
  }
  return tipeKatalogKasir(
    null,
    sinyalBidang: '${toko?.kategori ?? ''} ${toko?.bidangUsaha ?? ''} ${manifest?.verticalCode ?? ''}',
  );
});

/// Katalog KASIR toko aktif (tanpa produk berstok 0, seperti desktop).
/// Dependensi ke [activeTokoIdProvider] agar otomatis dimuat ulang saat toko
/// berganti; ke query untuk pencarian; ke [tipeKatalogKasirProvider] agar
/// jenis item mengikuti bidang usaha toko (laundry: jasa + barang).
final productsProvider = FutureProvider<List<Product>>((ref) async {
  final tokoId = ref.watch(activeTokoIdProvider).valueOrNull; // refetch saat toko berubah
  final query = ref.watch(productQueryProvider);
  final tipe = await ref.watch(tipeKatalogKasirProvider.future);
  final result = await ref.watch(productRepositoryProvider).list(query: query, tipe: tipe);
  final produk = result.when(ok: (v) => v, err: (e) => throw e);
  return terapkanDeltaStok(produk, await _deltaTertunda(ref, tokoId));
});

/// Stok tampil = stok server + delta transaksi yang masih menunggu dikirim
/// (offline). Setelah antrean kosong dan katalog ditarik ulang, delta hilang.
List<Product> terapkanDeltaStok(List<Product> produk, Map<String, double> delta) {
  if (delta.isEmpty) return produk;
  return [
    for (final p in produk)
      p.stok != null && delta.containsKey(p.id)
          ? p.copyWith(stok: p.stok! + delta[p.id]!)
          : p,
  ];
}

Future<Map<String, double>> _deltaTertunda(Ref ref, String? tokoId) async {
  ref.watch(antreanVersiProvider);
  try {
    return await ref.watch(antreanStoreProvider).deltaStokTertunda(tokoId: tokoId);
  } catch (_) {
    return const {};
  }
}

/// Katalog KELOLA (layar Produk): termasuk produk berstok 0 agar pemilik bisa
/// melihat dan merestoknya — tanpa ini produk habis "menghilang" dari aplikasi.
/// Jasa selalu ikut (`?tipe=SEMUA`, sama dengan desktop): server 2026-09-14
/// menyaring katalog tanpa `tipe` menurut bidang usaha, sehingga jasa yang
/// baru ditambahkan di toko retail akan hilang dari daftar kelolanya.
final produkKelolaProvider = FutureProvider<List<Product>>((ref) async {
  final tokoId = ref.watch(activeTokoIdProvider).valueOrNull;
  final query = ref.watch(productQueryProvider);
  final result = await ref
      .watch(productRepositoryProvider)
      .list(query: query, includeHabis: true, tipe: 'SEMUA');
  final produk = result.when(ok: (v) => v, err: (e) => throw e);
  return terapkanDeltaStok(produk, await _deltaTertunda(ref, tokoId));
});
