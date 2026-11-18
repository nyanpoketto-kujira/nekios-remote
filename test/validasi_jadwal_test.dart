import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nekios_remote/domain/validasi_jadwal.dart';

/// Jadwal kecil yang valid — basis mutasi untuk tiap kelas kesalahan.
/// Dilewatkan jsonEncode/jsonDecode supaya semua map berjenis
/// `Map<String, dynamic>` seperti berkas sungguhan.
Map<String, dynamic> jadwalValid() => jsonDecode(
  jsonEncode({
    'meta': {
      'sekolah': 'SMKN 1 Ukui',
      'judul': 'Jadwal Pelajaran TKJ',
      'tahunPelajaran': '2026/2027',
      'jurusan': 'TKJ',
    },
    'kelas': [
      {'id': 'X-TKJ-A', 'nama': 'X TKJ A', 'urutan': 1},
      {'id': 'X-TKJ-B', 'nama': 'X TKJ B', 'urutan': 2},
    ],
    'guru': [
      {'kg': 1, 'nama': 'Guru Satu', 'terverifikasi': true},
      {'kg': 2, 'nama': 'Guru Dua', 'terverifikasi': false},
    ],
    'mapel': [
      {
        'kode': 'IPAS',
        'namaPanjang': 'Ilmu Pengetahuan Alam dan Sosial',
        'warna': '#F0A868',
      },
      {'kode': 'KK', 'namaPanjang': 'Konsentrasi Keahlian', 'warna': '#7FB069'},
    ],
    'hari': [
      {
        'nama': 'Senin',
        'slots': [
          {
            'mulai': '07.15',
            'selesai': '08.00',
            'tipe': 'upacara',
            'label': 'UPACARA',
          },
          {
            'mulai': '08.00',
            'selesai': '08.45',
            'tipe': 'pelajaran',
            'entri': {
              'X-TKJ-A': {'mapel': 'IPAS', 'kg': 1},
              'X-TKJ-B': {'mapel': 'KK', 'kg': 2},
            },
          },
          {'mulai': '08.45', 'selesai': '09.00', 'tipe': 'istirahat'},
        ],
      },
    ],
  }),
) as Map<String, dynamic>;

List<dynamic> slots(Map<String, dynamic> j) =>
    ((j['hari'] as List).first as Map<String, dynamic>)['slots'] as List;

void main() {
  group('jadwal valid', () {
    test('fixture kecil lolos tanpa kesalahan + ringkasan benar', () {
      final hasil = validasiJadwalJson(jadwalValid());
      expect(hasil.valid, isTrue, reason: hasil.kesalahan.join('; '));
      final r = hasil.ringkasan!;
      expect(r.sekolah, 'SMKN 1 Ukui');
      expect(r.jumlahKelas, 2);
      expect(r.jumlahGuru, 2);
      expect(r.jumlahMapel, 2);
      expect(r.jumlahHari, 1);
      expect(r.totalSlot, 3);
      expect(r.totalSlotPelajaran, 1);
    });

    test('jadwal asli nekios-school (fixture) lolos §7', () {
      final mentah = File('test/fixtures/jadwal-sekolah.json')
          .readAsStringSync();
      final hasil = validasiJadwalJson(jsonDecode(mentah));
      expect(hasil.valid, isTrue, reason: hasil.kesalahan.join('; '));
      final r = hasil.ringkasan!;
      expect(r.jumlahKelas, 6);
      expect(r.jumlahGuru, 36);
      expect(r.jumlahMapel, 15);
      expect(r.jumlahHari, 5);
      expect(r.totalSlot, 60);
      expect(r.totalSlotPelajaran, 47);
    });
  });

  group('kelas kesalahan §7', () {
    test('aturan 1: slot tumpang tindih ditolak', () {
      final j = jadwalValid();
      (slots(j)[1] as Map<String, dynamic>)['mulai'] = '07.30';
      final hasil = validasiJadwalJson(j);
      expect(hasil.valid, isFalse);
      expect(hasil.kesalahan.join(), contains('tumpang tindih'));
    });

    test('aturan 1: slot tidak terurut ditolak', () {
      final j = jadwalValid();
      final s = slots(j);
      final tukar = s[0];
      s[0] = s[1];
      s[1] = tukar;
      final hasil = validasiJadwalJson(j);
      expect(hasil.valid, isFalse);
      expect(hasil.kesalahan.join(), contains('tidak terurut'));
    });

    test('aturan 4: mulai >= selesai ditolak', () {
      final j = jadwalValid();
      (slots(j)[2] as Map<String, dynamic>)['selesai'] = '08.45';
      final hasil = validasiJadwalJson(j);
      expect(hasil.kesalahan.join(), contains('mulai harus sebelum selesai'));
    });

    test('aturan 3: slot pelajaran kurang entri ditolak', () {
      final j = jadwalValid();
      final entri =
          (slots(j)[1] as Map<String, dynamic>)['entri']
              as Map<String, dynamic>;
      entri.remove('X-TKJ-B');
      final hasil = validasiJadwalJson(j);
      expect(hasil.kesalahan.join(), contains('tepat 2 entri'));
    });

    test('aturan 3: slot non-pelajaran ber-entri ditolak', () {
      final j = jadwalValid();
      (slots(j)[2] as Map<String, dynamic>)['entri'] = {
        'X-TKJ-A': {'mapel': 'IPAS', 'kg': 1},
      };
      final hasil = validasiJadwalJson(j);
      expect(hasil.kesalahan.join(), contains('tidak boleh punya entri'));
    });

    test('aturan 2: KG tidak dikenal ditolak', () {
      final j = jadwalValid();
      final entri =
          (slots(j)[1] as Map<String, dynamic>)['entri']
              as Map<String, dynamic>;
      (entri['X-TKJ-A'] as Map<String, dynamic>)['kg'] = 99;
      final hasil = validasiJadwalJson(j);
      expect(hasil.kesalahan.join(), contains('KG tidak dikenal 99'));
    });

    test('aturan 2: mapel tidak dikenal ditolak', () {
      final j = jadwalValid();
      final entri =
          (slots(j)[1] as Map<String, dynamic>)['entri']
              as Map<String, dynamic>;
      (entri['X-TKJ-A'] as Map<String, dynamic>)['mapel'] = 'XYZ';
      final hasil = validasiJadwalJson(j);
      expect(hasil.kesalahan.join(), contains('mapel tidak dikenal "XYZ"'));
    });

    test('aturan 2: kelas tidak dikenal ditolak', () {
      final j = jadwalValid();
      final entri =
          (slots(j)[1] as Map<String, dynamic>)['entri']
              as Map<String, dynamic>;
      entri['XII-TKJ-Z'] = {'mapel': 'IPAS', 'kg': 1};
      final hasil = validasiJadwalJson(j);
      expect(hasil.kesalahan.join(), contains('kelas tidak dikenal'));
    });

    test('aturan 5: warna bukan #RRGGBB ditolak', () {
      final j = jadwalValid();
      ((j['mapel'] as List).first as Map<String, dynamic>)['warna'] = 'merah';
      final hasil = validasiJadwalJson(j);
      expect(hasil.kesalahan.join(), contains('bukan format #RRGGBB'));
    });

    test('aturan 5: namaPanjang kosong ditolak', () {
      final j = jadwalValid();
      ((j['mapel'] as List).first as Map<String, dynamic>)['namaPanjang'] =
          '  ';
      final hasil = validasiJadwalJson(j);
      expect(hasil.kesalahan.join(), contains('namaPanjang kosong'));
    });
  });

  group('kesalahan struktur', () {
    test('akar bukan objek', () {
      final hasil = validasiJadwalJson([1, 2, 3]);
      expect(hasil.valid, isFalse);
      expect(hasil.ringkasan, isNull);
    });

    test('meta hilang', () {
      final j = jadwalValid()..remove('meta');
      final hasil = validasiJadwalJson(j);
      expect(hasil.kesalahan.join(), contains('"meta" hilang'));
      expect(hasil.ringkasan, isNull);
    });

    test('format jam rusak (bukan JJ.MM)', () {
      final j = jadwalValid();
      (slots(j)[0] as Map<String, dynamic>)['mulai'] = '7:15';
      final hasil = validasiJadwalJson(j);
      expect(hasil.kesalahan.join(), contains('JJ.MM'));
    });

    test('tipe slot tidak dikenal', () {
      final j = jadwalValid();
      (slots(j)[2] as Map<String, dynamic>)['tipe'] = 'libur';
      final hasil = validasiJadwalJson(j);
      expect(hasil.kesalahan.join(), contains('tipe slot tidak dikenal'));
    });

    test('ID kelas ganda', () {
      final j = jadwalValid();
      ((j['kelas'] as List)[1] as Map<String, dynamic>)['id'] = 'X-TKJ-A';
      final hasil = validasiJadwalJson(j);
      expect(hasil.kesalahan.join(), contains('ID kelas ganda'));
    });
  });
}
