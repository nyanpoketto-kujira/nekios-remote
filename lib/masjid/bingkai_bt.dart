/// Framing kabel Bluetooth Classic (RFCOMM) masjid-you: setiap paket
/// adalah SATU bingkai = 4 byte big-endian panjang payload + payload
/// UTF-8 berisi satu JSON `SyncPacket` utuh.
///
/// Di masjid-you framing ini hidup di kode native plugin
/// bluetooth_sync (Kotlin `sendLocked`/`readLoop`); di nekios-remote
/// framing dipindah ke Dart murni (plugin lokal hanya pipa byte
/// mentah) supaya bisa diuji unit — format di kabel IDENTIK,
/// tv_display tidak bisa membedakannya (ADR-003).
library;

import 'dart:typed_data';

/// Batas panjang payload satu bingkai (sama dengan `MAX_FRAME_BYTES`
/// plugin masjid-you): 64 MB. Bingkai di luar ini dianggap korup.
const int kMaksBingkaiBt = 64 * 1024 * 1024;

/// Bungkus [payload] menjadi satu bingkai kabel (header + payload).
Uint8List bingkaiBtEncode(Uint8List payload) {
  final panjang = payload.length;
  final hasil = Uint8List(4 + panjang);
  hasil[0] = (panjang >> 24) & 0xff;
  hasil[1] = (panjang >> 16) & 0xff;
  hasil[2] = (panjang >> 8) & 0xff;
  hasil[3] = panjang & 0xff;
  hasil.setRange(4, 4 + panjang, payload);
  return hasil;
}

/// Pengurai aliran byte RFCOMM menjadi payload per bingkai.
///
/// Byte dari socket tiba dalam potongan acak (satu bingkai bisa pecah
/// di banyak potongan; banyak bingkai bisa menempel di satu potongan).
/// [masukkan] menelan satu potongan dan mengembalikan daftar payload
/// yang bingkainya sudah lengkap. Panjang tidak valid (<= 0 atau
/// > [kMaksBingkaiBt]) melempar [FormatException] — pemanggil
/// memperlakukannya sebagai kesalahan koneksi fatal, sama seperti
/// perilaku `readLoop` native masjid-you yang memutus aliran.
class PenguraiBingkaiBt {
  Uint8List _sisa = Uint8List(0);

  /// Buang semua byte tertahan (mis. saat koneksi baru dimulai).
  void reset() => _sisa = Uint8List(0);

  /// Jumlah byte yang sedang tertahan menunggu bingkai lengkap.
  int get byteTertahan => _sisa.length;

  List<Uint8List> masukkan(Uint8List potongan) {
    if (potongan.isNotEmpty) {
      final gabung = Uint8List(_sisa.length + potongan.length);
      gabung.setRange(0, _sisa.length, _sisa);
      gabung.setRange(_sisa.length, gabung.length, potongan);
      _sisa = gabung;
    }
    final lengkap = <Uint8List>[];
    var offset = 0;
    while (_sisa.length - offset >= 4) {
      final panjang =
          (_sisa[offset] << 24) |
          (_sisa[offset + 1] << 16) |
          (_sisa[offset + 2] << 8) |
          _sisa[offset + 3];
      if (panjang <= 0 || panjang > kMaksBingkaiBt) {
        _sisa = Uint8List(0);
        throw FormatException('Panjang bingkai BT tidak valid: $panjang');
      }
      if (_sisa.length - offset < 4 + panjang) break;
      lengkap.add(
        Uint8List.fromList(_sisa.sublist(offset + 4, offset + 4 + panjang)),
      );
      offset += 4 + panjang;
    }
    if (offset > 0) {
      _sisa = Uint8List.fromList(_sisa.sublist(offset));
    }
    return lengkap;
  }
}
