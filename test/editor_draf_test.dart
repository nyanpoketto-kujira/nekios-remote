import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nekios_remote/domain/editor_jadwal.dart';
import 'package:nekios_remote/layanan/penyimpanan_draf.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> muatFixture() {
  final teks = File('test/fixtures/jadwal-sekolah.json').readAsStringSync();
  return jsonDecode(teks) as Map<String, dynamic>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PenyimpananDrafEditor penyimpanan;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    penyimpanan = PenyimpananDrafEditor(await SharedPreferences.getInstance());
  });

  test('round-trip: draf tersimpan & termuat kembali persis', () async {
    final editor = DokumenEditor.dariDokumen(
      muatFixture(),
      labelSumber: 'Fixture uji',
    );
    editor.assignSlot(0, 1, kodeMapel: 'KK', kg: 3);
    editor.kosongkanSlot(1, 0);
    editor.master.tambahGuru(40, 'Guru Baru, S.Pd.');
    editor.master.aturRelasiGuru(40, {'KK', 'MTK'});
    editor.pilihKelas('XI-TKJ-A');
    editor.assignSlot(2, 0, kodeMapel: 'MTK', kg: 40);

    await penyimpanan.simpan(editor, sekarang: DateTime(2026, 11, 18, 10, 30));

    final indeks = penyimpanan.daftarDraf();
    expect(indeks.length, 1);
    expect(indeks.first.kelasId, 'XI-TKJ-A');
    expect(indeks.first.labelSumber, 'Fixture uji');

    final termuat = penyimpanan.ambil('XI-TKJ-A');
    expect(termuat, isNotNull);
    expect(termuat!.kelasAktif, 'XI-TKJ-A');
    expect(termuat.labelSumber, 'Fixture uji');
    // Master data & relasi ikut pulih.
    expect(termuat.master.guruDariKg(40)?.nama, 'Guru Baru, S.Pd.');
    expect(termuat.master.mapelUntukGuru(40), {'KK', 'MTK'});
    // Dokumen rakitan kedua sesi identik byte-per-byte.
    expect(
      jsonEncode(termuat.rakitDokumen()),
      jsonEncode(editor.rakitDokumen()),
    );
  });

  test(
    'ambil kelas tanpa draf menghasilkan null; hapus membersihkan',
    () async {
      expect(penyimpanan.ambil('X-TKJ-A'), isNull);
      final editor = DokumenEditor.dariDokumen(
        muatFixture(),
        labelSumber: 'Fixture uji',
      );
      await penyimpanan.simpan(editor);
      expect(penyimpanan.daftarDraf().length, 1);
      await penyimpanan.hapus('X-TKJ-A');
      expect(penyimpanan.daftarDraf(), isEmpty);
      expect(penyimpanan.ambil('X-TKJ-A'), isNull);
    },
  );

  test('serialisasi editor: toJson → dariJsonDraf mempertahankan entri', () {
    final editor = DokumenEditor.dariDokumen(
      muatFixture(),
      labelSumber: 'Fixture uji',
    );
    editor.assignRentang(
      0,
      1,
      kodeMapel: 'KK',
      kg: 10,
      jumlahJam: 3,
      izinkanTimpa: true,
    );
    final pulih = DokumenEditor.dariJsonDraf(
      jsonDecode(jsonEncode(editor.toJson())) as Map<String, dynamic>,
    );
    expect(pulih.entriAktif(0, 2), const EntriSlot(kodeMapel: 'KK', kg: 10));
    expect(jsonEncode(pulih.rakitDokumen()), jsonEncode(editor.rakitDokumen()));
  });
}
