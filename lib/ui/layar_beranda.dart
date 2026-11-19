import 'package:flutter/material.dart';

import '../domain/perintah.dart';
import '../model/snapshot.dart';
import '../state/remote_store.dart';
import 'widget_bersama.dart';

/// Layar Beranda: cermin keadaan display dari `state.snapshot` —
/// status tampil, jam efektif (berjalan lokal di antara snapshot),
/// hitung mundur ke bel berikutnya, mading aktif, ringkasan jadwal,
/// dan status logo.
class LayarBeranda extends StatelessWidget {
  const LayarBeranda({super.key, required this.store});

  final RemoteStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (!store.terhubung) return const BadanBelumTerhubung();
        final snapshot = store.snapshot;
        if (snapshot == null || store.waktuSnapshot == null) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Menunggu snapshot dari display…'),
              ],
            ),
          );
        }
        return _IsiBeranda(store: store, snapshot: snapshot);
      },
    );
  }
}

class _IsiBeranda extends StatelessWidget {
  const _IsiBeranda({required this.store, required this.snapshot});

  final RemoteStore store;
  final SnapshotDisplay snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final diterima = store.waktuSnapshot!;
    final jadwal = snapshot.jadwal;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: scheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        snapshot.labelStatus,
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    if (snapshot.simulasiAktif)
                      Chip(
                        avatar: const Icon(Icons.science_outlined, size: 16),
                        label: const Text('SIMULASI'),
                        backgroundColor: scheme.tertiaryContainer,
                        labelStyle: TextStyle(
                          color: scheme.onTertiaryContainer,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                BerjalanTiapDetik(
                  builder: (context) {
                    final jam = snapshot.jamEfektifPada(
                      diterima,
                      DateTime.now(),
                    );
                    return Text(
                      jam == null ? '--:--:--' : formatJam(jam),
                      style: theme.textTheme.displayMedium?.copyWith(
                        color: scheme.onPrimaryContainer,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    );
                  },
                ),
                if (snapshot.slotAktif != null)
                  Text(
                    'Slot ${snapshot.slotAktif!.mulai}–${snapshot.slotAktif!.selesai}'
                    '${snapshot.slotAktif!.label != null ? ' • ${snapshot.slotAktif!.label}' : ''}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('Bel berikutnya'),
            subtitle: Text(
              snapshot.belBerikutnya == null
                  ? 'Tidak ada bel lagi pada jadwal aktif'
                  : 'Pukul ${formatJamMenit(snapshot.belBerikutnya!)}',
            ),
            trailing: snapshot.sisaKeBelDetik == null
                ? null
                : BerjalanTiapDetik(
                    builder: (context) {
                      final sisa = snapshot.sisaKeBelPada(
                        diterima,
                        DateTime.now(),
                      );
                      return Text(
                        sisa == null ? '' : formatSisaDetik(sisa),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      );
                    },
                  ),
          ),
        ),
        const SizedBox(height: 12),
        _KartuBel(store: store, snapshot: snapshot),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.campaign_outlined),
            title: const Text('Mading yang tayang'),
            subtitle: Text(
              snapshot.mading.isEmpty
                  ? '(Sambutan bawaan display)'
                  : snapshot.mading,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.school_outlined),
                    const SizedBox(width: 8),
                    Text(
                      'Jadwal di display',
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (jadwal == null)
                  const Text('Display belum memuat jadwal.')
                else ...[
                  Text(jadwal.judul, style: theme.textTheme.bodyLarge),
                  Text(
                    '${jadwal.sekolah} • ${jadwal.tahunPelajaran} • '
                    'Jurusan ${jadwal.jurusan}',
                  ),
                  Text(
                    '${jadwal.jumlahKelas} kelas • ${jadwal.jumlahHari} hari '
                    '• Hari aktif: ${jadwal.hariAktif}',
                  ),
                ],
                const Divider(height: 24),
                Row(
                  children: [
                    Icon(
                      snapshot.hasLogo
                          ? Icons.check_circle_outline
                          : Icons.cancel_outlined,
                      size: 20,
                      color: snapshot.hasLogo ? scheme.primary : scheme.error,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      snapshot.hasLogo
                          ? 'Logo terpasang di TV'
                          : 'Belum ada logo di TV',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Kartu "Bel Sekolah" di Beranda (ADR-017 nekios-school): saklar
/// bel aktif mengikuti snapshot TV (perintah `audio.konfigurasi`),
/// info bel terakhir yang berbunyi, dan tombol Tes Bel
/// (`audio.tes`). Keadaan saklar SELALU dari snapshot terbaru —
/// bukan tebakan lokal — jadi yang tampil adalah keadaan TV
/// sebenarnya.
class _KartuBel extends StatefulWidget {
  const _KartuBel({required this.store, required this.snapshot});

  final RemoteStore store;
  final SnapshotDisplay snapshot;

  @override
  State<_KartuBel> createState() => _KartuBelState();
}

class _KartuBelState extends State<_KartuBel> {
  bool _mengirim = false;

  Future<void> _aturBel(bool aktif) async {
    setState(() => _mengirim = true);
    final hasil = await widget.store.kirimPerintah(perintahAturBel(aktif));
    if (!mounted) return;
    setState(() => _mengirim = false);
    tampilkanHasil(
      context,
      hasil,
      aktif ? 'Bel sekolah diaktifkan.' : 'Bel sekolah dimatikan.',
    );
  }

  Future<void> _tesBel() async {
    setState(() => _mengirim = true);
    final hasil = await widget.store.kirimPerintah(perintahTesBel());
    if (!mounted) return;
    setState(() => _mengirim = false);
    tampilkanHasil(context, hasil, 'Tes bel diputar di TV.');
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final terakhir = snapshot.belTerakhir;
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.notifications_active_outlined),
            title: const Text('Bel sekolah'),
            subtitle: Text(
              snapshot.belAktif
                  ? 'Berbunyi otomatis tiap pergantian jam di TV'
                  : 'Diam — pergantian jam tanpa suara',
            ),
            value: snapshot.belAktif,
            onChanged: _mengirim ? null : _aturBel,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    terakhir == null
                        ? 'Belum pernah berbunyi sejak TV menyala'
                        : 'Bel terakhir: '
                              '${labelPengumumanBel(terakhir.berkas)} • '
                              '${formatJamMenit(terakhir.pada)}',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _mengirim ? null : _tesBel,
                  icon: const Icon(Icons.play_arrow_outlined),
                  label: const Text('Tes Bel'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
