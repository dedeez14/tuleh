import 'dart:convert';
import 'dart:math';

import '../../../core/network/api_exception.dart';
import '../../../core/offline/antrean.dart';
import '../../../core/offline/koneksi.dart';
import '../../../core/offline/nomor_lokal.dart';
import '../../cetak/domain/entities/struk.dart';
import '../domain/entities/cart_item.dart';
import 'datasources/transaction_remote_datasource.dart';

/// Hasil bayar: nomor (server, atau lokal `L-…` bila diantrekan), kembalian,
/// dan penanda apakah transaksi masih menunggu dikirim.
class HasilBayar {
  const HasilBayar({
    required this.nomor,
    required this.kembalian,
    this.tertunda = false,
    this.perluTinjau = false,
    this.clientRef,
  });

  final String nomor;
  final double kembalian;

  /// true = disimpan di perangkat, dikirim otomatis saat online.
  final bool tertunda;

  /// true = server mungkin sudah menerima (timeout setelah kirim); pengguna
  /// diminta memeriksa Riwayat sebelum mengirim ulang.
  final bool perluTinjau;
  final String? clientRef;
}

/// Checkout dengan jalur offline (fase 2):
/// 1. online → kirim langsung seperti biasa;
/// 2. diketahui offline / gagal jaringan sebelum sampai → simpan transaksi
///    lokal + antrean + delta stok dalam satu transaksi penyimpanan, beri
///    nomor lokal, kembalian dihitung di perangkat;
/// 3. timeout setelah terkirim → sama seperti 2 tetapi status TINJAU.
///
/// Setiap kiriman membawa `client_ref` (UUID) dan `waktu_klien` agar server
/// yang sudah mendukung idempotensi tidak mencatat dua kali.
class CheckoutRepository {
  CheckoutRepository({
    required this.remote,
    required this.antrean,
    required this.nomorLokal,
    this.koneksi,
    this.tokoId,
    Random? acak,
  }) : _acak = acak ?? Random.secure();

  final TransactionRemoteDataSource remote;
  final AntreanStore antrean;
  final NomorLokal nomorLokal;
  final PenandaKoneksi? koneksi;
  final String? tokoId;
  final Random _acak;

  String buatClientRef() {
    const hex = '0123456789abcdef';
    final b = List<int>.generate(16, (_) => _acak.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40; // versi 4
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => hex[x >> 4] + hex[x & 0x0f]).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }

  /// [diskonPersen] diterapkan ke setiap baris (`items.*.diskon_persen`),
  /// [idPelanggan] → `id_pelanggan`, [catatan] → `catatan` — kontrak yang
  /// sama dengan kasir desktop. [total] = yang harus dibayar (setelah diskon).
  Future<HasilBayar> bayar({
    required List<CartItem> items,
    required String metode,
    required double dibayar,
    required double total,
    required Struk Function(String nomor, double kembalian) buatStruk,
    double diskonPersen = 0,
    String? idPelanggan,
    String? catatan,
  }) async {
    final clientRef = buatClientRef();
    final waktu = DateTime.now();
    final payload = [
      for (final e in items)
        {
          'id_produk': e.product.id,
          'kuantitas': e.qty,
          'harga': e.product.harga,
          if (diskonPersen > 0) 'diskon_persen': diskonPersen,
        },
    ];
    final body = <String, dynamic>{
      'items': payload,
      'tipe_pembayaran': metode,
      'dibayar': dibayar,
      if (idPelanggan != null && idPelanggan.isNotEmpty) 'id_pelanggan': idPelanggan,
      if (catatan != null && catatan.trim().isNotEmpty) 'catatan': catatan.trim(),
      'client_ref': clientRef,
      'waktu_klien': waktu.toIso8601String(),
    };

    if (!(koneksi?.offline ?? false)) {
      try {
        final r = await remote.checkoutBody(body);
        return HasilBayar(nomor: r.nomor, kembalian: r.kembalian);
      } on ApiException catch (e) {
        if (!e.isJaringan) rethrow; // ditolak server: tampilkan apa adanya
        return _antrekan(
          body: body,
          clientRef: clientRef,
          items: items,
          metode: metode,
          dibayar: dibayar,
          total: total,
          waktu: waktu,
          buatStruk: buatStruk,
          tinjau: e.mungkinSampai,
        );
      }
    }
    return _antrekan(
      body: body,
      clientRef: clientRef,
      items: items,
      metode: metode,
      dibayar: dibayar,
      total: total,
      waktu: waktu,
      buatStruk: buatStruk,
      tinjau: false,
    );
  }

  Future<HasilBayar> _antrekan({
    required Map<String, dynamic> body,
    required String clientRef,
    required List<CartItem> items,
    required String metode,
    required double dibayar,
    required double total,
    required DateTime waktu,
    required Struk Function(String nomor, double kembalian) buatStruk,
    required bool tinjau,
  }) async {
    final nomor = await nomorLokal.berikutnya(sekarang: waktu);
    final kembalian = metode == 'TUNAI' ? max(0.0, dibayar - total) : 0.0;
    final struk = buatStruk(nomor, kembalian).salinDengan(
      catatanKaki: 'Belum tersinkron — nomor resmi menyusul setelah online.',
    );
    final delta = <String, double>{};
    for (final e in items) {
      if (e.product.stok == null) continue; // jasa / tanpa kelola stok
      delta[e.product.id] = (delta[e.product.id] ?? 0) - e.qty;
    }
    await antrean.antrekan(
      PesanAntrean(
        urut: 0,
        clientRef: clientRef,
        jenis: 'CHECKOUT',
        tokoId: tokoId,
        path: '/transaksi/checkout',
        body: body,
        dibuat: waktu,
        status: tinjau ? StatusAntrean.tinjau : StatusAntrean.menunggu,
        galatTerakhir: tinjau
            ? 'Server tidak menjawab setelah data dikirim. Periksa di Riwayat '
                  'apakah sudah tercatat sebelum mengirim ulang.'
            : null,
      ),
      transaksi: TransaksiTertunda(
        clientRef: clientRef,
        tokoId: tokoId,
        nomorLokal: nomor,
        tipePembayaran: metode,
        grandTotal: total,
        dibayar: dibayar,
        waktuKlien: waktu,
        strukJson: jsonEncode(struk.toJson()),
      ),
      deltaStok: delta,
    );
    return HasilBayar(
      nomor: nomor,
      kembalian: kembalian,
      tertunda: true,
      perluTinjau: tinjau,
      clientRef: clientRef,
    );
  }
}
