import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../features/pelanggan/domain/entities/pelanggan.dart';
import '../../products/domain/entities/product.dart';
import '../../toko/presentation/providers/toko_providers.dart';
import '../domain/entities/cart_item.dart';
import '../presentation/controllers/keranjang_meta.dart';

/// Parkir keranjang — kasir menyimpan keranjang yang belum dibayar (pelanggan
/// masih mengambil barang / antre bergantian) lalu melanjutkannya nanti.
/// Padanan desktop `lib/parkir.js`: per toko, paling banyak [maksParkir],
/// disimpan sebagai berkas JSON di folder aplikasi (bukan Keystore — data
/// tidak rahasia dan ukurannya bisa puluhan baris).
const maksParkir = 20;

/// Satu keranjang terparkir. Imutable.
class KeranjangParkir {
  const KeranjangParkir({
    required this.id,
    required this.nomor,
    required this.waktu,
    required this.items,
    this.meta = const KeranjangMeta(),
  });

  final String id;

  /// Nomor urut pendek (1–999) yang disebut kasir ke pelanggan.
  final int nomor;
  final DateTime waktu;
  final List<CartItem> items;
  final KeranjangMeta meta;

  /// Barang terukur dihitung satu baris = satu item (0,74 kg tetap "1 item").
  int get jumlahItem =>
      items.fold(0, (s, e) => s + (e.terukur ? 1 : e.qty.round()));
  double get totalKotor => items.fold(0, (s, e) => s + e.subtotal);
  double get total => totalKotor - hitungPotongan(totalKotor, meta.diskonPersen);

  /// Ringkasan isi: "2× Kopi Susu, 1× Roti" (maks 3 nama).
  String get ringkasan {
    final nama = [for (final e in items.take(3)) '${e.labelQty}× ${e.product.nama}'];
    final sisa = items.length - 3;
    return sisa > 0 ? '${nama.join(', ')}, +$sisa lainnya' : nama.join(', ');
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'nomor': nomor,
    'waktu': waktu.toIso8601String(),
    'items': [
      for (final e in items)
        {
          'qty': e.qty,
          'cara': e.cara.name,
          if (e.nominalDiminta != null) 'nominal_diminta': e.nominalDiminta,
          'produk': _produkKeJson(e.product),
        },
    ],
    'pelanggan': meta.pelanggan == null ? null : _pelangganKeJson(meta.pelanggan!),
    'diskon_persen': meta.diskonPersen,
    'catatan': meta.catatan,
  };

  static KeranjangParkir? fromJson(Map<String, dynamic> m) {
    final rawItems = m['items'];
    if (rawItems is! List || rawItems.isEmpty) return null;
    final items = <CartItem>[];
    for (final r in rawItems) {
      if (r is! Map) continue;
      final p = _produkDariJson(r['produk']);
      // Keranjang lama menyimpan qty sebagai bilangan bulat; keduanya terbaca.
      final qty = (r['qty'] as num?)?.toDouble() ?? 0;
      if (p == null || qty <= 0) continue;
      items.add(CartItem(
        product: p,
        qty: qty,
        cara: CaraInput.values.firstWhere(
          (c) => c.name == '${r['cara'] ?? ''}',
          orElse: () => CaraInput.satuan,
        ),
        nominalDiminta: (r['nominal_diminta'] as num?)?.toDouble(),
      ));
    }
    if (items.isEmpty) return null;
    final pel = m['pelanggan'];
    return KeranjangParkir(
      id: '${m['id'] ?? ''}',
      nomor: (m['nomor'] as num?)?.toInt() ?? 0,
      waktu: DateTime.tryParse('${m['waktu'] ?? ''}') ?? DateTime.now(),
      items: items,
      meta: KeranjangMeta(
        pelanggan: pel is Map ? _pelangganDariJson(Map<String, dynamic>.from(pel)) : null,
        diskonPersen: ((m['diskon_persen'] as num?)?.toDouble() ?? 0).clamp(0, 100).toDouble(),
        catatan: '${m['catatan'] ?? ''}',
      ),
    );
  }
}

Map<String, dynamic> _produkKeJson(Product p) => {
  'id': p.id,
  'nama': p.nama,
  'harga': p.harga,
  'tipe': p.tipe,
  'harga_beli': p.hargaBeli,
  'satuan': p.satuan,
  'kategori': p.kategori,
  'barcode': p.barcode,
  'stok': p.stok,
  'harga_normal': p.hargaNormal,
  'promo': p.promo,
  'gambar': p.gambar,
};

Product? _produkDariJson(dynamic v) {
  if (v is! Map) return null;
  final m = Map<String, dynamic>.from(v);
  final id = '${m['id'] ?? ''}';
  final harga = (m['harga'] as num?)?.toDouble();
  if (id.isEmpty || harga == null) return null;
  return Product(
    id: id,
    nama: '${m['nama'] ?? '-'}',
    harga: harga,
    tipe: m['tipe']?.toString(),
    hargaBeli: (m['harga_beli'] as num?)?.toDouble(),
    satuan: m['satuan']?.toString(),
    kategori: m['kategori']?.toString(),
    barcode: m['barcode']?.toString(),
    stok: (m['stok'] as num?)?.toDouble(),
    hargaNormal: (m['harga_normal'] as num?)?.toDouble(),
    promo: m['promo'] == true,
    gambar: m['gambar']?.toString(),
  );
}

Map<String, dynamic> _pelangganKeJson(Pelanggan p) => {
  'id': p.id,
  'nama': p.nama,
  'kode': p.kode,
  'telepon': p.telepon,
  'alamat': p.alamat,
};

Pelanggan? _pelangganDariJson(Map<String, dynamic> m) {
  final id = '${m['id'] ?? ''}';
  if (id.isEmpty) return null;
  return Pelanggan(
    id: id,
    nama: '${m['nama'] ?? '-'}',
    kode: m['kode']?.toString(),
    telepon: m['telepon']?.toString(),
    alamat: m['alamat']?.toString(),
  );
}

/// Dilempar saat daftar parkir penuh.
class ParkirPenuh implements Exception {
  const ParkirPenuh();
  String get pesan =>
      'Maksimal $maksParkir keranjang terparkir. Selesaikan atau hapus yang lama.';
  @override
  String toString() => pesan;
}

/// Berkas parkir ada tetapi tidak bisa dibaca — pemanggil harus memberi tahu
/// pengguna, BUKAN memperlakukannya sebagai daftar kosong.
class ParkirTidakTerbaca implements Exception {
  const ParkirTidakTerbaca(this.sebab);
  final Object sebab;
  String get pesan =>
      'Daftar keranjang terparkir tidak bisa dibaca di perangkat ini. '
      'Coba lagi; jangan memarkir keranjang baru dulu agar yang lama tidak tertimpa.';
  @override
  String toString() => '$pesan ($sebab)';
}

/// Penyimpan parkir per toko: `<dir>/parkir/<tokoId>.json`.
class ParkirStore {
  ParkirStore({Future<Directory> Function()? dir, DateTime Function()? jam})
    : _dir = dir ?? getApplicationSupportDirectory,
      _jam = jam ?? DateTime.now;

  final Future<Directory> Function() _dir;
  final DateTime Function() _jam;
  final _acak = Random();

  Future<File> _berkas(String? tokoId) async {
    final d = await _dir();
    final aman = (tokoId ?? 'default').replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    // id toko terenkripsi panjang (~267 karakter) → potong agar nama berkas wajar.
    final nama = aman.length > 60 ? '${aman.substring(0, 40)}_${aman.hashCode.toRadixString(16)}' : aman;
    return File('${d.path}${Platform.pathSeparator}parkir${Platform.pathSeparator}$nama.json');
  }

  Future<List<KeranjangParkir>> daftar(String? tokoId) async {
    final f = await _berkas(tokoId);
    if (!await f.exists()) return const [];
    String isi;
    try {
      isi = await f.readAsString();
    } catch (e) {
      // Berkas ADA tapi tidak terbaca (sedang terkunci, izin, disk bermasalah).
      // Jangan balas "kosong": pemanggil berikutnya akan menulis ulang daftar
      // dan keranjang yang sudah diparkir ikut terhapus. Lebih baik gagal jelas.
      throw ParkirTidakTerbaca(e);
    }
    try {
      final raw = jsonDecode(isi);
      if (raw is! List) throw const FormatException('bukan daftar');
      final hasil = <KeranjangParkir>[];
      for (final e in raw) {
        if (e is! Map) continue;
        final p = KeranjangParkir.fromJson(Map<String, dynamic>.from(e));
        if (p != null) hasil.add(p);
      }
      return hasil;
    } catch (_) {
      // Isinya rusak dan tidak akan pulih sendiri. Sisihkan berkasnya (masih
      // bisa diselamatkan manual) lalu mulai dari kosong supaya kasir tetap
      // bisa memarkir keranjang.
      try {
        await f.rename('${f.path}.rusak');
      } catch (_) {
        // gagal menyisihkan → biarkan; penulisan berikutnya menimpanya
      }
      return const [];
    }
  }

  Future<void> _tulis(String? tokoId, List<KeranjangParkir> daftar) async {
    final f = await _berkas(tokoId);
    await f.parent.create(recursive: true);
    final sementara = File('${f.path}.tmp');
    await sementara.writeAsString(jsonEncode([for (final p in daftar) p.toJson()]), flush: true);
    await sementara.rename(f.path);
  }

  /// Simpan keranjang; mengembalikan entri baru. Melempar [ParkirPenuh].
  Future<KeranjangParkir> simpan(
    String? tokoId, {
    required List<CartItem> items,
    KeranjangMeta meta = const KeranjangMeta(),
  }) async {
    if (items.isEmpty) throw ArgumentError('Keranjang kosong.');
    final lama = await daftar(tokoId);
    if (lama.length >= maksParkir) throw const ParkirPenuh();
    final now = _jam();
    final nomor = (lama.fold<int>(0, (m, p) => max(m, p.nomor)) % 999) + 1;
    final entri = KeranjangParkir(
      id: '${now.millisecondsSinceEpoch}-${_acak.nextInt(0xFFFFFF).toRadixString(36)}',
      nomor: nomor,
      waktu: now,
      items: List.unmodifiable(items),
      meta: meta,
    );
    await _tulis(tokoId, [...lama, entri]);
    return entri;
  }

  /// Ambil (dan hapus) satu entri untuk dilanjutkan; null bila sudah tidak ada.
  Future<KeranjangParkir?> ambil(String? tokoId, String id) async {
    final lama = await daftar(tokoId);
    KeranjangParkir? entri;
    for (final p in lama) {
      if (p.id == id) entri = p;
    }
    if (entri == null) return null;
    await _tulis(tokoId, [for (final p in lama) if (p.id != id) p]);
    return entri;
  }

  Future<void> hapus(String? tokoId, String id) async {
    final lama = await daftar(tokoId);
    await _tulis(tokoId, [for (final p in lama) if (p.id != id) p]);
  }
}

final parkirStoreProvider = Provider<ParkirStore>((ref) => ParkirStore());

/// Penanda perubahan agar daftar parkir dimuat ulang setelah simpan/ambil.
final parkirVersiProvider = StateProvider<int>((ref) => 0);

/// Daftar keranjang terparkir untuk toko aktif.
final parkirDaftarProvider = FutureProvider<List<KeranjangParkir>>((ref) async {
  ref.watch(parkirVersiProvider);
  final tokoId = ref.watch(activeTokoIdProvider).valueOrNull;
  return ref.watch(parkirStoreProvider).daftar(tokoId);
});
