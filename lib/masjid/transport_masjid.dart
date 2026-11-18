/// Transport menuju tv_display masjid-you (Rute A, ADR-003).
///
/// Protokol masjid bersifat fire-and-forget: tidak ada ack umum.
/// Antarmuka ini karenanya hanya menjanjikan aliran paket masuk dan
/// aliran kesalahan jalur; "keberhasilan" perintah dibuktikan oleh
/// paket susulan (`stateSnapshot`/`stateUpdate`) dan menjadi urusan
/// [MasjidStore], bukan transport.
library;

import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../model/display_tersimpan.dart';
import 'paket_masjid.dart';

/// Port WebSocket warisan tv_display masjid-you (`local_ws_server`).
const int kPortWsMasjid = 8080;

/// Satu jalur komunikasi ke TV masjid (WebSocket atau Bluetooth).
abstract interface class TransportMasjid {
  /// Jalur sedang tersambung (untuk Bluetooth: termasuk sudah lolos
  /// handshake PIN).
  bool get terhubung;

  /// Paket SyncPacket yang diterima dari TV (sudah dirakit ulang
  /// bila tadinya ter-chunk di jalur Bluetooth).
  Stream<SyncPacket> get paketMasuk;

  /// Kesalahan fatal jalur dengan pesan manusiawi (koneksi putus,
  /// autentikasi ditolak, aliran korup). Setelah peristiwa ini,
  /// [terhubung] bernilai false.
  Stream<String> get kesalahan;

  /// Buka jalur ke [display]; melempar [Exception] berpesan
  /// manusiawi bila gagal (termasuk PIN ditolak di jalur Bluetooth).
  Future<void> sambung(DisplayTersimpan display);

  /// Kirim satu paket ke TV. Paket besar di jalur Bluetooth
  /// dikompresi/di-chunk oleh transport; di WebSocket selalu asli.
  void kirim(SyncPacket paket);

  /// Tutup jalur. Aman dipanggil berulang.
  Future<void> putus();
}

/// Transport WebSocket menuju server warisan tv_display masjid-you
/// (`ws://<ip>:8080`, tanpa autentikasi — persis `ws_client.dart`
/// mobile_remote).
class TransportMasjidWs implements TransportMasjid {
  TransportMasjidWs({this.port = kPortWsMasjid});

  /// Port server TV; parameter agar bisa diuji dengan server lokal.
  final int port;

  WebSocketChannel? _kanal;
  StreamSubscription<dynamic>? _langganan;
  bool _terhubung = false;

  final StreamController<SyncPacket> _paketMasuk =
      StreamController<SyncPacket>.broadcast();
  final StreamController<String> _kesalahan =
      StreamController<String>.broadcast();

  @override
  bool get terhubung => _terhubung;

  @override
  Stream<SyncPacket> get paketMasuk => _paketMasuk.stream;

  @override
  Stream<String> get kesalahan => _kesalahan.stream;

  @override
  Future<void> sambung(DisplayTersimpan display) async {
    await putus();
    final kanal = WebSocketChannel.connect(
      Uri.parse('ws://${display.ip}:$port'),
    );
    try {
      await kanal.ready;
    } catch (_) {
      throw Exception(
        'Tidak bisa menyambung ke TV masjid di ${display.ip}:$port. '
        'Pastikan aplikasi TV masjid-you sedang berjalan dan HP berada '
        'di Wi-Fi yang sama.',
      );
    }
    _kanal = kanal;
    _terhubung = true;
    _langganan = kanal.stream.listen(
      (data) {
        if (data is! String) return;
        try {
          _paketMasuk.add(SyncPacket.fromJson(data));
        } on FormatException {
          // Bingkai JSON rusak dari TV diabaikan (paritas ws_client
          // mobile_remote yang membuang paket tak ter-decode).
        }
      },
      onError: (Object _) =>
          _jalurPutus('Koneksi Wi-Fi ke TV masjid terputus.'),
      onDone: () => _jalurPutus('Koneksi Wi-Fi ke TV masjid terputus.'),
    );
  }

  void _jalurPutus(String pesan) {
    if (!_terhubung) return;
    _terhubung = false;
    _kesalahan.add(pesan);
  }

  @override
  void kirim(SyncPacket paket) {
    // Jalur WebSocket selalu mengirim gambar ASLI tanpa chunking —
    // sama seperti mobile_remote.
    _kanal?.sink.add(jsonEncode(paket.toMap()));
  }

  @override
  Future<void> putus() async {
    _terhubung = false;
    await _langganan?.cancel();
    _langganan = null;
    await _kanal?.sink.close();
    _kanal = null;
  }
}
