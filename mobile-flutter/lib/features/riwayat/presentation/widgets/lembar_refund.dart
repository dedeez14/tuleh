import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/akses/akses.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/satuan_terukur.dart';
import '../../../kasir/domain/metode_pembayaran.dart';
import '../../../keamanan/presentation/widgets/dialog_otorisasi.dart';
import '../../../pengaturan/presentation/providers/pengaturan_providers.dart';
import '../../domain/entities/refund.dart';
import '../../domain/entities/transaksi_detail.dart';
import '../providers/riwayat_providers.dart';

/// Lembar refund per item (padanan lembar refund desktop). Mengembalikan
/// dokumen refund bila tercatat, null bila dibatalkan.
///
/// [otorisasiToken] = persetujuan atasan yang sudah didapat pemanggil untuk
/// kasir tanpa hak refund (§2c); sekali pakai.
Future<Refund?> tampilkanLembarRefund(
  BuildContext context,
  TransaksiDetail d, {
  String? otorisasiToken,
}) =>
    showModalBottomSheet<Refund>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _LembarRefund(d: d, otorisasiToken: otorisasiToken),
    );

class _LembarRefund extends ConsumerStatefulWidget {
  const _LembarRefund({required this.d, this.otorisasiToken});
  final TransaksiDetail d;
  final String? otorisasiToken;

  @override
  ConsumerState<_LembarRefund> createState() => _LembarRefundState();
}

class _LembarRefundState extends ConsumerState<_LembarRefund> {
  late final List<TrxItem> _baris = [for (final i in widget.d.items) if (i.qtyBisaRefund > 0 && i.id != null) i];
  late final Map<String, TextEditingController> _qty = {for (final i in _baris) i.id!: TextEditingController()};
  final _alasan = TextEditingController();
  // Dinormalkan terhadap daftar metode dari server di `build`.
  late String _metode = (widget.d.tipePembayaran ?? '').toUpperCase();
  bool _kembaliStok = true;
  bool _loading = false;
  String? _galat;
  // Satu client_ref per lembar: pengulangan tombol setelah timeout mengembalikan refund yang sama.
  final _clientRef = 'rf-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 30)}';

  /// Token persetujuan yang BELUM terkirim. Dikosongkan begitu ikut sebuah
  /// permintaan: server membakarnya walau refund lalu ditolak (422 melebihi
  /// sisa), jadi percobaan berikutnya wajib meminta persetujuan lagi.
  late String? _token = widget.otorisasiToken;

  @override
  void dispose() {
    for (final c in _qty.values) {
      c.dispose();
    }
    _alasan.dispose();
    super.dispose();
  }

  double _nilai(String id) => double.tryParse(_qty[id]!.text.replaceAll(',', '.')) ?? 0;

  /// Perkiraan dari nilai per unit yang dibayar (subtotal/qty); nilai pasti dihitung server.
  double get _perkiraan => _baris.fold(0, (s, i) => s + _nilai(i.id!) * (i.kuantitas > 0 ? i.subtotal / i.kuantitas : 0));

  List<BarisRefund>? _validasi() {
    final baris = <BarisRefund>[];
    for (final i in _baris) {
      final n = _nilai(i.id!);
      if (n <= 0) continue;
      if (n > i.qtyBisaRefund + 1e-9) {
        _galat = 'Jumlah refund ${i.nama} melebihi sisa (${labelKuantitas(i.qtyBisaRefund, i.satuan)}).';
        return null;
      }
      baris.add(BarisRefund(id: i.id!, kuantitas: n));
    }
    if (baris.isEmpty) {
      _galat = 'Pilih minimal satu item yang direfund.';
      return null;
    }
    if (_alasan.text.trim().length < 3) {
      _galat = 'Alasan refund minimal 3 karakter.';
      return null;
    }
    _galat = null;
    return baris;
  }

  Future<void> _kirim() async {
    final baris = _validasi();
    setState(() {});
    if (baris == null) return;
    setState(() => _loading = true);
    final ya = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Catat refund?'),
        content: Text(
          'Sekitar ${fmtIDR(_perkiraan)} dikembalikan ke pelanggan via $_metode. '
          'Dokumen refund bernomor akan dibuat dan tidak dapat diurungkan.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Kembali')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ya, catat')),
        ],
      ),
    );
    if (ya != true || !mounted) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    // Tanpa hak refund sendiri, tiap percobaan butuh token yang masih hidup —
    // termasuk percobaan ulang sesudah penolakan atau token kedaluwarsa.
    if (!ref.read(bisaProvider(aksiRefund)) && _token == null) {
      final token = await mintaOtorisasi(context, ref, aksi: aksiRefund, transaksiId: widget.d.id);
      if (!mounted) return;
      if (token == null) {
        setState(() => _loading = false);
        return;
      }
      _token = token;
    }
    final token = _token;
    _token = null;
    final hasil = await ref.read(riwayatRepositoryProvider).refund(
          widget.d.id,
          PermintaanRefund(
            baris: baris,
            metode: _metode,
            alasan: _alasan.text.trim(),
            kembaliStok: _kembaliStok,
            clientRef: _clientRef,
            waktuKlien: DateTime.now(),
            otorisasiToken: token,
          ),
        );
    if (!mounted) return;
    hasil.when(
      ok: (r) => Navigator.pop(context, r),
      err: (ApiException e) => setState(() {
        _loading = false;
        _galat = e.firstError() ?? e.message;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final metode = ref.watch(metodePembayaranProvider).valueOrNull ?? metodePembayaranBawaan;
    if (!metode.contains(_metode)) _metode = metode.first;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        children: [
          Text('Refund transaksi', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Transaksi ${widget.d.nomor}. Isi jumlah yang dikembalikan per item (kosong = tidak direfund).',
            style: TextStyle(color: cs.onSurface.withValues(alpha: 0.65)),
          ),
          const SizedBox(height: 12),
          for (final i in _baris) ...[
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(i.nama, style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                        'Sisa ${labelKuantitas(i.qtyBisaRefund, i.satuan)} · ${fmtIDR(i.kuantitas > 0 ? i.subtotal / i.kuantitas : 0)}/${i.satuan ?? 'item'}',
                        style: TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: 0.6)),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 96,
                  child: TextField(
                    key: ValueKey('rf-qty-${i.id}'),
                    controller: _qty[i.id],
                    textAlign: TextAlign.right,
                    keyboardType: TextInputType.numberWithOptions(decimal: apakahTerukur(i.satuan)),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(apakahTerukur(i.satuan) ? RegExp(r'[0-9.,]') : RegExp(r'[0-9]')),
                    ],
                    decoration: const InputDecoration(hintText: '0', isDense: true),
                    onChanged: (_) => setState(() => _galat = null),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          DropdownButtonFormField<String>(
            initialValue: _metode,
            decoration: const InputDecoration(labelText: 'Metode pengembalian dana'),
            items: [for (final m in metode) DropdownMenuItem(value: m, child: Text(m))],
            onChanged: (v) => setState(() => _metode = v ?? _metode),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('rf-alasan'),
            controller: _alasan,
            maxLength: 255,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Alasan (wajib)', hintText: 'Contoh: rasa tidak sesuai, barang rusak'),
            onChanged: (_) {
              if (_galat != null) setState(() => _galat = null);
            },
          ),
          CheckboxListTile(
            value: _kembaliStok,
            onChanged: (v) => setState(() => _kembaliStok = v ?? true),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Barang kembali ke stok'),
          ),
          const Divider(),
          Row(
            children: [
              const Expanded(child: Text('Perkiraan dana kembali')),
              Text(fmtIDR(_perkiraan), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ],
          ),
          Text(
            'Nilai pasti dihitung server (diskon & pajak ikut dihitung).',
            style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6)),
          ),
          if (_galat != null) ...[
            const SizedBox(height: 8),
            Text(_galat!, style: const TextStyle(color: AppColors.danger)),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _loading ? null : _kirim,
            icon: _loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.currency_exchange_rounded, size: 19),
            label: Text(_loading ? 'Mencatat…' : 'Catat refund'),
          ),
        ],
      ),
    );
  }
}
