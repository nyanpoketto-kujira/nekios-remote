import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Batas sisi terpanjang logo yang dikirim ke display (pola
/// masjid-you: mirror logo diperkecil ke maks 512px supaya paket
/// WebSocket tetap ringan; di TV logo tampil kecil di header).
const int kUkuranMaksLogo = 512;

/// Olah bytes gambar pilihan pengguna menjadi base64 siap kirim
/// (`logo.set`): decode, perkecil supaya sisi terpanjang ≤
/// [kUkuranMaksLogo], lalu encode ulang — PNG bila gambar punya
/// kanal alfa (logo umumnya transparan), JPEG kualitas 88 bila tidak.
///
/// Melempar [FormatException] bila bytes bukan gambar yang terbaca.
String olahLogoKeBase64(Uint8List bytes) {
  final gambar = img.decodeImage(bytes);
  if (gambar == null) {
    throw const FormatException('Berkas bukan gambar yang terbaca.');
  }
  var hasil = gambar;
  if (gambar.width > kUkuranMaksLogo || gambar.height > kUkuranMaksLogo) {
    hasil = gambar.width >= gambar.height
        ? img.copyResize(gambar, width: kUkuranMaksLogo)
        : img.copyResize(gambar, height: kUkuranMaksLogo);
  }
  final List<int> encoded = hasil.hasAlpha
      ? img.encodePng(hasil)
      : img.encodeJpg(hasil, quality: 88);
  return base64Encode(encoded);
}
