import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/features/demo/data/demo_engine.dart';

/// Mode Demo Flutter — mesin menjawab seluruh permintaan API di perangkat.
/// Test menjaga bentuk balasan tetap cocok dengan yang dibaca tiap datasource
/// (mis. /produk List telanjang, /bills {tables}, /laporan/penjualan-harian
/// {rows}), karena ketidakcocokan bentuk membuat layar kosong tanpa error.

void main() {
  late DemoEngine engine;

  setUp(() => engine = DemoEngine());

  DemoResponse get(String path, {Map<String, dynamic> query = const {}}) =>
      engine.handle(method: 'GET', path: path, query: query);

  DemoResponse post(String path, {Map<String, dynamic> query = const {}, dynamic body}) =>
      engine.handle(method: 'POST', path: path, query: query, body: body);

  dynamic dataOf(DemoResponse r) => r.body['data'];

  group('auth & toko', () {
    test('/auth/me memberi pengguna demo + perusahaan', () {
      final r = get('/auth/me');
      expect(r.status, 200);
      expect(r.body['success'], true);
      final d = dataOf(r) as Map;
      expect((d['user'] as Map)['name'], 'Kasir Demo');
      expect(d['pos_role'], 'OWNER');
      expect((d['company'] as Map)['nama'], isNotEmpty);
    });

    test('/auth/login mengembalikan token non-kosong (syarat datasource)', () {
      final d = dataOf(post('/auth/login', body: {'login': 'a', 'password': 'b'})) as Map;
      expect(d['token'], isA<String>());
      expect((d['token'] as String).isNotEmpty, isTrue);
    });

    test('/tokos = List telanjang berisi enam toko contoh', () {
      final d = dataOf(get('/tokos'));
      expect(d, isA<List>());
      expect((d as List).length, 6);
      final kode = [for (final t in d) (t['bidang_usaha'] as Map)['code']];
      expect(kode, containsAll(['minimarket', 'bakso', 'laundry', 'bengkel', 'doorsmeer', 'salon']));
    });

    test('manifest tiap toko punya lifecycle & stasiun yang sah', () {
      for (final id in ['TOKO-1', 'TOKO-2', 'TOKO-3', 'TOKO-4', 'TOKO-5', 'TOKO-6']) {
        final d = dataOf(get('/tokos/$id/manifest')) as Map;
        final states = (d['lifecycle'] as Map)['states'] as List;
        expect(states, isNotEmpty, reason: '$id punya tahapan');
        expect(states.last, 'SELESAI', reason: '$id berakhir di SELESAI');
        expect(d['station_types'], isNotEmpty);
        expect((d['menus'] as List).first['route_key'], 'dashboard');
      }
    });

    test('toko bertahap punya minimal dua tahap agar papan pesanan muncul', () {
      for (final id in ['TOKO-2', 'TOKO-3', 'TOKO-4', 'TOKO-5', 'TOKO-6']) {
        final d = dataOf(get('/tokos/$id/manifest')) as Map;
        expect(((d['lifecycle'] as Map)['states'] as List).length, greaterThanOrEqualTo(2));
      }
      final retail = dataOf(get('/tokos/TOKO-1/manifest')) as Map;
      expect(((retail['lifecycle'] as Map)['states'] as List).length, 1);
    });

    test('manifest toko tak dikenal → 404, bukan 401/426', () {
      expect(get('/tokos/TOKO-99/manifest').status, 404);
    });
  });

  group('katalog', () {
    test('/produk = List telanjang & ikut toko aktif', () {
      final bakso = dataOf(get('/produk', query: {'toko_id': 'TOKO-2'}));
      expect(bakso, isA<List>());
      expect((bakso as List).every((p) => '${p['id']}'.startsWith('BSO-')), isTrue);

      final bengkel = dataOf(get('/produk', query: {'toko_id': 'TOKO-4'})) as List;
      expect(bengkel.every((p) => '${p['id']}'.startsWith('BKL-')), isTrue);
    });

    test('pencarian q menyaring nama/kode/barcode', () {
      final r = dataOf(get('/produk', query: {'toko_id': 'TOKO-4', 'q': 'oli'})) as List;
      expect(r, isNotEmpty);
      expect(r.every((p) => '${p['nama']}'.toLowerCase().contains('oli')), isTrue);
    });

    test('jasa tanpa stok & tanpa harga beli; barang berstok punya keduanya', () {
      final rows = dataOf(get('/produk', query: {'toko_id': 'TOKO-4'})) as List;
      final jasa = rows.where((p) => p['tipe'] == 'JASA');
      final barang = rows.where((p) => p['tipe'] == 'PRODUK');
      expect(jasa, isNotEmpty);
      expect(barang, isNotEmpty);
      expect(jasa.every((p) => p['harga_beli'] == null && p['kelola_stok'] == false), isTrue);
      expect(barang.every((p) => p['harga_beli'] != null && p['kelola_stok'] == true), isTrue);
    });

    test('tambah produk masuk katalog toko itu (POST bukan pembacaan daftar)', () {
      const toko = {'toko_id': 'TOKO-1'};
      final awal = (dataOf(get('/produk', query: toko)) as List).length;

      final r = post('/produk', query: toko, body: {
        'nama': 'Kopi Sachet',
        'tipe': 'PRODUK',
        'harga_jual': 3000,
        'harga_beli': 2000,
      });
      expect(r.body['success'], true);
      expect(dataOf(r), isA<Map>()); // objek produk, bukan daftar

      final rows = dataOf(get('/produk', query: toko)) as List;
      expect(rows.length, awal + 1);
      final baru = rows.firstWhere((p) => p['nama'] == 'Kopi Sachet');
      expect(baru['kelola_stok'], true);
      expect(baru['harga_jual'], 3000);

      // Toko lain tidak ikut kebagian.
      final lain = dataOf(get('/produk', query: {'toko_id': 'TOKO-2'})) as List;
      expect(lain.any((p) => p['nama'] == 'Kopi Sachet'), isFalse);
    });

    test('tambah jasa tidak mengelola stok; nama kosong ditolak', () {
      const toko = {'toko_id': 'TOKO-6'};
      final d = dataOf(post('/produk', query: toko, body: {
        'nama': 'Pijat Kepala',
        'tipe': 'JASA',
        'harga_jual': 30000,
      })) as Map;
      expect(d['tipe'], 'JASA');
      expect(d['kelola_stok'], false);
      expect(d['harga_beli'], isNull);

      expect(post('/produk', query: toko, body: {'nama': '  '}).status, 422);
      expect(
        post('/produk', query: toko, body: {'nama': 'X', 'harga_jual': 0}).status,
        422,
      );
    });

    test('ubah produk mengganti harga & nama', () {
      const toko = {'toko_id': 'TOKO-1'};
      final p = (dataOf(get('/produk', query: toko)) as List).first;
      final r = engine.handle(
        method: 'PATCH',
        path: '/produk/${p['id']}',
        query: toko,
        body: {'nama': 'Nama Baru', 'harga_jual': 9999},
      );
      expect(r.body['success'], true);

      final sesudah = (dataOf(get('/produk', query: toko)) as List)
          .firstWhere((x) => x['id'] == p['id']);
      expect(sesudah['nama'], 'Nama Baru');
      expect(sesudah['harga_jual'], 9999);
    });

    test('setiap item punya id, nama, harga_jual (wajib bagi kasir)', () {
      for (final id in ['TOKO-1', 'TOKO-2', 'TOKO-6']) {
        for (final p in dataOf(get('/produk', query: {'toko_id': id})) as List) {
          expect('${p['id']}'.isNotEmpty, isTrue);
          expect('${p['nama']}'.isNotEmpty, isTrue);
          expect(p['harga_jual'], isA<num>());
        }
      }
    });
  });

  group('sesi kasir', () {
    test('/sesi/aktif memenuhi parser Sesi DAN SesiRekap sekaligus', () {
      final d = dataOf(get('/sesi/aktif', query: {'toko_id': 'TOKO-1'})) as Map;
      // Parser Sesi (gating checkout) butuh id + waktu buka.
      expect('${d['id']}'.isNotEmpty, isTrue);
      expect(d['waktu_buka'], isA<String>());
      // Parser SesiRekap butuh set kunci lengkap.
      for (final k in [
        'nomor',
        'status',
        'kasir',
        'kas_awal',
        'total_tunai',
        'total_transfer',
        'total_qris',
        'total_penjualan',
        'jumlah_transaksi',
        'kas_akhir_sistem',
      ]) {
        expect(d[k], isNotNull, reason: 'kunci $k ada');
      }
      expect(d['status'], 'BUKA');
    });

    test('/sesi memuat sesi BUKA (dipakai mencari id untuk tutup)', () {
      final rows = dataOf(get('/sesi', query: {'toko_id': 'TOKO-1'})) as List;
      final buka = rows.where((s) => s['status'] == 'BUKA');
      expect(buka.length, 1);
      expect('${buka.first['id']}'.isNotEmpty, isTrue);
    });

    test('/gudang memberi id untuk buka sesi', () {
      final rows = dataOf(get('/gudang')) as List;
      expect(rows, isNotEmpty);
      expect(rows.first['id'], isNotNull);
    });

    test('tutup lalu buka sesi: status & selisih terhitung', () {
      const toko = {'toko_id': 'TOKO-1'};
      final id = (dataOf(get('/sesi/aktif', query: toko)) as Map)['id'];
      final sistem = (dataOf(get('/sesi/aktif', query: toko)) as Map)['kas_akhir_sistem'] as num;

      final tutup = post('/sesi/$id/tutup', query: toko, body: {'kas_akhir_fisik': sistem + 5000});
      expect(tutup.body['success'], true);
      expect(dataOf(get('/sesi/aktif', query: toko)), isNull);

      final ditutup = (dataOf(get('/sesi', query: toko)) as List)
          .firstWhere((s) => s['id'] == id);
      expect(ditutup['status'], 'TUTUP');
      expect(ditutup['selisih'], 5000);

      expect(post('/sesi/buka', query: toko, body: {'kas_awal': 200000}).body['success'], true);
      final baru = dataOf(get('/sesi/aktif', query: toko)) as Map;
      expect(baru['kas_awal'], 200000);
    });
  });

  group('kasir / checkout', () {
    test('checkout menghasilkan struk; kembalian berupa angka, bukan teks', () {
      const toko = {'toko_id': 'TOKO-1'};
      final p = (dataOf(get('/produk', query: toko)) as List).first;
      final r = post('/transaksi/checkout', query: toko, body: {
        'items': [
          {'id_produk': p['id'], 'kuantitas': 2, 'harga': p['harga_jual']},
        ],
        'tipe_pembayaran': 'TUNAI',
        'dibayar': 500000,
      });
      expect(r.body['success'], true);
      final d = dataOf(r) as Map;
      expect('${d['nomor']}'.isNotEmpty, isTrue);
      expect(d['kembalian'], isA<num>()); // datasource tidak mem-parse string
      expect(d['grand_total'], (p['harga_jual'] as num) * 2);
    });

    test('barang berstok berkurang saat terjual, jasa tidak', () {
      const toko = {'toko_id': 'TOKO-4'};
      final rows = dataOf(get('/produk', query: toko)) as List;
      final oli = rows.firstWhere((p) => p['kode'] == 'OLI-001');
      final jasa = rows.firstWhere((p) => p['kode'] == 'JSV-001');
      final stokAwal = oli['stok'] as num;

      post('/transaksi/checkout', query: toko, body: {
        'items': [
          {'id_produk': oli['id'], 'kuantitas': 2, 'harga': oli['harga_jual']},
          {'id_produk': jasa['id'], 'kuantitas': 1, 'harga': jasa['harga_jual']},
        ],
        'tipe_pembayaran': 'TUNAI',
        'dibayar': 500000,
      });

      final sesudah = dataOf(get('/produk', query: toko)) as List;
      expect(sesudah.firstWhere((p) => p['kode'] == 'OLI-001')['stok'], stokAwal - 2);
      expect(sesudah.firstWhere((p) => p['kode'] == 'JSV-001')['stok'], 0);
    });

    test('toko bertahap: checkout menerbitkan pesanan bernomor antrian', () {
      const toko = {'toko_id': 'TOKO-5'};
      final p = (dataOf(get('/produk', query: toko)) as List).first;
      final d = dataOf(post('/transaksi/checkout', query: toko, body: {
        'items': [
          {'id_produk': p['id'], 'kuantitas': 1, 'harga': p['harga_jual']},
        ],
        'tipe_pembayaran': 'QRIS',
        'dibayar': p['harga_jual'],
      })) as Map;
      expect(d['no_antrian'], matches(RegExp(r'^D-\d{3}$')));

      final orders = dataOf(get('/orders', query: toko)) as List;
      expect(orders.any((o) => o['no_antrian'] == d['no_antrian']), isTrue);
    });

    test('minimarket tidak menerbitkan pesanan (bayar = selesai)', () {
      const toko = {'toko_id': 'TOKO-1'};
      final p = (dataOf(get('/produk', query: toko)) as List).first;
      final d = dataOf(post('/transaksi/checkout', query: toko, body: {
        'items': [
          {'id_produk': p['id'], 'kuantitas': 1, 'harga': p['harga_jual']},
        ],
        'tipe_pembayaran': 'TUNAI',
        'dibayar': 100000,
      })) as Map;
      expect(d.containsKey('no_antrian'), isFalse);
    });

    test('keranjang kosong & uang kurang ditolak dengan pesan', () {
      const toko = {'toko_id': 'TOKO-1'};
      final kosong = post('/transaksi/checkout', query: toko, body: {'items': []});
      expect(kosong.status, 422);
      expect(kosong.body['message'], contains('kosong'));

      final p = (dataOf(get('/produk', query: toko)) as List).first;
      final kurang = post('/transaksi/checkout', query: toko, body: {
        'items': [
          {'id_produk': p['id'], 'kuantitas': 1, 'harga': p['harga_jual']},
        ],
        'tipe_pembayaran': 'TUNAI',
        'dibayar': 1,
      });
      expect(kurang.status, 422);
    });
  });

  group('riwayat & laporan', () {
    test('/transaksi = List telanjang milik toko aktif', () {
      final rows = dataOf(get('/transaksi', query: {'toko_id': 'TOKO-2'}));
      expect(rows, isA<List>());
      expect(rows, isNotEmpty);
      for (final t in rows as List) {
        expect('${t['id']}'.isNotEmpty, isTrue);
        expect(t['grand_total'], isA<num>());
        expect(DateTime.tryParse('${t['tanggal']}'), isNotNull);
      }
    });

    test('detail transaksi memuat item dengan subtotal eksplisit', () {
      const toko = {'toko_id': 'TOKO-2'};
      final id = (dataOf(get('/transaksi', query: toko)) as List).first['id'];
      final d = dataOf(get('/transaksi/$id', query: toko)) as Map;
      expect(d['items'], isA<List>());
      for (final i in d['items'] as List) {
        expect(i['subtotal'], isA<num>()); // parser detail tak punya fallback
        expect(i['kuantitas'], isA<num>());
      }
    });

    test('/laporan/keuangan memuat lima kunci ringkasan', () {
      final d = dataOf(get('/laporan/keuangan', query: {'toko_id': 'TOKO-1'})) as Map;
      expect(d['bulan'], matches(RegExp(r'^\d{4}-\d{2}$')));
      expect(d['omset'], isA<num>());
      expect(d['jumlah_transaksi'], isA<num>());
      expect(d['pengeluaran'], isA<num>());
      expect(d['laba'], (d['omset'] as num) - (d['pengeluaran'] as num));
    });

    test('/laporan/penjualan-harian dibungkus {rows}, bukan List telanjang', () {
      final d = dataOf(get('/laporan/penjualan-harian', query: {'toko_id': 'TOKO-1'}));
      expect(d, isA<Map>());
      final rows = (d as Map)['rows'] as List;
      expect(rows.length, 8);
      expect(rows.first['total_omzet'], isA<num>()); // ejaan omzet, bukan omset
      expect(rows.first['tanggal'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    });

    test('/laporan/rekap-kasir memakai set kunci SesiRekap', () {
      final rows = dataOf(get('/laporan/rekap-kasir', query: {'toko_id': 'TOKO-1'})) as List;
      expect(rows, isNotEmpty);
      final tutup = rows.firstWhere((s) => s['status'] == 'TUTUP');
      expect(tutup['waktu_tutup'], isNotNull);
      expect(tutup['kas_akhir_fisik'], isA<num>());
      expect(tutup['selisih'], isA<num>());
    });

    test('/laporan/stok hanya memuat barang berstok', () {
      final rows = dataOf(get('/laporan/stok', query: {'toko_id': 'TOKO-4'})) as List;
      expect(rows, isNotEmpty);
      for (final r in rows) {
        expect('${r['kode']}'.isNotEmpty, isTrue);
        expect('${r['produk']}'.isNotEmpty, isTrue);
        expect(r['stok'], isA<num>());
      }
      expect(rows.any((r) => '${r['kode']}'.startsWith('JSV')), isFalse);
    });

    test('stok masuk menambah stok barang', () {
      const toko = {'toko_id': 'TOKO-4'};
      final oli = (dataOf(get('/produk', query: toko)) as List)
          .firstWhere((p) => p['kode'] == 'OLI-001');
      final awal = oli['stok'] as num;
      final r = post('/inventory/stok-masuk', query: toko, body: {
        'id_produk': oli['id'],
        'jumlah': 10,
      });
      expect(r.body['success'], true);
      final sesudah = (dataOf(get('/produk', query: toko)) as List)
          .firstWhere((p) => p['kode'] == 'OLI-001');
      expect(sesudah['stok'], awal + 10);
    });
  });

  group('papan pesanan', () {
    test('pesanan seed tersebar di tiap tahap & punya waktu ISO', () {
      for (final id in ['TOKO-3', 'TOKO-4', 'TOKO-5', 'TOKO-6']) {
        final rows = dataOf(get('/orders', query: {'toko_id': id})) as List;
        expect(rows, isNotEmpty, reason: '$id punya pesanan hidup');
        for (final o in rows) {
          expect(DateTime.tryParse('${o['created_at']}'), isNotNull);
          expect(o['total'], isA<num>());
          expect(o['items'], isA<List>());
        }
      }
    });

    test('daftar pesanan menyembunyikan tahap terminal', () {
      final rows = dataOf(get('/orders', query: {'toko_id': 'TOKO-6'})) as List;
      expect(rows.any((o) => o['stage'] == 'SELESAI'), isFalse);
    });

    test('saring per tahap', () {
      final rows = dataOf(
        get('/orders', query: {'toko_id': 'TOKO-6', 'stage': 'DILAYANI'}),
      ) as List;
      expect(rows, isNotEmpty);
      expect(rows.every((o) => o['stage'] == 'DILAYANI'), isTrue);
    });

    test('transisi maju urut; lompat tahap ditolak 409', () {
      const toko = {'toko_id': 'TOKO-5'};
      final o = (dataOf(get('/orders', query: toko)) as List)
          .firstWhere((x) => x['stage'] == 'ANTRIAN');
      final id = o['id'];

      expect(post('/orders/$id/transition', query: toko, body: {'to': 'FINISHING'}).status, 409);

      final maju = post('/orders/$id/transition', query: toko, body: {'to': 'PENCUCIAN'});
      expect(maju.body['success'], true);
      expect((dataOf(maju) as Map)['stage'], 'PENCUCIAN');
    });

    test('pelunasan lewat transisi menandai pesanan lunas', () {
      const toko = {'toko_id': 'TOKO-6'};
      final o = (dataOf(get('/orders', query: toko)) as List)
          .firstWhere((x) => x['stage'] == 'DILAYANI' && x['bayar'] == 'BELUM');
      final d = dataOf(post('/orders/${o['id']}/transition', query: toko, body: {
        'to': 'SELESAI',
        'tipe_pembayaran': 'TUNAI',
      })) as Map;
      expect(d['stage'], 'SELESAI');
      expect(d['bayar'], 'LUNAS');
    });
  });

  group('bon meja', () {
    const toko = {'toko_id': 'TOKO-2'};

    test('/bills dibungkus {tables} dan pax berupa angka', () {
      final d = dataOf(get('/bills', query: toko));
      expect(d, isA<Map>());
      final tables = (d as Map)['tables'] as List;
      expect(tables, isNotEmpty);
      final terisi = tables.where((t) => t['bill'] != null);
      expect(terisi, isNotEmpty);
      for (final t in terisi) {
        expect((t['bill'] as Map)['pax'], isA<num>()); // string diabaikan parser
        expect((t['bill'] as Map)['total'], isA<num>());
      }
      expect(tables.any((t) => t['bill'] == null), isTrue, reason: 'ada meja kosong');
    });

    test('buka bon di meja kosong, lalu meja tampak terisi', () {
      final kosong = ((dataOf(get('/bills', query: toko)) as Map)['tables'] as List)
          .firstWhere((t) => t['bill'] == null);
      final r = post('/bills', query: toko, body: {'meja_id': kosong['id'], 'pax': 4});
      expect(r.body['success'], true);

      final sesudah = ((dataOf(get('/bills', query: toko)) as Map)['tables'] as List)
          .firstWhere((t) => t['id'] == kosong['id']);
      expect(sesudah['bill'], isNotNull);
      expect((sesudah['bill'] as Map)['pax'], 4);
    });

    test('ronde menambah item bon dan menerbitkan tiket dapur berlabel meja', () {
      final bill = ((dataOf(get('/bills', query: toko)) as Map)['tables'] as List)
          .firstWhere((t) => t['bill'] != null)['bill'] as Map;
      final sebelum = (dataOf(get('/bills/${bill['id']}', query: toko)) as Map)['total'] as num;
      final p = (dataOf(get('/produk', query: toko)) as List).first;

      final r = post('/bills/${bill['id']}/rounds', query: toko, body: {
        'items': [
          {'id_produk': p['id'], 'kuantitas': 2},
        ],
      });
      expect(r.body['success'], true);

      final detail = dataOf(get('/bills/${bill['id']}', query: toko)) as Map;
      expect(detail['total'], sebelum + (p['harga_jual'] as num) * 2);
      expect(detail['pax'], isA<num>());

      final tiket = (dataOf(get('/orders', query: toko)) as List)
          .where((o) => o['meja'] == detail['label']);
      expect(tiket.length, greaterThanOrEqualTo(2), reason: 'ronde baru jadi tiket');
    });

    test('pelunasan bon membuat transaksi & mengosongkan meja', () {
      final tables = (dataOf(get('/bills', query: toko)) as Map)['tables'] as List;
      final meja = tables.firstWhere((t) => t['bill'] != null);
      final bill = meja['bill'] as Map;
      final jumlahTrx = (dataOf(get('/transaksi', query: toko)) as List).length;

      final r = post('/bills/${bill['id']}/settle', query: toko, body: {
        'tipe_pembayaran': 'TUNAI',
        'dibayar': bill['total'],
      });
      expect(r.body['success'], true);

      expect((dataOf(get('/transaksi', query: toko)) as List).length, jumlahTrx + 1);
      final sesudah = ((dataOf(get('/bills', query: toko)) as Map)['tables'] as List)
          .firstWhere((t) => t['id'] == meja['id']);
      expect(sesudah['bill'], isNull);
      expect(post('/bills/${bill['id']}/settle', query: toko, body: {}).status, 409);
    });
  });

  group('pengeluaran & pengaturan', () {
    test('tambah, saring per bulan, lalu hapus', () {
      const toko = {'toko_id': 'TOKO-1'};
      final bulan = DateTime.now().toIso8601String().substring(0, 7);
      final awal = (dataOf(get('/pengeluaran', query: {...toko, 'bulan': bulan})) as List).length;

      post('/pengeluaran', query: toko, body: {'keterangan': 'SEWA', 'nominal': 250000});
      var rows = dataOf(get('/pengeluaran', query: {...toko, 'bulan': bulan})) as List;
      expect(rows.length, awal + 1);
      final baru = rows.firstWhere((e) => e['keterangan'] == 'SEWA');
      expect(baru['nominal'], 250000);

      engine.handle(method: 'DELETE', path: '/pengeluaran/${baru['id']}', query: toko);
      rows = dataOf(get('/pengeluaran', query: {...toko, 'bulan': bulan})) as List;
      expect(rows.any((e) => e['keterangan'] == 'SEWA'), isFalse);

      final lain = dataOf(get('/pengeluaran', query: {...toko, 'bulan': '2001-01'})) as List;
      expect(lain, isEmpty);
    });

    test('profil usaha: struk.tampil_logo tersimpan sebagai bool', () {
      final awal = dataOf(get('/pengaturan/usaha')) as Map;
      expect((awal['struk'] as Map)['tampil_logo'], isA<bool>());

      engine.handle(method: 'PUT', path: '/pengaturan/usaha', query: {}, body: {
        'nama': 'Toko Baru',
        'alamat': null,
        'telepon': null,
        'email': null,
        'struk_footer': 'Sampai jumpa',
        'struk_tampil_logo': false,
      });
      final sesudah = dataOf(get('/pengaturan/usaha')) as Map;
      expect(sesudah['nama'], 'Toko Baru');
      expect((sesudah['struk'] as Map)['tampil_logo'], false);
      expect((sesudah['struk'] as Map)['footer'], 'Sampai jumpa');
    });

    test('/pelanggan List telanjang; penambahan mengembalikan id', () {
      expect(dataOf(get('/pelanggan')), isA<List>());
      final d = dataOf(post('/pelanggan', body: {'nama': 'Andi', 'no_whatsapp': '0812'})) as Map;
      expect('${d['id']}'.isNotEmpty, isTrue);
      expect(d['nama'], 'Andi');
      expect(d['telepon'], '0812');
      expect((dataOf(get('/pelanggan')) as List).any((c) => c['nama'] == 'Andi'), isTrue);
    });
  });

  group('keamanan balasan demo', () {
    test('tidak pernah 401 atau 426 (memicu sesi berakhir / wajib perbarui)', () {
      final jalur = [
        '/auth/me',
        '/tokos',
        '/tokos/TOKO-99/manifest',
        '/produk',
        '/entah-apa',
        '/transaksi/TIDAK-ADA',
        '/bills/TIDAK-ADA',
      ];
      for (final p in jalur) {
        final s = get(p).status;
        expect(s, isNot(401), reason: '$p tidak boleh 401');
        expect(s, isNot(426), reason: '$p tidak boleh 426');
      }
    });

    test('endpoint tak dikenal → 404 dengan pesan Indonesia', () {
      final r = get('/entah-apa');
      expect(r.status, 404);
      expect(r.body['success'], false);
      expect('${r.body['message']}', contains('Mode Demo'));
    });

    test('cek pembaruan tidak pernah menawarkan update di demo', () {
      final d = dataOf(get('/app/versi', query: {'versi': '1.0.0'})) as Map;
      expect(d['wajib'], false);
      expect(d['update_tersedia'], false);
    });

    test('mesin baru = data segar (demo direset tiap dimulai)', () {
      const toko = {'toko_id': 'TOKO-1'};
      final p = (dataOf(get('/produk', query: toko)) as List).first;
      final awal = p['stok'] as num;
      post('/transaksi/checkout', query: toko, body: {
        'items': [
          {'id_produk': p['id'], 'kuantitas': 1, 'harga': p['harga_jual']},
        ],
        'tipe_pembayaran': 'TUNAI',
        'dibayar': 100000,
      });

      final segar = DemoEngine();
      final p2 = (segar.handle(method: 'GET', path: '/produk', query: toko).body['data'] as List)
          .first;
      expect(p2['stok'], awal);
    });
  });
}
