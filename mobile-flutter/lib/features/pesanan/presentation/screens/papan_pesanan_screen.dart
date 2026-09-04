import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/format.dart';
import '../../../toko/presentation/providers/toko_providers.dart';
import '../../domain/entities/pesanan.dart';
import '../../domain/logic/papan_logic.dart';
import '../providers/pesanan_providers.dart';

/// Papan Pesanan — KDS dapur / Antrian / Papan Proses dalam satu layar.
/// Kolom (tab) dibaca dari `manifest.lifecycle.states` toko aktif, jadi layar
/// ini melayani bakso, laundry, bengkel, doorsmeer, salon, dan bidang usaha
/// baru yang dikirim server tanpa perubahan kode.
class PapanPesananScreen extends ConsumerStatefulWidget {
  const PapanPesananScreen({super.key});

  @override
  ConsumerState<PapanPesananScreen> createState() => _PapanPesananScreenState();
}

class _PapanPesananScreenState extends ConsumerState<PapanPesananScreen> {
  static const _pollInterval = Duration(seconds: 8);

  Timer? _timer;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    // Polling: server belum punya kanal push (Blueprint §11.6).
    _timer = Timer.periodic(_pollInterval, (_) {
      if (mounted && _busyId == null) ref.invalidate(pesananListProvider);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final manifestAsync = ref.watch(activeManifestProvider);

    return manifestAsync.when(
      loading: () => _shell(
        context,
        judul: 'Papan Pesanan',
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => _shell(
        context,
        judul: 'Papan Pesanan',
        body: _Pesan(
          icon: Icons.cloud_off_rounded,
          judul: 'Gagal memuat alur toko',
          detail: e is ApiException ? e.message : '$e',
          onRetry: () => ref.invalidate(activeManifestProvider),
        ),
      ),
      data: (manifest) {
        final states = manifest.lifecycleStates;
        final judul = manifest.menuPapan?.label ?? 'Papan Pesanan';
        if (!manifest.punyaPapanPesanan) {
          return _shell(
            context,
            judul: judul,
            body: const _Pesan(
              icon: Icons.inbox_rounded,
              judul: 'Toko ini tidak memakai alur pesanan',
              detail:
                  'Papan pesanan hanya tersedia untuk bidang usaha dengan tahapan, '
                  'misalnya kuliner, laundry, bengkel, doorsmeer, atau salon.',
            ),
          );
        }
        return _Board(
          judul: judul,
          states: states,
          busyId: _busyId,
          onAksi: (o, aksi) => _jalankanAksi(o, aksi, states),
        );
      },
    );
  }

  Widget _shell(
    BuildContext context, {
    required String judul,
    required Widget body,
  }) => Scaffold(appBar: AppBar(title: Text(judul)), body: body);

  Future<void> _jalankanAksi(
    Pesanan o,
    AksiKartu aksi,
    List<String> states,
  ) async {
    final next = tahapBerikut(o.stage, states);
    if (next == null) return;

    String? tipePembayaran;
    if (aksi == AksiKartu.konfirmasiBayar || aksi == AksiKartu.lunasi) {
      tipePembayaran = await _pilihPembayaran(o, aksi);
      if (tipePembayaran == null) return; // dibatalkan
    }

    setState(() => _busyId = o.id);
    try {
      await ref
          .read(pesananAksiProvider)
          .transition(
            o.id,
            to: aksi == AksiKartu.lunasi ? (tahapTerminal(states) ?? next) : next,
            tipePembayaran: tipePembayaran,
          );
      if (!mounted) return;
      _snack(
        aksi == AksiKartu.lunasi
            ? 'Pesanan ${o.label} lunas & diserahkan.'
            : 'Pesanan ${o.label} → ${stageLabel(next)}.',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      _snack(e.message, error: true);
      ref.invalidate(pesananListProvider); // selaraskan dgn kondisi server
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  /// Konfirmasi bayar & pelunasan butuh metode pembayaran (cermin papan desktop).
  Future<String?> _pilihPembayaran(Pesanan o, AksiKartu aksi) async {
    final manifest = ref.read(activeManifestProvider).valueOrNull;
    final modes = manifest?.paymentModes.isNotEmpty == true
        ? manifest!.paymentModes
        : const ['TUNAI', 'QRIS', 'TRANSFER'];

    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    aksi == AksiKartu.lunasi
                        ? 'Lunasi & Serahkan'
                        : 'Konfirmasi Pembayaran',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${o.label} · ${fmtIDR(o.total)}',
                    style: TextStyle(
                      color: Theme.of(sheetContext).colorScheme.onSurface
                          .withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
            ),
            for (final m in modes)
              ListTile(
                leading: Icon(_ikonBayar(m)),
                title: Text(m),
                onTap: () => Navigator.of(sheetContext).pop(m),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  static IconData _ikonBayar(String mode) => switch (mode.toUpperCase()) {
    'TUNAI' => Icons.payments_outlined,
    'QRIS' => Icons.qr_code_2_rounded,
    'TRANSFER' => Icons.account_balance_outlined,
    _ => Icons.credit_card_outlined,
  };

  void _snack(String pesan, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(pesan),
          backgroundColor: error ? Theme.of(context).colorScheme.error : null,
        ),
      );
  }
}

/// Papan bertab: satu tab per tahap, dengan jumlah pesanan di badge.
class _Board extends ConsumerWidget {
  const _Board({
    required this.judul,
    required this.states,
    required this.busyId,
    required this.onAksi,
  });

  final String judul;
  final List<String> states;
  final String? busyId;
  final void Function(Pesanan, AksiKartu) onAksi;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(pesananListProvider);
    final rows = async.valueOrNull ?? const <Pesanan>[];
    final adaMenungguBayar = rows.any((o) => o.menungguBayar);
    final kolom = kolomPapan(states, adaMenungguBayar: adaMenungguBayar);
    final ambang = ambangUmur(states);

    return DefaultTabController(
      length: kolom.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(judul),
          actions: [
            IconButton(
              tooltip: 'Muat ulang',
              onPressed: () => ref.invalidate(pesananListProvider),
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              for (final s in kolom)
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(stageLabel(s)),
                      const SizedBox(width: 6),
                      _Badge(jumlah: rows.where((o) => o.stage == s).length),
                    ],
                  ),
                ),
            ],
          ),
        ),
        body: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _Pesan(
            icon: Icons.cloud_off_rounded,
            judul: 'Gagal memuat pesanan',
            detail: e is ApiException ? e.message : '$e',
            onRetry: () => ref.invalidate(pesananListProvider),
          ),
          data: (_) => TabBarView(
            children: [
              for (final s in kolom)
                RefreshIndicator(
                  onRefresh: () async => ref.invalidate(pesananListProvider),
                  child: _Kolom(
                    rows: rows.where((o) => o.stage == s).toList(),
                    states: states,
                    ambang: ambang,
                    busyId: busyId,
                    onAksi: onAksi,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Kolom extends StatelessWidget {
  const _Kolom({
    required this.rows,
    required this.states,
    required this.ambang,
    required this.busyId,
    required this.onAksi,
  });

  final List<Pesanan> rows;
  final List<String> states;
  final UmurAmbang ambang;
  final String? busyId;
  final void Function(Pesanan, AksiKartu) onAksi;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      // Tetap scrollable agar pull-to-refresh bekerja saat kolom kosong.
      return ListView(
        padding: const EdgeInsets.only(top: 80),
        children: const [
          _Pesan(
            icon: Icons.check_circle_outline_rounded,
            judul: 'Tidak ada pesanan di tahap ini',
            detail: 'Tarik ke bawah untuk menyegarkan.',
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _Kartu(
        pesanan: rows[i],
        states: states,
        ambang: ambang,
        busy: busyId == rows[i].id,
        onAksi: onAksi,
      ),
    );
  }
}

class _Kartu extends StatelessWidget {
  const _Kartu({
    required this.pesanan,
    required this.states,
    required this.ambang,
    required this.busy,
    required this.onAksi,
  });

  final Pesanan pesanan;
  final List<String> states;
  final UmurAmbang ambang;
  final bool busy;
  final void Function(Pesanan, AksiKartu) onAksi;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final menit = umurMenit(pesanan);
    final warnaUmur = menit >= ambang.danger
        ? cs.error
        : menit >= ambang.warn
        ? Colors.orange.shade700
        : cs.onSurface.withValues(alpha: 0.55);
    final aksi = aksiKartu(pesanan, states);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: pesanan.dariMeja ? AppColors.mint400 : cs.outline,
          width: pesanan.dariMeja ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  pesanan.label,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: cs.primary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                fmtUmur(menit),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: warnaUmur,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          if (pesanan.ronde != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Ronde ${pesanan.ronde}',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
          if (pesanan.pelanggan != null &&
              pesanan.pelanggan!.isNotEmpty &&
              pesanan.pelanggan != pesanan.meja)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                pesanan.pelanggan!,
                style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ),
          const SizedBox(height: 10),
          for (final it in pesanan.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${fmtQty(it.kuantitas)}× ',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Expanded(child: Text(it.nama)),
                ],
              ),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                fmtIDR(pesanan.total),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (pesanan.belumBayar) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: cs.error.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Belum bayar',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: cs.error,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              if (aksi != null)
                FilledButton(
                  onPressed: busy ? null : () => onAksi(pesanan, aksi),
                  child: busy
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(labelAksi(aksi, pesanan.stage, states)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.jumlah});
  final int jumlah;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$jumlah',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: cs.primary,
        ),
      ),
    );
  }
}

class _Pesan extends StatelessWidget {
  const _Pesan({
    required this.icon,
    required this.judul,
    this.detail,
    this.onRetry,
  });

  final IconData icon;
  final String judul;
  final String? detail;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: cs.onSurface.withValues(alpha: 0.35)),
            const SizedBox(height: 12),
            Text(
              judul,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            if (detail != null) ...[
              const SizedBox(height: 6),
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurface.withValues(alpha: 0.65)),
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Coba lagi'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
