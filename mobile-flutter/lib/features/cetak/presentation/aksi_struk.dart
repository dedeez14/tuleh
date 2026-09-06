import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_colors.dart';
import '../data/printer_service.dart';
import '../data/struk_teks.dart';
import '../domain/entities/struk.dart';
import 'providers/printer_providers.dart';
import 'screens/printer_screen.dart';

/// Aksi struk yang dipakai lembar hasil transaksi dan detail riwayat:
/// cetak ke printer thermal (dengan arahan bila printer belum dipilih) dan
/// bagikan sebagai teks (WhatsApp, pesan, salin).

/// Cetak [struk]; mengembalikan true bila terkirim. Pesan ditampilkan lewat
/// [messenger] (ditangkap pemanggil sebelum async gap).
Future<bool> cetakStrukDenganUmpanBalik(
  BuildContext context,
  WidgetRef ref,
  Struk struk,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final terpilih = ref.read(printerTerpilihProvider).valueOrNull;
  final printer = terpilih?.printer;

  if (printer == null) {
    final keSetelan = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Printer belum dipilih'),
        content: const Text(
          'Pilih printer thermal Bluetooth lebih dulu di Pengaturan → '
          'Printer Struk.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Nanti')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Atur printer')),
        ],
      ),
    );
    if (keSetelan == true && context.mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const PrinterScreen()),
      );
    }
    return false;
  }

  try {
    await ref
        .read(printerServiceProvider)
        .cetak(struk, printer: printer, lebar: terpilih!.lebar);
    _pesan(messenger, 'Struk terkirim ke ${printer.nama}.');
    return true;
  } on PrinterException catch (e) {
    _pesan(messenger, e.saran == null ? e.pesan : '${e.pesan} ${e.saran}', gagal: true);
  } catch (e) {
    _pesan(messenger, 'Gagal mencetak: $e', gagal: true);
  }
  return false;
}

/// Bagikan [struk] sebagai teks lewat lembar bagikan Android.
Future<void> bagikanStruk(BuildContext context, Struk struk) async {
  final messenger = ScaffoldMessenger.of(context);
  final teks = const StrukTeks().bangun(struk);
  try {
    await SharePlus.instance.share(
      ShareParams(text: teks, subject: 'Struk ${struk.nomor} · ${struk.namaToko}'),
    );
  } catch (e) {
    _pesan(messenger, 'Gagal membuka lembar bagikan: $e', gagal: true);
  }
}

void _pesan(ScaffoldMessengerState m, String teks, {bool gagal = false}) {
  m
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: gagal ? AppColors.danger : AppColors.success,
        content: Text(teks),
      ),
    );
}
