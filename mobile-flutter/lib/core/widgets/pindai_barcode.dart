import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../theme/app_colors.dart';

/// Pemindai barcode/QR dengan kamera. Dua mode:
/// - sekali: pindaian pertama langsung dikembalikan (mis. isi kolom barcode);
/// - beruntun: tiap pindaian diserahkan ke [onKode] (kasir menambah item),
///   layar tetap terbuka sampai pengguna menekan Selesai. Kode yang sama tak
///   diproses dua kali dalam 1,5 detik agar satu barcode tak dobel masuk.
class PindaiBarcodeScreen extends StatefulWidget {
  const PindaiBarcodeScreen({
    super.key,
    this.judul = 'Pindai barcode',
    this.onKode,
  });

  final String judul;

  /// Mode beruntun bila diisi. Mengembalikan teks umpan balik (mis. nama
  /// produk yang ditambahkan) atau null bila tidak dikenal.
  final Future<String?> Function(String kode)? onKode;

  /// Buka pemindai sekali; hasil = kode atau null bila dibatalkan.
  static Future<String?> sekali(BuildContext context, {String judul = 'Pindai barcode'}) =>
      Navigator.of(context, rootNavigator: true).push<String>(
        MaterialPageRoute(builder: (_) => PindaiBarcodeScreen(judul: judul), fullscreenDialog: true),
      );

  /// Buka pemindai beruntun (kasir).
  static Future<void> beruntun(
    BuildContext context, {
    required Future<String?> Function(String kode) onKode,
    String judul = 'Pindai barcode produk',
  }) =>
      Navigator.of(context, rootNavigator: true).push<void>(
        MaterialPageRoute(
          builder: (_) => PindaiBarcodeScreen(judul: judul, onKode: onKode),
          fullscreenDialog: true,
        ),
      );

  @override
  State<PindaiBarcodeScreen> createState() => _PindaiBarcodeScreenState();
}

class _PindaiBarcodeScreenState extends State<PindaiBarcodeScreen> {
  final _ctrl = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.qrCode,
    ],
  );
  String? _terakhir;
  DateTime _terakhirPada = DateTime.fromMillisecondsSinceEpoch(0);
  String? _umpan;
  bool _umpanGagal = false;
  bool _selesai = false;
  int _jumlah = 0;
  Timer? _hapusUmpan;

  @override
  void dispose() {
    _hapusUmpan?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _terdeteksi(BarcodeCapture c) async {
    if (_selesai) return;
    final kode = c.barcodes.map((b) => b.rawValue).whereType<String>().map((s) => s.trim()).where((s) => s.isNotEmpty).firstOrNull;
    if (kode == null) return;
    final kini = DateTime.now();
    if (kode == _terakhir && kini.difference(_terakhirPada) < const Duration(milliseconds: 1500)) return;
    _terakhir = kode;
    _terakhirPada = kini;

    if (widget.onKode == null) {
      _selesai = true;
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.of(context).pop(kode);
      return;
    }
    final hasil = await widget.onKode!(kode);
    if (!mounted) return;
    if (hasil != null) {
      HapticFeedback.mediumImpact();
      _jumlah++;
    } else {
      HapticFeedback.heavyImpact();
    }
    setState(() {
      _umpan = hasil ?? 'Barcode $kode tidak dikenal';
      _umpanGagal = hasil == null;
    });
    _hapusUmpan?.cancel();
    _hapusUmpan = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _umpan = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final beruntun = widget.onKode != null;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.judul),
        actions: [
          IconButton(
            tooltip: 'Lampu',
            onPressed: () => _ctrl.toggleTorch(),
            icon: const Icon(Icons.flashlight_on_outlined),
          ),
          IconButton(
            tooltip: 'Ganti kamera',
            onPressed: () => _ctrl.switchCamera(),
            icon: const Icon(Icons.cameraswitch_outlined),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _ctrl,
            onDetect: _terdeteksi,
            errorBuilder: (_, e) => _Galat(pesan: switch (e.errorCode) {
              MobileScannerErrorCode.permissionDenied =>
                'Izin kamera ditolak. Buka Pengaturan HP → Aplikasi → Tuléh → Izin → Kamera.',
              MobileScannerErrorCode.unsupported => 'Perangkat ini tidak mendukung kamera.',
              _ => 'Kamera tidak bisa dibuka (${e.errorCode.name}).',
            }),
          ),
          // Bingkai bidik.
          Center(
            child: Container(
              width: 260,
              height: 170,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.mint400, width: 3),
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 18,
            child: Center(
              child: Text(
                beruntun ? 'Arahkan ke barcode produk — tiap pindaian masuk keranjang' : 'Arahkan kamera ke barcode',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          ),
          if (_umpan != null)
            Positioned(
              left: 20,
              right: 20,
              bottom: beruntun ? 110 : 40,
              child: AnimatedOpacity(
                opacity: 1,
                duration: const Duration(milliseconds: 150),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: _umpanGagal ? AppColors.danger : AppColors.mint600,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(_umpanGagal ? Icons.error_outline : Icons.check_circle_outline, color: Colors.white),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(_umpan!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (beruntun)
            Positioned(
              left: 20,
              right: 20,
              bottom: 28,
              child: SafeArea(
                top: false,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.check_rounded),
                  label: Text(_jumlah == 0 ? 'Selesai' : 'Selesai ($_jumlah item masuk)'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Galat extends StatelessWidget {
  const _Galat({required this.pesan});
  final String pesan;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.no_photography_outlined, color: Colors.white54, size: 48),
          const SizedBox(height: 12),
          Text(pesan, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
        ],
      ),
    ),
  );
}
