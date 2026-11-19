import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nekios_remote/layanan/gambar_banner.dart';

void main() {
  Uint8List buatPng(int lebar, int tinggi) {
    final gambar = img.Image(width: lebar, height: tinggi);
    img.fill(gambar, color: img.ColorRgb8(0, 106, 96));
    return Uint8List.fromList(img.encodePng(gambar));
  }

  test('gambar kecil lolos dengan ukuran yang sama (JPEG hasil)', () async {
    final hasil = await perkecilUntukBanner(buatPng(4, 2));
    final terbaca = img.decodeImage(hasil);
    expect(terbaca, isNotNull);
    expect(terbaca!.width, 4);
    expect(terbaca.height, 2);
  });

  test('gambar lebih lebar dari batas diperkecil ke lebar 1920', () async {
    final hasil = await perkecilUntukBanner(buatPng(2000, 100));
    final terbaca = img.decodeImage(hasil);
    expect(terbaca, isNotNull);
    expect(terbaca!.width, kLebarMaksBanner);
    expect(terbaca.height, lessThanOrEqualTo(kTinggiMaksBanner));
    // Rasio dipertahankan: 2000×100 → 1920×96.
    expect(terbaca.height, 96);
  });

  test('gambar lebih tinggi dari batas diperkecil ke tinggi 1080', () async {
    final hasil = await perkecilUntukBanner(buatPng(100, 2000));
    final terbaca = img.decodeImage(hasil);
    expect(terbaca, isNotNull);
    expect(terbaca!.height, kTinggiMaksBanner);
    expect(terbaca.width, lessThanOrEqualTo(kLebarMaksBanner));
    // Rasio dipertahankan: 100×2000 → 54×1080.
    expect(terbaca.width, 54);
  });

  test('bytes bukan gambar dikembalikan apa adanya', () async {
    final mentah = Uint8List.fromList([1, 2, 3, 4]);
    expect(await perkecilUntukBanner(mentah), mentah);
  });
}
