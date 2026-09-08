import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_background.dart';
import '../../../../core/widgets/motion.dart';
import '../../../../core/widgets/states.dart';
import '../../../pengaturan/presentation/providers/pengaturan_providers.dart';
import '../../data/printer_service.dart';
import '../../data/struk_esc_pos.dart';
import '../providers/printer_providers.dart';

/// Pengaturan printer thermal Bluetooth: pilih perangkat, atur lebar kertas,
/// lihat pratinjau struk, lalu uji cetak.
///
/// Penjodohan perangkat sengaja diserahkan ke setelan Bluetooth Android —
/// paling andal untuk printer thermal murah yang PIN-nya beragam.
class PrinterScreen extends ConsumerStatefulWidget {
  const PrinterScreen({super.key});

  @override
  ConsumerState<PrinterScreen> createState() => _PrinterScreenState();
}

class _PrinterScreenState extends ConsumerState<PrinterScreen> {
  bool _mencetak = false;

  Future<void> _ujiCetak() async {
    final terpilih = ref.read(printerTerpilihProvider).valueOrNull;
    final printer = terpilih?.printer;
    if (printer == null) {
      _pesan('Pilih printer lebih dulu.', gagal: true);
      return;
    }

    setState(() => _mencetak = true);
    try {
      final usaha = ref.read(profilUsahaProvider).valueOrNull;
      await ref
          .read(printerServiceProvider)
          .cetak(
            PrinterService.strukUji(namaToko: usaha?.nama ?? 'Tuléh POS'),
            printer: printer,
            lebar: terpilih!.lebar,
          );
      _pesan('Uji cetak terkirim ke ${printer.nama}.');
    } on PrinterException catch (e) {
      _pesan(
        e.saran == null ? e.pesan : '${e.pesan} ${e.saran}',
        gagal: true,
      );
    } catch (e) {
      _pesan('Gagal mencetak: $e', gagal: true);
    } finally {
      if (mounted) setState(() => _mencetak = false);
    }
  }

  void _pesan(String teks, {bool gagal = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: gagal ? AppColors.danger : AppColors.success,
          content: Text(teks),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final terpilih = ref.watch(printerTerpilihProvider).valueOrNull;
    final daftar = ref.watch(daftarPrinterProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Printer Struk'),
        actions: [
          IconButton(
            tooltip: 'Cari ulang perangkat',
            onPressed: () => ref.invalidate(daftarPrinterProvider),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: AppBackground(
        ombak: false,
        intensitas: 0.5,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            MunculBertahap(
              child: _KartuStatus(
                printer: terpilih?.printer,
                onLupakan: terpilih?.ada ?? false
                    ? () => ref.read(printerTerpilihProvider.notifier).lupakan()
                    : null,
              ),
            ),
            const SizedBox(height: 20),
            _Judul(
              teks: 'Perangkat terpasang',
              catatan: 'Pasangkan printer lewat setelan Bluetooth HP lebih dulu.',
            ),
            const SizedBox(height: 10),
            daftar.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 26),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => _KartuGagal(
                pesan: e is PrinterException ? e.pesan : 'Gagal membaca perangkat.',
                saran: e is PrinterException ? e.saran : null,
                onUlangi: () => ref.invalidate(daftarPrinterProvider),
              ),
              data: (list) => list.isEmpty
                  ? const KeadaanKosong(
                      ikon: Icons.bluetooth_disabled_rounded,
                      judul: 'Belum ada printer terpasang',
                      detail:
                          'Buka Setelan Android → Bluetooth, pasangkan printer '
                          'thermal Anda, lalu kembali dan tekan Cari ulang.',
                    )
                  : Column(
                      children: [
                        for (var i = 0; i < list.length; i++)
                          MunculBertahap(
                            urutan: i,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _BarisPrinter(
                                printer: list[i],
                                aktif: terpilih?.printer?.mac == list[i].mac,
                                onPilih: () => ref
                                    .read(printerTerpilihProvider.notifier)
                                    .pilih(list[i]),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 22),
            const _Judul(teks: 'Lebar kertas'),
            const SizedBox(height: 10),
            _PilihLebar(
              lebar: terpilih?.lebar ?? PaperSize.mm58,
              onPilih: (l) =>
                  ref.read(printerTerpilihProvider.notifier).aturLebar(l),
            ),
            const SizedBox(height: 22),
            const _Judul(teks: 'Setelah pembayaran'),
            const SizedBox(height: 10),
            _SaklarOtomatis(
              nyala: terpilih?.otomatis ?? false,
              aktif: terpilih?.ada ?? false,
              onUbah: (v) =>
                  ref.read(printerTerpilihProvider.notifier).aturOtomatis(v),
            ),
            const SizedBox(height: 22),
            const _Judul(
              teks: 'Pratinjau struk',
              catatan: 'Perkiraan hasil cetak sesuai lebar kertas yang dipilih.',
            ),
            const SizedBox(height: 10),
            _Pratinjau(lebar: terpilih?.lebar ?? PaperSize.mm58),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: _mencetak || !(terpilih?.ada ?? false)
                  ? null
                  : _ujiCetak,
              icon: _mencetak
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: AppColors.mint900,
                      ),
                    )
                  : const Icon(Icons.print_rounded, size: 20),
              label: Text(_mencetak ? 'Mengirim…' : 'Uji cetak sekarang'),
            ),
            const SizedBox(height: 10),
            Text(
              'Pastikan printer menyala dan kertas terpasang sebelum menguji.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Saklar "cetak struk otomatis setelah pembayaran". Mati & tidak bisa
/// diubah selama belum ada printer terpilih — supaya kasir tidak menunggu
/// struk yang tak akan pernah keluar.
class _SaklarOtomatis extends StatelessWidget {
  const _SaklarOtomatis({
    required this.nyala,
    required this.aktif,
    required this.onUbah,
  });

  final bool nyala;
  final bool aktif;
  final ValueChanged<bool> onUbah;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: SwitchListTile(
        value: aktif && nyala,
        onChanged: aktif ? onUbah : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text(
          'Cetak struk otomatis',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          aktif
              ? 'Struk langsung dicetak begitu pembayaran tercatat.'
              : 'Pilih printer lebih dulu untuk memakai cetak otomatis.',
          style: TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: 0.65)),
        ),
      ),
    );
  }
}

class _Judul extends StatelessWidget {
  const _Judul({required this.teks, this.catatan});
  final String teks;
  final String? catatan;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          teks,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
        if (catatan != null) ...[
          const SizedBox(height: 3),
          Text(
            catatan!,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: cs.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ],
    );
  }
}

class _KartuStatus extends StatelessWidget {
  const _KartuStatus({required this.printer, required this.onLupakan});

  final PrinterTersimpan? printer;
  final VoidCallback? onLupakan;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ada = printer != null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ada ? cs.primary.withValues(alpha: 0.10) : cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ada ? cs.primary : cs.outline),
      ),
      child: Row(
        children: [
          Container(
            height: 46,
            width: 46,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              ada ? Icons.print_rounded : Icons.print_disabled_rounded,
              color: cs.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ada ? printer!.nama : 'Belum ada printer dipilih',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  ada ? printer!.mac : 'Pilih salah satu perangkat di bawah.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: cs.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          if (onLupakan != null)
            TextButton(onPressed: onLupakan, child: const Text('Lupakan')),
        ],
      ),
    );
  }
}

class _BarisPrinter extends StatelessWidget {
  const _BarisPrinter({
    required this.printer,
    required this.aktif,
    required this.onPilih,
  });

  final PrinterTersimpan printer;
  final bool aktif;
  final VoidCallback onPilih;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onPilih,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: aktif ? cs.primary : cs.outline,
              width: aktif ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.bluetooth_rounded, size: 20, color: cs.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      printer.nama,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      printer.mac,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
              if (aktif)
                Icon(Icons.check_circle_rounded, color: cs.primary, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

class _PilihLebar extends StatelessWidget {
  const _PilihLebar({required this.lebar, required this.onPilih});

  final PaperSize lebar;
  final ValueChanged<PaperSize> onPilih;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<PaperSize>(
      segments: const [
        ButtonSegment(
          value: PaperSize.mm58,
          label: Text('58 mm'),
          icon: Icon(Icons.receipt_rounded, size: 18),
        ),
        ButtonSegment(
          value: PaperSize.mm80,
          label: Text('80 mm'),
          icon: Icon(Icons.receipt_long_rounded, size: 18),
        ),
      ],
      selected: {lebar},
      onSelectionChanged: (s) => onPilih(s.first),
    );
  }
}

/// Pratinjau teks struk memakai perhitungan kolom yang sama dengan cetakan.
class _Pratinjau extends ConsumerWidget {
  const _Pratinjau({required this.lebar});
  final PaperSize lebar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usaha = ref.watch(profilUsahaProvider).valueOrNull;
    final teks = StrukEscPos(lebar: lebar).pratinjau(
      PrinterService.strukUji(namaToko: usaha?.nama ?? 'Tuléh POS'),
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text(
          teks,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 11.5,
            height: 1.45,
            color: Color(0xFF14332C),
          ),
        ),
      ),
    );
  }
}

class _KartuGagal extends StatelessWidget {
  const _KartuGagal({
    required this.pesan,
    required this.saran,
    required this.onUlangi,
  });

  final String pesan;
  final String? saran;
  final VoidCallback onUlangi;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.error.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline_rounded, color: cs.error, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  pesan,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          if (saran != null) ...[
            const SizedBox(height: 6),
            Text(
              saran!,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: cs.onSurface.withValues(alpha: 0.75),
              ),
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onUlangi,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Coba lagi'),
          ),
        ],
      ),
    );
  }
}
