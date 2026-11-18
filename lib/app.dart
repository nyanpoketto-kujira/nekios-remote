import 'package:flutter/material.dart';

import 'state/remote_store.dart';
import 'tema.dart';
import 'ui/layar_beranda.dart';
import 'ui/layar_jadwal.dart';
import 'ui/layar_koneksi.dart';
import 'ui/layar_logo.dart';
import 'ui/layar_mading.dart';
import 'ui/layar_simulasi.dart';
import 'ui/widget_bersama.dart';

/// Akar aplikasi nekios-remote. Tema terang & gelap mengikuti sistem,
/// keduanya dari seed Nekios yang sama.
class NekiosRemoteApp extends StatelessWidget {
  const NekiosRemoteApp({super.key, required this.store});

  final RemoteStore store;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nekios Remote',
      theme: temaNekios(Brightness.light),
      darkTheme: temaNekios(Brightness.dark),
      themeMode: ThemeMode.system,
      home: LayarUtama(store: store),
    );
  }
}

/// Kerangka utama: AppBar + enam tab (Koneksi, Beranda, Mading,
/// Simulasi, Logo, Jadwal) dalam IndexedStack.
class LayarUtama extends StatefulWidget {
  const LayarUtama({super.key, required this.store});

  final RemoteStore store;

  @override
  State<LayarUtama> createState() => _LayarUtamaState();
}

class _LayarUtamaState extends State<LayarUtama> {
  int _tab = 0;

  RemoteStore get store => widget.store;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nekios Remote'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ListenableBuilder(
              listenable: store,
              builder: (context, _) => ChipStatusKoneksi(store: store),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          LayarKoneksi(store: store),
          LayarBeranda(store: store),
          LayarMading(store: store),
          LayarSimulasi(store: store),
          LayarLogo(store: store),
          LayarJadwal(store: store),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.wifi_outlined),
            selectedIcon: Icon(Icons.wifi),
            label: 'Koneksi',
          ),
          NavigationDestination(
            icon: Icon(Icons.monitor_outlined),
            selectedIcon: Icon(Icons.monitor),
            label: 'Beranda',
          ),
          NavigationDestination(
            icon: Icon(Icons.campaign_outlined),
            selectedIcon: Icon(Icons.campaign),
            label: 'Mading',
          ),
          NavigationDestination(
            icon: Icon(Icons.schedule_outlined),
            selectedIcon: Icon(Icons.schedule),
            label: 'Simulasi',
          ),
          NavigationDestination(
            icon: Icon(Icons.image_outlined),
            selectedIcon: Icon(Icons.image),
            label: 'Logo',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Jadwal',
          ),
        ],
      ),
    );
  }
}
