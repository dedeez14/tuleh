import 'dart:io';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../domain/entities/struk.dart';
import 'struk_esc_pos.dart';

/// Printer thermal Bluetooth yang terpasang (sudah dipasangkan di setelan HP).
class PrinterTersimpan {
  const PrinterTersimpan({required this.nama, required this.mac});

  final String nama;
  final String mac;

  @override
  bool operator ==(Object other) =>
      other is PrinterTersimpan && other.mac == mac;

  @override
  int get hashCode => mac.hashCode;
}

/// Kegagalan cetak dengan pesan yang bisa langsung ditampilkan ke pengguna.
class PrinterException implements Exception {
  const PrinterException(this.pesan, {this.saran});

  final String pesan;

  /// Langkah yang bisa dilakukan pengguna untuk memperbaiki.
  final String? saran;

  @override
  String toString() => pesan;
}

/// Cetak struk ke printer thermal Bluetooth (ESC/POS).
///
/// Alur yang disengaja: printer harus SUDAH dipasangkan lewat setelan Bluetooth
/// Android. Aplikasi hanya menghubungkan dan mengirim data, tidak melakukan
/// penjodohan sendiri — cara ini paling andal untuk printer thermal murah yang
/// PIN-nya beragam, dan menghindari izin pemindaian yang membingungkan pengguna.
class PrinterService {
  const PrinterService();

  /// Minta izin Bluetooth secara "usaha terbaik".
  ///
  /// Sengaja TIDAK dijadikan penghalang: di Android 10/11 izin runtime
  /// BLUETOOTH_CONNECT/SCAN belum ada, sehingga permintaannya bisa membalas
  /// "ditolak" padahal Bluetooth tetap boleh dipakai. Yang menentukan adalah
  /// hasil pemanggilan Bluetooth-nya sendiri, bukan jawaban dialog izin.
  Future<bool> mintaIzin() async {
    if (!Platform.isAndroid) return true;
    try {
      final hasil = await [Permission.bluetoothConnect, Permission.bluetoothScan]
          .request();
      return hasil.values.every((s) => s.isGranted || s.isLimited);
    } catch (_) {
      // Perangkat lama: izin tidak dikenal → dianggap tidak menghalangi.
      return true;
    }
  }

  Future<bool> bluetoothMenyala() async {
    try {
      return await PrintBluetoothThermal.bluetoothEnabled;
    } catch (_) {
      return false;
    }
  }

  /// Daftar printer yang sudah dipasangkan di setelan Bluetooth HP.
  ///
  /// Hanya membaca perangkat TERPASANG, tidak memindai. Bedanya penting untuk
  /// Android 10/11: pemindaian di sana menuntut izin lokasi, sedangkan membaca
  /// daftar perangkat terpasang tidak.
  Future<List<PrinterTersimpan>> daftarPrinter() async {
    if (!await bluetoothMenyala()) {
      throw const PrinterException(
        'Bluetooth belum aktif.',
        saran: 'Nyalakan Bluetooth di HP, lalu coba lagi.',
      );
    }
    final diizinkan = await mintaIzin();
    try {
      final list = await PrintBluetoothThermal.pairedBluetooths;
      return [
        for (final b in list)
          PrinterTersimpan(
            nama: b.name.trim().isEmpty ? b.macAdress : b.name.trim(),
            mac: b.macAdress,
          ),
      ];
    } catch (e) {
      // Gagal SETELAH izin ditolak → hampir pasti soal izin (Android 12+).
      if (!diizinkan) {
        throw const PrinterException(
          'Izin Bluetooth ditolak.',
          saran: 'Aktifkan izin "Perangkat di sekitar" untuk Tuléh di '
              'Setelan → Aplikasi → Izin.',
        );
      }
      throw PrinterException('Gagal membaca daftar perangkat: $e');
    }
  }

  Future<bool> terhubung() async {
    try {
      return await PrintBluetoothThermal.connectionStatus;
    } catch (_) {
      return false;
    }
  }

  /// Sambungkan ke printer. Aman dipanggil berulang: bila sudah tersambung ke
  /// perangkat yang sama, sambungan dipakai ulang.
  Future<void> hubungkan(PrinterTersimpan printer) async {
    if (await terhubung()) return;
    await mintaIzin(); // usaha terbaik; Android 10/11 tidak memerlukannya
    final ok = await PrintBluetoothThermal.connect(
      macPrinterAddress: printer.mac,
    );
    if (!ok) {
      throw PrinterException(
        'Tidak bisa tersambung ke ${printer.nama}.',
        saran: 'Pastikan printer menyala, kertas terpasang, tidak sedang '
            'dipakai perangkat lain, dan izin Bluetooth aplikasi aktif.',
      );
    }
  }

  Future<void> putuskan() async {
    try {
      await PrintBluetoothThermal.disconnect;
    } catch (_) {
      // Diabaikan: memutus sambungan yang sudah putus bukan kegagalan.
    }
  }

  /// Cetak satu struk. Sambungan dibuka bila perlu, lalu ditutup kembali agar
  /// printer bebas dipakai aplikasi lain.
  Future<void> cetak(
    Struk struk, {
    required PrinterTersimpan printer,
    PaperSize lebar = PaperSize.mm58,
  }) async {
    await hubungkan(printer);
    final bytes = await StrukEscPos(lebar: lebar).bangun(struk);
    final ok = await PrintBluetoothThermal.writeBytes(bytes);
    if (!ok) {
      throw const PrinterException(
        'Data gagal dikirim ke printer.',
        saran: 'Coba matikan lalu nyalakan printer, kemudian cetak ulang.',
      );
    }
  }

  /// Struk contoh untuk menguji printer tanpa transaksi sungguhan.
  static Struk strukUji({String namaToko = 'Tuléh POS'}) => Struk(
    namaToko: namaToko,
    alamat: 'Uji cetak printer thermal',
    nomor: 'TES-0001',
    waktu: DateTime.now(),
    kasir: 'Uji Coba',
    baris: const [
      StrukBaris(nama: 'Contoh item satu', kuantitas: 2, harga: 15000),
      StrukBaris(
        nama: 'Contoh item dengan nama panjang sekali',
        kuantitas: 1,
        harga: 125000,
      ),
    ],
    total: 155000,
    metode: 'TUNAI',
    dibayar: 200000,
    kembalian: 45000,
    catatanKaki: 'Uji cetak berhasil',
    barcode: 'TES-0001',
  );
}
