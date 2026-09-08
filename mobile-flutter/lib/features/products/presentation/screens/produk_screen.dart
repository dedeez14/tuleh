import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/layout/lebar.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/offline/antrean_tulis.dart';
import '../../../../core/offline/pengurai.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/format.dart';
import '../../../inventory/presentation/providers/inventory_providers.dart';
import '../../domain/entities/product.dart';
import '../providers/products_provider.dart';
import 'product_form_sheet.dart';

/// Layar Produk — katalog toko (lihat harga & stok). Tap untuk detail + tambah stok.
class ProdukScreen extends ConsumerWidget {
  const ProdukScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(produkKelolaProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Produk')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => const ProductFormSheet(),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Tambah Produk'),
      ),
      body: LebarKonten(child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              onChanged: (v) => ref.read(productQueryProvider.notifier).state = v,
              decoration: const InputDecoration(
                hintText: 'Cari produk / barcode…',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: products.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(e is ApiException ? e.message : 'Gagal memuat produk.',
                      textAlign: TextAlign.center),
                ),
              ),
              data: (list) => list.isEmpty
                  ? const Center(child: Text('Belum ada produk.'))
                  : RefreshIndicator(
                      onRefresh: () async => ref.invalidate(produkKelolaProvider),
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _Tile(product: list[i]),
                      ),
                    ),
            ),
          ),
        ],
      )),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.product});
  final Product product;

  bool get _jasa => (product.tipe ?? '').toUpperCase() == 'JASA';

  @override
  Widget build(BuildContext context) {
    final stok = product.stok;
    final habis = !_jasa && stok != null && stok <= 0;
    final menipis = !_jasa && stok != null && stok > 0 && stok <= 5;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        onTap: () async {
          final action = await showModalBottomSheet<String>(
            context: context,
            showDragHandle: true,
            builder: (_) => DetailProdukSheet(product: product),
          );
          if (action == 'edit' && context.mounted) {
            showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (_) => ProductFormSheet(product: product),
            );
          }
        },
        title: Text(product.nama, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text([
          fmtIDR(product.harga),
          if (product.satuan != null) '/ ${product.satuan}',
          if (product.kategori != null) '· ${product.kategori}',
        ].join(' ')),
        // Jasa tidak punya stok: sebelumnya tampil "Stok 0" merah seolah habis,
        // menyesatkan pemilik toko. Kini jasa berlencana "Jasa", barang
        // berlencana stok dengan warna habis/menipis/aman.
        trailing: _jasa
            ? _Lencana(teks: 'Jasa', warna: AppColors.mint700, ikon: Icons.handyman_outlined)
            : stok == null
                ? null
                : _Lencana(
                    teks: habis ? 'Habis' : 'Stok ${stok.toInt()}',
                    warna: habis
                        ? AppColors.danger
                        : menipis
                            ? AppColors.warn
                            : AppColors.mint700,
                  ),
      ),
    );
  }
}

/// Lembar detail produk: harga, atribut, dan aksi stok (tambah / opname).
/// Publik agar bisa diuji langsung tanpa melewati katalog.
class DetailProdukSheet extends ConsumerWidget {
  const DetailProdukSheet({super.key, required this.product});
  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(product.nama,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(fmtIDR(product.harga),
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.mint600)),
            const SizedBox(height: 16),
            _kv('Satuan', product.satuan),
            _kv('Kategori', product.kategori),
            _kv('Barcode', product.barcode),
            if ((product.tipe ?? '').toUpperCase() != 'JASA')
              _kv('Stok', product.stok?.toInt().toString()),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pop('edit'),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit'),
                  ),
                ),
                // Tambah stok tidak relevan untuk jasa.
                if ((product.tipe ?? '').toUpperCase() != 'JASA') ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () => _mutasiStok(context, ref, masuk: true),
                      icon: const Icon(Icons.add_box_outlined),
                      label: const Text('Tambah Stok'),
                    ),
                  ),
                ],
              ],
            ),
            // Opname: kurangi stok karena rusak/hilang/selisih hitung.
            if ((product.tipe ?? '').toUpperCase() != 'JASA')
              Padding(
                padding: const EdgeInsets.only(top: 10),
                // Teks memakai warna ink (kontras AA); ikon yang berwarna warn
                // sudah cukup menandai sifat aksinya.
                child: TextButton.icon(
                  onPressed: () => _mutasiStok(context, ref, masuk: false),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.onSurface,
                  ),
                  icon: const Icon(Icons.inventory_outlined, size: 18, color: AppColors.warn),
                  label: const Text('Opname — kurangi stok (rusak / hilang / selisih)'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String? v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: const TextStyle(color: Colors.grey)),
            Text((v == null || v.isEmpty) ? '—' : v,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      );

  /// Stok masuk ([masuk] = true) atau opname/kurangi stok (false). Keduanya
  /// lewat antrean tulis: offline → disimpan dan stok tampil langsung berubah
  /// lewat delta tertunda; server menolak opname melebihi stok (422).
  Future<void> _mutasiStok(BuildContext context, WidgetRef ref, {required bool masuk}) async {
    // null = server tidak mengirim stok; jangan diperlakukan sebagai 0.
    final stokKini = product.stok;
    final isian = await showDialog<({double jumlah, String keterangan})>(
      context: context,
      builder: (_) => _DialogMutasiStok(
        namaProduk: product.nama,
        masuk: masuk,
        stokKini: stokKini,
      ),
    );
    if (isian == null || isian.jumlah <= 0) return;
    final jumlah = isian.jumlah;
    final keterangan = isian.keterangan;
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (!masuk && stokKini != null && jumlah > stokKini) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            backgroundColor: AppColors.danger,
            content: Text('Stok tidak mencukupi — stok "${product.nama}" hanya ${fmtQty(stokKini)}.')));
      return;
    }
    final navigator = Navigator.of(context);
    final ds = ref.read(inventoryDataSourceProvider);
    try {
      final hasil = await ref.read(antreanTulisProvider).jalankan(
        jenis: masuk ? 'STOK_MASUK' : 'OPNAME',
        path: masuk ? '/inventory/stok-masuk' : '/inventory/opname',
        body: {
          'id_produk': product.id,
          'jumlah': jumlah,
          if (!masuk && keterangan.isNotEmpty) 'keterangan': keterangan,
        },
        kirim: masuk ? ds.stokMasukBody : ds.opnameBody,
        deltaStok: {product.id: masuk ? jumlah : -jumlah},
      );
      if (hasil.tertunda) ref.read(antreanVersiProvider.notifier).state++;
      ref.invalidate(produkKelolaProvider);
      ref.invalidate(productsProvider);
      navigator.pop();
      final tanda = masuk ? '+' : '−';
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            backgroundColor: hasil.tertunda ? AppColors.warn : AppColors.success,
            content: Text(hasil.tertunda
                ? 'Offline — stok $tanda${fmtQty(jumlah)} disimpan, dikirim saat internet kembali.'
                : masuk
                    ? 'Stok +${fmtQty(jumlah)} ditambahkan.'
                    : 'Stok −${fmtQty(jumlah)} dicatat sebagai opname.')));
    } on ApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            backgroundColor: AppColors.danger,
            content: Text(e.firstError() ?? e.message)));
    }
  }
}

/// Dialog stok masuk / opname. Memiliki TextEditingController-nya sendiri
/// supaya tidak dibuang selagi dialog masih beranimasi menutup (controller
/// yang sudah di-dispose lalu dipakai lagi memicu assertion di debug).
/// Mengembalikan (jumlah, keterangan), atau null bila dibatalkan.
class _DialogMutasiStok extends StatefulWidget {
  const _DialogMutasiStok({
    required this.namaProduk,
    required this.masuk,
    required this.stokKini,
  });

  final String namaProduk;
  final bool masuk;
  final double? stokKini;

  @override
  State<_DialogMutasiStok> createState() => _DialogMutasiStokState();
}

class _DialogMutasiStokState extends State<_DialogMutasiStok> {
  final _jumlahCtrl = TextEditingController();
  final _ketCtrl = TextEditingController();

  @override
  void dispose() {
    _jumlahCtrl.dispose();
    _ketCtrl.dispose();
    super.dispose();
  }

  void _simpan() {
    // "2,5" (koma desimal Indonesia) ikut diterima.
    final jumlah = double.tryParse(_jumlahCtrl.text.trim().replaceAll(',', '.')) ?? 0;
    Navigator.pop(context, (jumlah: jumlah, keterangan: _ketCtrl.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final stok = widget.stokKini;
    return AlertDialog(
      title: Text(
        widget.masuk
            ? 'Tambah Stok — ${widget.namaProduk}'
            : 'Opname — ${widget.namaProduk}',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _jumlahCtrl,
            keyboardType: TextInputType.number,
            autofocus: true,
            onSubmitted: widget.masuk ? (_) => _simpan() : null,
            decoration: InputDecoration(
              labelText: widget.masuk ? 'Jumlah masuk' : 'Jumlah rusak / hilang',
              helperText: widget.masuk || stok == null
                  ? null
                  : 'Stok saat ini ${fmtQty(stok)}',
            ),
          ),
          if (!widget.masuk) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _ketCtrl,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 120,
              onSubmitted: (_) => _simpan(),
              decoration: const InputDecoration(
                labelText: 'Keterangan (opsional)',
                hintText: 'mis. kemasan rusak, kedaluwarsa',
                counterText: '',
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(onPressed: _simpan, child: const Text('Simpan')),
      ],
    );
  }
}

class _Lencana extends StatelessWidget {
  const _Lencana({required this.teks, required this.warna, this.ikon});
  final String teks;
  final Color warna;
  final IconData? ikon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: warna.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (ikon != null) ...[
              Icon(ikon, size: 13, color: warna),
              const SizedBox(width: 4),
            ],
            Text(teks,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: warna)),
          ],
        ),
      );
}
