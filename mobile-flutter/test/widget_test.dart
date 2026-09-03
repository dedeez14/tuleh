import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/theme/app_theme.dart';

void main() {
  test('AppTheme light & dark terbentuk tanpa error', () {
    final light = AppTheme.light();
    final dark = AppTheme.dark();
    expect(light.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark);
    expect(light.useMaterial3, isTrue);
  });
}
