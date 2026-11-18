import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../model/display_tersimpan.dart';

/// Penyimpanan lokal remote: daftar display tersimpan dan IP terakhir
/// yang dipakai (auto-save — keputusan terkunci: IP terakhir otomatis
/// tersimpan supaya menyambung ulang tinggal satu ketukan).
class PenyimpananDisplay {
  PenyimpananDisplay(this._prefs);

  final SharedPreferences _prefs;

  static const String kunciDaftar = 'remote.daftarDisplay.v1';
  static const String kunciIpTerakhir = 'remote.ipTerakhir.v1';

  static Future<PenyimpananDisplay> muat() async =>
      PenyimpananDisplay(await SharedPreferences.getInstance());

  /// Daftar display tersimpan; daftar rusak diabaikan jadi kosong.
  List<DisplayTersimpan> daftar() {
    final mentah = _prefs.getString(kunciDaftar);
    if (mentah == null) return [];
    try {
      final decoded = jsonDecode(mentah);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(DisplayTersimpan.fromJson)
          .toList();
    } on FormatException {
      return [];
    }
  }

  Future<void> simpanDaftar(List<DisplayTersimpan> daftar) => _prefs.setString(
        kunciDaftar,
        jsonEncode(daftar.map((d) => d.toJson()).toList()),
      );

  /// IP terakhir yang berhasil dipakai menyambung (auto-save).
  String? get ipTerakhir => _prefs.getString(kunciIpTerakhir);

  Future<void> simpanIpTerakhir(String ip) =>
      _prefs.setString(kunciIpTerakhir, ip);
}
