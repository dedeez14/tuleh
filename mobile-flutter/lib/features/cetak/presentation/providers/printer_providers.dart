import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/secure_storage.dart';
import '../../data/printer_service.dart';

final printerServiceProvider = Provider<PrinterService>(
  (ref) => const PrinterService(),
);

/// Printer terpilih + lebar kertas, disimpan agar tidak perlu dipilih ulang
/// tiap transaksi.
class PrinterTerpilih {
  const PrinterTerpilih({
    this.printer,
    this.lebar = PaperSize.mm58,
    this.otomatis = false,
  });

  final PrinterTersimpan? printer;
  final PaperSize lebar;

  /// Cetak struk sendiri begitu pembayaran tercatat (padanan desktop 0.9.22).
  final bool otomatis;

  bool get ada => printer != null;

  /// Hanya berlaku bila printer sudah dipilih.
  bool get cetakOtomatis => otomatis && printer != null;

  PrinterTerpilih copyWith({
    PrinterTersimpan? printer,
    PaperSize? lebar,
    bool? otomatis,
  }) => PrinterTerpilih(
    printer: printer ?? this.printer,
    lebar: lebar ?? this.lebar,
    otomatis: otomatis ?? this.otomatis,
  );
}

class PrinterTerpilihNotifier extends AsyncNotifier<PrinterTerpilih> {
  static const _kMac = 'printer_mac';
  static const _kNama = 'printer_nama';
  static const _kLebar = 'printer_lebar';
  static const _kOtomatis = 'printer_otomatis';

  @override
  Future<PrinterTerpilih> build() async {
    final s = ref.watch(secureStorageProvider);
    final mac = await s.bacaNilai(_kMac);
    final nama = await s.bacaNilai(_kNama);
    final lebar = await s.bacaNilai(_kLebar);
    final otomatis = await s.bacaNilai(_kOtomatis);
    return PrinterTerpilih(
      printer: (mac == null || mac.isEmpty)
          ? null
          : PrinterTersimpan(nama: nama ?? mac, mac: mac),
      lebar: lebar == '80' ? PaperSize.mm80 : PaperSize.mm58,
      otomatis: otomatis == '1',
    );
  }

  Future<void> pilih(PrinterTersimpan printer) async {
    final s = ref.read(secureStorageProvider);
    await s.tulisNilai(_kMac, printer.mac);
    await s.tulisNilai(_kNama, printer.nama);
    state = AsyncData(
      (state.valueOrNull ?? const PrinterTerpilih()).copyWith(printer: printer),
    );
  }

  Future<void> aturLebar(PaperSize lebar) async {
    await ref
        .read(secureStorageProvider)
        .tulisNilai(_kLebar, lebar == PaperSize.mm80 ? '80' : '58');
    state = AsyncData(
      (state.valueOrNull ?? const PrinterTerpilih()).copyWith(lebar: lebar),
    );
  }

  Future<void> aturOtomatis(bool nyala) async {
    await ref.read(secureStorageProvider).tulisNilai(_kOtomatis, nyala ? '1' : '0');
    state = AsyncData(
      (state.valueOrNull ?? const PrinterTerpilih()).copyWith(otomatis: nyala),
    );
  }

  Future<void> lupakan() async {
    final s = ref.read(secureStorageProvider);
    await s.tulisNilai(_kMac, null);
    await s.tulisNilai(_kNama, null);
    await ref.read(printerServiceProvider).putuskan();
    state = AsyncData(PrinterTerpilih(lebar: state.valueOrNull?.lebar ?? PaperSize.mm58));
  }
}

final printerTerpilihProvider =
    AsyncNotifierProvider<PrinterTerpilihNotifier, PrinterTerpilih>(
      PrinterTerpilihNotifier.new,
    );

/// Daftar printer yang sudah dipasangkan di setelan Bluetooth HP.
final daftarPrinterProvider = FutureProvider.autoDispose<List<PrinterTersimpan>>(
  (ref) => ref.watch(printerServiceProvider).daftarPrinter(),
);
