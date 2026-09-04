import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/format.dart';
import '../../domain/entities/sesi_rekap.dart';
import '../providers/sesi_providers.dart';
import '../widgets/buka_sesi_dialog.dart';

/// Sesi Kasir — rekap sesi berjalan (kas & penjualan) + tutup / buka.
class SesiScreen extends ConsumerWidget {
  const SesiScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rekap = ref.watch(sesiRekapProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Sesi Kasir')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(sesiRekapProvider),
        child: rekap.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text(e is ApiException ? e.message : 'Gagal memuat sesi.',
                    textAlign: TextAlign.center),
              ),
            ),
          ]),
          data: (r) => (r == null || !r.isBuka)
              ? _Kosong()
              : _RekapView(rekap: r),
        ),
      ),
    );
  }
}

class _Kosong extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      children: [
        const SizedBox(height: 120),
        const Icon(Icons.point_of_sale_outlined, size: 64, color: AppColors.mint400),
        const SizedBox(height: 16),
        const Center(child: Text('Belum ada sesi kasir aktif.')),
        const SizedBox(height: 20),
        Center(
          child: FilledButton.icon(
            onPressed: () => _bukaDialog(context, ref),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Buka Sesi'),
          ),
        ),
      ],
    );
  }
}

class _RekapView extends ConsumerWidget {
  const _RekapView({required this.rekap});
  final SesiRekap rekap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        // Header sesi
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.mint600, AppColors.mint800],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.circle, color: AppColors.mint400, size: 10),
                  const SizedBox(width: 8),
                  Text('Sesi ${rekap.nomor}',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                ],
              ),
              const SizedBox(height: 6),
              Text('Kasir: ${rekap.kasir}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
              if (rekap.waktuBuka != null)
                Text('Dibuka: ${fmtTanggal(rekap.waktuBuka)}',
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _card(cs, 'Ringkasan Penjualan', [
          _row('Jumlah transaksi', '${rekap.jumlahTransaksi}'),
          _row('Tunai', fmtIDR(rekap.totalTunai)),
          _row('Transfer', fmtIDR(rekap.totalTransfer)),
          _row('QRIS', fmtIDR(rekap.totalQris)),
          const Divider(height: 20),
          _row('Total penjualan', fmtIDR(rekap.totalPenjualan), bold: true),
        ]),
        const SizedBox(height: 12),
        _card(cs, 'Kas', [
          _row('Kas awal', fmtIDR(rekap.kasAwal)),
          _row('+ Tunai masuk', fmtIDR(rekap.totalTunai)),
          const Divider(height: 20),
          _row('Kas akhir (sistem)', fmtIDR(rekap.kasAkhirSistem), bold: true),
        ]),
        const SizedBox(height: 24),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.danger,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: () => _tutupDialog(context, ref, rekap),
          icon: const Icon(Icons.stop_circle_outlined),
          label: const Text('Tutup Sesi', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }

  Widget _card(ColorScheme cs, String title, List<Widget> rows) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            ...rows,
          ],
        ),
      );

  // Label memakai Expanded dan nilai Flexible: dua Text telanjang di Row
  // spaceBetween meluber begitu label panjang bertemu nominal jutaan di
  // ponsel 320px.
  Widget _row(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(value,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                      fontSize: bold ? 15 : 14)),
            ),
          ],
        ),
      );
}

// ---------- Dialog Buka ----------
Future<void> _bukaDialog(BuildContext context, WidgetRef ref) async {
  // Messenger ditangkap SEBELUM await: buka sukses mengubah provider → widget
  // pemanggil (_Kosong) di-unmount, jadi .of(context) sesudahnya tak valid.
  final messenger = ScaffoldMessenger.of(context);
  final kas = await showBukaSesiDialog(context);
  if (kas == null) return;
  try {
    await ref.read(activeSesiProvider.notifier).buka(kas);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
          backgroundColor: AppColors.success, content: Text('Sesi kasir dibuka.')));
  } on ApiException catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          backgroundColor: AppColors.danger, content: Text(e.firstError() ?? e.message)));
  }
}

// ---------- Dialog Tutup (dengan pratinjau selisih) ----------
Future<void> _tutupDialog(BuildContext context, WidgetRef ref, SesiRekap rekap) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _TutupDialog(rekap: rekap),
  );
}

class _TutupDialog extends ConsumerStatefulWidget {
  const _TutupDialog({required this.rekap});
  final SesiRekap rekap;

  @override
  ConsumerState<_TutupDialog> createState() => _TutupDialogState();
}

class _TutupDialogState extends ConsumerState<_TutupDialog> {
  late final TextEditingController _fisik =
      TextEditingController(text: widget.rekap.kasAkhirSistem.round().toString());
  final _catatan = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _fisik.dispose();
    _catatan.dispose();
    super.dispose();
  }

  double get _selisih =>
      (double.tryParse(_fisik.text.trim()) ?? 0) - widget.rekap.kasAkhirSistem;

  Future<void> _submit() async {
    final fisik = double.tryParse(_fisik.text.trim()) ?? 0;
    // Tangkap navigator + messenger SEBELUM await (hindari BuildContext lintas-async).
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await ref.read(activeSesiProvider.notifier).tutup(
            kasAkhirFisik: fisik,
            catatan: _catatan.text,
          );
      navigator.pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
            backgroundColor: AppColors.success, content: Text('Sesi kasir ditutup.')));
    } on ApiException catch (e) {
      if (mounted) setState(() => _saving = false);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            backgroundColor: AppColors.danger, content: Text(e.firstError() ?? e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final selisih = _selisih;
    final selisihColor = selisih == 0
        ? AppColors.success
        : (selisih > 0 ? AppColors.mint700 : AppColors.danger);
    return AlertDialog(
      title: const Text('Tutup Sesi'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Kas akhir sistem: ${fmtIDR(widget.rekap.kasAkhirSistem)}',
              style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            controller: _fisik,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Kas akhir fisik', prefixText: 'Rp '),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Selisih', style: TextStyle(fontWeight: FontWeight.w700)),
              Text(fmtIDR(selisih),
                  style: TextStyle(fontWeight: FontWeight.w800, color: selisihColor)),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _catatan,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Catatan (opsional)'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  height: 20, width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
              : const Text('Tutup Sesi'),
        ),
      ],
    );
  }
}
