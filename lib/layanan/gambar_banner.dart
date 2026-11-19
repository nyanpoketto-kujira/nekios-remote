import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Batas ukuran gambar banner info masjid (pola mobile_remote:
/// gambar diperkecil saat DIPILIH supaya muat 1920×1080, lalu
/// disimpan sebagai JPEG kualitas 85 — paket `updateBanners`
/// tetap ringan di kedua jalur). Kompresi transport Bluetooth
/// adalah urusan terpisah di lapisan transport, bukan di sini.
const int kLebarMaksBanner = 1920;
const int kTinggiMaksBanner = 1080;

/// Perkecil [asli] agar muat dalam [kLebarMaksBanner]×
/// [kTinggiMaksBanner] (hanya mengecilkan, rasio dipertahankan),
/// lalu encode ulang sebagai JPEG kualitas 85.
///
/// Bytes yang tidak terbaca sebagai gambar dikembalikan apa
/// adanya — pemanggil (dialog banner) yang memutuskan apakah
/// hasilnya layak dipakai; helper ini tidak pernah melempar.
Future<Uint8List> perkecilUntukBanner(Uint8List asli) async {
  final gambar = img.decodeImage(asli);
  if (gambar == null) return asli;
  var hasil = gambar;
  if (gambar.width > kLebarMaksBanner || gambar.height > kTinggiMaksBanner) {
    // Sisi yang rasio kelebihannya lebih besar menentukan sumbu
    // perkecil; copyResize menjaga rasio dari sumbu lainnya.
    hasil =
        gambar.width / kLebarMaksBanner >= gambar.height / kTinggiMaksBanner
        ? img.copyResize(gambar, width: kLebarMaksBanner)
        : img.copyResize(gambar, height: kTinggiMaksBanner);
  }
  return Uint8List.fromList(img.encodeJpg(hasil, quality: 85));
}
