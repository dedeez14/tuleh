// Keputusan penyegaran identitas (Tahap B §2b) — fungsi MURNI, tanpa Riverpod
// dan tanpa widget, supaya bisa diuji sendiri. Efeknya dijalankan
// `AuthController.segarkanIdentitas` (memuat /auth/me) dan `IdentitasGate`
// (memuat ulang manifest & memulangkan layar). Padanan `lib/identitas.js` di
// desktop.

/// Sidik jari daftar hak: urutan dari server tidak dijamin, jadi diurutkan
/// dulu. Dipakai menjawab satu pertanyaan — "hak pengguna berubah atau tidak?"
/// — karena hak berubah berarti menu manifest (disaring server per hak) ikut
/// berubah walau `manifest_version` tidak bergerak.
String kunciAkses(Iterable<String>? akses) =>
    akses == null ? '\u0000belum' : (akses.toList()..sort()).join('|');

/// Layar yang harus ditinggalkan karena haknya baru saja dicabut.
///
/// [layar] jalur go_router yang sedang terbuka; [tersedia] rute yang punya
/// pintu SESUDAH hak/menu disegarkan; [sebelumnya] rute yang punya pintu
/// sebelumnya.
///
/// Hanya layar yang TADINYA punya pintu dan sekarang tidak lagi yang
/// dipulangkan. Layar yang memang tak pernah punya kartu (papan pesanan
/// dibuka lewat tab, layar rincian didorong dari layar lain) dibiarkan, dan
/// daftar kosong — mis. manifest gagal dimuat — tidak mengusir siapa pun
/// (gagal-terbuka: server tetap penentu lewat 403).
String? layarTujuan(
  String? layar,
  Set<String> tersedia,
  Set<String> sebelumnya, {
  String beranda = '/home',
}) {
  if (layar == null || layar.isEmpty || layar == beranda) return null;
  if (tersedia.isEmpty) return null;
  if (!sebelumnya.contains(layar)) return null;
  return tersedia.contains(layar) ? null : beranda;
}
