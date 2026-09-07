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
import '../../../pengaturan/domain/entities/pengaturan_pembayaran.dart';
import '../../../pengaturan/presentation/providers/pengaturan_providers.dart';
import '../../../sesi/presentation/providers/sesi_providers.dart';
import '../controllers/cart_controller.dart';
import '../controllers/keranjang_meta.dart';
import 'pilih_pelanggan_sheet.dart';
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
        perluTinjau: res.perluTinjau,
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
    bool perluTinjau = false,
  }) async {
    if (!mounted) return;
    await tampilkanLembar<void>(
      context,
      builder: (_) => HasilTransaksiSheet(
        struk: struk,
        kembalian: kembalian,
        tertunda: tertunda,
        perluTinjau: perluTinjau,
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
                    ? _DaftarItem(
                        onUbah: cart.setQty,
                        onHapus: cart.remove,
                        tambahan: const _KartuTambahan(),
                      )
                    : _FormBayar(
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
  });

  final _Langkah langkah;
  final int count;
  final VoidCallback onKembali;
  final VoidCallback? onKosongkan;

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
          if (!bayar && onKosongkan != null)
            TextButton.icon(
              onPressed: onKosongkan,
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text('Kosongkan'),
            ),
        ],
      ),
    );
  }
}

class _DaftarItem extends ConsumerWidget {
  const _DaftarItem({required this.onUbah, required this.onHapus, this.tambahan});

  final void Function(String id, int qty) onUbah;
  final void Function(String id) onHapus;

  /// Kartu di bawah daftar item (pelanggan, diskon, catatan).
  final Widget? tambahan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(cartControllerProvider);
    final cs = Theme.of(context).colorScheme;

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      itemCount: items.length + (tambahan == null ? 0 : 1),
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        if (i == items.length) return tambahan!;
        final it = items[i];
        return Dismissible(
          key: ValueKey(it.product.id),
          direction: DismissDirection.endToStart,
          onDismissed: (_) => onHapus(it.product.id),
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 18),
            decoration: BoxDecoration(
              color: cs.error.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.delete_outline_rounded, color: cs.error),
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.outline),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        it.product.nama,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${fmtIDR(it.product.harga)} × ${it.qty}',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: cs.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        fmtIDR(it.subtotal),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: cs.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                _Stepper(
                  qty: it.qty,
                  onUbah: (n) => onUbah(it.product.id, n),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Pelanggan, diskon transaksi, dan catatan — opsional, di bawah daftar item.
class _KartuTambahan extends ConsumerWidget {
  const _KartuTambahan();

  Future<void> _pilihPelanggan(BuildContext context, WidgetRef ref) async {
    final meta = ref.read(keranjangMetaProvider);
    final p = await PilihPelangganSheet.tampilkan(context, terpilih: meta.pelanggan);
    if (p == null) return;
    ref.read(keranjangMetaProvider.notifier).pilihPelanggan(
      identical(p, PilihPelangganSheet.hapus) ? null : p,
    );
  }

  Future<void> _aturDiskon(BuildContext context, WidgetRef ref) async {
    final meta = ref.read(keranjangMetaProvider);
    final ctrl = TextEditingController(
      text: meta.diskonPersen > 0 ? fmtQty(meta.diskonPersen) : '',
    );
    final hasil = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Diskon transaksi'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            suffixText: '%',
            helperText: 'Berlaku untuk semua item. Kosongkan untuk menghapus.',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, double.tryParse(v.replaceAll(',', '.')) ?? 0),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, double.tryParse(ctrl.text.replaceAll(',', '.')) ?? 0),
            child: const Text('Terapkan'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (hasil == null) return;
    if (hasil < 0 || hasil > 100) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
            backgroundColor: AppColors.danger, content: Text('Diskon harus 0–100%.')));
      return;
    }
    ref.read(keranjangMetaProvider.notifier).aturDiskon(hasil);
  }

  Future<void> _aturCatatan(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController(text: ref.read(keranjangMetaProvider).catatan);
    final hasil = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Catatan transaksi'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 200,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Mis. tanpa es, ambil jam 5'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Simpan')),
        ],
      ),
    );
    ctrl.dispose();
    if (hasil == null) return;
    ref.read(keranjangMetaProvider.notifier).aturCatatan(hasil);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meta = ref.watch(keranjangMetaProvider);
    final kotor = ref.watch(cartTotalProvider);
    final potongan = hitungPotongan(kotor, meta.diskonPersen);
    final cs = Theme.of(context).colorScheme;

    Widget baris({
      required IconData ikon,
      required String label,
      required String nilai,
      required bool terisi,
      required VoidCallback onTap,
    }) => ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      leading: Icon(ikon, color: terisi ? cs.primary : cs.onSurface.withValues(alpha: 0.5)),
      title: Text(label, style: const TextStyle(fontSize: 13.5)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              nilai,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: terisi ? FontWeight.w800 : FontWeight.w500,
                color: terisi ? cs.onSurface : cs.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, size: 18, color: cs.onSurface.withValues(alpha: 0.4)),
        ],
      ),
      onTap: onTap,
    );

    return Material(
      color: cs.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outline),
      ),
      child: Column(
        children: [
          baris(
            ikon: Icons.person_outline_rounded,
            label: 'Pelanggan',
            nilai: meta.pelanggan?.nama ?? 'Umum',
            terisi: meta.pelanggan != null,
            onTap: () => _pilihPelanggan(context, ref),
          ),
          const Divider(height: 1, indent: 12, endIndent: 12),
          baris(
            ikon: Icons.percent_rounded,
            label: 'Diskon transaksi',
            nilai: meta.diskonPersen > 0
                ? '${fmtQty(meta.diskonPersen)}% · −${fmtIDR(potongan)}'
                : 'Tidak ada',
            terisi: meta.diskonPersen > 0,
            onTap: () => _aturDiskon(context, ref),
          ),
          const Divider(height: 1, indent: 12, endIndent: 12),
          baris(
            ikon: Icons.sticky_note_2_outlined,
            label: 'Catatan',
            nilai: meta.catatan.isEmpty ? 'Tidak ada' : meta.catatan,
            terisi: meta.catatan.isNotEmpty,
            onTap: () => _aturCatatan(context, ref),
          ),
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.qty, required this.onUbah});

  final int qty;
  final ValueChanged<int> onUbah;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: qty == 1 ? 'Hapus' : 'Kurangi',
            onPressed: () {
              onUbah(qty - 1);
              HapticFeedback.selectionClick();
            },
            icon: Icon(
              qty == 1 ? Icons.delete_outline_rounded : Icons.remove_rounded,
              size: 19,
              color: cs.primary,
            ),
          ),
          SizedBox(
            width: 24,
            child: Text(
              '$qty',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: cs.primary,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Tambah',
            onPressed: () {
              onUbah(qty + 1);
              HapticFeedback.selectionClick();
            },
            icon: Icon(Icons.add_rounded, size: 19, color: cs.primary),
          ),
        ],
      ),
    );
  }
}

class _FormBayar extends StatelessWidget {
  const _FormBayar({
    required this.total,
    required this.metode,
    required this.terpilih,
    required this.uangCtrl,
    required this.saran,
    required this.pembayaran,
    required this.onPilihMetode,
    required this.onUbahUang,
  });

  final double total;
  final List<String> metode;
  final String terpilih;
  final TextEditingController uangCtrl;
  final List<double> saran;
  final AsyncValue<PengaturanPembayaran> pembayaran;
  final ValueChanged<String> onPilihMetode;
  final VoidCallback onUbahUang;

  static IconData _ikon(String m) => switch (m) {
    'TUNAI' => Icons.payments_outlined,
    'QRIS' => Icons.qr_code_2_rounded,
    _ => Icons.account_balance_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tunai = terpilih == 'TUNAI';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      children: [
        Text(
          'Metode pembayaran',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
            color: cs.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final m in metode) ...[
              Expanded(
                child: _PilihanMetode(
                  label: m,
                  ikon: _ikon(m),
                  aktif: m == terpilih,
                  onTap: () => onPilihMetode(m),
                ),
              ),
              if (m != metode.last) const SizedBox(width: 8),
            ],
          ],
        ),
        const SizedBox(height: 22),
        if (tunai) ...[
          Text(
            'Uang diterima',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
              color: cs.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: uangCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: const [RupiahInputFormatter()],
            autofocus: true,
            onChanged: (_) => onUbahUang(),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            decoration: const InputDecoration(
              prefixText: 'Rp ',
              hintText: '0',
              helperText: 'Ketik 50000, tampil 50.000',
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in saran)
                ActionChip(
                  label: Text(
                    s == total ? 'Uang pas' : fmtIDR(s),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  onPressed: () {
                    uangCtrl.text = teksRupiah(s);
                    onUbahUang();
                  },
                ),
            ],
          ),
        ] else if (terpilih == 'QRIS')
          _PanduanQris(total: total, pembayaran: pembayaran)
        else
          _PanduanTransfer(pembayaran: pembayaran),
      ],
    );
  }
}

class _PilihanMetode extends StatelessWidget {
  const _PilihanMetode({
    required this.label,
    required this.ikon,
    required this.aktif,
    required this.onTap,
  });

  final String label;
  final IconData ikon;
  final bool aktif;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: aktif ? cs.primary.withValues(alpha: 0.14) : cs.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: Gerak.cepat,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: aktif ? cs.primary : cs.outline,
              width: aktif ? 1.6 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                ikon,
                size: 21,
                color: aktif
                    ? cs.primary
                    : cs.onSurface.withValues(alpha: 0.65),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: aktif ? cs.primary : cs.onSurface,
                ),
              ),
            ],
          ),
        ),
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

/// Metode QRIS: tunjukkan gambar QRIS statis toko (diunggah pemilik di desktop,
/// Pengaturan → Pembayaran) beserta total, sama seperti layar bayar desktop.
class _PanduanQris extends StatelessWidget {
  const _PanduanQris({required this.total, required this.pembayaran});
  final double total;
  final AsyncValue<PengaturanPembayaran> pembayaran;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final url = pembayaran.valueOrNull?.qrStatis;
    if (pembayaran.isLoading) {
      return const Kerangka(tinggi: 220, radius: 16);
    }
    if (url == null) {
      return const _Catatan(
        ikon: Icons.qr_code_2_rounded,
        peringatan: true,
        teks: 'QRIS statis belum diunggah. Pemilik/Manajer: buka Pengaturan → '
            'Pembayaran di aplikasi desktop untuk mengunggah gambar QRIS usaha.',
      );
    }
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outline),
          ),
          child: AspectRatio(
            aspectRatio: 1,
            child: Image.network(
              url,
              fit: BoxFit.contain,
              loadingBuilder: (_, anak, prog) => prog == null
                  ? anak
                  : const Center(child: CircularProgressIndicator()),
              errorBuilder: (_, _, _) => const KeadaanKosong(
                ikon: Icons.broken_image_outlined,
                judul: 'Gambar QRIS gagal dimuat',
                detail: 'Periksa koneksi, lalu buka ulang keranjang.',
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          fmtIDR(total),
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const _Catatan(
          ikon: Icons.qr_code_scanner_rounded,
          teks: 'Tunjukkan QR ke pelanggan. Setelah pelanggan membayar dan Anda '
              'cek dananya masuk, tekan Bayar.',
        ),
      ],
    );
  }
}

/// Metode TRANSFER: daftar rekening toko dengan tombol salin.
class _PanduanTransfer extends StatelessWidget {
  const _PanduanTransfer({required this.pembayaran});
  final AsyncValue<PengaturanPembayaran> pembayaran;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bank = pembayaran.valueOrNull?.bank ?? const [];
    if (pembayaran.isLoading) {
      return const DaftarKerangka(jumlah: 2, tinggiBaris: 64);
    }
    if (bank.isEmpty) {
      return const _Catatan(
        ikon: Icons.account_balance_outlined,
        peringatan: true,
        teks: 'Belum ada rekening. Pemilik/Manajer: tambahkan di Pengaturan → '
            'Pembayaran di aplikasi desktop.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final b in bank) ...[
          Material(
            color: cs.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: cs.outline),
            ),
            child: ListTile(
              leading: Icon(Icons.account_balance_outlined, color: cs.primary),
              title: Text(
                b.rekening,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontFeatures: [FontFeature.tabularFigures()],
                  letterSpacing: 0.5,
                ),
              ),
              subtitle: Text('${b.bank} · a.n. ${b.atasNama}'),
              trailing: IconButton(
                tooltip: 'Salin nomor rekening',
                icon: const Icon(Icons.copy_rounded),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: b.rekening));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(
                        content: Text('No. rekening ${b.bank} disalin.'),
                      ),
                    );
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        const _Catatan(
          ikon: Icons.verified_outlined,
          teks: 'Pelanggan transfer ke salah satu rekening. Setelah dana masuk, '
              'tekan Bayar.',
        ),
      ],
    );
  }
}

class _Catatan extends StatelessWidget {
  const _Catatan({
    required this.ikon,
    required this.teks,
    this.peringatan = false,
  });
  final IconData ikon;
  final String teks;
  final bool peringatan;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final warna = peringatan ? AppColors.warn : cs.primary;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: warna.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ikon, color: warna),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              teks,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: cs.onSurface.withValues(alpha: 0.78),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
