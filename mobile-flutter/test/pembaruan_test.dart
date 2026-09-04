import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/features/update/data/datasources/github_release_source.dart';
import 'package:tuleh_pos/features/update/data/datasources/update_remote_datasource.dart';
import 'package:tuleh_pos/features/update/domain/entities/app_version_info.dart';
import 'package:tuleh_pos/features/update/domain/sumber_apk.dart';
import 'package:tuleh_pos/features/update/domain/versi.dart';

/// Auto-update aplikasi Flutter.
///
/// Kasus nyata yang memicu perbaikan ini: pengguna memasang APK 1.4.0, lalu
/// 2.0.0 terbit di GitHub, tetapi aplikasi tidak pernah menawarkan pembaruan
/// karena server `/app/versi` hanya mengenal versi aplikasi Android lama.

List<Map<String, dynamic>> _rilis() => [
  {
    'tag_name': 'v0.9.12',
    'draft': false,
    'prerelease': false,
    'assets': [
      {'name': 'Tuleh-Setup-0.9.12.exe', 'size': 90000000, 'browser_download_url': 'https://x/exe'},
      {'name': 'Tuleh-0.9.12-android.apk', 'size': 12000000, 'browser_download_url': 'https://x/cap.apk'},
    ],
  },
  {
    'tag_name': 'flutter-v2.0.0',
    'draft': false,
    'prerelease': false,
    'body': '## Navigasi Material 3\n- Bilah bawah\n- Dasbor beranda\n',
    'assets': [
      {'name': 'Tuleh-2.0.0-arm64-v8a.apk', 'size': 20249504, 'browser_download_url': 'https://github.com/dedeez14/tuleh/releases/download/flutter-v2.0.0/Tuleh-2.0.0-arm64-v8a.apk'},
      {'name': 'Tuleh-2.0.0-armeabi-v7a.apk', 'size': 17000000, 'browser_download_url': 'https://github.com/dedeez14/tuleh/releases/download/flutter-v2.0.0/Tuleh-2.0.0-armeabi-v7a.apk'},
      {'name': 'Tuleh-2.0.0-x86_64.apk', 'size': 21000000, 'browser_download_url': 'https://github.com/dedeez14/tuleh/releases/download/flutter-v2.0.0/Tuleh-2.0.0-x86_64.apk'},
    ],
  },
  {
    'tag_name': 'flutter-v1.4.0',
    'draft': false,
    'prerelease': false,
    'assets': [
      {'name': 'Tuleh-1.4.0-arm64-v8a.apk', 'size': 20117444, 'browser_download_url': 'https://x/1.4.0.apk'},
    ],
  },
  {
    'tag_name': 'flutter-v3.0.0',
    'draft': false,
    'prerelease': true, // pra-rilis tidak boleh ditawarkan
    'assets': [
      {'name': 'Tuleh-3.0.0-arm64-v8a.apk', 'size': 1, 'browser_download_url': 'https://x/3.apk'},
    ],
  },
];

void main() {
  group('Versi', () {
    test('parse berbagai bentuk tag', () {
      expect(Versi.parse('2.0.0'), const Versi(2, 0, 0));
      expect(Versi.parse('v1.4.0'), const Versi(1, 4, 0));
      expect(Versi.parse('flutter-v2.10.3'), const Versi(2, 10, 3));
      expect(Versi.parse('1.2.0+3'), const Versi(1, 2, 0));
      expect(Versi.parse('abc'), isNull);
      expect(Versi.parse(null), isNull);
    });

    test('membandingkan angka, bukan string ("0.9.10" > "0.9.9")', () {
      expect(Versi.parse('0.9.10')! > Versi.parse('0.9.9')!, isTrue);
      expect(Versi.parse('2.0.0')! > Versi.parse('1.4.0')!, isTrue);
      expect(Versi.parse('1.4.0')! < Versi.parse('1.10.0')!, isTrue);
      expect(Versi.parse('1.4.0') == Versi.parse('1.4.0'), isTrue);
    });
  });

  group('GitHub Releases', () {
    test('1.4.0 → menawarkan 2.0.0 dengan APK arm64 (kasus yang gagal)', () {
      final info = GithubReleaseSource.pilih(
        _rilis(),
        const Versi(1, 4, 0),
        abiPerangkat: ['arm64-v8a', 'armeabi-v7a', 'armeabi'],
      );
      expect(info, isNotNull);
      expect(info!.updateTersedia, isTrue);
      expect(info.wajib, isFalse); // GitHub tak berwenang memaksa
      expect(info.versiTerbaru, '2.0.0');
      expect(info.androidNama, 'Tuleh-2.0.0-arm64-v8a.apk');
      expect(info.androidUrl, startsWith('https://github.com/'));
      expect(info.hasAndroidDownload, isTrue);
      expect(info.ukuran, 20249504);
      expect(info.catatan, contains('Navigasi Material 3'));
    });

    test('sudah 2.0.0 → tidak ada tawaran; pra-rilis 3.0.0 diabaikan', () {
      expect(
        GithubReleaseSource.pilih(_rilis(), const Versi(2, 0, 0), abiPerangkat: ['arm64-v8a']),
        isNull,
      );
    });

    test('perangkat 32-bit mendapat APK armeabi-v7a, bukan arm64', () {
      final info = GithubReleaseSource.pilih(
        _rilis(),
        const Versi(1, 0, 0),
        abiPerangkat: ['armeabi-v7a', 'armeabi'],
      );
      expect(info!.androidNama, 'Tuleh-2.0.0-armeabi-v7a.apk');
    });

    test('ABI tak terbaca → jatuh ke arm64 (mayoritas Android 10+)', () {
      final info = GithubReleaseSource.pilih(_rilis(), const Versi(1, 0, 0), abiPerangkat: const []);
      expect(info!.androidNama, contains('arm64'));
    });

    test('tag desktop v0.9.12 tidak pernah dianggap rilis Flutter', () {
      // Aplikasi Flutter 0.5.0 (lebih rendah dari 0.9.12) — tetap harus dapat
      // flutter-v2.0.0, bukan APK Capacitor dari tag v0.9.12.
      final info = GithubReleaseSource.pilih(_rilis(), const Versi(0, 5, 0), abiPerangkat: ['arm64-v8a']);
      expect(info!.versiTerbaru, '2.0.0');
      expect(info.androidNama, isNot(contains('android.apk')));
    });

    test('bentuk tak terduga → null, bukan crash', () {
      expect(GithubReleaseSource.pilih(['x', 1, null], const Versi(1, 0, 0), abiPerangkat: const []), isNull);
      expect(GithubReleaseSource.pilih(const [], const Versi(1, 0, 0), abiPerangkat: const []), isNull);
      expect(
        GithubReleaseSource.pilih([{'tag_name': 'flutter-v9.9.9', 'assets': 'bukan list'}], const Versi(1, 0, 0), abiPerangkat: const []),
        isNull,
      );
    });
  });

  group('urutan sumber', () {
    Dio dioPalsu(Map<String, dynamic> balasan) {
      final dio = Dio(BaseOptions(validateStatus: (_) => true));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) => h.resolve(
            Response(requestOptions: o, statusCode: 200, data: balasan),
          ),
        ),
      );
      return dio;
    }

    test('server menjawab "tidak ada" → GitHub dipakai', () async {
      final github = GithubReleaseSource(dio: dioPalsu({}));
      // dioPalsu untuk GitHub membalas Map (bukan List) → dianggap gagal → null.
      // Jadi gunakan sumber yang membalas daftar rilis sungguhan:
      final githubOk = GithubReleaseSource(
        dio: Dio(BaseOptions(validateStatus: (_) => true))
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (o, h) => h.resolve(
                Response(requestOptions: o, statusCode: 200, data: _rilis()),
              ),
            ),
          ),
      );
      final ds = UpdateRemoteDataSource(
        dioPalsu({'success': true, 'data': {'wajib': false, 'update_tersedia': false}}),
        github: githubOk,
      );
      final info = await ds.cek('1.4.0', abiPerangkat: ['arm64-v8a']);
      expect(info.updateTersedia, isTrue);
      expect(info.versiTerbaru, '2.0.0');
      expect(github, isNotNull);
    });

    test('server menawarkan sendiri → server menang (termasuk wajib)', () async {
      final ds = UpdateRemoteDataSource(
        dioPalsu({
          'success': true,
          'data': {
            'wajib': true,
            'update_tersedia': true,
            'versi_terbaru': '9.9.9',
            'unduhan': {'android': {'url': 'https://server/apk', 'nama': 'x.apk', 'ukuran': 1}},
          },
        }),
        github: GithubReleaseSource(dio: dioPalsu({})),
      );
      final info = await ds.cek('1.4.0');
      expect(info.wajib, isTrue);
      expect(info.versiTerbaru, '9.9.9');
    });

    test('server & GitHub gagal → tidak ada pembaruan, tidak melempar', () async {
      final ds = UpdateRemoteDataSource(
        dioPalsu({'success': false}),
        github: GithubReleaseSource(dio: dioPalsu({'message': 'rate limited'})),
      );
      final info = await ds.cek('1.4.0');
      expect(info.updateTersedia, isFalse);
      expect(info.wajib, isFalse);
    });
  });

  group('sumber APK (kebijakan yang sama dengan MainActivity.kt)', () {
    // Kasus nyata 4 Sep 2026: banner menawarkan 2.2.0 dari GitHub, tetapi
    // tombol unduh gagal "URL unduhan tidak valid / host tidak diizinkan"
    // karena native hanya mengizinkan tatreport.com.
    test('aset Release GitHub repo ini diizinkan', () {
      expect(
        SumberApk.diizinkan(
          'https://github.com/dedeez14/tuleh/releases/download/flutter-v2.2.0/Tuleh-2.2.0-arm64-v8a.apk',
        ),
        isTrue,
      );
      expect(
        SumberApk.diizinkan('https://WWW.GitHub.com/dedeez14/tuleh/releases/download/x/y.apk'),
        isTrue,
      );
    });

    test('server MOVERA & subdomainnya diizinkan', () {
      expect(SumberApk.diizinkan('https://pos.tatreport.com/unduh/Tuleh-0.9.12-android.apk'), isTrue);
      expect(SumberApk.diizinkan('https://tatreport.com/x.apk'), isTrue);
    });

    test('ditolak: http, host lain, repo lain, host mirip', () {
      expect(SumberApk.diizinkan('http://github.com/dedeez14/tuleh/releases/download/x/y.apk'), isFalse);
      expect(SumberApk.diizinkan('https://github.com/orang-lain/tuleh/releases/download/x/y.apk'), isFalse);
      expect(SumberApk.diizinkan('https://github.com/dedeez14/tuleh/archive/main.zip'), isFalse);
      expect(SumberApk.diizinkan('https://evil-tatreport.com/x.apk'), isFalse);
      expect(SumberApk.diizinkan('https://tatreport.com.evil.net/x.apk'), isFalse);
      expect(SumberApk.diizinkan('https://objects.githubusercontent.com/x.apk'), isFalse);
      expect(SumberApk.diizinkan(null), isFalse);
      expect(SumberApk.diizinkan('bukan url'), isFalse);
    });

    test('pilihan rilis GitHub hanya memuat aset dengan URL yang diizinkan', () {
      final rilis = [
        {
          'tag_name': 'flutter-v9.0.0',
          'assets': [
            {'name': 'Tuleh-9.0.0-arm64-v8a.apk', 'size': 1, 'browser_download_url': 'https://cdn-lain.example/arm64.apk'},
            {'name': 'Tuleh-9.0.0-armeabi-v7a.apk', 'size': 2, 'browser_download_url': 'https://github.com/dedeez14/tuleh/releases/download/flutter-v9.0.0/Tuleh-9.0.0-armeabi-v7a.apk'},
          ],
        },
      ];
      final info = GithubReleaseSource.pilih(rilis, const Versi(1, 0, 0), abiPerangkat: ['arm64-v8a']);
      // arm64 ada tetapi URL-nya tak diizinkan → jatuh ke aset lain yang sah.
      expect(info!.androidNama, 'Tuleh-9.0.0-armeabi-v7a.apk');
      expect(info.hasAndroidDownload, isTrue);
    });

    test('info dari server dengan URL host asing → tidak ditawarkan unduh dalam-app', () {
      final info = AppVersionInfo.fromJson({
        'wajib': false,
        'update_tersedia': true,
        'versi_terbaru': '9.9.9',
        'unduhan': {'android': {'url': 'https://cdn-lain.example/x.apk', 'nama': 'x.apk'}},
      });
      expect(info.updateTersedia, isTrue);
      expect(info.hasAndroidDownload, isFalse);
    });
  });
}
