import 'package:flutter/material.dart';

/// Palet warna Tuléh — aksen mint (#7AE2CF) selaras aplikasi web/desktop.
/// Dipakai untuk membangun [ColorScheme] Material 3 (light & dark).
class AppColors {
  AppColors._();

  // Mint scale
  static const Color mint50 = Color(0xFFEAFBF6);
  static const Color mint100 = Color(0xFFCFF6EC);
  static const Color mint200 = Color(0xFFA7ECDC);
  static const Color mint300 = Color(0xFF86E6CF);
  static const Color mint400 = Color(0xFF7AE2CF); // aksen utama
  static const Color mint500 = Color(0xFF4FCDB7);
  static const Color mint600 = Color(0xFF37B8A4);
  static const Color mint700 = Color(0xFF17695D);
  static const Color mint800 = Color(0xFF0E4E45);
  static const Color mint900 = Color(0xFF08332C);

  // Netral
  static const Color ink = Color(0xFF14332C); // teks utama (light)
  static const Color ink2 = Color(0xFF4C675F); // teks sekunder
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceLight2 = Color(0xFFF7FCFA);
  static const Color bgLight = Color(0xFFF1F8F5);
  static const Color lineLight = Color(0xFFE1EDE8);

  // Dark
  static const Color bgDark = Color(0xFF071E1A);
  static const Color surfaceDark = Color(0xFF0F2E28);
  static const Color surfaceDark2 = Color(0xFF0C2822);
  static const Color lineDark = Color(0xFF1B4A41);
  static const Color inkDark = Color(0xFFEAFCF7);
  static const Color inkDark2 = Color(0xFFA9C9C1);

  // Semantik
  static const Color success = Color(0xFF16A34A);
  static const Color danger = Color(0xFFDC3545);
  static const Color warn = Color(0xFFD97706);
}
