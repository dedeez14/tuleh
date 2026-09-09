import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/layout/lebar.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/rupiah_input.dart';
import '../../../../core/utils/satuan_terukur.dart';
import '../../../products/domain/entities/product.dart';
import '../../domain/entities/cart_item.dart';

/// Hasil pengisian: ukuran yang dijual + cara kasir mengisinya.
typedef IsianUkuran = ({double qty, CaraInput cara, double? nominalDiminta});

/// Tanya ukuran barang yang dijual per kilo/liter/meter.
///
/// Dua cara isi yang sama-sama wajar di warung: pelanggan menyebut **berat**
/// ("dua kilo") atau menyebut **uang** ("dua puluh ribu"). Nominal diterjemahkan
/// ke berat lebih dulu — lihat PENJUALAN-TERUKUR.md — sehingga uang yang
/// ditagih selalu `berat × harga` dan cocok dengan hitungan server.
Future<IsianUkuran?> tanyaUkuran(
  BuildContext context,
  Product produk, {
  double? qtyAwal,
  String labelTambah = 'Tambah ke keranjang',
}) => tampilkanLembar<IsianUkuran>(
  context,
  builder: (_) =>
      LembarUkuran(produk: produk, qtyAwal: qtyAwal, labelTambah: labelTambah),
);

class LembarUkuran extends StatefulWidget {
  const LembarUkuran({
    super.key,
    required this.produk,
    this.qtyAwal,
    this.labelTambah = 'Tambah ke keranjang',
  });

  final Product produk;

  /// Isi baris yang sedang diubah (null = menambah baris baru).
  final double? qtyAwal;

  /// Tulisan tombol saat menambah baris baru — lembar ini juga dipakai bon meja.
  final String labelTambah;

  @override
  State<LembarUkuran> createState() => _LembarUkuranState();
}

class _LembarUkuranState extends State<LembarUkuran> {
  late final TextEditingController _ukuran = TextEditingController(
    text: widget.qtyAwal == null ? '' : fmtQtyRingkas(widget.qtyAwal!),
  );
  final _nominal = TextEditingController();
  bool _modeNominal = false;

  String get _satuan => widget.produk.satuan ?? '';
  double get _harga => widget.produk.harga;
  bool get _hargaSah => _harga > 0;

  /// Batas atas ukuran. Baris terukur selalu MENGGANTI isi baris, jadi
  /// batasnya stok penuh — bukan stok dikurangi isi keranjang. `null` =
  /// produk tanpa kelola stok (jasa, atau stok tak dilacak).
  double? get _sisaStok => widget.produk.stok;
  bool get _lebihStok {
    final sisa = _sisaStok;
    return sisa != null && _qty > sisa;
  }

  /// Ukuran hasil isian sekarang (sudah dibulatkan ke langkah satuan).
  double get _qty {
    if (!_modeNominal) {
      final angka = double.tryParse(_ukuran.text.trim().replaceAll(',', '.')) ?? 0;
      return bulatkanKuantitas(angka, _satuan);
    }
    return kuantitasDariNominal(parseRupiah(_nominal.text), _harga, _satuan);
  }

  double get _total => totalBaris(_qty, _harga);

  @override
  void dispose() {
    _ukuran.dispose();
    _nominal.dispose();
    super.dispose();
  }

  void _kirim() {
    final qty = _qty;
    if (qty <= 0 || _lebihStok) return;
    HapticFeedback.selectionClick();
    Navigator.pop(context, (
      qty: qty,
      cara: _modeNominal ? CaraInput.nominal : CaraInput.ukuran,
      nominalDiminta: _modeNominal ? parseRupiah(_nominal.text) : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final qty = _qty;
    final nominalDiminta = _modeNominal ? parseRupiah(_nominal.text) : 0;
    final kurangDariMinimal =
        _modeNominal && nominalDiminta > 0 && qty <= 0 && _hargaSah;
    final lebihStok = _lebihStok;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.produk.nama,
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                '${fmtIDR(_harga)} / $_satuan',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.mint600,
                ),
              ),
              if (_sisaStok != null)
                Text(
                  'Sisa stok ${fmtQtyRingkas(_sisaStok!)} $_satuan',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: cs.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              const SizedBox(height: 16),

              // Dua cara isi. Nominal dimatikan bila harga belum diisi —
              // membagi dengan nol tidak akan pernah masuk akal.
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                    value: false,
                    label: Text(_satuan.isEmpty ? 'Ukuran' : 'Per $_satuan'),
                    icon: const Icon(Icons.scale_outlined, size: 18),
                  ),
                  ButtonSegment(
                    value: true,
                    label: const Text('Nominal'),
                    icon: const Icon(Icons.payments_outlined, size: 18),
                    enabled: _hargaSah,
                  ),
                ],
                selected: {_modeNominal},
                onSelectionChanged: (v) => setState(() => _modeNominal = v.first),
              ),
              const SizedBox(height: 14),

              if (_modeNominal) ..._isiNominal(cs) else ..._isiUkuran(cs),

              const SizedBox(height: 14),
              _Ringkasan(
                qty: qty,
                satuan: _satuan,
                harga: _harga,
                total: _total,
                nominalDiminta: _modeNominal && nominalDiminta > 0 ? nominalDiminta.toDouble() : null,
                peringatan: lebihStok
                    ? 'Sisa stok hanya ${fmtQtyRingkas(_sisaStok!)} $_satuan.'
                    : kurangDariMinimal
                    ? 'Minimal ${fmtIDR(minimalNominal(_harga, _satuan))} '
                          '(${fmtQtyRingkas(langkahSatuan(_satuan))} $_satuan).'
                    : null,
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: qty > 0 && !lebihStok ? _kirim : null,
                icon: const Icon(Icons.add_shopping_cart_rounded, size: 19),
                label: Text(widget.qtyAwal == null ? widget.labelTambah : 'Simpan perubahan'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _isiUkuran(ColorScheme cs) => [
    TextField(
      controller: _ukuran,
      autofocus: true,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => _kirim(),
      decoration: InputDecoration(
        labelText: 'Berat / ukuran',
        suffixText: _satuan,
        hintText: 'mis. 0,74',
      ),
    ),
    const SizedBox(height: 10),
    _Pintasan(
      label: (v) => '${fmtQtyRingkas(v)} $_satuan',
      nilai: const [0.25, 0.5, 1, 2, 5],
      onPilih: (v) => setState(() => _ukuran.text = fmtQtyRingkas(v)),
    ),
  ];

  List<Widget> _isiNominal(ColorScheme cs) => [
    TextField(
      controller: _nominal,
      autofocus: true,
      keyboardType: TextInputType.number,
      inputFormatters: const [RupiahInputFormatter()],
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => _kirim(),
      decoration: const InputDecoration(
        labelText: 'Pelanggan minta berapa rupiah?',
        prefixText: 'Rp ',
        hintText: 'mis. 20.000',
      ),
    ),
    const SizedBox(height: 10),
    _Pintasan(
      label: (v) => fmtIDRSingkat(v),
      nilai: const [5000, 10000, 20000, 50000],
      onPilih: (v) => setState(() => _nominal.text = teksRupiah(v)),
    ),
  ];
}

/// Baris pintasan angka yang sering dipakai.
class _Pintasan extends StatelessWidget {
  const _Pintasan({required this.nilai, required this.label, required this.onPilih});

  final List<double> nilai;
  final String Function(double) label;
  final ValueChanged<double> onPilih;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final v in nilai)
        ActionChip(label: Text(label(v)), onPressed: () => onPilih(v)),
    ],
  );
}

/// Perhitungan yang sedang berjalan — kasir menyebutkan ini ke pelanggan.
class _Ringkasan extends StatelessWidget {
  const _Ringkasan({
    required this.qty,
    required this.satuan,
    required this.harga,
    required this.total,
    this.nominalDiminta,
    this.peringatan,
  });

  final double qty;
  final String satuan;
  final double harga;
  final double total;
  final double? nominalDiminta;
  final String? peringatan;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (peringatan != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          peringatan!,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.danger),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (nominalDiminta != null)
            Text(
              'Diminta ${fmtIDR(nominalDiminta!)}',
              style: TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: 0.65)),
            ),
          Text(
            qty > 0
                ? '${fmtQtyRingkas(qty)} $satuan × ${fmtIDR(harga)}'
                : 'Isi ukurannya lebih dulu',
            style: const TextStyle(fontSize: 13.5),
          ),
          const SizedBox(height: 2),
          Text(
            fmtIDR(total),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.mint600),
          ),
        ],
      ),
    );
  }
}
