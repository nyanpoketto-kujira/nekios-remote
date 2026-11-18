import 'package:flutter/material.dart';

import 'masjid/tautan_bt.dart';
import 'state/remote_store.dart';
import 'state/store_masjid.dart';
import 'tema.dart';
import 'ui/layar_beranda.dart';
import 'ui/layar_beranda_masjid.dart';
import 'ui/layar_jadwal.dart';
import 'ui/layar_koneksi.dart';
import 'ui/layar_logo.dart';
import 'ui/layar_mading.dart';
import 'ui/layar_simulasi.dart';
import 'ui/widget_bersama.dart';

/// Akar aplikasi nekios-remote. Tema terang & gelap mengikuti sistem,
/// keduanya dari seed Nekios yang sama.
class NekiosRemoteApp extends StatelessWidget {
  const NekiosRemoteApp({
    super.key,
    required this.store,
    required this.storeMasjid,
    required this.tautan,
  });

  final RemoteStore store;
  final MasjidStore storeMasjid;
  final TautanBluetooth tautan;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nekios Remote',
      theme: temaNekios(Brightness.light),
      darkTheme: temaNekios(Brightness.dark),
      themeMode: ThemeMode.system,
      home: LayarUtama(store: store, storeMasjid: storeMasjid, tautan: tautan),
    );
  }
}

/// Kerangka utama remote pusat: tab Koneksi dipakai bersama, lalu
/// shell mengikuti tipe display yang terakhir disambungkan —
/// shell SEKOLAH (Beranda, Mading, Simulasi, Logo, Jadwal) atau
/// shell MASJID (Beranda; Konten/Pengaturan/Tes masih placeholder
/// tahap berikutnya, Rute A tahap A1).
class LayarUtama extends StatefulWidget {
  const LayarUtama({
    super.key,
    required this.store,
    required this.storeMasjid,
    required this.tautan,
  });

  final RemoteStore store;
  final MasjidStore storeMasjid;
  final TautanBluetooth tautan;

  @override
  State<LayarUtama> createState() => _LayarUtamaState();
}

class _LayarUtamaState extends State<LayarUtama> {
  int _tab = 0;
  bool _shellMasjid = false;

  RemoteStore get store => widget.store;
  MasjidStore get storeMasjid => widget.storeMasjid;

  @override
  void initState() {
    super.initState();
    store.addListener(_ikutiKoneksi);
    storeMasjid.addListener(_ikutiKoneksi);
  }

  @override
  void dispose() {
    store.removeListener(_ikutiKoneksi);
    storeMasjid.removeListener(_ikutiKoneksi);
    super.dispose();
  }

  /// Shell mengikuti sambungan yang paling baru MULAI menyambung.
  void _ikutiKoneksi() {
    if (!mounted) return;
    var target = _shellMasjid;
    if (storeMasjid.statusKoneksi == StatusKoneksi.menyambung) {
      target = true;
    } else if (store.statusKoneksi == StatusKoneksi.menyambung) {
      target = false;
    }
    if (target != _shellMasjid) {
      setState(() {
        _shellMasjid = target;
        _tab = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final halaman = _shellMasjid ? _halamanMasjid() : _halamanSekolah();
    final tujuan = _shellMasjid ? _tujuanMasjid : _tujuanSekolah;
    final tabAman = _tab >= halaman.length ? 0 : _tab;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nekios Remote'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ListenableBuilder(
              listenable: Listenable.merge([store, storeMasjid]),
              builder: (context, _) => ChipStatusDari(
                status: _shellMasjid
                    ? storeMasjid.statusKoneksi
                    : store.statusKoneksi,
              ),
            ),
          ),
        ],
      ),
      body: IndexedStack(index: tabAman, children: halaman),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tabAman,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: tujuan,
      ),
    );
  }

  List<Widget> _halamanSekolah() => [
    LayarKoneksi(store: store, storeMasjid: storeMasjid, tautan: widget.tautan),
    LayarBeranda(store: store),
    LayarMading(store: store),
    LayarSimulasi(store: store),
    LayarLogo(store: store),
    LayarJadwal(store: store),
  ];

  List<Widget> _halamanMasjid() => [
    LayarKoneksi(store: store, storeMasjid: storeMasjid, tautan: widget.tautan),
    LayarBerandaMasjid(store: storeMasjid),
    const LayarTahapBerikut(
      judul: 'Konten masjid — tahap berikutnya',
      keterangan:
          'Editor teks berjalan, banner, kas, gambar khusus, gambar '
          'latar, dan logo untuk TV masjid dibangun pada tahap Rute A '
          'berikutnya. Tahap ini: koneksi + Beranda + aksi cepat.',
    ),
    const LayarTahapBerikut(
      judul: 'Pengaturan masjid — tahap berikutnya',
      keterangan:
          'Editor konfigurasi masjid (nama, koordinat, durasi iqamah, '
          'petugas Jumat, dan lainnya) dibangun pada tahap Rute A '
          'berikutnya.',
    ),
    const LayarTahapBerikut(
      judul: 'Tes masjid — tahap berikutnya',
      keterangan:
          'Uji fase & simulasi jadwal shalat untuk TV masjid dibangun '
          'pada tahap Rute A berikutnya.',
    ),
  ];

  static const _tujuanSekolah = [
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
  ];

  static const _tujuanMasjid = [
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
      icon: Icon(Icons.article_outlined),
      selectedIcon: Icon(Icons.article),
      label: 'Konten',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: 'Pengaturan',
    ),
    NavigationDestination(
      icon: Icon(Icons.science_outlined),
      selectedIcon: Icon(Icons.science),
      label: 'Tes',
    ),
  ];
}
