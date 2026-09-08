import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/rupiah_input.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/offline/pengurai.dart';
import '../../../../core/offline/rujukan_lokal.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/offline/nomor_lokal.dart';
import '../../../../core/storage/secure_storage.dart';
import '../../../cetak/domain/entities/struk.dart';
import '../../../demo/demo_session.dart';
import '../../../kasir/presentation/widgets/hasil_transaksi_sheet.dart';
import '../../../pengaturan/presentation/providers/pengaturan_providers.dart';
import '../../../products/domain/entities/product.dart';
import '../../../products/presentation/providers/products_provider.dart';
import '../../domain/entities/bill_detail.dart';
import '../providers/meja_providers.dart';

/// Detail bon meja — lihat item, tambah pesanan (ronde), bayar (settle).
class BillDetailScreen extends ConsumerWidget {
  const BillDetailScreen({super.key, required this.billId, required this.mejaNomor});

  final String billId;
  final String mejaNomor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(billDetailProvider(billId));
    return Scaffold(
      appBar: AppBar(title: Text('Meja $mejaNomor')),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(e is ApiException ? e.message : 'Gagal memuat bon.',
                textAlign: TextAlign.center),
          ),
        ),
        data: (b) => _Body(billId: billId, bill: b),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.billId, required this.bill});
  final String billId;
  final BillDetail bill;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(bill.nomor,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  if (bill.pax != null) Text('${bill.pax} org', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6))),
                ],
              ),
              if (adalahRujukanLokal(billId))
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Bon dibuka saat offline. Pesanan & pembayaran disimpan di ponsel dan '
                    'dikirim berurutan begitu online.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.warn, height: 1.4),
                  ),
                ),
              const Divider(height: 24),
              if (bill.items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('Belum ada pesanan. Tekan "Tambah Pesanan".')),
                )
              else
                for (final it in bill.items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(it.nama, style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text('${it.kuantitas.toInt()} × ${fmtIDR(it.harga ?? 0)}',
                                  style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6), fontSize: 13)),
                            ],
                          ),
                        ),
                        Text(fmtIDR(it.subtotal), style: const TextStyle(fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('TOTAL', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  Text(fmtIDR(bill.total),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.mint600)),
                ],
              ),
            ],
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      showDragHandle: true,
                      builder: (_) => _AddPesananSheet(billId: billId),
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('Tambah Pesanan'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: bill.total <= 0 ? null : () => _bayar(context, ref, bill.total),
                    icon: const Icon(Icons.payments_outlined),
                    label: const Text('Bayar'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _bayar(BuildContext context, WidgetRef ref, double total) async {
    final dibayar = await showDialog<double>(
      context: context,
      builder: (_) => _DialogBayarTunai(total: total),
    );
    if (dibayar == null || !context.mounted) return;
    final struk = _struk(ref, dibayar: dibayar, total: total);
    final r = await ref.read(mejaRepositoryProvider).bayar(billId, tipe: 'TUNAI', dibayar: dibayar);
    // Bon yang dibuka offline bernomor sama ("Bon offline") untuk semua meja;
    // beri nomor lokal unik supaya dua pelanggan tidak menerima struk kembar
    // dan nomornya bisa dicocokkan lagi di layar Sinkronisasi.
    String? nomorLokal;
    if (r.isOk && (r.valueOrNull?.tertunda ?? false)) {
      try {
        nomorLokal = await NomorLokal(ref.read(secureStorageProvider)).berikutnya();
      } catch (_) {
        nomorLokal = null; // penyimpanan bermasalah — pakai nomor bon apa adanya
      }
    }
    if (!context.mounted) return;
    r.when(
      ok: (h) {
        if (h.tertunda) ref.read(antreanVersiProvider.notifier).state++;
        ref.invalidate(mejaPetaProvider);
        final navigator = Navigator.of(context);
        navigator.pop(); // kembali ke peta
        // Struk bon meja: sama seperti kasir — bisa dicetak, dibagikan, dan
        // ikut cetak otomatis bila diatur di Pengaturan → Printer Struk.
        showModalBottomSheet<void>(
          context: navigator.context,
          useRootNavigator: true,
          isScrollControlled: true,
          useSafeArea: true,
          showDragHandle: true,
          builder: (_) => HasilTransaksiSheet(
            struk: h.tertunda
                ? struk.salinDengan(
                    nomor: nomorLokal,
                    barcode: nomorLokal,
                    catatanKaki: 'Belum tersinkron — nomor resmi menyusul setelah online.',
                  )
                : struk,
            kembalian: struk.kembalian ?? 0,
            tertunda: h.tertunda,
            perluTinjau: h.perluTinjau,
          ),
        );
      },
      err: (e) => ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            backgroundColor: AppColors.danger, content: Text(e.firstError() ?? e.message))),
    );
  }

  /// Struk bon meja dari item yang tampil di layar + profil usaha.
  // (helper struk di bawah)
  Struk _struk(WidgetRef ref, {required double dibayar, required double total}) {
    final usaha = ref.read(profilUsahaProvider).valueOrNull;
    final kembalian = dibayar - total;
    return Struk(
      namaToko: usaha?.nama ?? 'Tuléh POS',
      alamat: usaha?.alamat,
      telepon: usaha?.telepon,
      nomor: bill.nomor,
      waktu: DateTime.now(),
      baris: [
        for (final it in bill.items)
          StrukBaris(
            nama: it.nama,
            kuantitas: it.kuantitas,
            harga: it.harga ?? (it.kuantitas > 0 ? it.subtotal / it.kuantitas : it.subtotal),
          ),
      ],
      total: total,
      metode: 'TUNAI',
      dibayar: dibayar,
      kembalian: kembalian > 0 ? kembalian : 0,
      catatanKaki: usaha?.strukFooter,
      barcode: bill.nomor,
      logoUrl: (usaha?.strukTampilLogo ?? false) ? usaha?.logo : null,
      demo: ref.read(demoSessionProvider).active,
      pelanggan: bill.label,
    );
  }
}

/// Dialog "Bayar Tunai" — memiliki TextEditingController-nya sendiri supaya
/// tidak dibuang selagi dialog masih beranimasi menutup (controller yang sudah
/// di-dispose lalu dipakai lagi = assertion di debug, perilaku tak menentu di
/// rilis). Mengembalikan nominal yang dibayar, atau null bila dibatalkan.
class _DialogBayarTunai extends StatefulWidget {
  const _DialogBayarTunai({required this.total});

  final double total;

  @override
  State<_DialogBayarTunai> createState() => _DialogBayarTunaiState();
}

class _DialogBayarTunaiState extends State<_DialogBayarTunai> {
  late final TextEditingController _ctrl = TextEditingController(
    text: teksRupiah(widget.total),
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  double get _diterima {
    final teks = _ctrl.text.trim();
    return teks.isEmpty ? 0 : parseRupiah(teks);
  }

  /// Kurang bayar = server tetap menerimanya (tidak divalidasi di sana), jadi
  /// kasirlah yang harus dijaga di sini — sama seperti lembar bayar kasir.
  double get _kurang => widget.total - _diterima;

  void _kirim() {
    if (_kurang > 0) return;
    Navigator.pop(context, _diterima);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final kurang = _kurang;
    return AlertDialog(
      title: const Text('Bayar Tunai'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Total ${fmtIDR(widget.total)}'),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            keyboardType: TextInputType.number,
            inputFormatters: const [RupiahInputFormatter()],
            autofocus: true,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _kirim(),
            decoration: const InputDecoration(labelText: 'Uang diterima', prefixText: 'Rp '),
          ),
          const SizedBox(height: 10),
          Text(
            kurang > 0
                ? 'Kurang ${fmtIDR(kurang)}'
                : 'Kembalian ${fmtIDR(-kurang)}',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: kurang > 0 ? cs.error : AppColors.mint600,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(onPressed: kurang > 0 ? null : _kirim, child: const Text('Bayar')),
      ],
    );
  }
}

/// Sheet pilih produk → kirim sebagai ronde ke bon.
class _AddPesananSheet extends ConsumerStatefulWidget {
  const _AddPesananSheet({required this.billId});
  final String billId;

  @override
  ConsumerState<_AddPesananSheet> createState() => _AddPesananSheetState();
}

class _AddPesananSheetState extends ConsumerState<_AddPesananSheet> {
  final Map<String, int> _qty = {}; // productId → qty
  final Map<String, Product> _prod = {};
  bool _loading = false;

  int get _count => _qty.values.fold(0, (s, q) => s + q);

  Future<void> _kirim() async {
    if (_count == 0) return;
    setState(() => _loading = true);
    final items = [
      for (final e in _qty.entries)
        if (e.value > 0) {'id_produk': e.key, 'kuantitas': e.value},
    ];
    // Nama & harga hanya untuk tampilan selama belum terkirim (offline).
    final tampilan = [
      for (final e in _qty.entries)
        if (e.value > 0)
          {
            'id_produk': e.key,
            'nama': _prod[e.key]?.nama ?? '-',
            'harga': _prod[e.key]?.harga ?? 0,
            'kuantitas': e.value,
            'kelola_stok': _prod[e.key]?.stok != null,
          },
    ];
    final r = await ref
        .read(mejaRepositoryProvider)
        .tambahRonde(widget.billId, items, tampilan: tampilan);
    if (!mounted) return;
    r.when(
      ok: (h) {
        if (h.tertunda) ref.read(antreanVersiProvider.notifier).state++;
        ref.invalidate(billDetailProvider(widget.billId));
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
              backgroundColor: h.tertunda ? AppColors.warn : AppColors.success,
              content: Text(h.tertunda
                  ? '$_count item disimpan offline — dikirim ke dapur saat online.'
                  : '$_count item dikirim ke dapur.')));
      },
      err: (e) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
              backgroundColor: AppColors.danger, content: Text(e.firstError() ?? e.message)));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(productsProvider);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Tambah Pesanan',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            Expanded(
              child: products.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text(e is ApiException ? e.message : 'Gagal memuat produk.')),
                data: (list) => ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final p = list[i];
                    _prod[p.id] = p;
                    final q = _qty[p.id] ?? 0;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(p.nama),
                      subtitle: Text(fmtIDR(p.harga)),
                      trailing: q == 0
                          ? IconButton(
                              icon: const Icon(Icons.add_circle, color: AppColors.mint600),
                              onPressed: () => setState(() => _qty[p.id] = 1),
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline),
                                  onPressed: () => setState(() {
                                    final n = q - 1;
                                    if (n <= 0) {
                                      _qty.remove(p.id);
                                    } else {
                                      _qty[p.id] = n;
                                    }
                                  }),
                                ),
                                Text('$q', style: const TextStyle(fontWeight: FontWeight.w700)),
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline),
                                  onPressed: () => setState(() => _qty[p.id] = q + 1),
                                ),
                              ],
                            ),
                    );
                  },
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(
                  onPressed: (_count == 0 || _loading) ? null : _kirim,
                  child: _loading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.mint900))
                      : Text(_count == 0 ? 'Pilih item' : 'Kirim ke Dapur ($_count item)'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
