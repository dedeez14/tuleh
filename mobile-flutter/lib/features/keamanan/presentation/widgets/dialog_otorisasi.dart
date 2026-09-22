import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/offline/koneksi.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/otorisasi.dart';
import '../../domain/galat_pin.dart';
import '../providers/keamanan_providers.dart';

/// Nilai `aksi` yang dikenal `POST /keamanan/otorisasi` — sama persis dengan
/// kunci hak yang digerbangi server, bukan nama peran.
const aksiBatal = 'transaksi.batal';
const aksiRefund = 'transaksi.refund';

/// Label tombol aksi: kasir harus tahu SEBELUM menekan bahwa atasan akan
/// diminta menyetujui. Padanan `labelAksi()` di `lib/otorisasi.js` desktop.
String labelAksi(String dasar, {required bool punyaHak}) =>
    punyaHak ? dasar : '$dasar (perlu persetujuan)';

/// Sebab aksi mati saat offline. Tanpa hak sendiri, yang butuh jaringan bukan
/// aksinya saja tetapi permintaan persetujuannya (daftar pemberi + tukar PIN).
String alasanOffline(String dasar, {required bool punyaHak}) => punyaHak
    ? '$dasar hanya bisa dilakukan saat terhubung ke internet.'
    : 'Persetujuan atasan hanya bisa diminta saat terhubung ke internet.';

/// Aksi bertoken (batal/refund) hanya hidup online: aksinya tidak diantrekan,
/// dan permintaan persetujuan (daftar pemberi + tukar PIN) juga butuh server.
/// Diperiksa SEBELUM tiap konfirmasi merusak — jangan minta kasir menyetujui
/// tindakan yang pasti gagal — termasuk di lembar refund, karena koneksi bisa
/// putus selagi lembar/dialognya terbuka.
bool pastikanOnline(BuildContext context, WidgetRef ref, String alasan) {
  if (ref.read(koneksiProvider).online) return true;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(backgroundColor: AppColors.danger, content: Text(alasan)));
  return false;
}

/// Pesan galat isian dialog; null = sah. Padanan `validasiIsianOtorisasi()` desktop.
String? galatIsianOtorisasi({required String pemberiId, required String pin}) {
  if (pemberiId.isEmpty) return 'Pilih pemberi persetujuan lebih dulu.';
  if (!RegExp(r'^\d{4,8}$').hasMatch(pin)) return 'PIN harus 4–8 digit angka.';
  return null;
}

/// Dialog "Minta persetujuan": pilih pemegang hak yang sudah menyetel PIN, ia
/// mengetik PIN-nya di perangkat kasir, server menukarnya dengan token sekali
/// pakai untuk SATU aksi & satu transaksi. PIN tidak pernah disimpan.
///
/// @returns token, atau null bila dibatalkan / tidak ada pemberi / PIN gagal.
Future<String?> mintaOtorisasi(
  BuildContext context,
  WidgetRef ref, {
  required String aksi,
  required String transaksiId,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  void beritahu(String pesan) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(pesan)));

  List<PemberiOtorisasi> pemberi;
  try {
    pemberi = await ref.read(keamananDataSourceProvider).pemberi();
  } on ApiException catch (e) {
    if (context.mounted) beritahu(e.firstError() ?? e.message);
    return null;
  }
  if (!context.mounted) return null;
  // Daftar kosong itu keadaan nyata: tak ada yang bisa dimintai, jadi
  // formulir PIN tidak ditawarkan — sebabnya dijelaskan, bukan dialog buntu.
  if (pemberi.isEmpty) {
    beritahu(
      'Belum ada atasan yang menyetel PIN persetujuan. Minta Owner/Manajer '
      'membukanya di Pengaturan → PIN persetujuan saya.',
    );
    return null;
  }

  return showDialog<String>(
    context: context,
    builder: (ctx) => _DialogOtorisasi(pemberi: pemberi, aksi: aksi, transaksiId: transaksiId),
  );
}

class _DialogOtorisasi extends ConsumerStatefulWidget {
  const _DialogOtorisasi({required this.pemberi, required this.aksi, required this.transaksiId});

  final List<PemberiOtorisasi> pemberi;
  final String aksi;
  final String transaksiId;

  @override
  ConsumerState<_DialogOtorisasi> createState() => _DialogOtorisasiState();
}

class _DialogOtorisasiState extends ConsumerState<_DialogOtorisasi> {
  late String _pemberiId = widget.pemberi.first.id;
  final _pin = TextEditingController();
  bool _loading = false;
  String? _galat;

  /// Sisa kuncian PIN di server (detik); 0 = tidak terkunci.
  int _sisaKunci = 0;
  Timer? _hitungMundur;

  @override
  void dispose() {
    _hitungMundur?.cancel();
    _pin.dispose();
    super.dispose();
  }

  bool get _bisaKirim => !_loading && _sisaKunci == 0;

  /// Hitung mundur kuncian: angkanya dari server (`data.terkunci_detik`), yang
  /// berjalan di sini hanya penampilannya. Timer WAJIB mati saat dialog lepas.
  void _mulaiKunci(int detik) {
    _hitungMundur?.cancel();
    setState(() {
      _sisaKunci = detik;
      _galat = kalimatTerkunci(detik);
    });
    _hitungMundur = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _sisaKunci -= 1;
        if (_sisaKunci <= 0) {
          _sisaKunci = 0;
          _galat = 'Silakan coba lagi.';
          t.cancel();
          _hitungMundur = null;
        } else {
          _galat = kalimatTerkunci(_sisaKunci);
        }
      });
    });
  }

  Future<void> _kirim() async {
    final galat = galatIsianOtorisasi(pemberiId: _pemberiId, pin: _pin.text);
    if (galat != null) {
      setState(() => _galat = galat);
      return;
    }
    setState(() {
      _loading = true;
      _galat = null;
    });
    try {
      final ot = await ref.read(keamananDataSourceProvider).otorisasi(
            pemberiId: _pemberiId,
            pin: _pin.text,
            aksi: widget.aksi,
            transaksiId: widget.transaksiId,
          );
      if (!mounted) return;
      // Ditutup selagi permintaan melayang (overlay/tombol kembali): dialognya
      // sudah menjawab null dan pemanggil berhenti. Token memang terbit di
      // server, tapi tak ada yang dibatalkan/direfund — jangan pop lagi (itu
      // akan menutup layar di bawahnya) dan jangan mengaku sukses.
      final rute = ModalRoute.of(context);
      if (rute == null || !rute.isActive) return;
      Navigator.pop(context, ot.token);
    } on ApiException catch (e) {
      if (!mounted) return;
      _pin.clear();
      setState(() => _loading = false);
      final detik = detikTerkunci(e);
      if (detik > 0) {
        _mulaiKunci(detik);
        return;
      }
      setState(() => _galat = pesanTerkunci(e) ?? e.firstError() ?? e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Minta persetujuan'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Aksi ini memerlukan persetujuan. Minta atasan memasukkan PIN-nya di perangkat ini.',
            style: TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: 0.7)),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: const ValueKey('ot-pemberi'),
            initialValue: _pemberiId,
            // Tanpa ini nama+peran yang panjang meluap dari lebar dialog
            // (ellipsis baru bekerja bila isiannya dipaksa selebar kolom).
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Pemberi persetujuan'),
            items: [
              for (final p in widget.pemberi)
                DropdownMenuItem(
                  value: p.id,
                  child: Text(
                    p.peran == null || p.peran!.isEmpty ? p.nama : '${p.nama} — ${p.peran}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: _loading ? null : (v) => setState(() => _pemberiId = v ?? _pemberiId),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('ot-pin'),
            controller: _pin,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 8,
            decoration: const InputDecoration(labelText: 'PIN persetujuan', counterText: ''),
            onChanged: (_) {
              // Selama terkunci, pesannya milik hitung mundur — jangan dihapus.
              if (_galat != null && _sisaKunci == 0) setState(() => _galat = null);
            },
          ),
          if (_galat != null) ...[
            const SizedBox(height: 6),
            Text(_galat!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _bisaKirim ? _kirim : null,
          child: Text(_loading ? 'Memeriksa…' : 'Setujui'),
        ),
      ],
    );
  }
}
