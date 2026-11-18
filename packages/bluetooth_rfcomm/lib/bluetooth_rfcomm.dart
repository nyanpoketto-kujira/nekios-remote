/// Plugin Bluetooth Classic (RFCOMM) sisi klien — pipa byte MENTAH.
///
/// Port dari separuh klien plugin `bluetooth_sync` masjid-you
/// (Rute A, ADR-003): kontrak channel & perilaku native-nya sama,
/// tetapi plugin ini SENGAJA tidak membingkai byte dan tidak menjadi
/// host. Framing 4-byte big-endian + JSON, handshake PIN, dan chunking
/// hidup di lapisan Dart nekios-remote (`lib/masjid/`) agar teruji
/// unit; di kabel hasilnya identik dengan implementasi masjid-you.
///
/// Android saja — platform lain melempar [MissingPluginException]
/// dari channel, yang ditangani lapisan transport sebagai "Bluetooth
/// tidak tersedia".
library;

import 'dart:async';

import 'package:flutter/services.dart';

/// UUID layanan RFCOMM tv_display masjid-you (tetap, dari
/// `bluetooth_sync` masjid-you).
const String kUuidRfcommMasjid = '8f5f0b1a-2c3d-4e5f-8a9b-1c2d3e4f5a6b';

/// Perangkat Bluetooth (bonded atau hasil discovery).
class PerangkatRfcomm {
  const PerangkatRfcomm({required this.name, required this.address});

  final String name;
  final String address;

  factory PerangkatRfcomm.fromMap(Map<dynamic, dynamic> map) => PerangkatRfcomm(
    name: map['name'] as String? ?? '',
    address: map['address'] as String? ?? '',
  );

  Map<String, String> toMap() => {'name': name, 'address': address};

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PerangkatRfcomm &&
          other.name == name &&
          other.address == address;

  @override
  int get hashCode => Object.hash(name, address);

  @override
  String toString() => 'PerangkatRfcomm(name: $name, address: $address)';
}

/// Peristiwa dari lapisan native plugin.
sealed class PeristiwaRfcomm {
  const PeristiwaRfcomm();
}

/// Socket RFCOMM terhubung ke perangkat [perangkat].
class RfcommTerhubung extends PeristiwaRfcomm {
  const RfcommTerhubung(this.perangkat);
  final PerangkatRfcomm perangkat;
}

/// Potongan byte mentah yang baru tiba dari socket (belum dibingkai).
class RfcommData extends PeristiwaRfcomm {
  const RfcommData(this.bytes);
  final Uint8List bytes;
}

/// Koneksi berakhir (diputus lokal atau dari sisi TV).
class RfcommTerputus extends PeristiwaRfcomm {
  const RfcommTerputus();
}

/// Kegagalan koneksi/aliran dengan pesan yang bisa ditampilkan.
class RfcommGagal extends PeristiwaRfcomm {
  const RfcommGagal(this.pesan);
  final String pesan;
}

/// Satu perangkat ditemukan selama discovery.
class RfcommPerangkatDitemukan extends PeristiwaRfcomm {
  const RfcommPerangkatDitemukan(this.perangkat);
  final PerangkatRfcomm perangkat;
}

/// Discovery selesai (berhenti sendiri atau diminta).
class RfcommDiscoverySelesai extends PeristiwaRfcomm {
  const RfcommDiscoverySelesai();
}

/// Klien channel plugin. Satu instance cukup untuk seluruh aplikasi;
/// socket-nya tunggal (satu TV pada satu waktu), sama seperti sumber.
class BluetoothRfcomm {
  static const MethodChannel _methods = MethodChannel(
    'id.nekios/bluetooth_rfcomm',
  );
  static const EventChannel _events = EventChannel(
    'id.nekios/bluetooth_rfcomm/events',
  );

  Stream<PeristiwaRfcomm>? _peristiwa;

  /// Aliran peristiwa native (broadcast). Berlangganan TIDAK memulai
  /// apa pun selain stream platform.
  Stream<PeristiwaRfcomm> get peristiwa =>
      _peristiwa ??= _events.receiveBroadcastStream().map(_petakanPeristiwa);

  static PeristiwaRfcomm _petakanPeristiwa(Object? mentah) {
    if (mentah is Map) {
      switch (mentah['type'] as String?) {
        case 'connected':
          final device = mentah['device'];
          return RfcommTerhubung(
            device is Map
                ? PerangkatRfcomm.fromMap(device)
                : const PerangkatRfcomm(name: '', address: ''),
          );
        case 'data':
          final data = mentah['data'];
          return RfcommData(
            data is Uint8List ? data : Uint8List.fromList(const []),
          );
        case 'disconnected':
          return const RfcommTerputus();
        case 'error':
          return RfcommGagal(
            mentah['message'] as String? ?? 'Kesalahan Bluetooth',
          );
        case 'discovered':
          return RfcommPerangkatDitemukan(
            PerangkatRfcomm(
              name: mentah['name'] as String? ?? '',
              address: mentah['address'] as String? ?? '',
            ),
          );
        case 'discoveryFinished':
          return const RfcommDiscoverySelesai();
      }
    }
    return const RfcommGagal('Peristiwa Bluetooth tidak dikenal');
  }

  /// Perangkat punya hardware Bluetooth.
  Future<bool> get didukung async =>
      await _methods.invokeMethod<bool>('isSupported') ?? false;

  /// Bluetooth sedang menyala.
  Future<bool> get aktif async =>
      await _methods.invokeMethod<bool>('isEnabled') ?? false;

  /// Minta menyalakan Bluetooth (dialog sistem). `false` bila
  /// pengguna menolak.
  Future<bool> mintaAktif() async =>
      await _methods.invokeMethod<bool>('enable') ?? false;

  /// Semua izin runtime Bluetooth sudah diberikan.
  Future<bool> get punyaIzin async =>
      await _methods.invokeMethod<bool>('hasPermission') ?? false;

  /// Minta izin runtime Bluetooth bila belum ada.
  Future<bool> mintaIzin() async =>
      await _methods.invokeMethod<bool>('requestPermission') ?? false;

  /// Daftar perangkat yang sudah ter-bond (pernah dipasangkan).
  Future<List<PerangkatRfcomm>> perangkatTerpasang() async {
    final mentah = await _methods.invokeMethod<List<dynamic>>(
      'getBondedDevices',
    );
    return [
      for (final d in mentah ?? const [])
        if (d is Map) PerangkatRfcomm.fromMap(d),
    ];
  }

  /// Mulai discovery perangkat Classic di sekitar.
  Future<bool> mulaiDiscovery() async =>
      await _methods.invokeMethod<bool>('startDiscovery') ?? false;

  /// Hentikan discovery yang sedang berjalan.
  Future<void> berhentiDiscovery() async {
    await _methods.invokeMethod<bool>('stopDiscovery');
  }

  /// Sambungkan socket RFCOMM (insecure, sama seperti sumber) ke
  /// [address] dengan service [uuid]. Sukses/gagal tiba sebagai
  /// peristiwa [RfcommTerhubung]/[RfcommGagal]; nilai kembali hanya
  /// menandakan upaya dimulai.
  Future<bool> sambungkan(
    String address, {
    String uuid = kUuidRfcommMasjid,
  }) async =>
      await _methods.invokeMethod<bool>('connect', {
        'address': address,
        'uuid': uuid,
      }) ??
      false;

  /// Putuskan koneksi aktif.
  Future<void> putuskan() async {
    await _methods.invokeMethod<bool>('disconnect');
  }

  /// Ada socket yang sedang terhubung.
  Future<bool> get tersambung async =>
      await _methods.invokeMethod<bool>('isConnected') ?? false;

  /// Kirim byte MENTAH apa adanya (pembingkaian adalah urusan
  /// pemanggil). Melempar [PlatformException] bila tidak terhubung.
  Future<void> kirim(Uint8List bytes) async {
    await _methods.invokeMethod<bool>('send', bytes);
  }
}
