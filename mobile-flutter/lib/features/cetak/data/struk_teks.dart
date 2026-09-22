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
    if (s.judul != null) {
      tengah(s.judul!);
      garis();
    }
    b.add(_duaKolom('No', s.nomor));
    // Nomor antrian: yang disebut pelanggan laundry/bengkel saat mengambil.
    if (s.noAntrian?.isNotEmpty ?? false) {
      b.add(_duaKolom('No. antrian', s.noAntrian!));
    }
    if (s.rujukan?.isNotEmpty ?? false) b.add(_duaKolom('Transaksi', s.rujukan!));
    b.add(_duaKolom('Waktu', _waktu(s.waktu)));
    if (s.kasir?.isNotEmpty ?? false) {
      b.add(_duaKolom(s.judul == null ? 'Kasir' : 'Oleh', s.kasir!));
    }
    if (s.pelanggan?.isNotEmpty ?? false) b.add(_duaKolom('Pelanggan', s.pelanggan!));
    garis();
    for (final r in s.baris) {
      b.addAll(StrukEscPos.bungkus(r.nama, kolom));
      b.add(_duaKolom('  ${r.labelKuantitas} x ${fmtIDR(r.harga)}', fmtIDR(r.subtotal)));
      if ((r.nominalDiminta ?? 0) > 0) b.add('  (diminta ${fmtIDR(r.nominalDiminta!)})');
    }
    garis();
    if ((s.diskon ?? 0) > 0) {
      b.add(_duaKolom('Subtotal', fmtIDR(s.total + s.diskon!)));
      b.add(_duaKolom('Diskon', '-${fmtIDR(s.diskon!)}'));
    }
    b.add(_duaKolom(s.labelTotal, fmtIDR(s.total)));
    if (s.metode?.isNotEmpty ?? false) {
      b.add(_duaKolom(s.judul == null ? 'Bayar' : 'Dikembalikan via', s.metode!));
    }
    // Fase 3: nota DP & struk pelunasan — uang muka lalu sisa tagihan.
    if ((s.uangMuka ?? 0) > 0) b.add(_duaKolom(s.labelUangMuka, fmtIDR(s.uangMuka!)));
    if (s.sisa != null) b.add(_duaKolom(s.labelSisa, fmtIDR(s.sisa!)));
    if (s.dibayar != null) b.add(_duaKolom('Tunai', fmtIDR(s.dibayar!)));
    if ((s.kembalian ?? 0) > 0) b.add(_duaKolom('Kembali', fmtIDR(s.kembalian!)));
    if (s.alasan?.trim().isNotEmpty ?? false) {
      b.addAll(StrukEscPos.bungkus('Alasan: ${s.alasan!.trim()}', kolom));
    }
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
