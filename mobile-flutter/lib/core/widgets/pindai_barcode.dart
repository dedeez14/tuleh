import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../theme/app_colors.dart';

/// Pemindai barcode/QR dengan kamera. Dua mode:
/// - sekali: pindaian pertama langsung dikembalikan (mis. isi kolom barcode);
/// - beruntun: tiap pindaian diserahkan ke [onKode] (kasir menambah item),
///   layar tetap terbuka sampai pengguna menekan Selesai.
///
/// Dua aturan yang membuat pemindaian bisa dipercaya di meja kasir:
/// 1. HANYA yang berada di dalam bingkai bidik yang dibaca ([scanWindow]),
///    sehingga barcode tetangga di rak/kemasan lain tidak ikut masuk.
/// 2. Satu barcode baru bisa masuk lagi setelah BENAR-BENAR menghilang dari
///    kamera selama [jedaAbsen] — bukan sekadar lewat tenggat waktu. Menahan
///    ponsel di depan satu barcode karena itu tidak menambah item berulang.
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

  /// Kode → kapan terakhir TERLIHAT kamera (diperbarui tiap frame).
  final Map<String, DateTime> _terlihat = {};

  /// Sedang memproses satu kode — detektor lain diabaikan dulu.
  bool _sibuk = false;
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
    final kini = DateTime.now();
    // Catat SEMUA kode yang terlihat frame ini, supaya yang sedang ditahan di
    // depan kamera tidak dianggap "hilang" hanya karena kode lain diproses.
    final semua = c.barcodes
        .map((b) => b.rawValue)
        .whereType<String>()
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (semua.isEmpty) return;
    String? kode;
    for (final k in semua) {
      final boleh = bolehDiprosesBarcode(kode: k, kini: kini, terlihat: _terlihat);
      if (boleh && kode == null) kode = k;
    }
    if (kode == null || _sibuk) return;

    if (widget.onKode == null) {
      _selesai = true;
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.of(context).pop(kode);
      return;
    }
    _sibuk = true;
    final String? hasil;
    try {
      hasil = await widget.onKode!(kode);
    } finally {
      _sibuk = false;
      // Kode baru saja diproses: hitung ulang absennya dari SEKARANG, bukan
      // dari frame pertama, supaya proses yang lambat tidak membuka celah.
      _terlihat[kode] = DateTime.now();
    }
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
      body: LayoutBuilder(
        builder: (context, batas) {
          // Bingkai bidik = jendela pemindaian. Keduanya memakai persegi yang
          // SAMA, jadi apa yang di luar bingkai memang tidak dibaca.
          final bidik = kotakBidikBarcode(batas.biggest);
          return Stack(
            fit: StackFit.expand,
            children: [
              MobileScanner(
                controller: _ctrl,
                onDetect: _terdeteksi,
                scanWindow: bidik,
                errorBuilder: (_, e) => _Galat(pesan: switch (e.errorCode) {
                  MobileScannerErrorCode.permissionDenied =>
                    'Izin kamera ditolak. Buka Pengaturan HP → Aplikasi → Tuléh → Izin → Kamera.',
                  MobileScannerErrorCode.unsupported => 'Perangkat ini tidak mendukung kamera.',
                  _ => 'Kamera tidak bisa dibuka (${e.errorCode.name}).',
                }),
              ),
              // Gelapkan luar bingkai supaya kasir tahu area yang dibaca.
              IgnorePointer(
                child: ColorFiltered(
                  colorFilter: const ColorFilter.mode(Colors.black54, BlendMode.srcOut),
                  child: Stack(
                    children: [
                      Container(
                        decoration: const BoxDecoration(
                          color: Colors.black,
                          backgroundBlendMode: BlendMode.dstOut,
                        ),
                      ),
                      Positioned.fromRect(
                        rect: bidik,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned.fromRect(
                rect: bidik,
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.mint400, width: 3),
                      borderRadius: BorderRadius.circular(18),
                    ),
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
          );
        },
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

// ---------------------------------------------------------------- aturan

/// Barcode harus hilang dari kamera selama ini sebelum boleh masuk lagi.
const jedaAbsenBarcode = Duration(milliseconds: 1200);

/// Boleh diproses? Sekaligus mencatat bahwa [kode] sedang terlihat.
///
/// Kamera mengirim frame terus-menerus selama barcode ada di depan lensa, jadi
/// "sudah pernah terlihat baru saja" = masih barcode yang sama, bukan pindaian
/// baru. Aturan ini yang mencegah satu item masuk berulang kali saat kasir
/// menahan ponsel di depan label.
bool bolehDiprosesBarcode({
  required String kode,
  required DateTime kini,
  required Map<String, DateTime> terlihat,
}) {
  final sebelumnya = terlihat[kode];
  terlihat[kode] = kini;
  if (sebelumnya != null && kini.difference(sebelumnya) < jedaAbsenBarcode) return false;
  // Buang catatan lama agar peta tidak tumbuh selama sesi pemindaian panjang.
  if (terlihat.length > 64) {
    terlihat.removeWhere((_, t) => kini.difference(t) > const Duration(minutes: 2));
  }
  return true;
}

/// Persegi bidik di tengah layar — dipakai SEKALIGUS sebagai jendela
/// pemindaian, sehingga barcode di luar bingkai memang tidak dibaca.
Rect kotakBidikBarcode(Size layar) {
  final lebar = layar.width * 0.78 > 300 ? 300.0 : layar.width * 0.78;
  final tinggi = lebar * 0.62;
  return Rect.fromCenter(
    center: Offset(layar.width / 2, layar.height / 2),
    width: lebar,
    height: tinggi,
  );
}
