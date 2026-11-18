/// Persiapan gambar untuk jalur Bluetooth masjid — PORT dari
/// `apps/mobile_remote/lib/services/background_send_service.dart` dan
/// `logo_send_service.dart` masjid-you (Rute A, ADR-003).
///
/// Jalur WebSocket selalu mengirim gambar ASLI; hanya salinan kirim
/// Bluetooth yang dikompresi/diperkecil lalu di-chunk (lihat
/// `transfer_chunk.dart`). Data gambar yang tersimpan tidak pernah
/// diubah fungsi-fungsi ini.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'paket_masjid.dart';

/// Jalur transport pengiriman gambar latar ke TV.
enum BackgroundSendTransport { bluetooth, websocket }

/// Keputusan kompresi gambar latar saat kirim:
///
/// - Bluetooth + opsi "tanpa kompresi" MATI (default) -> kompres.
/// - Bluetooth + opsi "tanpa kompresi" AKTIF -> kirim asli.
/// - WebSocket -> selalu asli (LAN cepat, tidak perlu kompres).
bool shouldCompressBackgroundForSend({
  required BackgroundSendTransport transport,
  required bool sendUncompressed,
}) {
  return transport == BackgroundSendTransport.bluetooth && !sendUncompressed;
}

/// Batas dimensi terbesar hasil kompresi gambar latar (piksel).
const int kBackgroundCompressMaxDimension = 1920;

/// Kualitas JPEG hasil kompresi gambar latar (0-100).
const int kBackgroundCompressJpegQuality = 80;

/// Kompresi bytes gambar untuk pengiriman Bluetooth: decode, perkecil
/// bila dimensi terbesar melebihi [kBackgroundCompressMaxDimension],
/// lalu encode ulang sebagai JPEG kualitas
/// [kBackgroundCompressJpegQuality].
///
/// Fail-soft: gambar yang tidak bisa di-decode dikembalikan apa
/// adanya, dan bila hasil kompresi ternyata tidak lebih kecil, bytes
/// asli yang dipakai.
Uint8List compressBackgroundImageBytes(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    var working = decoded;
    final maxDimension = decoded.width > decoded.height
        ? decoded.width
        : decoded.height;
    if (maxDimension > kBackgroundCompressMaxDimension) {
      working = decoded.width >= decoded.height
          ? img.copyResize(decoded, width: kBackgroundCompressMaxDimension)
          : img.copyResize(decoded, height: kBackgroundCompressMaxDimension);
    }
    final encoded = img.encodeJpg(
      working,
      quality: kBackgroundCompressJpegQuality,
    );
    if (encoded.isEmpty || encoded.length >= bytes.length) return bytes;
    return Uint8List.fromList(encoded);
  } catch (_) {
    return bytes;
  }
}

/// Terapkan [compressBackgroundImageBytes] ke salinan base64 (untuk
/// payload sync). String rusak dikembalikan apa adanya.
String compressBackgroundBase64(String base64Image) {
  if (base64Image.isEmpty) return base64Image;
  try {
    final bytes = base64Decode(base64Image);
    return base64Encode(compressBackgroundImageBytes(bytes));
  } catch (_) {
    return base64Image;
  }
}

/// Salinan [packet] `updateBackgroundImages` dengan setiap gambar
/// terkompresi (untuk jalur Bluetooth). Paket asli tidak diubah;
/// aksi lain dikembalikan apa adanya.
SyncPacket compressedBackgroundPacket(SyncPacket packet) {
  if (packet.action != SyncAction.updateBackgroundImages) return packet;
  final rawImages = packet.payload['images'];
  if (rawImages is! List) return packet;
  return SyncPacket(
    action: packet.action,
    payload: {
      ...packet.payload,
      'images': [
        for (final entry in rawImages)
          if (entry is Map)
            {
              for (final e in entry.entries) '${e.key}': e.value,
              if (entry['base64Image'] is String)
                'base64Image': compressBackgroundBase64(
                  entry['base64Image'] as String,
                ),
            }
          else
            entry,
      ],
    },
  );
}

/// Batas dimensi terbesar logo untuk jalur Bluetooth. Logo tampil di
/// header TV sebagai kotak 1:1 setinggi ±76 dp — 512 px sudah jauh di
/// atas kebutuhan tampilnya.
const int kLogoBluetoothMaxDimension = 512;

/// Kualitas JPEG logo jalur Bluetooth bila gambar tanpa alpha.
const int kLogoBluetoothJpegQuality = 85;

/// Siapkan bytes logo untuk jalur Bluetooth: perkecil dimensi
/// terbesar ke maks [kLogoBluetoothMaxDimension] px. Logo **menjaga
/// transparansi**: gambar ber-alpha di-encode ulang sebagai PNG,
/// gambar tanpa alpha sebagai JPEG kualitas
/// [kLogoBluetoothJpegQuality]. Gambar yang sudah cukup kecil
/// dikembalikan apa adanya. Fail-soft seperti fungsi latar.
Uint8List prepareLogoBytesForBluetooth(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    final maxDimension = decoded.width > decoded.height
        ? decoded.width
        : decoded.height;
    if (maxDimension <= kLogoBluetoothMaxDimension) return bytes;
    final resized = decoded.width >= decoded.height
        ? img.copyResize(decoded, width: kLogoBluetoothMaxDimension)
        : img.copyResize(decoded, height: kLogoBluetoothMaxDimension);
    final encoded = decoded.hasAlpha
        ? img.encodePng(resized)
        : img.encodeJpg(resized, quality: kLogoBluetoothJpegQuality);
    if (encoded.isEmpty) return bytes;
    return Uint8List.fromList(encoded);
  } catch (_) {
    return bytes;
  }
}

/// Terapkan [prepareLogoBytesForBluetooth] ke salinan base64.
/// String rusak dikembalikan apa adanya.
String prepareLogoBase64ForBluetooth(String base64Image) {
  if (base64Image.isEmpty) return base64Image;
  try {
    final bytes = base64Decode(base64Image);
    return base64Encode(prepareLogoBytesForBluetooth(bytes));
  } catch (_) {
    return base64Image;
  }
}

/// Salinan [packet] `updateLogo` dengan logo disiapkan untuk jalur
/// Bluetooth. Paket asli tidak diubah; aksi lain dan logo kosong
/// (penghapusan) dikembalikan apa adanya.
SyncPacket compressedLogoPacket(SyncPacket packet) {
  if (packet.action != SyncAction.updateLogo) return packet;
  final rawLogo = packet.payload['logoBase64'];
  if (rawLogo is! String || rawLogo.isEmpty) return packet;
  return SyncPacket(
    action: packet.action,
    payload: {
      ...packet.payload,
      'logoBase64': prepareLogoBase64ForBluetooth(rawLogo),
    },
  );
}
