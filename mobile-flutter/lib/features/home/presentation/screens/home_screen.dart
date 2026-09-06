import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/widgets/app_background.dart';
import '../../../../core/widgets/motion.dart';
import '../../../../core/widgets/states.dart';
import '../../../auth/domain/entities/user.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../demo/data/masa_coba_service.dart';
import '../../../demo/demo_session.dart';
import '../../../pengaturan/presentation/screens/pengaturan_screen.dart' show keluarDenganPenjagaAntrean;
import '../../../laporan/presentation/providers/laporan_providers.dart';
import '../../../riwayat/domain/entities/transaksi.dart';
import '../../../riwayat/presentation/providers/riwayat_providers.dart';
import '../../../sesi/presentation/providers/sesi_providers.dart';
import '../../../toko/domain/entities/toko.dart';
import '../../../toko/presentation/providers/toko_providers.dart';

/// Beranda — dasbor hari ini, bukan daftar menu.
///
/// Navigasi sudah dipegang bilah bawah, jadi beranda bebas menjawab tiga hal
/// yang ditanya pemilik toko tiap membuka aplikasi: sesi kasir sudah dibuka
/// belum, berapa penjualan hari ini, dan apa yang terakhir terjadi.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).value;
    final tokoAsync = ref.watch(tokoListProvider);
    final tokos = tokoAsync.valueOrNull ?? const <Toko>[];
    final activeId = ref.watch(activeTokoIdProvider).valueOrNull;

    // Toko aktif belum ada, atau id tersimpan tidak dikenal akun ini (sisa
    // akun/demo sebelumnya) → pakai toko pertama. Tanpa ini kepala dasbor
    // terjebak di "Memuat toko…" selamanya.
    final idDikenal = tokos.any((t) => t.id == activeId);
    if (tokos.isNotEmpty && (activeId == null || !idDikenal)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(activeTokoIdProvider.notifier).select(tokos.first.id);
      });
    }
    Toko? activeToko;
    for (final t in tokos) {
      if (t.id == activeId) activeToko = t;
    }

    final manifest = ref.watch(activeManifestProvider).valueOrNull;
    final pakaiMeja = manifest?.capabilities.contains('tables_qr') ?? false;
    final bertahap = manifest?.punyaPapanPesanan ?? false;

    return Scaffold(
      body: AppBackground(
        pola: true,
        child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(activeSesiProvider);
              ref.invalidate(sesiRekapProvider);
              ref.invalidate(penjualanHarianProvider);
              ref.invalidate(riwayatListProvider);
            },
            child: LayoutBuilder(
              builder: (context, c) {
                final pad = c.maxWidth >= 700 ? 28.0 : 20.0;
                return ListView(
                  padding: EdgeInsets.fromLTRB(pad, 12, pad, 28),
                  children: [
                    MunculBertahap(
                      child: _Header(
                        user: user,
                        toko: activeToko,
                        tokoGagal: tokoAsync.hasError,
                        onMuatUlangToko: () => ref.invalidate(tokoListProvider),
                        bisaGanti: tokos.length > 1,
                        isDemo: ref.read(demoSessionProvider).active,
                        sisaHariDemo: ref.read(demoSessionProvider).active
                            ? ref.watch(masaCobaStatusProvider).valueOrNull?.sisaHari
                            : null,
                        onGantiToko: tokos.length > 1
                            ? () => _pilihToko(context, ref, tokos, activeId)
                            : null,
                        onLogout: () => keluarDenganPenjagaAntrean(context, ref),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const MunculBertahap(urutan: 1, child: _KartuSesi()),
                    const SizedBox(height: 14),
                    const MunculBertahap(urutan: 2, child: _RingkasanHariIni()),
                    const SizedBox(height: 22),
                    MunculBertahap(
                      urutan: 3,
                      child: _AksiCepat(bertahap: bertahap, pakaiMeja: pakaiMeja),
                    ),
                    const SizedBox(height: 22),
                    const MunculBertahap(urutan: 4, child: _TransaksiTerbaru()),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Lembar pilih toko. Dibuka di navigator AKAR (bukan cabang tab) agar
  /// menutupi bilah navigasi bawah, dan daftarnya bisa digulir — dengan
  /// banyak toko, Column biasa meluber sehingga toko di bawah tak bisa dipilih.
  Future<void> _pilihToko(
    BuildContext context,
    WidgetRef ref,
    List<Toko> tokos,
    String? activeId,
  ) async {
    final tinggiLayar = MediaQuery.sizeOf(context).height;
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      constraints: BoxConstraints(maxHeight: tinggiLayar * 0.8),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'Pilih toko',
              style: Theme.of(
                ctx,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 12),
              itemCount: tokos.length,
              itemBuilder: (_, i) {
                final t = tokos[i];
                return ListTile(
                  key: ValueKey('toko-${t.id}'),
                  leading: const Icon(Icons.storefront_outlined),
                  title: Text(t.nama),
                  subtitle: t.bidangUsaha != null ? Text(t.bidangUsaha!) : null,
                  trailing: t.id == activeId
                      ? const Icon(Icons.check_circle, color: AppColors.mint600)
                      : null,
                  onTap: () {
                    ref.read(activeTokoIdProvider.notifier).select(t.id);
                    Navigator.of(ctx).pop();
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.user,
    required this.toko,
    required this.bisaGanti,
    required this.isDemo,
    required this.onGantiToko,
    required this.onLogout,
    this.tokoGagal = false,
    this.onMuatUlangToko,
    this.sisaHariDemo,
  });

  /// Sisa hari masa coba Mode Demo (null = tidak diketahui / bukan demo).
  final int? sisaHariDemo;

  final User? user;
  final Toko? toko;
  /// Daftar toko gagal dimuat → tampilkan sebab + tombol ulang, bukan
  /// "Memuat toko…" tanpa akhir.
  final bool tokoGagal;
  final VoidCallback? onMuatUlangToko;
  final bool bisaGanti;
  final bool isDemo;
  final VoidCallback? onGantiToko;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = user?.name ?? 'Kasir';
    final firstName = name.split(' ').first;
    final initials = name
        .split(RegExp(r'\s+'))
        .take(2)
        .map((w) => w.isNotEmpty ? w[0] : '')
        .join()
        .toUpperCase();

    return Row(
      children: [
        CircleAvatar(
          radius: 23,
          backgroundColor: cs.primaryContainer,
          child: Text(
            initials.isEmpty ? 'K' : initials,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: cs.onPrimaryContainer,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      'Halo, $firstName',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isDemo) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.warn.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        sisaHariDemo == null
                            ? 'DEMO'
                            : 'DEMO · $sisaHariDemo HARI',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                          color: AppColors.warn,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              // Nama toko sebagai tombol pilih — bukan kartu terpisah.
              InkWell(
                onTap: tokoGagal ? onMuatUlangToko : onGantiToko,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        tokoGagal
                            ? Icons.refresh_rounded
                            : Icons.storefront_outlined,
                        size: 15,
                        color: tokoGagal
                            ? cs.error
                            : cs.onSurface.withValues(alpha: 0.6),
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          toko?.nama ??
                              (tokoGagal
                                  ? 'Toko gagal dimuat · ketuk untuk ulang'
                                  : 'Memuat toko…'),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: tokoGagal
                                ? cs.error
                                : cs.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                      if (bisaGanti)
                        Icon(
                          Icons.expand_more_rounded,
                          size: 18,
                          color: cs.primary,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: isDemo ? 'Keluar dari Mode Demo' : 'Keluar',
          onPressed: onLogout,
          icon: const Icon(Icons.logout_rounded),
        ),
      ],
    );
  }
}

/// Status sesi kasir — hal pertama yang harus jelas saat buka aplikasi.
/// Belum dibuka → ajakan besar; sudah dibuka → kas & transaksi berjalan.
class _KartuSesi extends ConsumerWidget {
  const _KartuSesi();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesi = ref.watch(activeSesiProvider);
    final rekap = ref.watch(sesiRekapProvider).valueOrNull;
    final cs = Theme.of(context).colorScheme;

    return sesi.when(
      loading: () => const _KerangkaKartu(tinggi: 96),
      error: (_, _) => const SizedBox.shrink(),
      data: (s) {
        if (s == null) {
          return Material(
            color: AppColors.warn.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => context.push('/sesi'),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: AppColors.warn.withValues(alpha: 0.45),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.lock_clock_outlined,
                      color: AppColors.warn,
                      size: 26,
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sesi kasir belum dibuka',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Buka sesi dengan kas awal untuk mulai berjualan.',
                            style: TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.tonal(
                      onPressed: () => context.push('/sesi'),
                      child: const Text('Buka'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cs.outline),
          ),
          child: Row(
            children: [
              Container(
                height: 44,
                width: 44,
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.point_of_sale_rounded,
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Sesi ${s.nomor ?? rekap?.nomor ?? 'kasir'}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.13),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'Buka',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.success,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      rekap == null
                          ? 'Kas berjalan sedang dimuat…'
                          : 'Kas ${fmtIDR(rekap.kasAkhirSistem)} · '
                                '${rekap.jumlahTransaksi} transaksi',
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Kelola sesi',
                onPressed: () => context.push('/sesi'),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Dua angka hari ini dari laporan harian — omzet & jumlah transaksi.
class _RingkasanHariIni extends ConsumerWidget {
  const _RingkasanHariIni();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final harian = ref.watch(penjualanHarianProvider);

    return harian.when(
      loading: () => const _KerangkaKartu(tinggi: 92),
      error: (_, _) => const SizedBox.shrink(),
      data: (rows) {
        final hariIni = DateTime.now().toIso8601String().substring(0, 10);
        final r = rows.where((x) => x.tanggal.startsWith(hariIni)).toList();
        final omzet = r.isEmpty ? 0.0 : r.first.totalOmzet;
        final trx = r.isEmpty ? 0 : r.first.jumlahTransaksi;

        return Row(
          children: [
            Expanded(
              flex: 3,
              child: _Angka(
                label: 'Omzet hari ini',
                nilai: fmtIDR(omzet),
                ikon: Icons.payments_outlined,
                utama: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: _Angka(
                label: 'Transaksi',
                nilai: '$trx',
                ikon: Icons.receipt_outlined,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Angka extends StatelessWidget {
  const _Angka({
    required this.label,
    required this.nilai,
    required this.ikon,
    this.utama = false,
  });

  final String label;
  final String nilai;
  final IconData ikon;
  final bool utama;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: utama ? cs.primaryContainer : cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: utama ? Colors.transparent : cs.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                ikon,
                size: 16,
                color: (utama ? cs.onPrimaryContainer : cs.onSurface)
                    .withValues(alpha: 0.65),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: (utama ? cs.onPrimaryContainer : cs.onSurface)
                        .withValues(alpha: 0.65),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            nilai,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: utama ? 20 : 20,
              fontWeight: FontWeight.w800,
              color: utama ? cs.onPrimaryContainer : cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

/// Aksi yang paling sering ditekan, dalam jangkauan ibu jari.
class _AksiCepat extends StatelessWidget {
  const _AksiCepat({required this.bertahap, required this.pakaiMeja});

  final bool bertahap;
  final bool pakaiMeja;

  @override
  Widget build(BuildContext context) {
    final aksi = <(String, IconData, String)>[
      ('Kasir', Icons.point_of_sale_rounded, '/kasir'),
      if (pakaiMeja) ('Meja', Icons.table_restaurant_outlined, '/meja'),
      if (bertahap) ('Pesanan', Icons.view_kanban_outlined, '/aktivitas'),
      ('Produk', Icons.inventory_2_outlined, '/produk'),
      ('Stok', Icons.warehouse_outlined, '/stok'),
      ('Pengeluaran', Icons.receipt_long_outlined, '/pengeluaran'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _JudulBagian(teks: 'Aksi cepat'),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final a in aksi.take(4)) ...[
              Expanded(
                child: _TombolAksi(
                  label: a.$1,
                  ikon: a.$2,
                  utama: a.$1 == 'Kasir',
                  onTap: () => a.$3 == '/kasir' || a.$3 == '/aktivitas'
                      ? context.go(a.$3)
                      : context.push(a.$3),
                ),
              ),
              if (a != aksi.take(4).last) const SizedBox(width: 10),
            ],
          ],
        ),
      ],
    );
  }
}

class _TombolAksi extends StatelessWidget {
  const _TombolAksi({
    required this.label,
    required this.ikon,
    required this.onTap,
    this.utama = false,
  });

  final String label;
  final IconData ikon;
  final VoidCallback onTap;
  final bool utama;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: utama ? cs.primary : cs.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: utama ? Colors.transparent : cs.outline),
          ),
          child: Column(
            children: [
              Icon(
                ikon,
                size: 24,
                color: utama ? cs.onPrimary : cs.primary,
              ),
              const SizedBox(height: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: utama ? cs.onPrimary : cs.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lima transaksi terakhir — "apa yang baru saja terjadi".
class _TransaksiTerbaru extends ConsumerWidget {
  const _TransaksiTerbaru();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final riwayat = ref.watch(riwayatListProvider);
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: _JudulBagian(teks: 'Transaksi terbaru')),
            TextButton(
              onPressed: () => context.push('/riwayat'),
              child: const Text('Lihat semua'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        riwayat.when(
          loading: () => const _KerangkaKartu(tinggi: 150),
          error: (e, _) => KeadaanGagal(
            error: e,
            onUlangi: () => ref.invalidate(riwayatListProvider),
          ),
          data: (rows) => rows.isEmpty
              ? const KeadaanKosong(
                  ikon: Icons.receipt_long_outlined,
                  judul: 'Belum ada transaksi',
                  detail: 'Transaksi dari kasir akan muncul di sini.',
                )
              // Material (bukan Container berwarna): ListTile melukis riak
              // sentuhnya ke Material terdekat, jadi Container akan menutupinya.
              : Material(
                  color: cs.surface,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: cs.outline),
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < rows.length && i < 5; i++) ...[
                        _BarisTransaksi(t: rows[i]),
                        if (i < rows.length - 1 && i < 4)
                          Divider(height: 1, color: cs.outline, indent: 16),
                      ],
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _BarisTransaksi extends StatelessWidget {
  const _BarisTransaksi({required this.t});
  final Transaksi t;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final batal = (t.status ?? '').toUpperCase() == 'DIBATALKAN';
    return ListTile(
      dense: true,
      leading: Icon(
        batal ? Icons.cancel_outlined : Icons.receipt_outlined,
        size: 20,
        color: batal ? cs.error : cs.primary,
      ),
      title: Text(
        t.nomor,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          decoration: batal ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: Text(
        [
          if (t.metode != null && t.metode!.isNotEmpty) t.metode!,
          fmtTanggal(t.tanggal),
        ].join(' · '),
      ),
      trailing: Text(
        fmtIDR(t.grandTotal),
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      onTap: () => context.push('/riwayat'),
    );
  }
}

class _JudulBagian extends StatelessWidget {
  const _JudulBagian({required this.teks});
  final String teks;

  @override
  Widget build(BuildContext context) => Text(
    teks,
    style: Theme.of(
      context,
    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
  );
}

class _KerangkaKartu extends StatelessWidget {
  const _KerangkaKartu({required this.tinggi});
  final double tinggi;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: tinggi,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Kerangka(tinggi: 12, lebar: 140),
          SizedBox(height: 10),
          Kerangka(tinggi: 18, lebar: 180),
        ],
      ),
    );
  }
}
