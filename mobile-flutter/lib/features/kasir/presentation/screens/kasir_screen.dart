import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/layout/lebar.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/widgets/app_background.dart';
import '../../../../core/widgets/motion.dart';
import '../../../../core/widgets/pindai_barcode.dart';
import '../../../../core/widgets/states.dart';
import '../../../products/domain/entities/product.dart';
import '../../../products/presentation/providers/products_provider.dart';
import '../../../sesi/presentation/providers/sesi_providers.dart';
import '../../../sesi/presentation/widgets/buka_sesi_dialog.dart';
import '../../data/parkir_store.dart';
import '../controllers/cart_controller.dart';
import '../controllers/keranjang_meta.dart';
import '../widgets/cart_sheet.dart';
import '../widgets/parkir_sheet.dart';

/// Layar Kasir — katalog, pencarian, penyaring kategori, dan keranjang.
///
/// Susunan mengikuti urutan kerja kasir: cari atau pilih kategori, ketuk item
/// untuk menambah, lalu bayar lewat bilah keranjang yang selalu mengambang di
/// bawah. Item yang sudah masuk keranjang menampilkan pengatur jumlah langsung
/// di kartunya sehingga koreksi jumlah tidak perlu membuka keranjang.
class KasirScreen extends ConsumerStatefulWidget {
  const KasirScreen({super.key});

  @override
  ConsumerState<KasirScreen> createState() => _KasirScreenState();
}

class _KasirScreenState extends ConsumerState<KasirScreen> {
  final _queryCtrl = TextEditingController();
  String? _kategori;

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    setState(() {});
    ref.read(productQueryProvider.notifier).state = value;
  }

  void _clearQuery() {
    _queryCtrl.clear();
    _onQueryChanged('');
    FocusScope.of(context).unfocus();
  }

  void _bukaKeranjang() {
    FocusScope.of(context).unfocus();
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const CartSheet(),
    );
  }

  void _tambah(Product p) {
    ref.read(cartControllerProvider.notifier).add(p);
    HapticFeedback.selectionClick();
  }

  /// Pindai beruntun: tiap barcode yang dikenal langsung masuk keranjang.
  /// Dicocokkan ke katalog yang sudah termuat (semua halaman) — bekerja juga
  /// saat offline; bila tak ada, dicari ke server berdasarkan kode.
  Future<void> _pindai() async {
    FocusScope.of(context).unfocus();
    await PindaiBarcodeScreen.beruntun(context, onKode: (kode) async {
      final produk = await _cariBarcode(kode);
      if (produk == null) return null;
      ref.read(cartControllerProvider.notifier).add(produk);
      final qty = ref.read(cartControllerProvider).firstWhere((e) => e.product.id == produk.id).qty;
      return '${produk.nama} · ×$qty';
    });
  }

  Future<Product?> _cariBarcode(String kode) async {
    final k = kode.trim();
    bool cocok(Product p) => (p.barcode ?? '').trim() == k;
    final termuat = ref.read(productsProvider).valueOrNull ?? const <Product>[];
    for (final p in termuat) {
      if (cocok(p)) return p;
    }
    final r = await ref.read(productRepositoryProvider).list(query: k);
    return r.when(
      ok: (list) {
        for (final p in list) {
          if (cocok(p)) return p;
        }
        return null;
      },
      err: (_) => null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(productsProvider);
    final count = ref.watch(cartCountProvider);
    final total = ref.watch(cartGrandTotalProvider);
    final items = ref.watch(cartControllerProvider);
    final cart = ref.read(cartControllerProvider.notifier);

    // Kuantitas per produk — dipakai kartu untuk menampilkan pengatur jumlah.
    final qty = <String, int>{for (final e in items) e.product.id: e.qty};

    final semua = products.valueOrNull ?? const <Product>[];
    final kategori = <String>{
      for (final p in semua)
        if (p.kategori != null && p.kategori!.trim().isNotEmpty) p.kategori!.trim(),
    }.toList()..sort();
    final tampil = _kategori == null
        ? semua
        : semua.where((p) => p.kategori?.trim() == _kategori).toList();
    final lebar = layarLebar(context);

    // Isi katalog (kepala, cari, kategori, daftar/grid) — dipakai kedua tata letak.
    Widget katalog() => Column(
      children: [
        const _SesiBanner(),
        _Pencarian(
          controller: _queryCtrl,
          onChanged: _onQueryChanged,
          onClear: _clearQuery,
        ),
        if (kategori.isNotEmpty)
          _FilterKategori(
            kategori: kategori,
            terpilih: _kategori,
            onPilih: (k) => setState(() => _kategori = k),
          ),
        Expanded(
          child: products.when(
            loading: () => const DaftarKerangka(),
            error: (e, _) => KeadaanGagal(
              error: e,
              onUlangi: () => ref.invalidate(productsProvider),
            ),
            data: (_) => tampil.isEmpty
                ? _kosong()
                : RefreshIndicator(
                    onRefresh: () async => ref.invalidate(productsProvider),
                    child: lebar
                        // Tablet: grid kartu ringkas 2–3 kolom seperti katalog desktop.
                        ? LayoutBuilder(
                            builder: (_, c) => GridView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                              // Kolom mengikuti lebar (sel ≥ 320 dp) agar nama
                              // & harga tidak terhimpit di panel yang sempit.
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: ((c.maxWidth - 32) / 320).floor().clamp(1, 4),
                                mainAxisExtent: 112,
                                mainAxisSpacing: 10,
                                crossAxisSpacing: 10,
                              ),
                              itemCount: tampil.length,
                              itemBuilder: (_, i) => _KartuProduk(
                                product: tampil[i],
                                qty: qty[tampil[i].id] ?? 0,
                                onTambah: () => _tambah(tampil[i]),
                                onUbahQty: (n) => cart.setQty(tampil[i].id, n),
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: EdgeInsets.fromLTRB(
                              16,
                              6,
                              16,
                              count == 0 ? 24 : 118,
                            ),
                            itemCount: tampil.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 10),
                            itemBuilder: (_, i) => MunculBertahap(
                              urutan: i,
                              child: _KartuProduk(
                                product: tampil[i],
                                qty: qty[tampil[i].id] ?? 0,
                                onTambah: () => _tambah(tampil[i]),
                                onUbahQty: (n) => cart.setQty(tampil[i].id, n),
                              ),
                            ),
                          ),
                  ),
          ),
        ),
      ],
    );

    if (lebar) {
      // Tablet ala desktop: katalog di kiri, keranjang menetap di kanan.
      return Scaffold(
        appBar: AppBar(
          title: const Text('Kasir'),
          actions: [
            const _TombolParkir(),
            IconButton(
              tooltip: 'Pindai barcode dengan kamera',
              onPressed: _pindai,
              icon: const Icon(Icons.qr_code_scanner_rounded),
            ),
            IconButton(
              tooltip: 'Muat ulang katalog',
              onPressed: () => ref.invalidate(productsProvider),
              icon: const Icon(Icons.refresh_rounded),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: AppBackground(
          ombak: false,
          intensitas: 0.55,
          child: SafeArea(
            bottom: false,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: katalog()),
                const _PanelKeranjang(),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      extendBody: true, // bilah keranjang mengambang di atas daftar
      appBar: AppBar(
        title: const Text('Kasir'),
        actions: [
          const _TombolParkir(),
          IconButton(
            tooltip: 'Pindai barcode dengan kamera',
            onPressed: _pindai,
            icon: const Icon(Icons.qr_code_scanner_rounded),
          ),
          IconButton(
            tooltip: 'Muat ulang katalog',
            onPressed: () => ref.invalidate(productsProvider),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: AppBackground(
        ombak: false,
        intensitas: 0.55,
        child: SafeArea(bottom: false, child: katalog()),
      ),
      bottomNavigationBar: BilahKeranjang(
        count: count,
        total: total,
        onTap: _bukaKeranjang,
      ),
    );
  }

  Widget _kosong() {
    if (_kategori != null) {
      return KeadaanKosong(
        ikon: Icons.filter_alt_off_outlined,
        judul: 'Tidak ada item di kategori ini',
        detail: 'Kategori "$_kategori" belum berisi item.',
        aksi: OutlinedButton(
          onPressed: () => setState(() => _kategori = null),
          child: const Text('Tampilkan semua'),
        ),
      );
    }
    if (_queryCtrl.text.isNotEmpty) {
      return KeadaanKosong(
        ikon: Icons.search_off_rounded,
        judul: 'Tidak ada hasil',
        detail: 'Tidak ada item yang cocok dengan "${_queryCtrl.text}".',
        aksi: OutlinedButton(
          onPressed: _clearQuery,
          child: const Text('Hapus pencarian'),
        ),
      );
    }
    return const KeadaanKosong(
      ikon: Icons.inventory_2_outlined,
      judul: 'Katalog masih kosong',
      detail: 'Tambahkan produk atau layanan lebih dulu lewat menu Produk.',
    );
  }
}

/// Ikon "Keranjang terparkir" di AppBar dengan lencana jumlah; tersembunyi
/// saat tidak ada yang terparkir agar bilah tetap lega.
class _TombolParkir extends ConsumerWidget {
  const _TombolParkir();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jumlah = ref.watch(parkirDaftarProvider).valueOrNull?.length ?? 0;
    if (jumlah == 0) return const SizedBox.shrink();
    return IconButton(
      tooltip: 'Keranjang terparkir ($jumlah)',
      onPressed: () => bukaDaftarParkir(context),
      icon: Badge.count(
        count: jumlah,
        backgroundColor: AppColors.warn,
        child: const Icon(Icons.local_parking_rounded),
      ),
    );
  }
}

/// Panel keranjang menetap di kanan (tablet): lembar keranjang yang sama
/// dengan ponsel, tertanam — langkah bayar berlangsung di panel ini.
class _PanelKeranjang extends StatelessWidget {
  const _PanelKeranjang();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 380,
      margin: const EdgeInsets.fromLTRB(0, 8, 16, 16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outline),
      ),
      child: const CartSheet(tertanam: true),
    );
  }
}

/// Kolom cari — menempel di bawah judul, dengan tombol bersih yang muncul
/// hanya saat ada isian.
class _Pencarian extends StatelessWidget {
  const _Pencarian({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: TextField(
        controller: controller,
        textInputAction: TextInputAction.search,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: 'Cari nama, kode, atau barcode…',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Hapus pencarian',
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded),
                ),
        ),
      ),
    );
  }
}

/// Penyaring kategori — diambil dari katalog yang termuat, bukan daftar tetap,
/// sehingga ikut menyesuaikan bidang usaha toko.
class _FilterKategori extends StatelessWidget {
  const _FilterKategori({
    required this.kategori,
    required this.terpilih,
    required this.onPilih,
  });

  final List<String> kategori;
  final String? terpilih;
  final ValueChanged<String?> onPilih;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: kategori.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final semua = i == 0;
          final nama = semua ? 'Semua' : kategori[i - 1];
          final aktif = semua ? terpilih == null : terpilih == nama;
          return ChoiceChip(
            label: Text(nama),
            selected: aktif,
            onSelected: (_) => onPilih(semua ? null : nama),
            showCheckmark: false,
            labelStyle: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: aktif
                  ? AppColors.mint900
                  : Theme.of(context).colorScheme.onSurface,
            ),
            selectedColor: AppColors.mint400,
            side: aktif
                ? BorderSide.none
                : BorderSide(color: Theme.of(context).colorScheme.outline),
          );
        },
      ),
    );
  }
}

/// Kartu item katalog. Saat sudah ada di keranjang, tombol Tambah berganti
/// menjadi pengatur jumlah dan kartu diberi bingkai aksen — jadi kasir bisa
/// melihat sekilas apa saja yang sudah masuk.
class _KartuProduk extends StatelessWidget {
  const _KartuProduk({
    required this.product,
    required this.qty,
    required this.onTambah,
    required this.onUbahQty,
  });

  final Product product;
  final int qty;
  final VoidCallback onTambah;
  final ValueChanged<int> onUbahQty;

  bool get _jasa => (product.tipe ?? '').toUpperCase() == 'JASA';
  bool get _diKeranjang => qty > 0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTambah,
        child: AnimatedContainer(
          duration: Gerak.cepat,
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _diKeranjang ? cs.primary : cs.outline,
              width: _diKeranjang ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              _Lambang(jasa: _jasa, gambar: product.gambar),
              const SizedBox(width: 12),
              Expanded(
                // Di sel grid bertinggi tetap (tablet), isi yang kelewat
                // panjang dipotong rapi alih-alih meluap.
                child: ClipRect(
                  child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      product.nama,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 5),
                    // Harga · satuan · lencana stok dalam satu baris agar kartu
                    // ringkas dan lebih banyak produk terlihat sekali pandang.
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Text(
                          fmtIDR(product.harga),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: cs.primary,
                          ),
                        ),
                        if (product.promo && product.hargaNormal != null)
                          Text(
                            fmtIDR(product.hargaNormal!),
                            style: TextStyle(
                              fontSize: 12,
                              decoration: TextDecoration.lineThrough,
                              color: cs.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                        if (product.satuan != null && product.satuan!.isNotEmpty)
                          Text(
                            '/ ${product.satuan}',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: cs.onSurface.withValues(alpha: 0.55),
                            ),
                          ),
                        if (!_jasa && product.stok != null)
                          _LencanaStok(stok: product.stok!),
                      ],
                    ),
                  ],
                ),
                ),
              ),
              const SizedBox(width: 10),
              AnimatedSwitcher(
                duration: Gerak.cepat,
                child: _diKeranjang
                    ? _PengaturJumlah(
                        key: const ValueKey('qty'),
                        qty: qty,
                        onUbah: onUbahQty,
                      )
                    : Semantics(
                        key: const ValueKey('tambah'),
                        button: true,
                        label: 'Tambah ${product.nama}',
                        child: Material(
                          color: AppColors.mint400,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: onTambah,
                            child: const SizedBox(
                              height: 44,
                              width: 44,
                              child: Icon(
                                Icons.add_rounded,
                                size: 24,
                                color: AppColors.mint900,
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lambang item: foto produk bila ada (seperti kartu kasir desktop), selain
/// itu ikon jenis — membedakan jasa dari barang secara sekilas.
class _Lambang extends StatelessWidget {
  const _Lambang({required this.jasa, this.gambar});
  final bool jasa;
  final String? gambar;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ikon = Icon(
      jasa ? Icons.handyman_outlined : Icons.inventory_2_outlined,
      size: 22,
      color: cs.primary,
    );
    return Container(
      height: 46,
      width: 46,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: gambar == null
          ? ikon
          : Image.network(
              gambar!,
              fit: BoxFit.cover,
              // Ukuran dekode dibatasi: kartu 46dp, bukan foto 2000px penuh.
              cacheWidth: 138,
              errorBuilder: (_, _, _) => ikon,
            ),
    );
  }
}

/// Lencana stok berwarna: habis (merah), menipis (jingga), aman (netral).
class _LencanaStok extends StatelessWidget {
  const _LencanaStok({required this.stok});
  final double stok;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (warna, teks) = stok <= 0
        ? (cs.error, 'Stok habis')
        : stok <= 5
        ? (AppColors.warn, 'Sisa ${stok.toInt()}')
        : (cs.onSurface.withValues(alpha: 0.6), 'Stok ${stok.toInt()}');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: warna.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        teks,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: warna,
        ),
      ),
    );
  }
}

/// Pengatur jumlah ringkas (−  n  +) dengan sasaran sentuh yang layak.
class _PengaturJumlah extends StatelessWidget {
  const _PengaturJumlah({super.key, required this.qty, required this.onUbah});

  final int qty;
  final ValueChanged<int> onUbah;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.primary.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TombolBulat(
            ikon: qty == 1 ? Icons.delete_outline_rounded : Icons.remove_rounded,
            tooltip: qty == 1 ? 'Hapus dari keranjang' : 'Kurangi',
            onTekan: () {
              onUbah(qty - 1);
              HapticFeedback.selectionClick();
            },
          ),
          SizedBox(
            width: 26,
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
          _TombolBulat(
            ikon: Icons.add_rounded,
            tooltip: 'Tambah',
            onTekan: () {
              onUbah(qty + 1);
              HapticFeedback.selectionClick();
            },
          ),
        ],
      ),
    );
  }
}

class _TombolBulat extends StatelessWidget {
  const _TombolBulat({
    required this.ikon,
    required this.tooltip,
    required this.onTekan,
  });

  final IconData ikon;
  final String tooltip;
  final VoidCallback onTekan;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTekan,
        customBorder: const CircleBorder(),
        child: SizedBox(
          height: 44,
          width: 40,
          child: Icon(ikon, size: 19, color: cs.primary),
        ),
      ),
    );
  }
}

/// Bilah keranjang mengambang — muncul dari bawah saat keranjang terisi dan
/// menghilang saat kosong, jadi ruang layar tidak terpakai percuma.
class BilahKeranjang extends StatelessWidget {
  const BilahKeranjang({
    super.key,
    required this.count,
    required this.total,
    required this.onTap,
  });

  final int count;
  final double total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final terlihat = count > 0;
    final kurangiGerak = Gerak.dikurangi(context);

    final bilah = SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        child: Material(
          color: AppColors.mint600,
          borderRadius: BorderRadius.circular(18),
          elevation: 10,
          shadowColor: AppColors.mint900.withValues(alpha: 0.45),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                children: [
                  Container(
                    height: 34,
                    width: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(
                      Icons.shopping_cart_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$count item di keranjang',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                        const SizedBox(height: 1),
                        AngkaBerubah(
                          nilai: total,
                          format: fmtIDR,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Bayar',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppColors.mint900,
                          ),
                        ),
                        SizedBox(width: 4),
                        Icon(
                          Icons.arrow_forward_rounded,
                          size: 17,
                          color: AppColors.mint900,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (kurangiGerak) {
      return terlihat ? bilah : const SizedBox.shrink();
    }
    return AnimatedSlide(
      offset: terlihat ? Offset.zero : const Offset(0, 1.4),
      duration: Gerak.normal,
      curve: Gerak.kurva,
      child: AnimatedOpacity(
        opacity: terlihat ? 1 : 0,
        duration: Gerak.cepat,
        child: IgnorePointer(ignoring: !terlihat, child: bilah),
      ),
    );
  }
}

/// Peringatan bila sesi kasir belum dibuka — checkout membutuhkannya.
class _SesiBanner extends ConsumerWidget {
  const _SesiBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesi = ref.watch(activeSesiProvider);
    if (sesi.isLoading || sesi.valueOrNull != null) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.warn.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warn.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: AppColors.warn, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Sesi kasir belum dibuka.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: () => bukaSesiDenganUmpanBalik(context, ref),
            child: const Text('Buka sesi'),
          ),
        ],
      ),
    );
  }
}

/// Buka sesi kasir + tampilkan hasilnya. Dipakai layar Kasir dan keranjang.
Future<void> bukaSesiDenganUmpanBalik(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context); // sebelum async gap
  final modal = await showBukaSesiDialog(context);
  if (modal == null) return;
  try {
    final tertunda = await ref.read(activeSesiProvider.notifier).buka(modal);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: tertunda ? AppColors.warn : AppColors.success,
          content: Text(tertunda
              ? 'Sesi dibuka offline. Dikirim ke server saat online, sebelum transaksi.'
              : 'Sesi kasir dibuka.'),
        ),
      );
  } on ApiException catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: AppColors.danger,
          content: Text(e.firstError() ?? e.message),
        ),
      );
  }
}
