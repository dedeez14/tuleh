import '../../../core/utils/format.dart';
import '../domain/entities/struk.dart';
import 'struk_esc_pos.dart';

/// Struk sebagai teks polos (lebar tetap) untuk dibagikan lewat WhatsApp,
/// pesan, atau disalin. Susunannya mengikuti struk thermal agar pelanggan
/// menerima bentuk yang sama dengan yang tercetak.
class StrukTeks {
  const StrukTeks({this.kolom = 32});

  final int kolom;

  static const tandaDemo = 'MODE DEMO - BUKAN BUKTI PEMBAYARAN';

  String bangun(Struk s) {
    final b = <String>[];
    void tengah(String t) => b.add(_tengah(t));
    void garis() => b.add('-' * kolom);

    if (s.demo) {
      tengah(tandaDemo);
      garis();
    }
    tengah(s.namaToko.toUpperCase());
    if (s.alamat?.trim().isNotEmpty ?? false) {
      for (final p in StrukEscPos.bungkus(s.alamat!.trim(), kolom)) {
        tengah(p);
      }
    }
    if (s.telepon?.trim().isNotEmpty ?? false) tengah('Telp ${s.telepon!.trim()}');
    garis();
    b.add(_duaKolom('No', s.nomor));
    b.add(_duaKolom('Waktu', _waktu(s.waktu)));
    if (s.kasir?.isNotEmpty ?? false) b.add(_duaKolom('Kasir', s.kasir!));
    garis();
    for (final r in s.baris) {
      b.addAll(StrukEscPos.bungkus(r.nama, kolom));
      b.add(_duaKolom('  ${fmtQty(r.kuantitas)} x ${fmtIDR(r.harga)}', fmtIDR(r.subtotal)));
    }
    garis();
    b.add(_duaKolom('TOTAL', fmtIDR(s.total)));
    if (s.metode?.isNotEmpty ?? false) b.add(_duaKolom('Bayar', s.metode!));
    if (s.dibayar != null) b.add(_duaKolom('Tunai', fmtIDR(s.dibayar!)));
    if ((s.kembalian ?? 0) > 0) b.add(_duaKolom('Kembali', fmtIDR(s.kembalian!)));
    garis();
    tengah(
      (s.catatanKaki?.trim().isNotEmpty ?? false)
          ? s.catatanKaki!.trim()
          : 'Terima kasih atas kunjungan Anda',
    );
    if (s.demo) {
      garis();
      tengah(tandaDemo);
    }
    return b.join('\n');
  }

  String _tengah(String t) {
    if (t.length >= kolom) return t;
    return '${' ' * ((kolom - t.length) ~/ 2)}$t';
  }

  String _duaKolom(String kiri, String kanan) {
    final maks = kolom - kanan.length - 1;
    var l = kiri;
    if (maks < 1) return '$kiri $kanan';
    if (l.length > maks) l = l.substring(0, maks);
    return '$l${' ' * (kolom - l.length - kanan.length)}$kanan';
  }

  static String _waktu(DateTime w) {
    String dua(int n) => n.toString().padLeft(2, '0');
    return '${dua(w.day)}/${dua(w.month)}/${w.year} ${dua(w.hour)}:${dua(w.minute)}';
  }
}
