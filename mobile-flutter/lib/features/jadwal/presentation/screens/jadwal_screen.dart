import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/akses/akses.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/states.dart';
import '../../../pelanggan/presentation/providers/pelanggan_providers.dart';
import '../../domain/entities/jadwal.dart';
import '../providers/jadwal_providers.dart';

const _hari = ['Minggu', 'Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu'];
const _bulan = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
const _statusPeserta = {'TERDAFTAR': 'Terdaftar', 'HADIR': 'Hadir', 'BATAL': 'Batal'};

String _labelTanggal(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  final teks = '${_hari[d.weekday % 7]}, ${d.day} ${_bulan[d.month - 1]} ${d.year}';
  final kini = tanggalKey(DateTime.now());
  if (iso == kini) return 'Hari ini · $teks';
  return teks;
}

String _labelKuota(JadwalSlot s) => s.kuota == null
    ? '${s.pesertaCount} peserta · tanpa batas'
    : '${s.pesertaCount} / ${s.kuota} peserta${s.penuh ? ' · penuh' : ''}';

/// Jadwal (gym, klinik) — slot kelas/janji temu satu hari beserta pesertanya.
/// Menata slot & peserta digerbang hak `jadwal.kelola` dari server; pemegang
/// `jadwal.lihat` saja tetap bisa membaca (server memeriksa ulang, 403).
class JadwalScreen extends ConsumerWidget {
  const JadwalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tanggal = ref.watch(tanggalJadwalProvider);
    final daftar = ref.watch(jadwalHariProvider);
    final kelola = ref.watch(bisaProvider('jadwal.kelola'));

    void geser(int n) {
      final d = DateTime.parse(tanggal).add(Duration(days: n));
      ref.read(tanggalJadwalProvider.notifier).state = tanggalKey(d);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Jadwal')),
      floatingActionButton: kelola
          ? FloatingActionButton.extended(
              key: const ValueKey('jdw-tambah'),
              onPressed: () => _bukaForm(context, ref, tanggal, null),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Tambah jadwal'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
            child: Row(
              children: [
                IconButton(onPressed: () => geser(-1), icon: const Icon(Icons.chevron_left_rounded)),
                Expanded(
                  child: Text(
                    _labelTanggal(tanggal),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(onPressed: () => geser(1), icon: const Icon(Icons.chevron_right_rounded)),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(jadwalHariProvider),
              child: daftar.when(
                loading: () => const DaftarKerangka(jumlah: 5, tinggiBaris: 72),
                error: (e, _) => ListView(
                  children: [KeadaanGagal(error: e, onUlangi: () => ref.invalidate(jadwalHariProvider))],
                ),
                data: (rows) => rows.isEmpty
                    ? ListView(
                        children: [
                          const SizedBox(height: 60),
                          KeadaanKosong(
                            ikon: Icons.event_available_outlined,
                            judul: 'Belum ada jadwal',
                            detail: kelola
                                ? 'Tambahkan slot kelas atau janji temu lewat tombol di bawah.'
                                : 'Minta pemilik atau manajer menambahkan slotnya.',
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                        itemCount: rows.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _KartuSlot(
                          slot: rows[i],
                          onBuka: () => _bukaDetail(context, ref, rows[i].id),
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KartuSlot extends StatelessWidget {
  const _KartuSlot({required this.slot, required this.onBuka});

  final JadwalSlot slot;
  final VoidCallback onBuka;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onBuka,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: [
              SizedBox(
                width: 96,
                child: Text(
                  slot.rentangJam,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      slot.nama,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        decoration: slot.aktif ? null : TextDecoration.lineThrough,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [_labelKuota(slot), if (slot.pengajar != null) slot.pengajar!].join(' · '),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: slot.penuh ? AppColors.warn : cs.onSurface.withValues(alpha: 0.62),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────── lembar formulir

Future<void> _bukaForm(BuildContext context, WidgetRef ref, String tanggal, JadwalSlot? slot) async {
  final hasil = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _FormSlot(tanggal: tanggal, slot: slot),
  );
  if (hasil != true) return;
  ref.invalidate(jadwalHariProvider);
  if (slot != null) ref.invalidate(jadwalDetailProvider(slot.id));
}

class _FormSlot extends ConsumerStatefulWidget {
  const _FormSlot({required this.tanggal, this.slot});

  final String tanggal;
  final JadwalSlot? slot;

  @override
  ConsumerState<_FormSlot> createState() => _FormSlotState();
}

class _FormSlotState extends ConsumerState<_FormSlot> {
  late final _nama = TextEditingController(text: widget.slot?.nama ?? '');
  late final _mulai = TextEditingController(text: widget.slot?.jamMulai ?? '');
  late final _selesai = TextEditingController(text: widget.slot?.jamSelesai ?? '');
  late final _kuota = TextEditingController(text: widget.slot?.kuota?.toString() ?? '');
  late final _pengajar = TextEditingController(text: widget.slot?.pengajar ?? '');
  late final _catatan = TextEditingController(text: widget.slot?.catatan ?? '');
  String? _galat;
  bool _kirim = false;

  @override
  void dispose() {
    for (final c in [_nama, _mulai, _selesai, _kuota, _pengajar, _catatan]) {
      c.dispose();
    }
    super.dispose();
  }

  IsianJadwal? _validasi() {
    String t(TextEditingController c) => c.text.trim();
    if (t(_nama).isEmpty) {
      _galat = 'Nama jadwal wajib diisi.';
      return null;
    }
    if (t(_mulai).isEmpty) {
      _galat = 'Jam mulai wajib diisi (HH:MM).';
      return null;
    }
    if (t(_selesai).isNotEmpty && t(_selesai).compareTo(t(_mulai)) <= 0) {
      _galat = 'Jam selesai harus setelah jam mulai.';
      return null;
    }
    final kuota = t(_kuota).isEmpty ? null : int.tryParse(t(_kuota));
    if (t(_kuota).isNotEmpty && (kuota == null || kuota < 1)) {
      _galat = 'Kuota minimal 1 peserta — kosongkan bila tanpa batas.';
      return null;
    }
    _galat = null;
    return IsianJadwal(
      nama: t(_nama),
      tanggal: widget.slot?.tanggal ?? widget.tanggal,
      jamMulai: t(_mulai),
      jamSelesai: t(_selesai).isEmpty ? null : t(_selesai),
      kuota: kuota,
      pengajar: t(_pengajar).isEmpty ? null : t(_pengajar),
      catatan: t(_catatan).isEmpty ? null : t(_catatan),
    );
  }

  Future<void> _simpan() async {
    final isian = _validasi();
    setState(() {});
    if (isian == null) return;
    setState(() => _kirim = true);
    final repo = ref.read(jadwalRepositoryProvider);
    final hasil = widget.slot == null ? await repo.simpan(isian) : await repo.ubah(widget.slot!.id, isian);
    if (!mounted) return;
    hasil.when(
      ok: (_) => Navigator.pop(context, true),
      err: (ApiException e) => setState(() {
        _kirim = false;
        _galat = e.firstError() ?? e.message;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        children: [
          Text(
            widget.slot == null ? 'Tambah jadwal' : 'Ubah jadwal',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('jdw-nama'),
            controller: _nama,
            maxLength: 150,
            decoration: const InputDecoration(labelText: 'Nama jadwal', hintText: 'mis. Yoga Pagi, Poli Gigi', counterText: ''),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('jdw-jam-mulai'),
                  controller: _mulai,
                  decoration: const InputDecoration(labelText: 'Jam mulai', hintText: '07:00'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  key: const ValueKey('jdw-jam-selesai'),
                  controller: _selesai,
                  decoration: const InputDecoration(labelText: 'Jam selesai', hintText: 'opsional'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('jdw-kuota'),
                  controller: _kuota,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Kuota', hintText: 'kosong = tanpa batas'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  key: const ValueKey('jdw-pengajar'),
                  controller: _pengajar,
                  maxLength: 100,
                  decoration: const InputDecoration(labelText: 'Pengajar / petugas', counterText: ''),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('jdw-catatan'),
            controller: _catatan,
            maxLength: 255,
            decoration: const InputDecoration(labelText: 'Catatan', counterText: ''),
          ),
          if (_galat != null) ...[
            const SizedBox(height: 8),
            Text(_galat!, style: const TextStyle(color: AppColors.danger)),
          ],
          const SizedBox(height: 14),
          FilledButton(
            onPressed: _kirim ? null : _simpan,
            child: Text(_kirim ? 'Menyimpan…' : 'Simpan'),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────────────────────────────────── lembar detail

Future<void> _bukaDetail(BuildContext context, WidgetRef ref, String id) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _DetailSlot(id: id),
  );
  ref.invalidate(jadwalHariProvider);
}

class _DetailSlot extends ConsumerWidget {
  const _DetailSlot({required this.id});

  final String id;

  /// Aksi destruktif (lepas peserta, batalkan jadwal) wajib dikonfirmasi — pola yang sama
  /// dengan layar Meja; tidak ada "aktifkan kembali" dari aplikasi.
  Future<bool> _konfirmasi(BuildContext context, {required String judul, required String isi, required String tombol}) async {
    final ya = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(judul),
        content: Text(isi),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Kembali')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tombol),
          ),
        ],
      ),
    );
    return ya == true;
  }

  Future<void> _lepasPeserta(BuildContext context, WidgetRef ref, PesertaJadwal p) async {
    final ya = await _konfirmasi(
      context,
      judul: 'Lepas ${p.nama} dari jadwal?',
      isi: 'Peserta dihapus dari daftar slot ini dan kuotanya kembali tersedia.',
      tombol: 'Lepas',
    );
    if (!ya || !context.mounted) return;
    await _jalankan(
      context,
      ref,
      () => ref.read(jadwalRepositoryProvider).lepasPeserta(id, p.id),
      sukses: '${p.nama} dilepas dari jadwal.',
    );
  }

  Future<void> _batalkanJadwal(BuildContext context, WidgetRef ref, JadwalSlot s) async {
    final ya = await _konfirmasi(
      context,
      judul: 'Batalkan jadwal "${s.nama}"?',
      isi: 'Slot ditandai batal dan tidak bisa diaktifkan lagi dari aplikasi. '
          'Peserta yang sudah terdaftar tetap tercatat.',
      tombol: 'Batalkan jadwal',
    );
    if (!ya || !context.mounted) return;
    await _jalankan(
      context,
      ref,
      () => ref.read(jadwalRepositoryProvider).batal(id),
      sukses: 'Jadwal "${s.nama}" dibatalkan.',
    );
  }

  /// Jalankan aksi tulis; sukses → muat ulang detail + kabar singkat, gagal → kalimat server
  /// (409 KUOTA_PENUH/SUDAH_TERDAFTAR/JADWAL_BATAL tampil apa adanya).
  Future<void> _jalankan(
    BuildContext context,
    WidgetRef ref,
    Future<dynamic> Function() aksi, {
    required String sukses,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final hasil = await aksi();
    if (!context.mounted) return;
    hasil.when(
      ok: (_) {
        ref.invalidate(jadwalDetailProvider(id));
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(backgroundColor: AppColors.success, content: Text(sukses)));
      },
      err: (e) {
        final pesan = e is ApiException ? (e.firstError() ?? e.message) : '$e';
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(backgroundColor: AppColors.danger, content: Text(pesan)));
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(jadwalDetailProvider(id));
    final kelola = ref.watch(bisaProvider('jadwal.kelola'));

    return detail.when(
      loading: () => const Padding(padding: EdgeInsets.all(28), child: DaftarKerangka(jumlah: 3, tinggiBaris: 64)),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(20),
        child: KeadaanGagal(error: e, onUlangi: () => ref.invalidate(jadwalDetailProvider(id))),
      ),
      data: (s) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          Text(s.nama, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            '${s.rentangJam} · ${_labelTanggal(s.tanggal)} · ${_labelKuota(s)}',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65)),
          ),
          if (s.catatan != null) ...[const SizedBox(height: 6), Text(s.catatan!)],
          const Divider(height: 24),
          if (s.peserta.isEmpty)
            const Text('Belum ada peserta terdaftar.')
          else
            for (final p in s.peserta)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(p.nama, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text([if (p.telepon != null) p.telepon!, _statusPeserta[p.status] ?? p.status].join(' · ')),
                trailing: kelola
                    ? PopupMenuButton<String>(
                        key: ValueKey('jdw-status-${p.id}'),
                        icon: const Icon(Icons.more_vert_rounded),
                        onSelected: (nilai) => nilai == 'LEPAS'
                            ? _lepasPeserta(context, ref, p)
                            : _jalankan(
                                context,
                                ref,
                                () => ref.read(jadwalRepositoryProvider).ubahStatusPeserta(id, p.id, nilai),
                                sukses: '${p.nama}: ${_statusPeserta[nilai] ?? nilai}.',
                              ),
                        itemBuilder: (_) => [
                          for (final e in _statusPeserta.entries)
                            PopupMenuItem(value: e.key, child: Text(e.value)),
                          const PopupMenuItem(value: 'LEPAS', child: Text('Lepas peserta')),
                        ],
                      )
                    : null,
              ),
          if (kelola) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              key: const ValueKey('jdw-daftarkan'),
              onPressed: () => _daftarkanPeserta(context, ref, s),
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 19),
              label: const Text('Daftarkan peserta'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _bukaForm(context, ref, s.tanggal, s),
              icon: const Icon(Icons.edit_outlined, size: 19),
              label: const Text('Ubah jadwal'),
            ),
            if (s.aktif)
              TextButton(
                onPressed: () => _batalkanJadwal(context, ref, s),
                style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                child: const Text('Batalkan jadwal'),
              ),
          ],
        ],
      ),
    );
  }
}

Future<void> _daftarkanPeserta(BuildContext context, WidgetRef ref, JadwalSlot slot) async {
  final pilihan = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _PilihPelanggan(),
  );
  if (pilihan == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final hasil = await ref.read(jadwalRepositoryProvider).tambahPeserta(slot.id, pilihan);
  hasil.when(
    ok: (p) {
      ref.invalidate(jadwalDetailProvider(slot.id));
      ref.invalidate(jadwalHariProvider);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(backgroundColor: AppColors.success, content: Text('${p.nama} didaftarkan.')));
    },
    err: (e) => messenger
      ..hideCurrentSnackBar()
      // Pesan 409 KUOTA_PENUH / SUDAH_TERDAFTAR dari server sudah siap tampil.
      ..showSnackBar(SnackBar(backgroundColor: AppColors.danger, content: Text(e.firstError() ?? e.message))),
  );
}

class _PilihPelanggan extends ConsumerWidget {
  const _PilihPelanggan();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final daftar = ref.watch(pelangganListProvider);
    return daftar.when(
      loading: () => const Padding(padding: EdgeInsets.all(28), child: DaftarKerangka(jumlah: 4, tinggiBaris: 64)),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(20),
        child: KeadaanGagal(error: e, onUlangi: () => ref.invalidate(pelangganListProvider)),
      ),
      data: (rows) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          Text('Pilih peserta', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (rows.isEmpty)
            const KeadaanKosong(
              ikon: Icons.people_alt_outlined,
              judul: 'Belum ada pelanggan',
              detail: 'Tambahkan pelanggan lewat menu Pelanggan lebih dulu.',
            )
          else
            for (final c in rows)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(c.nama),
                subtitle: c.telepon == null ? null : Text(c.telepon!),
                onTap: () => Navigator.pop(context, c.id),
              ),
        ],
      ),
    );
  }
}
