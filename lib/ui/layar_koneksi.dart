import 'package:flutter/material.dart';
import 'package:nekios_core/nekios_core.dart';

import '../model/display_tersimpan.dart';
import '../state/remote_store.dart';
import 'widget_bersama.dart';

/// Layar Koneksi: status sambungan, sambung cepat via IP (IP terakhir
/// terisi otomatis — auto-save), dan daftar display tersimpan
/// (tambah / ubah / hapus / ketuk untuk menyambung).
class LayarKoneksi extends StatefulWidget {
  const LayarKoneksi({super.key, required this.store});

  final RemoteStore store;

  @override
  State<LayarKoneksi> createState() => _LayarKoneksiState();
}

class _LayarKoneksiState extends State<LayarKoneksi> {
  late final TextEditingController _ipController;

  RemoteStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    _ipController = TextEditingController(text: store.ipTerakhir ?? '');
  }

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  Future<void> _sambungCepat() async {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) return;
    final cocok = store.daftarDisplay.where((d) => d.ip == ip);
    final display = cocok.isNotEmpty
        ? cocok.first
        : DisplayTersimpan(nama: 'Display $ip', ip: ip);
    await store.sambungkan(display);
  }

  Future<void> _dialogDisplay({int? index}) async {
    final awal = index != null ? store.daftarDisplay[index] : null;
    final namaController = TextEditingController(text: awal?.nama ?? '');
    final ipController = TextEditingController(text: awal?.ip ?? '');
    final simpan = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(awal == null ? 'Tambah display' : 'Ubah display'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: namaController,
              decoration: const InputDecoration(
                labelText: 'Nama display',
                hintText: 'Mis. TV Pameran',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ipController,
              decoration: const InputDecoration(
                labelText: 'Alamat IP',
                hintText: 'Mis. 192.168.1.20',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (simpan != true) return;
    final nama = namaController.text.trim();
    final ip = ipController.text.trim();
    if (nama.isEmpty || ip.isEmpty) return;
    final display = DisplayTersimpan(nama: nama, ip: ip);
    if (index == null) {
      await store.tambahDisplay(display);
    } else {
      await store.ubahDisplay(index, display);
    }
  }

  Future<void> _hapusDisplay(int index) async {
    final display = store.daftarDisplay[index];
    final yakin = await mintaKonfirmasi(
      context,
      judul: 'Hapus display?',
      isi: '“${display.nama}” (${display.ip}) akan dihapus dari daftar.',
      tombolSetuju: 'Hapus',
    );
    if (yakin) await store.hapusDisplay(index);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final theme = Theme.of(context);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Status koneksi',
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        ChipStatusKoneksi(store: store),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(switch (store.statusKoneksi) {
                      StatusKoneksi.terhubung =>
                        'Terhubung ke ${store.displayAktif?.nama ?? ''} '
                            '(${store.displayAktif?.ip ?? ''}:$kNekiosPort)',
                      StatusKoneksi.menyambung =>
                        'Menyambung ke ${store.displayAktif?.ip ?? ''}…',
                      StatusKoneksi.terputus =>
                        'Tidak ada display yang terhubung.',
                    }, style: theme.textTheme.bodyMedium),
                    if (store.pesanKoneksi != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        store.pesanKoneksi!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                    if (store.terhubung) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => store.putuskan(),
                        icon: const Icon(Icons.link_off),
                        label: const Text('Putuskan'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Sambung cepat', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _ipController,
                    decoration: InputDecoration(
                      labelText: 'Alamat IP display',
                      hintText: 'Mis. 192.168.1.20',
                      helperText:
                          'Port tetap $kNekiosPort. IP terakhir '
                          'tersimpan otomatis.',
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.url,
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: store.statusKoneksi == StatusKoneksi.menyambung
                      ? null
                      : _sambungCepat,
                  icon: const Icon(Icons.wifi),
                  label: const Text('Sambungkan'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Display tersimpan',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _dialogDisplay(),
                  icon: const Icon(Icons.add),
                  label: const Text('Tambah'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (store.daftarDisplay.isEmpty)
              Text(
                'Belum ada display tersimpan. Tambahkan TV pameran di '
                'sini supaya menyambung berikutnya tinggal ketuk.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            for (var i = 0; i < store.daftarDisplay.length; i++)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.tv),
                  title: Text(store.daftarDisplay[i].nama),
                  subtitle: Text('${store.daftarDisplay[i].ip}:$kNekiosPort'),
                  trailing: PopupMenuButton<String>(
                    onSelected: (pilihan) {
                      if (pilihan == 'ubah') _dialogDisplay(index: i);
                      if (pilihan == 'hapus') _hapusDisplay(i);
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'ubah', child: Text('Ubah')),
                      PopupMenuItem(value: 'hapus', child: Text('Hapus')),
                    ],
                  ),
                  onTap: () => store.sambungkan(store.daftarDisplay[i]),
                ),
              ),
          ],
        );
      },
    );
  }
}
