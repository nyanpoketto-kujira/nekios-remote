import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nekios_remote/masjid/kompresi_gambar.dart';
import 'package:nekios_remote/masjid/model_masjid.dart';
import 'package:nekios_remote/masjid/paket_masjid.dart';

/// Gambar derau deterministik (PNG besar, JPEG jauh lebih kecil) —
/// hash per piksel agar datanya benar-benar tak terkompresi dan test
/// stabil tanpa berkas contoh.
Uint8List gambarDerau(int lebar, int tinggi, {bool alpha = false}) {
  int acak(int x, int y, int kanal) {
    var h = (x * 374761393 + y * 668265263 + kanal * 974634211) & 0xffffffff;
    h = (h ^ (h >> 13)) & 0xffffffff;
    h = (h * 1274126177) & 0xffffffff;
    h = (h ^ (h >> 16)) & 0xffffffff;
    return h % 256;
  }

  final gambar = img.Image(width: lebar, height: tinggi, numChannels: 4);
  for (var y = 0; y < tinggi; y++) {
    for (var x = 0; x < lebar; x++) {
      gambar.setPixelRgba(
        x,
        y,
        acak(x, y, 0),
        acak(x, y, 1),
        acak(x, y, 2),
        alpha ? 200 : 255,
      );
    }
  }
  return Uint8List.fromList(img.encodePng(gambar));
}

void main() {
  group('keputusan kompresi latar', () {
    test('hanya Bluetooth tanpa opsi asli yang mengompresi', () {
      expect(
        shouldCompressBackgroundForSend(
          transport: BackgroundSendTransport.bluetooth,
          sendUncompressed: false,
        ),
        isTrue,
      );
      expect(
        shouldCompressBackgroundForSend(
          transport: BackgroundSendTransport.bluetooth,
          sendUncompressed: true,
        ),
        isFalse,
      );
      expect(
        shouldCompressBackgroundForSend(
          transport: BackgroundSendTransport.websocket,
          sendUncompressed: false,
        ),
        isFalse,
      );
    });
  });

  group('compressBackgroundImageBytes', () {
    test('gambar lebar diperkecil ke maks 1920 & menjadi JPEG', () {
      final asli = gambarDerau(2100, 60);
      final hasil = compressBackgroundImageBytes(asli);
      expect(hasil.length, lessThan(asli.length));
      final terdekode = img.decodeImage(hasil);
      expect(terdekode, isNotNull);
      expect(terdekode!.width, kBackgroundCompressMaxDimension);
    });

    test('bytes bukan gambar dikembalikan apa adanya (fail-soft)', () {
      final rusak = Uint8List.fromList([1, 2, 3, 4, 5]);
      expect(compressBackgroundImageBytes(rusak), rusak);
    });
  });

  group('prepareLogoBytesForBluetooth', () {
    test('logo ber-alpha 1024px menjadi PNG 512px (alpha terjaga)', () {
      final asli = gambarDerau(1024, 1024, alpha: true);
      final hasil = prepareLogoBytesForBluetooth(asli);
      final terdekode = img.decodeImage(hasil);
      expect(terdekode, isNotNull);
      expect(terdekode!.width, kLogoBluetoothMaxDimension);
      expect(terdekode.hasAlpha, isTrue);
    });

    test('logo kecil tidak di-encode ulang', () {
      final kecil = gambarDerau(300, 300);
      expect(prepareLogoBytesForBluetooth(kecil), kecil);
    });
  });

  group('paket terkompresi', () {
    test(
      'compressedBackgroundPacket hanya menyentuh updateBackgroundImages',
      () {
        final besar = base64Encode(gambarDerau(2100, 60));
        final paket = SyncPacket(
          action: SyncAction.updateBackgroundImages,
          payload: {
            'images': [BackgroundImage(id: 'b', base64Image: besar).toMap()],
          },
        );
        final hasil = compressedBackgroundPacket(paket);
        final gambarHasil =
            ((hasil.payload['images'] as List).single as Map)['base64Image']
                as String;
        expect(gambarHasil, isNot(besar));
        expect(
          base64Decode(gambarHasil).length,
          lessThan(base64Decode(besar).length),
        );
        // Paket asli tidak berubah.
        expect(
          ((paket.payload['images'] as List).single as Map)['base64Image'],
          besar,
        );

        const lain = SyncPacket(
          action: SyncAction.setMuted,
          payload: {'muted': true},
        );
        expect(compressedBackgroundPacket(lain), same(lain));
      },
    );

    test('compressedLogoPacket: logo null (hapus) & aksi lain apa adanya', () {
      const hapus = SyncPacket(
        action: SyncAction.updateLogo,
        payload: {'logoBase64': null},
      );
      expect(compressedLogoPacket(hapus), same(hapus));
      const lain = SyncPacket(action: SyncAction.skipAdhan, payload: {});
      expect(compressedLogoPacket(lain), same(lain));
    });
  });
}
