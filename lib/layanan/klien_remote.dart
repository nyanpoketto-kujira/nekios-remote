import 'package:nekios_core/nekios_core.dart';

/// Antarmuka klien WebSocket remote — sengaja tipis supaya store bisa
/// diuji dengan klien palsu tanpa jaringan sungguhan.
abstract interface class KlienRemote {
  /// Apakah jalur ke display sedang tersambung.
  bool get terhubung;

  /// Stream paket balasan dari display (ack / error / state.snapshot).
  Stream<NekiosPacket> get paketMasuk;

  /// Menyambung ke display di [host]:[port]; melempar bila gagal.
  Future<void> sambung(String host, {int port = kNekiosPort});

  /// Kirim satu paket perintah ke display.
  void kirim(NekiosPacket paket);

  /// Putuskan koneksi. Aman dipanggil berulang.
  Future<void> putus();
}

/// Implementasi [KlienRemote] di atas [NekiosKlien] dari nekios_core.
class KlienRemoteNekios implements KlienRemote {
  KlienRemoteNekios([NekiosKlien? klien]) : _klien = klien ?? NekiosKlien();

  final NekiosKlien _klien;

  @override
  bool get terhubung => _klien.isConnected;

  @override
  Stream<NekiosPacket> get paketMasuk => _klien.packets;

  @override
  Future<void> sambung(String host, {int port = kNekiosPort}) =>
      _klien.connect(host, port: port);

  @override
  void kirim(NekiosPacket paket) => _klien.send(paket);

  @override
  Future<void> putus() => _klien.close();
}
