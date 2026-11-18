import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:nekios_remote/masjid/bingkai_bt.dart';
import 'package:nekios_remote/masjid/paket_masjid.dart';
import 'package:nekios_remote/masjid/tautan_bt.dart';
import 'package:nekios_remote/masjid/transport_masjid.dart';
import 'package:nekios_remote/model/display_tersimpan.dart';

/// Transport masjid palsu untuk test store: sambung/putus instan,
/// paket keluar dicatat, paket masuk & kesalahan dipicu manual.
class TransportMasjidPalsu implements TransportMasjid {
  bool gagalSambung = false;
  bool _terhubung = false;

  final List<SyncPacket> terkirim = [];
  DisplayTersimpan? displayTerakhir;

  final StreamController<SyncPacket> _paket =
      StreamController<SyncPacket>.broadcast();
  final StreamController<String> _kesalahan =
      StreamController<String>.broadcast();

  @override
  bool get terhubung => _terhubung;

  @override
  Stream<SyncPacket> get paketMasuk => _paket.stream;

  @override
  Stream<String> get kesalahan => _kesalahan.stream;

  @override
  Future<void> sambung(DisplayTersimpan display) async {
    if (gagalSambung) throw Exception('Sengaja gagal menyambung.');
    displayTerakhir = display;
    _terhubung = true;
  }

  @override
  void kirim(SyncPacket paket) => terkirim.add(paket);

  @override
  Future<void> putus() async {
    _terhubung = false;
  }

  /// Seolah satu paket tiba dari TV.
  void terima(SyncPacket paket) => _paket.add(paket);

  /// Seolah jalur putus dengan [pesan].
  void picuKesalahan(String pesan) {
    _terhubung = false;
    _kesalahan.add(pesan);
  }
}

/// Tautan Bluetooth palsu: kejadian dipicu manual oleh test, byte
/// keluar dicatat mentah (sudah terbingkai oleh transport).
class TautanBluetoothPalsu implements TautanBluetooth {
  final StreamController<KejadianBt> _kejadian =
      StreamController<KejadianBt>.broadcast();

  final List<Uint8List> byteTerkirim = [];
  String? alamatTerakhir;
  bool hasilSambung = true;
  int jumlahPutus = 0;

  @override
  Stream<KejadianBt> get kejadian => _kejadian.stream;

  void picu(KejadianBt kejadian) => _kejadian.add(kejadian);

  /// Semua paket yang sudah dikirim transport, di-decode dari
  /// bingkai-bingkai mentahnya.
  List<SyncPacket> get paketTerkirim {
    final pengurai = PenguraiBingkaiBt();
    return [
      for (final potongan in byteTerkirim)
        for (final bingkai in pengurai.masukkan(potongan))
          SyncPacket.fromJson(utf8.decode(bingkai)),
    ];
  }

  @override
  Future<bool> didukung() async => true;

  @override
  Future<bool> aktif() async => true;

  @override
  Future<bool> mintaAktif() async => true;

  @override
  Future<bool> punyaIzin() async => true;

  @override
  Future<bool> mintaIzin() async => true;

  @override
  Future<List<PerangkatBt>> perangkatTerpasang() async => const [];

  @override
  Future<bool> mulaiDiscovery() async => true;

  @override
  Future<void> berhentiDiscovery() async {}

  @override
  Future<bool> sambungkan(String alamat) async {
    alamatTerakhir = alamat;
    return hasilSambung;
  }

  @override
  Future<void> putuskan() async {
    jumlahPutus++;
  }

  @override
  Future<void> kirim(Uint8List bytes) async {
    byteTerkirim.add(bytes);
  }
}
