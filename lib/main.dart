import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'layanan/klien_remote.dart';
import 'layanan/penyimpanan.dart';
import 'layanan/penyelidik.dart';
import 'masjid/tautan_bt.dart';
import 'masjid/transport_masjid.dart';
import 'masjid/transport_masjid_bt.dart';
import 'state/remote_store.dart';
import 'state/sesi.dart';
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
  // Preferensi kirim gambar latar tanpa kompresi (keputusan A2 #9)
  // disimpan lokal di HP, bukan di TV.
  final prefs = await SharedPreferences.getInstance();
  const kunciTanpaKompresi = 'remote.kirimLatarTanpaKompresi.v1';
  final storeMasjid = MasjidStore(
    buatTransport: (display) => display.pakaiBluetooth
        ? TransportMasjidBt(tautan)
        : TransportMasjidWs(),
    kirimLatarTanpaKompresiAwal:
        prefs.getBool(kunciTanpaKompresi) ?? false,
    onKirimLatarTanpaKompresiBerubah: (nilai) =>
        unawaited(prefs.setBool(kunciTanpaKompresi, nilai)),
  );
  // Sesi = penjaga gateway + auto-detect + shell dinamis (ADR-004).
  final sesi = SesiRemote(
    storeSekolah: store,
    storeMasjid: storeMasjid,
    pendeteksi: PendekteksiDisplay.bawaan(),
  );
  runApp(
    NekiosRemoteApp(
      store: store,
      storeMasjid: storeMasjid,
      sesi: sesi,
      tautan: tautan,
    ),
  );
}
