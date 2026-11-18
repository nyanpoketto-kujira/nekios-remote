import 'package:flutter/material.dart';

import '../domain/perintah.dart';
import '../state/remote_store.dart';
import 'widget_bersama.dart';

/// Layar Simulasi Jam: senjata demo pameran. Display menampilkan
/// keadaan seolah jam menunjukkan momen pilihan — tanpa menunggu
/// waktu asli.
///
/// - **Lompat ke bel berikutnya**: satu ketukan menuju bunyi bel
///   selanjutnya (dari snapshot `belBerikutnya`).
/// - **Lompat ke jam tertentu**: pemilih jam pada tanggal jam efektif.
/// - **Kembali ke jam nyata**: `clock.clear`.
class LayarSimulasi extends StatelessWidget {
  const LayarSimulasi({super.key, required this.store});

  final RemoteStore store;

  Future<void> _lompatKeBel(BuildContext context) async {
    final snapshot = store.snapshot;
    if (snapshot == null) return;
    final paket = perintahLompatKeBelBerikutnya(snapshot);
    if (paket == null) return;
    final yakin = await mintaKonfirmasi(
      context,
      judul: 'Lompat ke bel berikutnya?',
      isi:
          'Jam di TV akan melompat ke pukul '
          '${formatJamMenit(snapshot.belBerikutnya!)} — keadaan tampilan '
          'mengikuti seolah bel itu berbunyi sekarang.',
      tombolSetuju: 'Lompat',
    );
    if (!yakin || !context.mounted) return;
    final hasil = await store.kirimPerintah(paket);
    if (!context.mounted) return;
    tampilkanHasil(context, hasil, 'Jam TV melompat ke bel berikutnya.');
  }

  Future<void> _lompatKeJam(BuildContext context) async {
    final snapshot = store.snapshot;
    final jamEfektif = snapshot?.jamEfektif;
    if (snapshot == null || jamEfektif == null) return;
    final pilihan = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(jamEfektif),
      helpText: 'Lompat ke jam',
    );
    if (pilihan == null || !context.mounted) return;
    final teksJam = pilihan.format(context);
    final paket = perintahSimulasiKeJam(
      snapshot,
      jam: pilihan.hour,
      menit: pilihan.minute,
    );
    final hasil = await store.kirimPerintah(paket);
    if (!context.mounted) return;
    tampilkanHasil(context, hasil, 'Jam TV melompat ke $teksJam.');
  }

  Future<void> _kembaliKeJamNyata(BuildContext context) async {
    final yakin = await mintaKonfirmasi(
      context,
      judul: 'Kembali ke jam nyata?',
      isi: 'Simulasi diakhiri; TV kembali mengikuti jam sebenarnya.',
      tombolSetuju: 'Kembali',
    );
    if (!yakin || !context.mounted) return;
    final hasil = await store.kirimPerintah(perintahKembaliKeJamNyata());
    if (!context.mounted) return;
    tampilkanHasil(context, hasil, 'TV kembali ke jam nyata.');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (!store.terhubung) return const BadanBelumTerhubung();
        final theme = Theme.of(context);
        final snapshot = store.snapshot;
        final diterima = store.waktuSnapshot;
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
                            'Jam efektif di TV',
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        if (snapshot?.simulasiAktif ?? false)
                          const Chip(
                            avatar: Icon(Icons.science_outlined, size: 16),
                            label: Text('SIMULASI'),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (snapshot == null || diterima == null)
                      const Text('Menunggu snapshot…')
                    else
                      BerjalanTiapDetik(
                        builder: (context) {
                          final jam = snapshot.jamEfektifPada(
                            diterima,
                            DateTime.now(),
                          );
                          return Text(
                            jam == null ? '--:--:--' : formatJam(jam),
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          );
                        },
                      ),
                    Text(
                      (snapshot?.simulasiAktif ?? false)
                          ? 'TV sedang MENYIMULASIKAN jam di atas.'
                          : 'TV mengikuti jam nyata.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: snapshot?.belBerikutnya == null
                  ? null
                  : () => _lompatKeBel(context),
              icon: const Icon(Icons.skip_next),
              label: Text(
                snapshot?.belBerikutnya == null
                    ? 'Lompat ke bel berikutnya'
                    : 'Lompat ke bel berikutnya '
                          '(${formatJamMenit(snapshot!.belBerikutnya!)})',
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
            ),
            if (snapshot != null && snapshot.belBerikutnya == null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Tidak ada bel berikutnya pada jadwal aktif '
                  '(sudah pulang / tidak ada jadwal).',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: snapshot?.jamEfektif == null
                  ? null
                  : () => _lompatKeJam(context),
              icon: const Icon(Icons.schedule),
              label: const Text('Lompat ke jam tertentu…'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: (snapshot?.simulasiAktif ?? false)
                  ? () => _kembaliKeJamNyata(context)
                  : null,
              icon: const Icon(Icons.restore),
              label: const Text('Kembali ke jam nyata'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
          ],
        );
      },
    );
  }
}
