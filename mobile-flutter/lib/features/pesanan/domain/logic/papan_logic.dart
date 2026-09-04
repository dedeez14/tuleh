import '../entities/pesanan.dart';

/// Logika murni papan pesanan (tanpa Flutter/Riverpod) — cermin orders.js &
/// lib/stage-label.js desktop, sehingga bisa diuji langsung.
///
/// Kolom papan TIDAK di-hardcode: dibaca dari `manifest.lifecycle.states`
/// toko aktif; satu layar melayani bakso (4 tahap), laundry (7), bengkel,
/// doorsmeer, salon, dan bidang usaha baru yang belum dikenal app.

/// Label manusiawi untuk kode tahap umum; selain ini → Title Case otomatis.
const stageLabels = <String, String>{
  'MENUNGGU_BAYAR': 'Menunggu Bayar',
  'ANTRIAN': 'Antrian',
  'DIPROSES': 'Diproses',
  'READY': 'Siap',
  'PENCUCIAN': 'Pencucian',
  'PENGERINGAN': 'Pengeringan',
  'LIPAT': 'Lipat & Kemas',
  'SIAP_AMBIL': 'Siap Diambil',
  'SELESAI': 'Selesai',
  // Jasa kendaraan & salon (manifest_override server)
  'PEMERIKSAAN': 'Pemeriksaan',
  'PENGERJAAN': 'Pengerjaan',
  'DILAYANI': 'Dilayani',
  'FINISHING': 'Finishing & Poles',
};

String stageLabel(String? stage) {
  if (stage == null || stage.isEmpty) return '';
  final known = stageLabels[stage];
  if (known != null) return known;
  return stage
      .toLowerCase()
      .split('_')
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

/// Ambang umur pesanan (menit) untuk pewarnaan: alur pendek (dapur F&B)
/// dihitung menit; alur panjang bertahap (>4 tahap) wajarnya berjam-jam.
class UmurAmbang {
  const UmurAmbang({required this.warn, required this.danger});

  final int warn;
  final int danger;
}

const umurCepat = UmurAmbang(warn: 10, danger: 15);
const umurPanjang = UmurAmbang(warn: 240, danger: 480);

UmurAmbang ambangUmur(List<String> states) =>
    states.length > 4 ? umurPanjang : umurCepat;

int umurMenit(Pesanan o, {DateTime? now}) {
  final t = o.createdAt;
  if (t == null) return 0;
  final diff = (now ?? DateTime.now()).difference(t).inMinutes;
  return diff < 0 ? 0 : diff;
}

String fmtUmur(int menit) {
  if (menit < 60) return '$menit mnt';
  return '${menit ~/ 60} j ${menit % 60} mnt';
}

/// Tahap terminal (kolom terakhir tidak ditampilkan sebagai kolom).
String? tahapTerminal(List<String> states) =>
    states.isEmpty ? null : states.last;

/// Kolom papan: semua tahap kecuali terminal; `MENUNGGU_BAYAR` (order QR meja
/// belum bayar) ditambahkan di depan hanya bila ada pesanan di tahap itu.
List<String> kolomPapan(List<String> states, {bool adaMenungguBayar = false}) {
  if (states.length < 2) return const [];
  final kolom = states.sublist(0, states.length - 1);
  return adaMenungguBayar ? ['MENUNGGU_BAYAR', ...kolom] : kolom;
}

/// Tahap berikutnya untuk sebuah pesanan; null bila sudah terminal / tak dikenal.
String? tahapBerikut(String stage, List<String> states) {
  if (states.isEmpty) return null;
  if (stage == 'MENUNGGU_BAYAR') return states.first;
  final idx = states.indexOf(stage);
  if (idx == -1 || idx >= states.length - 1) return null;
  return states[idx + 1];
}

/// Aksi tombol pada kartu, mengikuti aturan papan desktop:
/// - order QR meja belum bayar → Konfirmasi Bayar (masuk tahap pertama);
/// - di kolom terakhir & nota belum lunas → Lunasi & Serahkan (bayar + selesai);
/// - selain itu → maju ke tahap berikutnya (tahap terakhir = tandai selesai).
enum AksiKartu { konfirmasiBayar, lunasi, maju, selesai }

AksiKartu? aksiKartu(Pesanan o, List<String> states) {
  if (o.menungguBayar) return AksiKartu.konfirmasiBayar;
  final next = tahapBerikut(o.stage, states);
  if (next == null) return null;
  final terakhir = next == tahapTerminal(states);
  if (terakhir && o.belumBayar) return AksiKartu.lunasi;
  return terakhir ? AksiKartu.selesai : AksiKartu.maju;
}

/// Teks tombol untuk [aksiKartu].
String labelAksi(AksiKartu aksi, String stage, List<String> states) {
  final next = tahapBerikut(stage, states);
  return switch (aksi) {
    AksiKartu.konfirmasiBayar => 'Konfirmasi Bayar',
    AksiKartu.lunasi => 'Lunasi & Serahkan',
    AksiKartu.selesai => '${stageLabel(next)} ✓',
    AksiKartu.maju => '→ ${stageLabel(next)}',
  };
}
