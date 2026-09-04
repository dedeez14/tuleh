/// Perbandingan versi semantik "X.Y.Z" — SERVER-AUTO-UPDATE.md memperingatkan:
/// jangan bandingkan sebagai string ("0.9.10" < "0.9.9" bila string).
class Versi implements Comparable<Versi> {
  const Versi(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  /// Terima "2.0.0", "v2.0.0", "flutter-v2.0.0", "2.0.0+6". Null bila tak
  /// mengandung pola angka.angka.angka.
  static Versi? parse(String? teks) {
    if (teks == null) return null;
    final m = RegExp(r'(\d+)\.(\d+)\.(\d+)').firstMatch(teks);
    if (m == null) return null;
    return Versi(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
    );
  }

  @override
  int compareTo(Versi other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  bool operator >(Versi o) => compareTo(o) > 0;
  bool operator <(Versi o) => compareTo(o) < 0;

  @override
  bool operator ==(Object other) =>
      other is Versi && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}
