// Layar Jadwal (2.32.0): daftar slot satu hari; menata slot & peserta hanya
// muncul bila server memberi hak `jadwal.kelola` (gagal-tertutup).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/akses/akses.dart';
import 'package:tuleh_pos/core/network/api_result.dart';
import 'package:tuleh_pos/features/jadwal/domain/entities/jadwal.dart';
import 'package:tuleh_pos/features/jadwal/domain/repositories/jadwal_repository.dart';
import 'package:tuleh_pos/features/jadwal/presentation/providers/jadwal_providers.dart';
import 'package:tuleh_pos/features/jadwal/presentation/screens/jadwal_screen.dart';
import 'package:tuleh_pos/features/toko/presentation/providers/toko_providers.dart';

const _slot = JadwalSlot(
  id: 'J1', nama: 'Yoga Pagi', tanggal: '2026-09-21', jamMulai: '07:00', jamSelesai: '08:00',
  kuota: 2, sisaKuota: 1, pesertaCount: 1, pengajar: 'Sari', status: 'AKTIF',
);
const _penuh = JadwalSlot(
  id: 'J2', nama: 'Zumba Sore', tanggal: '2026-09-21', jamMulai: '17:00',
  kuota: 1, sisaKuota: 0, pesertaCount: 1, status: 'AKTIF',
);
const _detail = JadwalSlot(
  id: 'J1', nama: 'Yoga Pagi', tanggal: '2026-09-21', jamMulai: '07:00', jamSelesai: '08:00',
  kuota: 2, sisaKuota: 1, pesertaCount: 1, status: 'AKTIF',
  peserta: [PesertaJadwal(id: 'P1', pelangganId: 'C1', nama: 'Budi', telepon: '628123', status: 'TERDAFTAR')],
);

class _RepoPalsu implements JadwalRepository {
  String? statusDiubah;
  IsianJadwal? disimpan;

  @override
  Future<Result<List<JadwalSlot>>> daftar(String tanggal, {bool semua = false}) async => const Ok([_slot, _penuh]);
  @override
  Future<Result<JadwalSlot>> detail(String id) async => const Ok(_detail);
  @override
  Future<Result<JadwalSlot>> simpan(IsianJadwal isian) async {
    disimpan = isian;
    return const Ok(_slot);
  }
  @override
  Future<Result<JadwalSlot>> ubah(String id, IsianJadwal isian) async => const Ok(_slot);
  @override
  Future<Result<JadwalSlot>> batal(String id) async => const Ok(_slot);
  @override
  Future<Result<PesertaJadwal>> tambahPeserta(String id, String pelangganId) async =>
      const Ok(PesertaJadwal(id: 'P2', pelangganId: 'C2', nama: 'Sinta', status: 'TERDAFTAR'));
  @override
  Future<Result<PesertaJadwal>> ubahStatusPeserta(String id, String pesertaId, String status) async {
    statusDiubah = status;
    return Ok(PesertaJadwal(id: pesertaId, pelangganId: 'C1', nama: 'Budi', status: status));
  }
  @override
  Future<Result<void>> lepasPeserta(String id, String pesertaId) async => const Ok(null);
}

/// `jadwalHariProvider` ikut mengamati toko aktif. Notifier aslinya membaca
/// Keystore lewat kanal platform yang tidak ada di lingkungan test, jadi di
/// sini diganti supaya layar diuji tanpa menyentuh penyimpanan perangkat.
class _TokoAktifPalsu extends ActiveTokoNotifier {
  @override
  Future<String?> build() async => 'TOKO-1';
}

Future<void> _buka(WidgetTester t, _RepoPalsu repo, Set<String> akses) async {
  t.view.physicalSize = const Size(420, 900);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final c = ProviderContainer(overrides: [
    jadwalRepositoryProvider.overrideWithValue(repo),
    aksesProvider.overrideWithValue(akses),
    tanggalJadwalProvider.overrideWith((ref) => '2026-09-21'),
    activeTokoIdProvider.overrideWith(_TokoAktifPalsu.new),
  ]);
  addTearDown(c.dispose);
  await t.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: const MaterialApp(home: JadwalScreen()),
  ));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('daftar slot: jam, kuota terpakai, penanda penuh', (t) async {
    await _buka(t, _RepoPalsu(), {'jadwal.lihat'});
    expect(find.text('Yoga Pagi'), findsOneWidget);
    expect(find.text('07:00–08:00'), findsOneWidget);
    expect(find.textContaining('1 / 2 peserta'), findsOneWidget);
    expect(find.textContaining('penuh'), findsOneWidget, reason: 'Zumba Sore sisa 0');
  });

  testWidgets('tanpa hak kelola: tanpa tombol tambah, peserta hanya terbaca', (t) async {
    await _buka(t, _RepoPalsu(), {'jadwal.lihat'});
    expect(find.byKey(const ValueKey('jdw-tambah')), findsNothing);

    await t.tap(find.text('Yoga Pagi'));
    await t.pumpAndSettle();
    expect(find.text('Budi'), findsOneWidget);
    expect(find.byKey(const ValueKey('jdw-daftarkan')), findsNothing);
    expect(find.byKey(const ValueKey('jdw-status-P1')), findsNothing);
  });

  testWidgets('dengan hak kelola: tambah slot mengirim isian ke repositori', (t) async {
    final repo = _RepoPalsu();
    await _buka(t, repo, {'jadwal.lihat', 'jadwal.kelola'});

    await t.tap(find.byKey(const ValueKey('jdw-tambah')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('jdw-nama')), 'Pilates');
    await t.enterText(find.byKey(const ValueKey('jdw-jam-mulai')), '09:00');
    await t.enterText(find.byKey(const ValueKey('jdw-kuota')), '8');
    await t.tap(find.text('Simpan'));
    await t.pumpAndSettle();

    expect(repo.disimpan!.nama, 'Pilates');
    expect(repo.disimpan!.tanggal, '2026-09-21');
    expect(repo.disimpan!.jamMulai, '09:00');
    expect(repo.disimpan!.kuota, 8);
  });

  testWidgets('dengan hak kelola: menandai peserta hadir', (t) async {
    final repo = _RepoPalsu();
    await _buka(t, repo, {'jadwal.lihat', 'jadwal.kelola'});

    await t.tap(find.text('Yoga Pagi'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('jdw-status-P1')));
    await t.pumpAndSettle();
    await t.tap(find.text('Hadir').last);
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 5)); // habiskan pewaktu SnackBar sukses

    expect(repo.statusDiubah, 'HADIR');
  });

  testWidgets('isian tak lengkap ditolak sebelum menyentuh repositori', (t) async {
    final repo = _RepoPalsu();
    await _buka(t, repo, {'jadwal.lihat', 'jadwal.kelola'});
    await t.tap(find.byKey(const ValueKey('jdw-tambah')));
    await t.pumpAndSettle();
    await t.tap(find.text('Simpan'));
    await t.pumpAndSettle();
    expect(find.text('Nama jadwal wajib diisi.'), findsOneWidget);
    expect(repo.disimpan, isNull);
  });
}
