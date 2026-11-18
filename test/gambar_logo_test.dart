import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nekios_remote/layanan/gambar_logo.dart';

void main() {
  Uint8List buatPng(int lebar, int tinggi, {bool alfa = false}) {
    final gambar = img.Image(
      width: lebar,
      height: tinggi,
      numChannels: alfa ? 4 : 3,
    );
    img.fill(
      gambar,
      color: alfa ? img.ColorRgba8(0, 106, 96, 128) : img.ColorRgb8(0, 106, 96),
    );
    return Uint8List.fromList(img.encodePng(gambar));
  }

  test('gambar besar diperkecil ke maks 512px', () {
    final base64 = olahLogoKeBase64(buatPng(1200, 800));
    final hasil = img.decodeImage(base64Decode(base64));
    expect(hasil, isNotNull);
    expect(hasil!.width, kUkuranMaksLogo);
    expect(hasil.height, lessThanOrEqualTo(kUkuranMaksLogo));
  });

  test('gambar kecil tidak diperbesar', () {
    final base64 = olahLogoKeBase64(buatPng(100, 50));
    final hasil = img.decodeImage(base64Decode(base64));
    expect(hasil!.width, 100);
    expect(hasil.height, 50);
  });

  test('bytes bukan gambar melempar FormatException', () {
    expect(
      () => olahLogoKeBase64(Uint8List.fromList([1, 2, 3, 4])),
      throwsFormatException,
    );
  });
}
