import 'package:flutter/material.dart';
import 'package:nekios_core/nekios_core.dart';

import 'masjid/tautan_bt.dart';
import 'masjid/transport_masjid.dart';
import 'model/display_tersimpan.dart';
import 'state/remote_store.dart';
import 'state/sesi.dart';
import 'state/store_masjid.dart';
import 'tema.dart';
import 'ui/layar_beranda.dart';
import 'ui/layar_beranda_masjid.dart';
import 'ui/layar_gateway.dart';
import 'ui/layar_jadwal.dart';
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
    required this.sesi,
    required this.tautan,
  });

  final RemoteStore store;
  final MasjidStore storeMasjid;
  final SesiRemote sesi;
  final TautanBluetooth tautan;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nekios Remote',
      theme: temaNekios(Brightness.light),
      darkTheme: temaNekios(Brightness.dark),
      themeMode: ThemeMode.system,
      home: LayarUtama(
        store: store,
        storeMasjid: storeMasjid,
        sesi: sesi,
        tautan: tautan,
      ),
    );
  }
}

/// Penjaga akar aplikasi (connection guard + dynamic shell, ADR-004):
/// * tidak ada store terhubung → [LayarGateway] (satu-satunya jalan
///   masuk; dashboard tidak bisa dicapai sebelum koneksi sukses);
/// * [RemoteStore] terhubung → shell SEKOLAH;
/// * [MasjidStore] terhubung → shell MASJID.
/// Putus (sengaja atau tak terduga) mengembalikan tampilan ke
/// gateway secara otomatis karena tidak ada lagi store terhubung.
class LayarUtama extends StatelessWidget {
  const LayarUtama({
    super.key,
    required this.store,
    required this.storeMasjid,
    required this.sesi,
    required this.tautan,
  });

  final RemoteStore store;
  final MasjidStore storeMasjid;
  final SesiRemote sesi;
  final TautanBluetooth tautan;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([store, storeMasjid, sesi]),
      builder: (context, _) {
        if (store.terhubung) {
          return _ShellSekolah(store: store, sesi: sesi);
        }
        if (storeMasjid.terhubung) {
          return _ShellMasjid(store: storeMasjid, sesi: sesi);
        }
        return LayarGateway(sesi: sesi, tautan: tautan);
      },
    );
  }
}

/// Strip status koneksi di puncak shell: display aktif + jalur,
/// dan aksi Putuskan (kembali ke gateway). Menggantikan tab Koneksi
/// lama — urusan menyambung sepenuhnya milik gateway.
class _StripKoneksi extends StatelessWidget {
  const _StripKoneksi({
    required this.nama,
    required this.keterangan,
    required this.onPutus,
  });

  final String nama;
  final String keterangan;
  final VoidCallback onPutus;

  @override
  Widget build(BuildContext context) {
    final skema = Theme.of(context).colorScheme;
    return Material(
      color: skema.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            Icon(Icons.tv_outlined, size: 20, color: skema.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Terhubung ke $nama · $keterangan',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            TextButton.icon(
              onPressed: onPutus,
              icon: const Icon(Icons.link_off, size: 18),
              label: const Text('Putuskan'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shell SEKOLAH: Beranda, Mading, Simulasi, Logo, Jadwal.
class _ShellSekolah extends StatefulWidget {
  const _ShellSekolah({required this.store, required this.sesi});

  final RemoteStore store;
  final SesiRemote sesi;

  @override
  State<_ShellSekolah> createState() => _ShellSekolahState();
}

class _ShellSekolahState extends State<_ShellSekolah> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final halaman = [
      LayarBeranda(store: store),
      LayarMading(store: store),
      LayarSimulasi(store: store),
      LayarLogo(store: store),
      LayarJadwal(store: store),
    ];
    final tabAman = _tab >= halaman.length ? 0 : _tab;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nekios Remote'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ChipStatusDari(status: store.statusKoneksi),
          ),
        ],
      ),
      body: Column(
        children: [
          _StripKoneksi(
            nama: store.displayAktif?.nama ?? '',
            keterangan:
                'Wi-Fi · ${store.displayAktif?.ip ?? ''}:$kNekiosPort',
            onPutus: () => widget.sesi.putuskan(),
          ),
          Expanded(child: IndexedStack(index: tabAman, children: halaman)),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tabAman,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: const [
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

/// Shell MASJID: Beranda; Konten/Pengaturan/Tes masih placeholder
/// tahap A2 (Rute A).
class _ShellMasjid extends StatefulWidget {
  const _ShellMasjid({required this.store, required this.sesi});

  final MasjidStore store;
  final SesiRemote sesi;

  @override
  State<_ShellMasjid> createState() => _ShellMasjidState();
}

class _ShellMasjidState extends State<_ShellMasjid> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final halaman = [
      LayarBerandaMasjid(store: store),
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
    final tabAman = _tab >= halaman.length ? 0 : _tab;
    final aktif = store.displayAktif;
    final keterangan = switch (aktif?.transport) {
      JalurMasjid.bluetooth =>
        'Bluetooth · ${aktif?.namaBluetooth ?? ''} ${aktif?.alamatBluetooth ?? ''}',
      _ => 'Wi-Fi · ${aktif?.ip ?? ''}:$kPortWsMasjid',
    };
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nekios Remote'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ChipStatusDari(status: store.statusKoneksi),
          ),
        ],
      ),
      body: Column(
        children: [
          _StripKoneksi(
            nama: aktif?.nama ?? '',
            keterangan: keterangan,
            onPutus: () => widget.sesi.putuskan(),
          ),
          Expanded(child: IndexedStack(index: tabAman, children: halaman)),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tabAman,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: const [
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
        ],
      ),
    );
  }
}
