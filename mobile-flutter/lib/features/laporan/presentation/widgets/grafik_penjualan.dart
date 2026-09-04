import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/utils/format.dart';
import '../../domain/entities/penjualan_hari.dart';

/// Grafik batang omzet harian.
///
/// Keputusan bentuk & warna (mengikuti prosedur visualisasi data):
/// - Hari itu diskret dan yang dibandingkan besarannya → batang, bukan garis.
/// - Batang selalu mulai dari nol; memotong dasar sumbu melebih-lebihkan selisih.
/// - Satu deret data → tanpa kotak legenda; judul yang menamainya.
/// - Warna batang `#2A9A88` dipilih karena lolos uji kontras ≥ 3:1 terhadap
///   permukaan terang (mint600 hanya 2,39:1 sehingga batang terlihat samar).
/// - Label nilai hanya pada batang tertinggi; sisanya lewat ketukan (tooltip)
///   dan tabel harian di bawah grafik.
class GrafikPenjualan extends StatefulWidget {
  const GrafikPenjualan({super.key, required this.rows});

  final List<PenjualanHari> rows;

  /// Batang: terang dipakai di tema terang, muda di tema gelap — dua-duanya
  /// sudah diuji kontrasnya terhadap permukaan masing-masing.
  static const _batangTerang = Color(0xFF2A9A88);
  static const _batangGelap = Color(0xFF4FCDB7);

  @override
  State<GrafikPenjualan> createState() => _GrafikPenjualanState();
}

class _GrafikPenjualanState extends State<GrafikPenjualan> {
  int? _disentuh;

  /// Label sumbu tanggal: cukup angka harinya, kecuali pada entri pertama dan
  /// pergantian bulan yang juga menyebut bulannya. "28 Agu" untuk setiap batang
  /// membuat label bertumpuk pada layar ponsel.
  static String _labelSumbu(List<PenjualanHari> rows, int i) {
    final d = DateTime.tryParse(rows[i].tanggal)?.toLocal();
    if (d == null) return fmtTanggalPendek(rows[i].tanggal);
    final sebelum = i == 0 ? null : DateTime.tryParse(rows[i - 1].tanggal)?.toLocal();
    final gantiBulan = sebelum == null || sebelum.month != d.month;
    return gantiBulan ? fmtTanggalPendek(rows[i].tanggal) : '${d.day}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final warna = isDark
        ? GrafikPenjualan._batangGelap
        : GrafikPenjualan._batangTerang;

    final rows = widget.rows;
    if (rows.isEmpty) return const SizedBox.shrink();

    final nilai = [for (final r in rows) r.totalOmzet];
    final maks = nilai.reduce((a, b) => a > b ? a : b);
    final idxMaks = nilai.indexOf(maks);
    // Ruang di atas batang tertinggi supaya label nilainya tidak terpotong.
    final atas = maks <= 0 ? 1.0 : maks * 1.28;
    final garis = maks <= 0 ? 1.0 : maks / 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 208,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: atas,
              minY: 0, // batang harus berdasar nol
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => isDark
                      ? const Color(0xFF0C2822)
                      : const Color(0xFF14332C),
                  tooltipBorderRadius: BorderRadius.circular(10),
                  tooltipPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  getTooltipItem: (group, _, rod, _) {
                    final r = rows[group.x];
                    return BarTooltipItem(
                      '${fmtTanggalPendek(r.tanggal)}\n',
                      const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                      children: [
                        TextSpan(
                          text: fmtIDR(r.totalOmzet),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        TextSpan(
                          text: '\n${r.jumlahTransaksi} transaksi',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                touchCallback: (event, response) {
                  setState(() {
                    _disentuh = event.isInterestedForInteractions
                        ? response?.spot?.touchedBarGroupIndex
                        : null;
                  });
                },
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 46,
                    interval: garis,
                    getTitlesWidget: (v, _) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text(
                        v <= 0 ? '0' : fmtIDRSingkat(v),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: cs.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 26,
                    getTitlesWidget: (v, _) {
                      final i = v.toInt();
                      if (i < 0 || i >= rows.length) return const SizedBox.shrink();
                      // Label tanggal diselang-seling pada rentang panjang agar
                      // tidak saling bertumpuk.
                      final rapat = rows.length > 9;
                      if (rapat && i.isOdd) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          _labelSumbu(rows, i),
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: i == _disentuh
                                ? FontWeight.w800
                                : FontWeight.w500,
                            color: cs.onSurface.withValues(
                              alpha: i == _disentuh ? 0.9 : 0.55,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: garis,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: cs.onSurface.withValues(alpha: 0.08),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              barGroups: [
                for (var i = 0; i < rows.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: rows[i].totalOmzet,
                        width: rows.length > 9 ? 12 : 18,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4), // ujung data membulat 4px
                        ),
                        color: _disentuh == null || _disentuh == i
                            ? warna
                            : warna.withValues(alpha: 0.42),
                        backDrawRodData: BackgroundBarChartRodData(
                          show: true,
                          toY: atas,
                          color: cs.onSurface.withValues(alpha: 0.04),
                        ),
                      ),
                    ],
                    // Nilai ditulis hanya di batang tertinggi — angka di setiap
                    // batang membuat grafik penuh dan justru sulit dibaca.
                    showingTooltipIndicators: const [],
                  ),
              ],
              extraLinesData: ExtraLinesData(
                horizontalLines: [
                  if (maks > 0)
                    HorizontalLine(
                      y: maks,
                      color: warna.withValues(alpha: 0.35),
                      strokeWidth: 1,
                      dashArray: [4, 4],
                      label: HorizontalLineLabel(
                        show: true,
                        alignment: Alignment.topRight,
                        padding: const EdgeInsets.only(bottom: 3, right: 2),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface.withValues(alpha: 0.75),
                        ),
                        labelResolver: (_) =>
                            'Tertinggi ${fmtIDRSingkat(maks)}',
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Ketuk batang untuk melihat rinciannya. '
          'Hari tertinggi: ${fmtTanggalPendek(rows[idxMaks].tanggal)}.',
          style: TextStyle(
            fontSize: 11.5,
            height: 1.4,
            color: cs.onSurface.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }
}
