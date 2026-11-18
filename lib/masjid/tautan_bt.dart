/// Abstraksi tautan Bluetooth Classic mentah di atas plugin lokal
/// `bluetooth_rfcomm` — supaya transport Bluetooth masjid bisa diuji
/// unit dengan tautan palsu, tanpa perangkat sungguhan (ADR-003).
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:bluetooth_rfcomm/bluetooth_rfcomm.dart';

/// Perangkat Bluetooth yang dikenal remote (bonded / hasil temuan).
class PerangkatBt {
  const PerangkatBt({required this.nama, required this.alamat});

  final String nama;
  final String alamat;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PerangkatBt && other.nama == nama && other.alamat == alamat;

  @override
  int get hashCode => Object.hash(nama, alamat);

  @override
  String toString() => 'PerangkatBt(nama: $nama, alamat: $alamat)';
}

/// Kejadian dari tautan Bluetooth mentah.
sealed class KejadianBt {
  const KejadianBt();
}

/// Socket RFCOMM terhubung ke [perangkat].
class BtTerhubung extends KejadianBt {
  const BtTerhubung(this.perangkat);
  final PerangkatBt perangkat;
}

/// Potongan byte mentah yang tiba dari socket (belum dibingkai).
class BtData extends KejadianBt {
  const BtData(this.bytes);
  final Uint8List bytes;
}

/// Koneksi berakhir.
class BtTerputus extends KejadianBt {
  const BtTerputus();
}

/// Kegagalan koneksi/aliran (pesan dari lapisan native).
class BtGagal extends KejadianBt {
  const BtGagal(this.pesan);
  final String pesan;
}

/// Satu perangkat ditemukan selama discovery.
class BtDitemukan extends KejadianBt {
  const BtDitemukan(this.perangkat);
  final PerangkatBt perangkat;
}

/// Discovery selesai.
class BtDiscoverySelesai extends KejadianBt {
  const BtDiscoverySelesai();
}

/// Tautan Bluetooth Classic mentah: byte masuk/keluar apa adanya.
/// Pembingkaian & protokol adalah urusan pemanggil.
abstract interface class TautanBluetooth {
  Stream<KejadianBt> get kejadian;

  Future<bool> didukung();
  Future<bool> aktif();
  Future<bool> mintaAktif();
  Future<bool> punyaIzin();
  Future<bool> mintaIzin();
  Future<List<PerangkatBt>> perangkatTerpasang();
  Future<bool> mulaiDiscovery();
  Future<void> berhentiDiscovery();

  /// Mulai upaya menyambung ke [alamat]; hasil akhirnya tiba sebagai
  /// [BtTerhubung]/[BtGagal]. `false` = upaya gagal dimulai.
  Future<bool> sambungkan(String alamat);

  Future<void> putuskan();
  Future<void> kirim(Uint8List bytes);
}

/// [TautanBluetooth] di atas plugin lokal `bluetooth_rfcomm`
/// (Android). Di platform tanpa plugin, panggilan melempar
/// MissingPluginException — transport memperlakukannya sebagai
/// kegagalan sambungan biasa.
class TautanBluetoothPlugin implements TautanBluetooth {
  TautanBluetoothPlugin([BluetoothRfcomm? plugin])
    : _plugin = plugin ?? BluetoothRfcomm();

  final BluetoothRfcomm _plugin;

  @override
  Stream<KejadianBt> get kejadian => _plugin.peristiwa.map((peristiwa) {
    return switch (peristiwa) {
      RfcommTerhubung(:final perangkat) => BtTerhubung(
        PerangkatBt(nama: perangkat.name, alamat: perangkat.address),
      ),
      RfcommData(:final bytes) => BtData(bytes),
      RfcommTerputus() => const BtTerputus(),
      RfcommGagal(:final pesan) => BtGagal(pesan),
      RfcommPerangkatDitemukan(:final perangkat) => BtDitemukan(
        PerangkatBt(nama: perangkat.name, alamat: perangkat.address),
      ),
      RfcommDiscoverySelesai() => const BtDiscoverySelesai(),
    };
  });

  @override
  Future<bool> didukung() => _plugin.didukung;

  @override
  Future<bool> aktif() => _plugin.aktif;

  @override
  Future<bool> mintaAktif() => _plugin.mintaAktif();

  @override
  Future<bool> punyaIzin() => _plugin.punyaIzin;

  @override
  Future<bool> mintaIzin() => _plugin.mintaIzin();

  @override
  Future<List<PerangkatBt>> perangkatTerpasang() async => [
    for (final p in await _plugin.perangkatTerpasang())
      PerangkatBt(nama: p.name, alamat: p.address),
  ];

  @override
  Future<bool> mulaiDiscovery() => _plugin.mulaiDiscovery();

  @override
  Future<void> berhentiDiscovery() => _plugin.berhentiDiscovery();

  @override
  Future<bool> sambungkan(String alamat) => _plugin.sambungkan(alamat);

  @override
  Future<void> putuskan() => _plugin.putuskan();

  @override
  Future<void> kirim(Uint8List bytes) => _plugin.kirim(bytes);
}
