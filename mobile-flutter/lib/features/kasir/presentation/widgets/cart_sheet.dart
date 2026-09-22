import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/layout/lebar.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/rupiah_input.dart';
import '../../../../core/widgets/motion.dart';
import '../../../../core/widgets/states.dart';
import '../../../cetak/domain/entities/struk.dart';
import '../../../cetak/domain/struk_server.dart';
import '../../../demo/demo_session.dart';
import '../../../keamanan/presentation/widgets/dialog_otorisasi.dart';
import '../../../pesanan/domain/entities/hasil_pesanan.dart';
import '../../../pesanan/presentation/providers/pesanan_providers.dart';
import '../../../pesanan/presentation/widgets/lembar_struk_pesanan.dart';
import 'hasil_transaksi_sheet.dart';
import '../../../pengaturan/presentation/providers/pengaturan_providers.dart';
import '../../../sesi/presentation/providers/sesi_providers.dart';
import '../../../toko/presentation/providers/toko_providers.dart';
import '../../domain/entities/cart_item.dart';
import '../../domain/galat_kasir.dart';
import '../../domain/metode_pembayaran.dart';
import '../controllers/cart_controller.dart';
import '../controllers/keranjang_meta.dart';
import 'keranjang_daftar_item.dart';
import 'keranjang_form_bayar.dart';
import 'keranjang_kartu_tambahan.dart';
import 'lembar_ukuran.dart';
import 'parkir_sheet.dart';
import '../../../../core/offline/pengurai.dart';
import '../../../products/presentation/providers/products_provider.dart';
import '../providers/checkout_providers.dart';
import '../screens/kasir_screen.dart' show bukaSesiDenganUmpanBalik;

/// Lembar keranjang — daftar item, metode bayar, uang diterima, lalu bayar.
///
/// Dibuat dua langkah agar layar tidak padat: langkah "Keranjang" untuk
/// memeriksa dan mengoreksi item, langkah "Pembayaran" untuk memilih metode
/// dan menghitung kembalian. Tombol utama selalu di bawah, dalam jangkauan ibu jari.
/// Pesan galat uang muka; null = sah. Batas sama dengan server: uang muka
/// harus di antara Rp0 dan total pesanan (bayar penuh = pilih Lunas).
String? validasiUangMuka(double uangMuka, double total) {
  if (uangMuka <= 0) return 'Isi uang muka lebih dari Rp0.';
  if (uangMuka >= total) {
    return 'Uang muka harus kurang dari total pesanan. Untuk bayar penuh pilih Lunas.';
  }
  return null;
}

class CartSheet extends ConsumerStatefulWidget {
  const CartSheet({super.key, this.tertanam = false});

  /// true = dipasang sebagai panel menetap (tablet), bukan bottom sheet:
  /// tanpa batas tinggi, tidak menutup diri setelah bayar.
  final bool tertanam;

  @override
  ConsumerState<CartSheet> createState() => _CartSheetState();
}

enum _Langkah { keranjang, bayar }

class _CartSheetState extends ConsumerState<CartSheet> {
  _Langkah _langkah = _Langkah.keranjang;

  /// Dinormalkan terhadap daftar metode dari server di [build] — toko boleh
  /// menonaktifkan TUNAI, dan mengirimkannya tetap akan ditolak server (422).
  String _metodeTerpilih = 'TUNAI';
  final _uangCtrl = TextEditingController();
  final _uangMukaCtrl = TextEditingController();
  ModeBayar _mode = ModeBayar.lunas;
  bool _loading = false;

  /// Satu `client_ref` per nota yang sedang dikonfirmasi: kirim ulang setelah
  /// gagal jaringan menghasilkan pesanan yang SAMA (server `pos.idempoten`),
  /// bukan pesanan kembar. Dikosongkan sesudah nota tersimpan.
  String? _clientRefNota;

  @override
  void dispose() {
    _uangCtrl.dispose();
    _uangMukaCtrl.dispose();
    super.dispose();
  }

  double get _uangDiterima => parseRupiah(_uangCtrl.text);

  /// Saran nominal uang: pas, pembulatan ribuan/puluh-ribuan terdekat di atas.
  List<double> _saranUang(double total) {
    final out = <double>{total};
    for (final kelipatan in [5000, 10000, 20000, 50000, 100000]) {
      final naik = (total / kelipatan).ceil() * kelipatan.toDouble();
      if (naik > total) out.add(naik);
    }
    final urut = out.toList()..sort();
    return urut.take(4).toList();
  }

  Future<void> _bayar() async {
    final items = ref.read(cartControllerProvider);
    final total = ref.read(cartGrandTotalProvider);
    final meta = ref.read(keranjangMetaProvider);
    final potongan = hitungPotongan(
      ref.read(cartTotalProvider),
      meta.diskonPersen,
    );
    if (items.isEmpty) return;

    final tunai = _metodeTerpilih == 'TUNAI';
    // Tunai: uang diterima WAJIB diisi dan cukup — tombol Bayar sudah
    // dinonaktifkan oleh _Kaki bila belum; ini pengaman kedua.
    final dibayar = tunai ? _uangDiterima : total;
    if (tunai && dibayar <= 0) {
      _pesan('Isi dulu uang yang diterima dari pelanggan.', gagal: true);
      return;
    }
    if (tunai && dibayar < total) {
      _pesan('Uang diterima kurang dari total.', gagal: true);
      return;
    }

    setState(() => _loading = true);
    try {
      // Struk disusun dari keranjang SEBELUM dikosongkan, agar bisa dicetak
      // ulang dari lembar hasil (dan disimpan bila transaksi diantrekan offline).
      final usaha = ref.read(profilUsahaProvider).valueOrNull;
      final waktu = DateTime.now();
      Struk buatStruk(String nomor, double kembalian) => Struk(
        namaToko: usaha?.nama ?? 'Tuléh POS',
        alamat: usaha?.alamat,
        telepon: usaha?.telepon,
        nomor: nomor.isEmpty ? '-' : nomor,
        waktu: waktu,
        baris: [
          for (final e in items)
            StrukBaris(
              nama: e.product.nama,
              kuantitas: e.qty,
              harga: e.product.harga,
              satuan: e.terukur ? e.product.satuan : null,
              dijualPerUkuran: e.terukur,
              nominalDiminta: e.nominalCheckout,
            ),
        ],
        total: total,
        metode: _metodeTerpilih,
        dibayar: tunai ? dibayar : null,
        kembalian: tunai ? kembalian : null,
        catatanKaki: usaha?.strukFooter,
        barcode: nomor.isEmpty ? null : nomor,
        logoUrl: (usaha?.strukTampilLogo ?? false) ? usaha?.logo : null,
        demo: ref.read(demoSessionProvider).active,
        pelanggan: meta.pelanggan?.nama,
        diskon: potongan > 0 ? potongan : null,
      );

      final res = await ref
          .read(checkoutRepositoryProvider)
          .bayar(
            items: items,
            metode: _metodeTerpilih,
            dibayar: dibayar,
            total: total,
            buatStruk: buatStruk,
            diskonPersen: meta.diskonPersen,
            idPelanggan: meta.pelanggan?.id,
            catatan: meta.catatan,
          );
      final struk = buatStruk(res.nomor, res.kembalian);

      ref.read(cartControllerProvider.notifier).clear();
      ref.invalidate(activeSesiProvider); // rekap kas ikut segar
      if (res.tertunda) {
        ref.read(antreanVersiProvider.notifier).state++;
        ref.invalidate(productsProvider); // stok tampil ikut delta tertunda
      }
      if (!mounted) return;
      if (widget.tertanam) {
        setState(() {
          _langkah = _Langkah.keranjang;
          _uangCtrl.clear();
        });
      } else {
        Navigator.of(context).pop();
      }
      HapticFeedback.mediumImpact();
      await _tampilkanHasil(struk, res.kembalian, tertunda: res.tertunda);
    } on ApiException catch (e) {
      if (!mounted) return;
      // Dua bentuk 409: sesi kasir belum dibuka, atau sesi terbuka DI TOKO
      // LAIN (§2a). Keduanya menampilkan KALIMAT server apa adanya — kode
      // mesinnya (errors.kode) hanya dibaca program untuk memilih tombol.
      if (e.statusCode == 409) {
        final kode = kodeGalat(e);
        final sesi = kode == 'SESI_BEDA_TOKO' ? tokoSesi(e) : null;
        final cocok = sesi == null
            ? null
            : pilihTokoSesi(
                ref.read(tokoListProvider).valueOrNull ?? const [],
                sesi,
              );
        if (cocok != null) {
          _pesan(
            e.message,
            gagal: true,
            aksi: ('Pindah ke ${cocok.nama}', () => _pindahToko(cocok.id, cocok.nama)),
          );
        } else if (kode == 'SESI_BEDA_TOKO') {
          // Toko sesi tidak bisa dicocokkan dengan daftar `/tokos` pengguna
          // ini — entah amplopnya tanpa `meta.sesi_toko` (server lama), entah
          // tokonya memang tak ada di daftar. Tombol pindah tidak ditawarkan:
          // id pada amplop 409 adalah ciphertext yang tak dikenal baris
          // `/tokos` mana pun, dan memilihnya hanya klaim kosong — Beranda
          // (cabang yang hidup berdampingan dengan kasir) menyetel ulang toko
          // aktif ke toko pertama dalam satu frame, lalu checkout berikutnya
          // 409 lagi. "Buka sesi" pun BUKAN jalan keluarnya: sesi kasir sudah
          // terbuka, hanya di toko lain, jadi server menolaknya dengan alasan
          // yang sama. Kalimat server sudah memuat jalan keluarnya ("pilih
          // toko itu atau tutup sesi dulu"), jadi itu yang ditampilkan.
          _pesan(e.message, gagal: true);
        } else {
          _pesan(e.message, gagal: true, aksi: ('Buka sesi', _bukaSesi));
        }
      } else {
        _pesan(e.firstError() ?? e.message, gagal: true);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Simpan keranjang sebagai NOTA PESANAN: bayar saat ambil (`NANTI`) atau
  /// dengan uang muka (`DP`). Bukan checkout — belum ada transaksi, dan untuk
  /// DP uangnya tercatat sebagai uang muka di sesi kasir penerimanya.
  Future<void> _simpanNota() async {
    final items = ref.read(cartControllerProvider);
    final total = ref.read(cartGrandTotalProvider);
    final meta = ref.read(keranjangMetaProvider);
    if (items.isEmpty) return;
    // Server menghitung total nota dari harga katalog; diskon keranjang tak
    // ikut terkirim, jadi menyimpannya akan menagih lebih saat pelunasan.
    if (meta.diskonPersen > 0) {
      _pesan(
        'Diskon belum bisa dipakai untuk nota bayar nanti atau uang muka — '
        'hapus diskon atau pilih Lunas.',
        gagal: true,
      );
      return;
    }
    // Uang + kewajiban tidak diantrekan diam-diam (antrean offline = Fase 4).
    if (!pastikanOnline(
      context,
      ref,
      'Nota bayar nanti dan uang muka hanya bisa disimpan saat terhubung ke server.',
    )) {
      return;
    }
    final dp = _mode == ModeBayar.dp;
    final uangMuka = parseRupiah(_uangMukaCtrl.text);
    // Pengaman kedua: tombol sudah dikunci _Kaki, tapi `dp.jumlah: null`
    // tak boleh pernah sampai ke server.
    if (dp && validasiUangMuka(uangMuka, total) != null) return;

    setState(() => _loading = true);
    try {
      final hasil = await ref
          .read(pesananAksiProvider)
          .buatNota(
            bayar: dp ? 'DP' : 'NANTI',
            items: [
              for (final e in items)
                ItemNota(
                  idProduk: e.product.id,
                  kuantitas: e.qty,
                  harga: e.product.harga,
                ),
            ],
            idPelanggan: meta.pelanggan?.id,
            catatan: meta.catatan,
            uangMuka: dp ? uangMuka : null,
            metodeUangMuka: dp ? _metodeTerpilih : null,
            clientRef: _clientRefNota ??= ref
                .read(checkoutRepositoryProvider)
                .buatClientRef(),
          );
      if (!mounted) return;
      _clientRefNota = null;
      final usaha = ref.read(profilUsahaProvider).valueOrNull;
      final struk = strukDariServer(
        hasil.nota,
        namaToko: usaha?.nama ?? 'Tuléh POS',
        alamat: usaha?.alamat,
        telepon: usaha?.telepon,
        catatanKaki: usaha?.strukFooter,
        logoUrl: (usaha?.strukTampilLogo ?? false) ? usaha?.logo : null,
        demo: ref.read(demoSessionProvider).active,
      );
      ref.read(cartControllerProvider.notifier).clear();
      ref.invalidate(activeSesiProvider); // uang muka ikut rekap kas
      _uangMukaCtrl.clear();
      setState(() {
        _mode = ModeBayar.lunas;
        _langkah = _Langkah.keranjang;
      });
      HapticFeedback.mediumImpact();
      await tampilkanLembar<void>(
        context,
        builder: (_) => LembarStrukPesanan(
          struk: struk,
          judul: dp ? 'Nota & uang muka tersimpan' : 'Nota tersimpan',
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      _pesan(e.firstError() ?? e.message, gagal: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _bukaSesi() => bukaSesiDenganUmpanBalik(context, ref);

  /// Pindah ke toko tempat sesi kasir terbuka. Keranjang ikut dikosongkan oleh
  /// CartController (yang mendengarkan toko aktif) — item toko lain memang tak
  /// sah di sini.
  ///
  /// [id] SELALU id dari daftar `/tokos` (baris yang cocok lewat kode/nama),
  /// tak pernah id dari amplop 409: layar lain membandingkan toko aktif dengan
  /// baris daftar itu, dan id amplop — ciphertext dengan IV acak — tak cocok
  /// dengan satu pun di antaranya.
  Future<void> _pindahToko(String id, String nama) async {
    await ref.read(activeTokoIdProvider.notifier).select(id);
    if (!mounted) return;
    _pesan('Toko aktif dipindah ke $nama. Masukkan ulang pesanan pelanggan.');
  }

  /// Lembar hasil transaksi: kembalian besar (yang paling dicari kasir) plus
  /// tombol cetak struk. Dipisah dari snackbar agar tidak hilang sendiri saat
  /// kasir sedang menghitung uang.
  Future<void> _tampilkanHasil(
    Struk struk,
    double kembalian, {
    bool tertunda = false,
  }) async {
    if (!mounted) return;
    await tampilkanLembar<void>(
      context,
      builder: (_) => HasilTransaksiSheet(
        struk: struk,
        kembalian: kembalian,
        tertunda: tertunda,
      ),
    );
  }

  void _pesan(String teks, {bool gagal = false, (String, VoidCallback)? aksi}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: gagal ? AppColors.danger : AppColors.success,
          content: Text(teks),
          action: aksi == null
              ? null
              : SnackBarAction(
                  label: aksi.$1,
                  textColor: Colors.white,
                  onPressed: aksi.$2,
                ),
        ),
      );
  }

  /// Barang terukur di keranjang: timbang ulang lewat lembar yang sama dengan
  /// katalog, lalu GANTI isinya (bukan menambah) — menjumlahkan dua penimbangan
  /// diam-diam akan menagih lebih.
  Future<void> _ubahUkuran(CartItem it) async {
    final isian = await tanyaUkuran(context, it.product, qtyAwal: it.qty);
    if (isian == null || !mounted) return;
    ref
        .read(cartControllerProvider.notifier)
        .tambahUkuran(
          it.product,
          isian.qty,
          cara: isian.cara,
          nominalDiminta: isian.nominalDiminta,
          ganti: true,
        );
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(cartControllerProvider);
    final total = ref.watch(cartGrandTotalProvider);
    final count = ref.watch(cartCountProvider);
    final cart = ref.read(cartControllerProvider.notifier);
    final pembayaran = ref.watch(pengaturanPembayaranProvider);
    final metode = ref.watch(metodePembayaranProvider).valueOrNull ?? metodePembayaranBawaan;
    // Toko yang mematikan TUNAI: tanpa normalisasi tak ada chip terpilih, UI
    // kembalian tetap tampil, dan checkout mengirim metode yang ditolak server
    // (422, Rule::in kode aktif). Daftar kosong (server menjawab `[]`) jatuh ke
    // metode cadangan pertama, bukan melempar dari dalam build.
    if (!metode.contains(_metodeTerpilih)) {
      _metodeTerpilih = metode.isEmpty ? metodePembayaranBawaan.first : metode.first;
    }
    // Nota bayar-nanti & uang muka hanya untuk toko ber-alur PAYMENT_OR_LATER
    // (laundry, bengkel, salon, doorsmeer, konter HP …). Minimarket: Lunas saja,
    // dan pemilih modenya tidak dirender sama sekali.
    final manifest = ref.watch(activeManifestProvider).valueOrNull;
    final modeTersedia = (manifest?.bolehBayarNanti ?? false)
        ? const [ModeBayar.lunas, ModeBayar.nanti, ModeBayar.dp]
        : const [ModeBayar.lunas];
    if (!modeTersedia.contains(_mode)) _mode = ModeBayar.lunas;
    final uangMuka = parseRupiah(_uangMukaCtrl.text);
    final galatUangMuka = _mode == ModeBayar.dp
        ? validasiUangMuka(uangMuka, total)
        : null;
    final cs = Theme.of(context).colorScheme;

    // Keranjang dikosongkan dari layar lain → tutup lembar ini.
    if (items.isEmpty && _langkah == _Langkah.bayar) {
      _langkah = _Langkah.keranjang;
    }

    final isi = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Judul(
          langkah: _langkah,
          count: count,
          onKembali: () => setState(() => _langkah = _Langkah.keranjang),
          onKosongkan: items.isEmpty || _loading ? null : cart.clear,
          onParkir: items.isEmpty || _loading
              ? null
              : () async {
                  final ok = await parkirKeranjang(context, ref);
                  // Lembar ponsel ditutup setelah parkir; panel tablet tetap.
                  if (ok && !widget.tertanam && context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
        ),
        const Divider(height: 1),
        Expanded(
          child: items.isEmpty
              ? const KeadaanKosong(
                  ikon: Icons.shopping_cart_outlined,
                  judul: 'Keranjang masih kosong',
                  detail: 'Ketuk item di katalog untuk menambahkannya.',
                )
              : _langkah == _Langkah.keranjang
              ? DaftarItemKeranjang(
                  onUbah: cart.setQty,
                  onUbahUkuran: (it) => _ubahUkuran(it),
                  onHapus: cart.remove,
                  tambahan: const KartuTambahanKeranjang(),
                )
              : FormBayar(
                  total: total,
                  metode: metode,
                  terpilih: _metodeTerpilih,
                  uangCtrl: _uangCtrl,
                  saran: _saranUang(total),
                  pembayaran: pembayaran,
                  onPilihMetode: (m) => setState(() => _metodeTerpilih = m),
                  onUbahUang: () => setState(() {}),
                  modeTersedia: modeTersedia,
                  mode: _mode,
                  onPilihMode: (m) => setState(() => _mode = m),
                  uangMukaCtrl: _uangMukaCtrl,
                  galatUangMuka: galatUangMuka,
                  sisaUangMuka: galatUangMuka == null && _mode == ModeBayar.dp
                      ? total - uangMuka
                      : null,
                ),
        ),
        if (items.isNotEmpty)
          _Kaki(
            total: total,
            langkah: _langkah,
            metode: _metodeTerpilih,
            uangDiterima: _uangDiterima,
            loading: _loading,
            mode: _mode,
            bolehKirimNota: galatUangMuka == null,
            onLanjut: () => setState(() => _langkah = _Langkah.bayar),
            onBayar: _mode == ModeBayar.lunas ? _bayar : _simpanNota,
            cs: cs,
          ),
      ],
    );

    if (widget.tertanam) {
      return Padding(padding: const EdgeInsets.only(top: 10), child: isi);
    }
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: FractionallySizedBox(heightFactor: 0.9, child: isi),
      ),
    );
  }
}

class _Judul extends StatelessWidget {
  const _Judul({
    required this.langkah,
    required this.count,
    required this.onKembali,
    required this.onKosongkan,
    this.onParkir,
  });

  final _Langkah langkah;
  final int count;
  final VoidCallback onKembali;
  final VoidCallback? onKosongkan;
  final VoidCallback? onParkir;

  @override
  Widget build(BuildContext context) {
    final bayar = langkah == _Langkah.bayar;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 12, 10),
      child: Row(
        children: [
          if (bayar)
            IconButton(
              tooltip: 'Kembali ke keranjang',
              onPressed: onKembali,
              icon: const Icon(Icons.arrow_back_rounded),
            )
          else
            const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  bayar ? 'Pembayaran' : 'Keranjang',
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (!bayar && count > 0)
                  Text(
                    '$count item',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
              ],
            ),
          ),
          // Berlabel: "P" saja tidak terbaca sebagai parkir oleh kasir baru.
          if (!bayar && onParkir != null)
            TextButton.icon(
              onPressed: onParkir,
              icon: const Icon(Icons.local_parking_rounded, size: 18),
              label: const Text('Parkir'),
            ),
          // Berlabel & agak jauh dari Parkir: ikon tong sampah telanjang di
          // sebelah Parkir membuat satu ketukan meleset menghapus keranjang.
          if (!bayar && onKosongkan != null) ...[
            const SizedBox(width: 4),
            TextButton.icon(
              onPressed: onKosongkan,
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text('Kosongkan'),
            ),
          ],
        ],
      ),
    );
  }
}

class _Kaki extends StatelessWidget {
  const _Kaki({
    required this.total,
    required this.langkah,
    required this.metode,
    required this.uangDiterima,
    required this.loading,
    required this.mode,
    required this.bolehKirimNota,
    required this.onLanjut,
    required this.onBayar,
    required this.cs,
  });

  final double total;
  final _Langkah langkah;
  final String metode;
  final double uangDiterima;
  final bool loading;

  /// Lunas = checkout; nanti/dp = nota pesanan (label & gerbang tombol beda).
  final ModeBayar mode;

  /// Uang muka sah (atau mode bayar-nanti yang memang tanpa nominal).
  final bool bolehKirimNota;
  final VoidCallback onLanjut;
  final VoidCallback onBayar;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final bayar = langkah == _Langkah.bayar;
    final lunas = mode == ModeBayar.lunas;
    final tunai = lunas && metode == 'TUNAI';
    final kembalian = uangDiterima - total;
    final kurang = tunai && uangDiterima > 0 && kembalian < 0;
    final belumIsi = tunai && uangDiterima <= 0;
    // Tunai tanpa nominal atau kurang: Bayar dikunci; kasir tahu sebabnya
    // dari baris di atas tombol, bukan dari snackbar setelah gagal. Nota uang
    // muka dikunci dengan cara yang sama (galatnya tampil di kolom nominal).
    final bisaBayar = !bayar
        ? true
        : lunas
        ? (!tunai || (!belumIsi && !kurang))
        : bolehKirimNota;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outline)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                'Total',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const Spacer(),
              AngkaBerubah(
                nilai: total,
                format: fmtIDR,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  color: cs.primary,
                ),
              ),
            ],
          ),
          if (bayar && tunai && uangDiterima > 0) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  kurang ? 'Kurang' : 'Kembalian',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: kurang
                        ? cs.error
                        : cs.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                const Spacer(),
                Text(
                  fmtIDR(kembalian.abs()),
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: kurang ? cs.error : AppColors.success,
                  ),
                ),
              ],
            ),
          ],
          if (bayar && belumIsi) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: cs.error),
                const SizedBox(width: 6),
                Text(
                  'Isi uang diterima dulu',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: cs.error,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          FilledButton(
            onPressed: loading || !bisaBayar
                ? null
                : (bayar ? onBayar : onLanjut),
            child: loading
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: AppColors.mint900,
                    ),
                  )
                : Text(_label(bayar)),
          ),
        ],
      ),
    );
  }

  String _label(bool bayar) {
    if (!bayar) return 'Lanjut ke pembayaran';
    return switch (mode) {
      ModeBayar.lunas => 'Bayar ${fmtIDR(total)}',
      ModeBayar.nanti => 'Simpan Nota — Bayar Saat Ambil',
      ModeBayar.dp => 'Simpan Nota + Uang Muka',
    };
  }
}
