import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nekios_remote/domain/editor_jadwal.dart';
import 'package:nekios_remote/domain/validasi_jadwal.dart';

Map<String, dynamic> muatFixture() {
  final teks = File('test/fixtures/jadwal-sekolah.json').readAsStringSync();
  return jsonDecode(teks) as Map<String, dynamic>;
}

DokumenEditor editorBaru() =>
    DokumenEditor.dariDokumen(muatFixture(), labelSumber: 'Fixture uji');

void main() {
  group('muat dari dokumen', () {
    test('master data + templat terisi dari fixture SMKN 1 Ukui', () {
      final e = editorBaru();
      expect(e.master.guru.length, 36);
      expect(e.master.mapel.length, 15);
      expect(e.daftarKelas.length, 6);
      expect(e.kelasAktif, 'X-TKJ-A');
      expect(e.templatHari.length, 5);
      expect(e.templatHari[0].slots.length, 12);
      expect(e.templatHari[0].slots[0].adalahPelajaran, isFalse); // upacara
      expect(e.entriAktif(0, 1), const EntriSlot(kodeMapel: 'IPAS', kg: 7));
    });

    test('relasi disimpulkan dari pemakaian nyata (many-to-many)', () {
      final e = editorBaru();
      // KK diajar banyak guru (team-teaching alami di jadwal nyata).
      final pengajarKK = e.master.guruUntukMapel('KK').map((g) => g.kg).toSet();
      expect(pengajarKK.length, greaterThan(1));
      expect(pengajarKK, containsAll(<int>{3, 10}));
      // Satu guru mengajar banyak mapel.
      expect(
        e.master.mapelUntukGuru(3),
        containsAll(<String>{'KK', 'PEMINATAN'}),
      );
    });
  });

  group('master data', () {
    test('tambah guru: duplikat KG & nama kosong ditolak', () {
      final e = editorBaru();
      expect(e.master.tambahGuru(3, 'Guru Baru').sukses, isFalse);
      expect(e.master.tambahGuru(40, '  ').sukses, isFalse);
      expect(e.master.tambahGuru(40, 'Guru Baru, S.Pd.').sukses, isTrue);
      expect(e.master.guruDariKg(40)?.nama, 'Guru Baru, S.Pd.');
    });

    test('tambah mapel: kode ganda ditolak, warna wajib #RRGGBB', () {
      final e = editorBaru();
      expect(e.master.tambahMapel('KK', 'Duplikat', '#8FC48F').sukses, isFalse);
      expect(
        e.master.tambahMapel('BARU', 'Mapel Baru', 'hijau').sukses,
        isFalse,
      );
      expect(
        e.master.tambahMapel('BARU', 'Mapel Baru', '#8FC48F').sukses,
        isTrue,
      );
    });

    test('relasi bisa diatur dua arah & mendukung team-teaching', () {
      final e = editorBaru();
      e.master.aturRelasiMapel('MTK', {24});
      expect(e.master.guruUntukMapel('MTK').map((g) => g.kg), [24]);
      e.master.aturRelasiGuru(24, {'MTK', 'IPAS'});
      expect(e.master.mapelUntukGuru(24), {'MTK', 'IPAS'});
      expect(
        e.master.guruUntukMapel('IPAS').map((g) => g.kg),
        containsAll(<int>{7, 24}),
      );
    });

    test('hapus guru yang masih dipakai kelas LAIN ditolak jelas', () {
      final e = editorBaru(); // kelas aktif X-TKJ-A
      // KG 6 dipakai XII-TKJ-B (dan kelas lain) di fixture.
      final hasil = e.hapusGuru(6);
      expect(hasil.sukses, isFalse);
      expect(hasil.pesan, contains('masih dipakai'));
      expect(e.master.guruDariKg(6), isNotNull);
    });

    test('hapus mapel yang masih dipakai ditolak', () {
      final e = editorBaru();
      final hasil = e.hapusMapel('KK');
      expect(hasil.sukses, isFalse);
      expect(hasil.pesan, contains('masih dipakai'));
    });

    test('hapus yang tidak terpakai berhasil & relasi ikut bersih', () {
      final e = editorBaru();
      e.master.tambahGuru(40, 'Guru Cadangan, S.Pd.');
      e.master.aturRelasiGuru(40, {'KK'});
      expect(e.hapusGuru(40).sukses, isTrue);
      expect(e.master.guruDariKg(40), isNull);
      expect(e.master.mapelUntukGuru(40), isEmpty);

      e.master.tambahMapel('BARU', 'Mapel Baru', '#8FC48F');
      e.master.aturRelasiMapel('BARU', {3});
      expect(e.hapusMapel('BARU').sukses, isTrue);
      expect(e.master.mapelUntukGuru(3), isNot(contains('BARU')));
    });
  });

  group('assign slot & rentang', () {
    test('assign tunggal mengubah entri; slot non-pelajaran ditolak', () {
      final e = editorBaru();
      expect(e.assignSlot(0, 1, kodeMapel: 'MTK', kg: 24).sukses, isTrue);
      expect(e.entriAktif(0, 1), const EntriSlot(kodeMapel: 'MTK', kg: 24));
      // Slot 0 Senin = upacara.
      expect(e.assignSlot(0, 0, kodeMapel: 'MTK', kg: 24).sukses, isFalse);
      // Mapel / guru tak dikenal.
      expect(e.assignSlot(0, 2, kodeMapel: 'XXX', kg: 24).sukses, isFalse);
      expect(e.assignSlot(0, 2, kodeMapel: 'MTK', kg: 99).sukses, isFalse);
    });

    test('relasi adalah panduan, bukan kunci: guru luar relasi tetap bisa', () {
      final e = editorBaru();
      // KG 16 (PJOK) tidak berelasi dengan MTK, tetapi assign tetap sah.
      expect(e.master.mapelUntukGuru(16), isNot(contains('MTK')));
      expect(e.assignSlot(0, 1, kodeMapel: 'MTK', kg: 16).sukses, isTrue);
    });

    test('rentang berhenti di slot non-pelajaran (mentok)', () {
      final e = editorBaru();
      // Senin: slot 1,2,3 pelajaran lalu slot 4 istirahat.
      final p = e.pratinjauRentang(0, 1, 4);
      expect(p.indeksSlot, [1, 2, 3]);
      expect(p.mentok, isTrue);
    });

    test('rentang menimpa hanya dengan izin', () {
      final e = editorBaru();
      // Slot 1–3 Senin sudah terisi IPAS.
      final tanpaIzin = e.assignRentang(
        0,
        1,
        kodeMapel: 'KK',
        kg: 3,
        jumlahJam: 3,
      );
      expect(tanpaIzin.sukses, isFalse);
      expect(e.entriAktif(0, 1)?.kodeMapel, 'IPAS');
      final denganIzin = e.assignRentang(
        0,
        1,
        kodeMapel: 'KK',
        kg: 3,
        jumlahJam: 3,
        izinkanTimpa: true,
      );
      expect(denganIzin.sukses, isTrue);
      for (final s in [1, 2, 3]) {
        expect(e.entriAktif(0, s), const EntriSlot(kodeMapel: 'KK', kg: 3));
      }
    });

    test('rentang di slot kosong terpotong isoma tanpa perlu izin', () {
      final e = editorBaru();
      e.kosongkanSlot(0, 5);
      e.kosongkanSlot(0, 6);
      // Slot 5,6 kosong; slot 7 isoma → rentang 4 hanya terisi 2.
      final hasil = e.assignRentang(
        0,
        5,
        kodeMapel: 'DDBP',
        kg: 33,
        jumlahJam: 4,
      );
      expect(hasil.sukses, isTrue);
      expect(hasil.pesan, contains('Terisi 2 jam'));
      expect(e.entriAktif(0, 5)?.kodeMapel, 'DDBP');
      expect(e.entriAktif(0, 6)?.kodeMapel, 'DDBP');
    });

    test('rentang di tepi akhir hari terpotong', () {
      final e = editorBaru();
      // Jumat (indeks 4): slot 9 pelajaran terakhir, slot 10 isoma.
      final p = e.pratinjauRentang(4, 9, 4);
      expect(p.indeksSlot, [9]);
      expect(p.mentok, isTrue);
      // Rentang mulai dari slot non-pelajaran ditolak.
      expect(
        e.assignRentang(4, 10, kodeMapel: 'KK', kg: 3, jumlahJam: 2).sukses,
        isFalse,
      );
    });

    test('kosongkan slot mengosongkan; non-pelajaran ditolak', () {
      final e = editorBaru();
      expect(e.kosongkanSlot(0, 1).sukses, isTrue);
      expect(e.entriAktif(0, 1), isNull);
      expect(e.kosongkanSlot(0, 4).sukses, isFalse); // istirahat
    });
  });

  group('perakitan dokumen', () {
    test('fixture yang diedit lolos validator §7; kelas lain utuh', () {
      final asal = muatFixture();
      final e = editorBaru();
      e.assignSlot(0, 1, kodeMapel: 'KK', kg: 3);
      e.assignRentang(
        1,
        0,
        kodeMapel: 'MTK',
        kg: 12,
        jumlahJam: 2,
        izinkanTimpa: true,
      );
      final rakit = e.rakitDokumen();

      final hasil = validasiJadwalJson(rakit);
      expect(hasil.valid, isTrue, reason: hasil.kesalahan.join('; '));

      // Entri hasil edit masuk.
      final senin = (rakit['hari'] as List)[0] as Map<String, dynamic>;
      final slot1 = (senin['slots'] as List)[1] as Map<String, dynamic>;
      expect((slot1['entri'] as Map)['X-TKJ-A'], {'mapel': 'KK', 'kg': 3});
      // Kelas lain pada slot yang sama persis seperti berkas asal.
      final seninAsal = (asal['hari'] as List)[0] as Map<String, dynamic>;
      final slot1Asal = (seninAsal['slots'] as List)[1] as Map<String, dynamic>;
      for (final kelas in [
        'X-TKJ-B',
        'XI-TKJ-A',
        'XI-TKJ-B',
        'XII-TKJ-A',
        'XII-TKJ-B',
      ]) {
        expect(
          (slot1['entri'] as Map)[kelas],
          (slot1Asal['entri'] as Map)[kelas],
          reason: 'entri $kelas tidak boleh berubah',
        );
      }
      // Meta & field ekstra hari dipertahankan.
      expect((rakit['meta'] as Map)['sekolah'], 'SMKN 1 UKUI');
      expect(senin['statusDecode'], 'lengkap-dari-foto');
    });

    test('slot kosong menghilangkan entri → validator menolak (penjaga)', () {
      final e = editorBaru();
      e.kosongkanSlot(0, 1);
      final rakit = e.rakitDokumen();
      final senin = (rakit['hari'] as List)[0] as Map<String, dynamic>;
      final slot1 = (senin['slots'] as List)[1] as Map<String, dynamic>;
      expect((slot1['entri'] as Map).containsKey('X-TKJ-A'), isFalse);
      final hasil = validasiJadwalJson(rakit);
      expect(hasil.valid, isFalse);
      expect(
        hasil.kesalahan.any((p) => p.contains('tepat 6 entri')),
        isTrue,
        reason: hasil.kesalahan.join('; '),
      );
    });

    test('edit master data ikut terakit (guru baru & nama berubah)', () {
      final e = editorBaru();
      e.master.tambahGuru(40, 'Guru Baru, S.Pd.');
      e.master.ubahNamaGuru(3, 'Agus Priyono, S.T., M.T.');
      final rakit = e.rakitDokumen();
      final guru = (rakit['guru'] as List).cast<Map<String, dynamic>>();
      expect(guru.length, 37);
      expect(
        guru.firstWhere((g) => g['kg'] == 3)['nama'],
        'Agus Priyono, S.T., M.T.',
      );
      // Field ekstra guru (terverifikasi) dipertahankan.
      expect(guru.firstWhere((g) => g['kg'] == 3)['terverifikasi'], isTrue);
    });

    test('berpindah kelas mempertahankan master data & edit kelas lama', () {
      final e = editorBaru();
      e.assignSlot(0, 1, kodeMapel: 'KK', kg: 3);
      e.pilihKelas('XII-TKJ-B');
      expect(e.kelasAktif, 'XII-TKJ-B');
      e.master.tambahMapel('BARU', 'Mapel Baru', '#8FC48F');
      e.assignSlot(0, 1, kodeMapel: 'BARU', kg: 3);
      e.pilihKelas('X-TKJ-A');
      expect(e.entriAktif(0, 1), const EntriSlot(kodeMapel: 'KK', kg: 3));
      expect(e.master.mapelDariKode('BARU'), isNotNull);
      // Rakitan memuat edit DUA kelas sekaligus dan tetap valid.
      final hasil = validasiJadwalJson(e.rakitDokumen());
      expect(hasil.valid, isTrue, reason: hasil.kesalahan.join('; '));
    });

    test('ringkasan kelas menghitung terisi per hari', () {
      final e = editorBaru();
      final senin = e.ringkasanKelas('X-TKJ-A').first;
      expect(senin.namaHari, 'senin');
      expect(senin.totalPelajaran, 9);
      expect(senin.terisi, 9);
      e.kosongkanSlot(0, 1);
      final senin2 = e.ringkasanKelas('X-TKJ-A').first;
      expect(senin2.terisi, 8);
      expect(senin2.kosong, 1);
    });
  });
}
