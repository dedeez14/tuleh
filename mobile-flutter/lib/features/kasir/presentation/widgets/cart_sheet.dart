import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/layout/lebar.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/rupiah_input.dart';
import '../../../../core/widgets/motion.dart';
import '../../../../core/widgets/states.dart';
import '../../../cetak/domain/entities/struk.dart';
import '../../../demo/demo_session.dart';
import 'hasil_transaksi_sheet.dart';
import '../../../pengaturan/presentation/providers/pengaturan_providers.dart';
import '../../../sesi/presentation/providers/sesi_providers.dart';
import '../../domain/entities/cart_item.dart';
import '../controllers/cart_controller.dart';
import '../controllers/keranjang_meta.dart';
import 'keranjang_daftar_item.dart';
import 'keranjang_form_bayar.dart';
import 'keranjang_kartu_tambahan.dart';
import 'lembar_ukuran.dart';
import 'parkir_sheet.dart';
import '../../../../core/offline/pengurai.dart';
import '../../../products/presentation/providers/products_provider.dart';
import '../providers/checkout_providers.dart';
import '../screens/kasir_screen.dart' show bukaSesiDenganUmpanBalik;

/// Lembar keranjang — daftar item, metode bayar, uang diterima, lalu bayar.
///
/// Dibuat dua langkah agar layar tidak padat: langkah "Keranjang" untuk
/// memeriksa dan mengoreksi item, langkah "Pembayaran" untuk memilih metode
/// dan menghitung kembalian. Tombol utama selalu di bawah, dalam jangkauan ibu jari.
class CartSheet extends ConsumerStatefulWidget {
  const CartSheet({super.key, this.tertanam = false});

  /// true = dipasang sebagai panel menetap (tablet), bukan bottom sheet:
  /// tanpa batas tinggi, tidak menutup diri setelah bayar.
  final bool tertanam;

  @override
  ConsumerState<CartSheet> createState() => _CartSheetState();
}

enum _Langkah { keranjang, bayar }

class _CartSheetState extends ConsumerState<CartSheet> {
  static const _metode = ['TUNAI', 'QRIS', 'TRANSFER'];

  _Langkah _langkah = _Langkah.keranjang;
  String _metodeTerpilih = 'TUNAI';
  final _uangCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _uangCtrl.dispose();
    super.dispose();
  }

  double get _uangDiterima => parseRupiah(_uangCtrl.text);

  /// Saran nominal uang: pas, pembulatan ribuan/puluh-ribuan terdekat di atas.
  List<double> _saranUang(double total) {
    final out = <double>{total};
    for (final kelipatan in [5000, 10000, 20000, 50000, 100000]) {
      final naik = (total / kelipatan).ceil() * kelipatan.toDouble();
      if (naik > total) out.add(naik);
    }
    final urut = out.toList()..sort();
    return urut.take(4).toList();
  }

  Future<void> _bayar() async {
    final items = ref.read(cartControllerProvider);
    final total = ref.read(cartGrandTotalProvider);
    final meta = ref.read(keranjangMetaProvider);
    final potongan = hitungPotongan(ref.read(cartTotalProvider), meta.diskonPersen);
    if (items.isEmpty) return;

    final tunai = _metodeTerpilih == 'TUNAI';
    // Tunai: uang diterima WAJIB diisi dan cukup — tombol Bayar sudah
    // dinonaktifkan oleh _Kaki bila belum; ini pengaman kedua.
    final dibayar = tunai ? _uangDiterima : total;
    if (tunai && dibayar <= 0) {
      _pesan('Isi dulu uang yang diterima dari pelanggan.', gagal: true);
      return;
    }
    if (tunai && dibayar < total) {
      _pesan('Uang diterima kurang dari total.', gagal: true);
      return;
    }

    setState(() => _loading = true);
    try {
      // Struk disusun dari keranjang SEBELUM dikosongkan, agar bisa dicetak
      // ulang dari lembar hasil (dan disimpan bila transaksi diantrekan offline).
      final usaha = ref.read(profilUsahaProvider).valueOrNull;
      final waktu = DateTime.now();
      Struk buatStruk(String nomor, double kembalian) => Struk(
        namaToko: usaha?.nama ?? 'Tuléh POS',
        alamat: usaha?.alamat,
        telepon: usaha?.telepon,
        nomor: nomor.isEmpty ? '-' : nomor,
        waktu: waktu,
        baris: [
          for (final e in items)
            StrukBaris(
              nama: e.product.nama,
              kuantitas: e.qty,
              harga: e.product.harga,
              satuan: e.terukur ? e.product.satuan : null,
            ),
        ],
        total: total,
        metode: _metodeTerpilih,
        dibayar: tunai ? dibayar : null,
        kembalian: tunai ? kembalian : null,
        catatanKaki: usaha?.strukFooter,
        barcode: nomor.isEmpty ? null : nomor,
        logoUrl: (usaha?.strukTampilLogo ?? false) ? usaha?.logo : null,
        demo: ref.read(demoSessionProvider).active,
        pelanggan: meta.pelanggan?.nama,
        diskon: potongan > 0 ? potongan : null,
      );

      final res = await ref.read(checkoutRepositoryProvider).bayar(
        items: items,
        metode: _metodeTerpilih,
        dibayar: dibayar,
        total: total,
        buatStruk: buatStruk,
        diskonPersen: meta.diskonPersen,
        idPelanggan: meta.pelanggan?.id,
        catatan: meta.catatan,
      );
      final struk = buatStruk(res.nomor, res.kembalian);

      ref.read(cartControllerProvider.notifier).clear();
      ref.invalidate(activeSesiProvider); // rekap kas ikut segar
      if (res.tertunda) {
        ref.read(antreanVersiProvider.notifier).state++;
        ref.invalidate(productsProvider); // stok tampil ikut delta tertunda
      }
      if (!mounted) return;
      if (widget.tertanam) {
        setState(() {
          _langkah = _Langkah.keranjang;
          _uangCtrl.clear();
        });
      } else {
        Navigator.of(context).pop();
      }
      HapticFeedback.mediumImpact();
      await _tampilkanHasil(
        struk,
        res.kembalian,
        tertunda: res.tertunda,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      // 409 = sesi kasir belum dibuka; tawarkan jalan keluarnya langsung.
      if (e.statusCode == 409) {
        _pesan(e.message, gagal: true, aksi: ('Buka sesi', _bukaSesi));
      } else {
        _pesan(e.firstError() ?? e.message, gagal: true);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _bukaSesi() => bukaSesiDenganUmpanBalik(context, ref);

  /// Lembar hasil transaksi: kembalian besar (yang paling dicari kasir) plus
  /// tombol cetak struk. Dipisah dari snackbar agar tidak hilang sendiri saat
  /// kasir sedang menghitung uang.
  Future<void> _tampilkanHasil(
    Struk struk,
    double kembalian, {
    bool tertunda = false,
  }) async {
    if (!mounted) return;
    await tampilkanLembar<void>(
      context,
      builder: (_) => HasilTransaksiSheet(
        struk: struk,
        kembalian: kembalian,
        tertunda: tertunda,
      ),
    );
  }

  void _pesan(
    String teks, {
    bool gagal = false,
    (String, VoidCallback)? aksi,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: gagal ? AppColors.danger : AppColors.success,
          content: Text(teks),
          action: aksi == null
              ? null
              : SnackBarAction(
                  label: aksi.$1,
                  textColor: Colors.white,
                  onPressed: aksi.$2,
                ),
        ),
      );
  }

  /// Barang terukur di keranjang: timbang ulang lewat lembar yang sama dengan
  /// katalog, lalu GANTI isinya (bukan menambah) — menjumlahkan dua penimbangan
  /// diam-diam akan menagih lebih.
  Future<void> _ubahUkuran(CartItem it) async {
    final isian = await tanyaUkuran(context, it.product, qtyAwal: it.qty);
    if (isian == null || !mounted) return;
    ref.read(cartControllerProvider.notifier).tambahUkuran(
      it.product,
      isian.qty,
      cara: isian.cara,
      nominalDiminta: isian.nominalDiminta,
      ganti: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(cartControllerProvider);
    final total = ref.watch(cartGrandTotalProvider);
    final count = ref.watch(cartCountProvider);
    final cart = ref.read(cartControllerProvider.notifier);
    final pembayaran = ref.watch(pengaturanPembayaranProvider);
    final cs = Theme.of(context).colorScheme;

    // Keranjang dikosongkan dari layar lain → tutup lembar ini.
    if (items.isEmpty && _langkah == _Langkah.bayar) {
      _langkah = _Langkah.keranjang;
    }

    final isi = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Judul(
                langkah: _langkah,
                count: count,
                onKembali: () => setState(() => _langkah = _Langkah.keranjang),
                onKosongkan: items.isEmpty || _loading ? null : cart.clear,
                onParkir: items.isEmpty || _loading
                    ? null
                    : () async {
                        final ok = await parkirKeranjang(context, ref);
                        // Lembar ponsel ditutup setelah parkir; panel tablet tetap.
                        if (ok && !widget.tertanam && context.mounted) Navigator.of(context).pop();
                      },
              ),
              const Divider(height: 1),
              Expanded(
                child: items.isEmpty
                    ? const KeadaanKosong(
                        ikon: Icons.shopping_cart_outlined,
                        judul: 'Keranjang masih kosong',
                        detail: 'Ketuk item di katalog untuk menambahkannya.',
                      )
                    : _langkah == _Langkah.keranjang
                    ? DaftarItemKeranjang(
                        onUbah: cart.setQty,
                        onUbahUkuran: (it) => _ubahUkuran(it),
                        onHapus: cart.remove,
                        tambahan: const KartuTambahanKeranjang(),
                      )
                    : FormBayar(
                        total: total,
                        metode: _metode,
                        terpilih: _metodeTerpilih,
                        uangCtrl: _uangCtrl,
                        saran: _saranUang(total),
                        pembayaran: pembayaran,
                        onPilihMetode: (m) =>
                            setState(() => _metodeTerpilih = m),
                        onUbahUang: () => setState(() {}),
                      ),
              ),
              if (items.isNotEmpty)
                _Kaki(
                  total: total,
                  langkah: _langkah,
                  metode: _metodeTerpilih,
                  uangDiterima: _uangDiterima,
                  loading: _loading,
                  onLanjut: () => setState(() => _langkah = _Langkah.bayar),
                  onBayar: _bayar,
                  cs: cs,
                ),
            ],
          );

    if (widget.tertanam) {
      return Padding(padding: const EdgeInsets.only(top: 10), child: isi);
    }
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: FractionallySizedBox(heightFactor: 0.9, child: isi),
      ),
    );
  }
}

class _Judul extends StatelessWidget {
  const _Judul({
    required this.langkah,
    required this.count,
    required this.onKembali,
    required this.onKosongkan,
    this.onParkir,
  });

  final _Langkah langkah;
  final int count;
  final VoidCallback onKembali;
  final VoidCallback? onKosongkan;
  final VoidCallback? onParkir;

  @override
  Widget build(BuildContext context) {
    final bayar = langkah == _Langkah.bayar;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 12, 10),
      child: Row(
        children: [
          if (bayar)
            IconButton(
              tooltip: 'Kembali ke keranjang',
              onPressed: onKembali,
              icon: const Icon(Icons.arrow_back_rounded),
            )
          else
            const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  bayar ? 'Pembayaran' : 'Keranjang',
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (!bayar && count > 0)
                  Text(
                    '$count item',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
              ],
            ),
          ),
          // Berlabel: "P" saja tidak terbaca sebagai parkir oleh kasir baru.
          if (!bayar && onParkir != null)
            TextButton.icon(
              onPressed: onParkir,
              icon: const Icon(Icons.local_parking_rounded, size: 18),
              label: const Text('Parkir'),
            ),
          // Berlabel & agak jauh dari Parkir: ikon tong sampah telanjang di
          // sebelah Parkir membuat satu ketukan meleset menghapus keranjang.
          if (!bayar && onKosongkan != null) ...[
            const SizedBox(width: 4),
            TextButton.icon(
              onPressed: onKosongkan,
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text('Kosongkan'),
            ),
          ],
        ],
      ),
    );
  }
}

class _Kaki extends StatelessWidget {
  const _Kaki({
    required this.total,
    required this.langkah,
    required this.metode,
    required this.uangDiterima,
    required this.loading,
    required this.onLanjut,
    required this.onBayar,
    required this.cs,
  });

  final double total;
  final _Langkah langkah;
  final String metode;
  final double uangDiterima;
  final bool loading;
  final VoidCallback onLanjut;
  final VoidCallback onBayar;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final bayar = langkah == _Langkah.bayar;
    final tunai = metode == 'TUNAI';
    final kembalian = uangDiterima - total;
    final kurang = tunai && uangDiterima > 0 && kembalian < 0;
    final belumIsi = tunai && uangDiterima <= 0;
    // Tunai tanpa nominal atau kurang: Bayar dikunci; kasir tahu sebabnya
    // dari baris di atas tombol, bukan dari snackbar setelah gagal.
    final bisaBayar = !bayar || !tunai || (!belumIsi && !kurang);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outline)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                'Total',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const Spacer(),
              AngkaBerubah(
                nilai: total,
                format: fmtIDR,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          if (bayar && tunai && uangDiterima > 0) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  kurang ? 'Kurang' : 'Kembalian',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: kurang ? cs.error : cs.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                const Spacer(),
                Text(
                  fmtIDR(kembalian.abs()),
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: kurang ? cs.error : AppColors.success,
                  ),
                ),
              ],
            ),
          ],
          if (bayar && belumIsi) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: cs.error),
                const SizedBox(width: 6),
                Text(
                  'Isi uang diterima dulu',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: cs.error,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          FilledButton(
            onPressed: loading || !bisaBayar
                ? null
                : (bayar ? onBayar : onLanjut),
            child: loading
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: AppColors.mint900,
                    ),
                  )
                : Text(bayar ? 'Bayar ${fmtIDR(total)}' : 'Lanjut ke pembayaran'),
          ),
        ],
      ),
    );
  }
}
