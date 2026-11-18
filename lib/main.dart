import 'package:flutter/material.dart';

import 'app.dart';
import 'layanan/klien_remote.dart';
import 'layanan/penyimpanan.dart';
import 'state/remote_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final penyimpanan = await PenyimpananDisplay.muat();
  final store = RemoteStore(
    klien: KlienRemoteNekios(),
    penyimpanan: penyimpanan,
  );
  runApp(NekiosRemoteApp(store: store));
}
