import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:image/image.dart' as img;

import '../../../core/utils/format.dart';
import '../domain/entities/struk.dart';

/// Menyusun [Struk] menjadi perintah ESC/POS untuk printer thermal.
///
/// Lebar kertas 58 mm ≈ 32 karakter, 80 mm ≈ 48 karakter. Nama item yang
/// panjang dipotong ke beberapa baris agar kolom harga tidak pernah bergeser —
/// penyebab paling umum struk thermal terlihat berantakan.
class StrukEscPos {
  const StrukEscPos({this.lebar = PaperSize.mm58});

  final PaperSize lebar;

  int get _kolom => lebar == PaperSize.mm80 ? 48 : 32;

  /// [logo] = bitmap hitam-putih siap cetak (lihat LogoStruk.siapkan); null
  /// bila toko tak punya logo atau unduhannya gagal — struk tetap tercetak.
  Future<List<int>> bangun(Struk s, {img.Image? logo}) async {
    final profil = await CapabilityProfile.load();
    final g = Generator(lebar, profil);
    final b = <int>[];

    // --- tanda demo (kepala) ---
    if (s.demo) {
      b.addAll(g.text('*** MODE DEMO ***', styles: const PosStyles(align: PosAlign.center, bold: true)));
      b.addAll(g.text('Bukan bukti pembayaran', styles: const PosStyles(align: PosAlign.center)));
      b.addAll(g.hr());
    }

    // --- kepala ---
    if (logo != null) {
      b.addAll(g.image(logo, align: PosAlign.center));
      b.addAll(g.feed(1));
    }
    b.addAll(
      g.text(
        s.namaToko,
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      ),
    );
    if (s.alamat != null && s.alamat!.trim().isNotEmpty) {
      b.addAll(
        g.text(s.alamat!.trim(), styles: const PosStyles(align: PosAlign.center)),
      );
    }
    if (s.telepon != null && s.telepon!.trim().isNotEmpty) {
      b.addAll(
        g.text(
          'Telp ${s.telepon!.trim()}',
          styles: const PosStyles(align: PosAlign.center),
        ),
      );
    }
    b.addAll(g.hr());

    // --- info transaksi ---
    b.addAll(_duaKolom(g, 'No', s.nomor));
    b.addAll(_duaKolom(g, 'Waktu', _waktu(s.waktu)));
    if (s.kasir != null && s.kasir!.isNotEmpty) {
      b.addAll(_duaKolom(g, 'Kasir', s.kasir!));
    }
    if (s.pelanggan != null && s.pelanggan!.isNotEmpty) {
      b.addAll(_duaKolom(g, 'Pelanggan', s.pelanggan!));
    }
    b.addAll(g.hr());

    // --- item ---
    for (final baris in s.baris) {
      // Nama dibungkus sendiri per kata; bila diserahkan ke printer, potongan
      // terjadi di tengah kata dan struk terlihat berantakan.
      for (final potong in bungkus(baris.nama, _kolom)) {
        b.addAll(g.text(potong, styles: const PosStyles(bold: true)));
      }
      b.addAll(
        _duaKolom(
          g,
          '  ${baris.labelKuantitas} x ${fmtIDR(baris.harga)}',
          fmtIDR(baris.subtotal),
        ),
      );
    }
    b.addAll(g.hr());

    // --- total ---
    if ((s.diskon ?? 0) > 0) {
      b.addAll(_duaKolom(g, 'Subtotal', fmtIDR(s.total + s.diskon!)));
      b.addAll(_duaKolom(g, 'Diskon', '-${fmtIDR(s.diskon!)}'));
    }
    b.addAll(
      _duaKolom(g, 'TOTAL', fmtIDR(s.total), tebal: true, besar: true),
    );
    if (s.metode != null && s.metode!.isNotEmpty) {
      b.addAll(_duaKolom(g, 'Bayar', s.metode!));
    }
    if (s.dibayar != null) {
      b.addAll(_duaKolom(g, 'Tunai', fmtIDR(s.dibayar!)));
    }
    if (s.kembalian != null && s.kembalian! > 0) {
      b.addAll(_duaKolom(g, 'Kembali', fmtIDR(s.kembalian!), tebal: true));
    }

    // --- kaki ---
    b.addAll(g.feed(1));
    if (s.barcode != null && s.barcode!.trim().isNotEmpty) {
      b.addAll(g.qrcode(s.barcode!.trim(), size: QRSize.size4));
      b.addAll(
        g.text(
          s.barcode!.trim(),
          styles: const PosStyles(align: PosAlign.center),
        ),
      );
      b.addAll(g.feed(1));
    }
    b.addAll(
      g.text(
        (s.catatanKaki?.trim().isNotEmpty ?? false)
            ? s.catatanKaki!.trim()
            : 'Terima kasih atas kunjungan Anda',
        styles: const PosStyles(align: PosAlign.center),
      ),
    );
    if (s.demo) {
      b.addAll(g.hr());
      b.addAll(g.text('*** MODE DEMO - BUKAN BUKTI PEMBAYARAN ***', styles: const PosStyles(align: PosAlign.center, bold: true)));
    }
    b.addAll(g.feed(2));
    b.addAll(g.cut());
    return b;
  }

  /// Baris kiri-kanan dengan pengisi spasi; label dipotong bila kepanjangan
  /// agar nilai di kanan tidak terdorong ke baris berikutnya.
  List<int> _duaKolom(
    Generator g,
    String kiri,
    String kanan, {
    bool tebal = false,
    bool besar = false,
  }) {
    final lebarNilai = kanan.length;
    final ruangLabel = (_kolom - lebarNilai - 1).clamp(1, _kolom);
    final label = kiri.length > ruangLabel
        ? '${kiri.substring(0, ruangLabel - 1)}…'
        : kiri;
    final isi = label.padRight(ruangLabel) + kanan.padLeft(_kolom - ruangLabel);
    return g.text(
      isi,
      styles: PosStyles(
        bold: tebal,
        height: besar ? PosTextSize.size2 : PosTextSize.size1,
      ),
    );
  }

  /// Bungkus teks ke beberapa baris selebar [lebar], memutus di spasi.
  /// Kata tunggal yang lebih panjang dari kertas dipotong keras (tak ada
  /// pilihan lain), sisanya tetap utuh per kata.
  static List<String> bungkus(String teks, int lebar) {
    final bersih = teks.trim();
    if (bersih.isEmpty) return const [''];
    if (bersih.length <= lebar) return [bersih];

    final keluar = <String>[];
    var baris = '';
    for (final kata in bersih.split(RegExp(r'\s+'))) {
      var sisa = kata;
      while (sisa.length > lebar) {
        if (baris.isNotEmpty) {
          keluar.add(baris);
          baris = '';
        }
        keluar.add(sisa.substring(0, lebar));
        sisa = sisa.substring(lebar);
      }
      if (baris.isEmpty) {
        baris = sisa;
      } else if (baris.length + 1 + sisa.length <= lebar) {
        baris = '$baris $sisa';
      } else {
        keluar.add(baris);
        baris = sisa;
      }
    }
    if (baris.isNotEmpty) keluar.add(baris);
    return keluar;
  }

  static String _waktu(DateTime d) {
    String dua(int n) => n.toString().padLeft(2, '0');
    return '${dua(d.day)}/${dua(d.month)}/${d.year} ${dua(d.hour)}:${dua(d.minute)}';
  }

  /// Pratinjau teks struk (tanpa printer) — dipakai layar pratinjau & test,
  /// memakai perhitungan lebar kolom yang sama dengan cetakan sebenarnya.
  String pratinjau(Struk s) {
    final baris = <String>[
      _tengah(s.namaToko.toUpperCase()),
      if (s.alamat != null && s.alamat!.trim().isNotEmpty) _tengah(s.alamat!.trim()),
      if (s.telepon != null && s.telepon!.trim().isNotEmpty)
        _tengah('Telp ${s.telepon!.trim()}'),
      '-' * _kolom,
      _pasangan('No', s.nomor),
      _pasangan('Waktu', _waktu(s.waktu)),
      if (s.kasir != null && s.kasir!.isNotEmpty) _pasangan('Kasir', s.kasir!),
      '-' * _kolom,
      for (final b in s.baris) ...[
        ...bungkus(b.nama, _kolom),
        _pasangan(
          '  ${b.labelKuantitas} x ${fmtIDR(b.harga)}',
          fmtIDR(b.subtotal),
        ),
      ],
      '-' * _kolom,
      _pasangan('TOTAL', fmtIDR(s.total)),
      if (s.metode != null && s.metode!.isNotEmpty) _pasangan('Bayar', s.metode!),
      if (s.dibayar != null) _pasangan('Tunai', fmtIDR(s.dibayar!)),
      if (s.kembalian != null && s.kembalian! > 0)
        _pasangan('Kembali', fmtIDR(s.kembalian!)),
      '',
      _tengah(
        (s.catatanKaki?.trim().isNotEmpty ?? false)
            ? s.catatanKaki!.trim()
            : 'Terima kasih atas kunjungan Anda',
      ),
    ];
    return baris.join('\n');
  }

  String _tengah(String teks) {
    if (teks.length >= _kolom) return teks.substring(0, _kolom);
    final kiri = ((_kolom - teks.length) / 2).floor();
    return ' ' * kiri + teks;
  }

  String _pasangan(String kiri, String kanan) {
    final ruang = (_kolom - kanan.length - 1).clamp(1, _kolom);
    final label = kiri.length > ruang
        ? '${kiri.substring(0, ruang - 1)}…'
        : kiri;
    return label.padRight(ruang) + kanan.padLeft(_kolom - ruang);
  }
}
