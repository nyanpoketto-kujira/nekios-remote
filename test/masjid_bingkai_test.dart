import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nekios_remote/masjid/bingkai_bt.dart';

Uint8List byteDari(String teks) => Uint8List.fromList(utf8.encode(teks));

void main() {
  group('bingkaiBtEncode', () {
    test('header 4 byte big-endian + payload apa adanya', () {
      final bingkai = bingkaiBtEncode(byteDari('abc'));
      expect(bingkai, [0, 0, 0, 3, 97, 98, 99]);
    });

    test('panjang besar ter-encode di keempat byte header', () {
      final payload = Uint8List(70000);
      final bingkai = bingkaiBtEncode(payload);
      expect(bingkai.length, 70004);
      // 70000 = 0x00011170
      expect(bingkai.sublist(0, 4), [0, 1, 0x11, 0x70]);
    });
  });

  group('PenguraiBingkaiBt', () {
    test('satu bingkai utuh dalam satu potongan', () {
      final pengurai = PenguraiBingkaiBt();
      final hasil = pengurai.masukkan(bingkaiBtEncode(byteDari('{"a":1}')));
      expect(hasil, hasLength(1));
      expect(utf8.decode(hasil.single), '{"a":1}');
      expect(pengurai.byteTertahan, 0);
    });

    test('bingkai pecah per byte tetap terangkai', () {
      final pengurai = PenguraiBingkaiBt();
      final bingkai = bingkaiBtEncode(byteDari('halo-masjid'));
      final hasil = <Uint8List>[];
      for (final b in bingkai) {
        hasil.addAll(pengurai.masukkan(Uint8List.fromList([b])));
      }
      expect(hasil, hasLength(1));
      expect(utf8.decode(hasil.single), 'halo-masjid');
    });

    test('dua bingkai menempel dalam satu potongan', () {
      final pengurai = PenguraiBingkaiBt();
      final gabung = Uint8List.fromList([
        ...bingkaiBtEncode(byteDari('satu')),
        ...bingkaiBtEncode(byteDari('dua')),
      ]);
      final hasil = pengurai.masukkan(gabung);
      expect(hasil.map(utf8.decode), ['satu', 'dua']);
    });

    test('header terbelah: menunggu sampai payload lengkap', () {
      final pengurai = PenguraiBingkaiBt();
      final bingkai = bingkaiBtEncode(byteDari('12345'));
      expect(pengurai.masukkan(bingkai.sublist(0, 2)), isEmpty);
      expect(pengurai.byteTertahan, 2);
      expect(pengurai.masukkan(bingkai.sublist(2, 6)), isEmpty);
      final hasil = pengurai.masukkan(bingkai.sublist(6));
      expect(hasil.map(utf8.decode), ['12345']);
    });

    test('panjang nol / raksasa ditolak sebagai korup', () {
      final nol = PenguraiBingkaiBt();
      expect(
        () => nol.masukkan(Uint8List.fromList([0, 0, 0, 0])),
        throwsFormatException,
      );
      final raksasa = PenguraiBingkaiBt();
      expect(
        () => raksasa.masukkan(Uint8List.fromList([0xff, 0xff, 0xff, 0xff])),
        throwsFormatException,
      );
      // Setelah gagal, pengurai bersih dan bisa dipakai lagi.
      final hasil = raksasa.masukkan(bingkaiBtEncode(byteDari('ok')));
      expect(hasil.map(utf8.decode), ['ok']);
    });

    test('reset membuang sisa bingkai tak lengkap', () {
      final pengurai = PenguraiBingkaiBt();
      pengurai.masukkan(bingkaiBtEncode(byteDari('separuh')).sublist(0, 5));
      pengurai.reset();
      expect(pengurai.byteTertahan, 0);
      final hasil = pengurai.masukkan(bingkaiBtEncode(byteDari('baru')));
      expect(hasil.map(utf8.decode), ['baru']);
    });
  });
}
