import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/editor_jadwal.dart';

/// Info ringkas satu draf editor untuk daftar "Lanjutkan draf".
class InfoDraf {
  const InfoDraf({
    required this.kelasId,
    required this.labelSumber,
    required this.diubahPada,
  });

  final String kelasId;
  final String labelSumber;
  final DateTime diubahPada;
}

/// Penyimpanan draf Editor Jadwal (R2b) di shared_preferences.
///
/// Draf disimpan PER KELAS AKTIF (kunci `editor.draf.v1.<kelasId>`)
/// dan berisi seluruh sesi (dokumen asal + master data bersama +
/// entri semua kelas yang tersentuh), jadi melanjutkan draf satu
/// kelas mengembalikan sesi persis seperti terakhir ditinggalkan.
/// Indeks kecil (`editor.drafIndeks.v1`) memuat daftar draf yang
/// ada untuk layar awal editor.
class PenyimpananDrafEditor {
  PenyimpananDrafEditor(this._prefs);

  final SharedPreferences _prefs;

  static const String kunciIndeks = 'editor.drafIndeks.v1';
  static const String awalanKunciDraf = 'editor.draf.v1.';

  static Future<PenyimpananDrafEditor> muat() async =>
      PenyimpananDrafEditor(await SharedPreferences.getInstance());

  static String _kunciUntuk(String kelasId) => '$awalanKunciDraf$kelasId';

  /// Simpan sesi [editor] sebagai draf kelas aktifnya.
  Future<void> simpan(DokumenEditor editor, {DateTime? sekarang}) async {
    final waktu = sekarang ?? DateTime.now();
    await _prefs.setString(
      _kunciUntuk(editor.kelasAktif),
      jsonEncode(editor.toJson()),
    );
    final indeks =
        daftarDraf().where((d) => d.kelasId != editor.kelasAktif).toList()..add(
          InfoDraf(
            kelasId: editor.kelasAktif,
            labelSumber: editor.labelSumber,
            diubahPada: waktu,
          ),
        );
    indeks.sort((a, b) => b.diubahPada.compareTo(a.diubahPada));
    await _prefs.setString(
      kunciIndeks,
      jsonEncode([
        for (final d in indeks)
          {
            'kelasId': d.kelasId,
            'labelSumber': d.labelSumber,
            'diubahPada': d.diubahPada.toIso8601String(),
          },
      ]),
    );
  }

  /// Daftar draf yang tersimpan (terbaru dulu); indeks rusak
  /// diperlakukan sebagai tidak ada draf.
  List<InfoDraf> daftarDraf() {
    final mentah = _prefs.getString(kunciIndeks);
    if (mentah == null) return [];
    try {
      final decoded = jsonDecode(mentah);
      if (decoded is! List) return [];
      return decoded.whereType<Map<String, dynamic>>().map((m) {
        return InfoDraf(
          kelasId: m['kelasId'] as String,
          labelSumber: m['labelSumber'] as String? ?? 'Draf',
          diubahPada:
              DateTime.tryParse(m['diubahPada'] as String? ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0),
        );
      }).toList();
    } on FormatException {
      return [];
    }
  }

  /// Ambil sesi draf untuk [kelasId]; null bila tidak ada / rusak.
  DokumenEditor? ambil(String kelasId) {
    final mentah = _prefs.getString(_kunciUntuk(kelasId));
    if (mentah == null) return null;
    try {
      final decoded = jsonDecode(mentah);
      if (decoded is! Map<String, dynamic>) return null;
      return DokumenEditor.dariJsonDraf(decoded);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  /// Hapus draf satu kelas (isi + entri indeksnya).
  Future<void> hapus(String kelasId) async {
    await _prefs.remove(_kunciUntuk(kelasId));
    final indeks = daftarDraf().where((d) => d.kelasId != kelasId).toList();
    await _prefs.setString(
      kunciIndeks,
      jsonEncode([
        for (final d in indeks)
          {
            'kelasId': d.kelasId,
            'labelSumber': d.labelSumber,
            'diubahPada': d.diubahPada.toIso8601String(),
          },
      ]),
    );
  }
}
