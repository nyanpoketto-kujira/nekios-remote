import 'package:flutter/material.dart';

/// Tema Material You nekios-remote.
///
/// Seed SAMA PERSIS dengan masjid-you & nekios-school (0xFF006A60,
/// hijau emerald/teal Nekios) — satu ekosistem, satu identitas warna.
/// Semua warna UI wajib diambil dari peran `ColorScheme` (primary,
/// surfaceContainer*, onSurface, dst.); tidak ada hex hardcode lain
/// di lapisan UI.
const Color kSeedNekios = Color(0xFF006A60);

ThemeData temaNekios(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: kSeedNekios,
    brightness: brightness,
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
  );
}
