/// Entitas toko (outlet) — POS Tuléh mendukung multi-toko per tenant.
///
/// Kelas biasa (bukan freezed): entitas ini hanya dibaca — tak ada `copyWith`
/// di aplikasi — dan [kode] perlu ditambahkan tanpa menjalankan build_runner.
class Toko {
  const Toko({
    required this.id,
    required this.nama,
    this.kode,
    this.bidangUsaha,
    this.kategori,
  });

  /// Id terenkripsi dari server. **Bukan penanda tetap**: `encrypt_id`
  /// (Crypt::encryptString) memakai IV acak, jadi toko yang sama bisa muncul
  /// dengan id berbeda di `/tokos` dan di `meta.sesi_toko` amplop 409. Sah
  /// dipakai memanggil server, TIDAK sah dipakai membandingkan dua toko.
  final String id;

  final String nama;

  /// Kode toko yang stabil dari server (mis. `TK-001`) — satu-satunya penanda
  /// yang bisa dibandingkan antar-endpoint. null = server belum mengirimnya.
  final String? kode;

  final String? bidangUsaha;
  final String? kategori;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Toko &&
          other.id == id &&
          other.nama == nama &&
          other.kode == kode &&
          other.bidangUsaha == bidangUsaha &&
          other.kategori == kategori;

  @override
  int get hashCode => Object.hash(id, nama, kode, bidangUsaha, kategori);

  @override
  String toString() => 'Toko(id: $id, nama: $nama, kode: $kode)';
}
