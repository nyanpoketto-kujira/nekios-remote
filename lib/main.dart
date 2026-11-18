import 'package:flutter/material.dart';

import 'app.dart';
import 'layanan/klien_remote.dart';
import 'layanan/penyimpanan.dart';
import 'masjid/tautan_bt.dart';
import 'masjid/transport_masjid.dart';
import 'masjid/transport_masjid_bt.dart';
import 'state/remote_store.dart';
import 'state/store_masjid.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final penyimpanan = await PenyimpananDisplay.muat();
  final store = RemoteStore(
    klien: KlienRemoteNekios(),
    penyimpanan: penyimpanan,
  );
  // Remote pusat (Rute A): satu tautan Bluetooth dipakai bersama oleh
  // transport BT masjid dan pemilih perangkat di layar Koneksi.
  final tautan = TautanBluetoothPlugin();
  final storeMasjid = MasjidStore(
    buatTransport: (display) => display.pakaiBluetooth
        ? TransportMasjidBt(tautan)
        : TransportMasjidWs(),
  );
  runApp(
    NekiosRemoteApp(store: store, storeMasjid: storeMasjid, tautan: tautan),
  );
}
