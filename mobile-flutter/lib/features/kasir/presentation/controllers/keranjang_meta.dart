import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../pelanggan/domain/entities/pelanggan.dart';
import 'cart_controller.dart';

/// Keterangan tambahan keranjang (pelanggan, diskon transaksi, catatan).
/// Terpisah dari daftar item agar isi keranjang tetap sederhana; ikut kosong
/// saat keranjang dikosongkan atau transaksi selesai.
class KeranjangMeta {
  const KeranjangMeta({this.pelanggan, this.diskonPersen = 0, this.catatan = ''});

  final Pelanggan? pelanggan;

  /// Diskon transaksi dalam persen (0–100), diterapkan ke setiap baris sebagai
  /// `items.*.diskon_persen` — kontrak checkout yang sama dengan desktop.
  final double diskonPersen;
  final String catatan;

  bool get kosong => pelanggan == null && diskonPersen <= 0 && catatan.trim().isEmpty;

  KeranjangMeta salin({
    Object? pelanggan = _tetap,
    double? diskonPersen,
    String? catatan,
  }) => KeranjangMeta(
    pelanggan: identical(pelanggan, _tetap) ? this.pelanggan : pelanggan as Pelanggan?,
    diskonPersen: diskonPersen ?? this.diskonPersen,
    catatan: catatan ?? this.catatan,
  );

  static const _tetap = Object();
}

class KeranjangMetaNotifier extends Notifier<KeranjangMeta> {
  @override
  KeranjangMeta build() {
    // Keranjang kosong (dikosongkan, ganti toko/akun, selesai bayar) → reset.
    ref.listen<List<Object>>(cartControllerProvider, (prev, next) {
      if (next.isEmpty && (prev?.isNotEmpty ?? false)) state = const KeranjangMeta();
    });
    return const KeranjangMeta();
  }

  void pilihPelanggan(Pelanggan? p) => state = state.salin(pelanggan: p);

  void aturDiskon(double persen) =>
      state = state.salin(diskonPersen: persen.clamp(0, 100).toDouble());

  void aturCatatan(String c) => state = state.salin(catatan: c.trim());

  void reset() => state = const KeranjangMeta();

  /// Pulihkan meta utuh (melanjutkan keranjang terparkir).
  void atur(KeranjangMeta m) => state = m;
}

final keranjangMetaProvider =
    NotifierProvider<KeranjangMetaNotifier, KeranjangMeta>(KeranjangMetaNotifier.new);

/// Potongan diskon transaksi (rupiah) dari total kotor keranjang.
double hitungPotongan(double totalKotor, double diskonPersen) {
  if (diskonPersen <= 0) return 0;
  return (totalKotor * diskonPersen / 100 * 100).round() / 100;
}

/// Total yang harus dibayar = total kotor − potongan diskon transaksi.
final cartGrandTotalProvider = Provider<double>((ref) {
  final kotor = ref.watch(cartTotalProvider);
  final diskon = ref.watch(keranjangMetaProvider.select((m) => m.diskonPersen));
  return kotor - hitungPotongan(kotor, diskon);
});
