import 'package:flutter/material.dart';

import '../masjid/model_masjid.dart';
import '../model/snapshot.dart' show formatSisaDetik;
import '../state/store_masjid.dart';
import 'widget_bersama.dart';

/// Layar Tes untuk display MASJID (Rute A tahap A2a): kartu status
/// fase TV dari `stateUpdate` + tombol paksa fase (`forcePhase`)
/// untuk menguji overlay & state machine TV, berkelompok persis
/// seperti layar simulasi mobile_remote — Hari Biasa dan Hari
/// Jumat. TV tetap sumber kebenaran: keberhasilan perintah
/// dibuktikan kartu status yang berubah mengikuti broadcast TV.
///
/// Keputusan terkunci (ADR-006): SEMUA fase selain Normal wajib
/// konfirmasi sebelum ditembak; Khutbah nonaktif bila konfigurasi
/// TV tidak memakai shalat Jumat; `triggerBeep` BUKAN kontrol di
/// sini — aksi itu mati dan remote tidak pernah mengirimnya.
class LayarTesMasjid extends StatelessWidget {
  const LayarTesMasjid({super.key, required this.store});

  final MasjidStore store;

  static const _faseBiasa = <(PrayerPhase, IconData, String)>[
    (PrayerPhase.normal, Icons.rocket_launch_outlined, 'Normal (Standby)'),
    (
      PrayerPhase.preAdhan,
      Icons.access_time_filled,
      'PRE_ADHAN · Menjelang Azan',
    ),
    (PrayerPhase.adhan, Icons.campaign, 'ADHAN · Azan Berkumandang'),
    (PrayerPhase.preIqomah, Icons.groups, 'PRE_IQOMAH · Jeda Ikamah'),
    (PrayerPhase.shalat, Icons.dark_mode, 'SHALAT · Shalat Berlangsung'),
  ];

  static const _faseJumat = <(PrayerPhase, IconData, String)>[
    (PrayerPhase.khutbah, Icons.menu_book_rounded, 'KHUTBAH · Khutbah Jumat'),
  ];

  Future<void> _paksaFase(BuildContext context, PrayerPhase fase) async {
    // Normal adalah jalan pulang dari pengujian — tanpa gesekan.
    // Fase lain mengubah tampilan TV seketika, jadi wajib
    // konfirmasi (keputusan #12).
    if (fase != PrayerPhase.normal) {
      final yakin = await mintaKonfirmasi(
        context,
        judul: 'Paksa fase ${fase.label}?',
        isi:
            'TV akan langsung masuk fase ${fase.label} dengan '
            'durasi penuh dari konfigurasinya.',
        tombolSetuju: 'Paksa',
      );
      if (!yakin || !context.mounted) return;
    }
    final hasil = await store.paksaFase(fase);
    if (context.mounted) {
      tampilkanHasil(
        context,
        hasil,
        'Perintah paksa fase ${fase.label} terkirim.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (!store.terhubung) return const BadanBelumTerhubung();
        return _IsiTesMasjid(store: store, paksaFase: _paksaFase);
      },
    );
  }
}

class _IsiTesMasjid extends StatelessWidget {
  const _IsiTesMasjid({required this.store, required this.paksaFase});

  final MasjidStore store;
  final Future<void> Function(BuildContext, PrayerPhase) paksaFase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = store.statusTv;
    final sibuk = store.sedangMengirim;
    final tanpaJumat = store.snapshot != null &&
        !store.snapshot!.config.hasFridayPrayer;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: scheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Menu Tes — Simulasi Waktu Shalat',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Paksa TV masuk ke fase tertentu untuk menguji '
                  'overlay, state machine, dan tombol aksi cepat.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 12),
                if (status == null)
                  Row(
                    children: [
                      Icon(
                        Icons.tv_outlined,
                        size: 18,
                        color: scheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Belum ada status fase dari TV.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  )
                else ...[
                  Text(
                    status.phase.label,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  if (status.prayer != null)
                    Text(
                      'Shalat ${status.prayer!.displayName}',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  if (status.totalSeconds > 0) ...[
                    const SizedBox(height: 4),
                    BerjalanTiapDetik(
                      builder: (context) {
                        final sisa = store.sisaDetikFase;
                        return Text(
                          sisa == null ? '--:--' : formatSisaDetik(sisa),
                          style: theme.textTheme.displayMedium?.copyWith(
                            color: scheme.onPrimaryContainer,
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        );
                      },
                    ),
                    Text(
                      'dari total ${formatSisaDetik(status.totalSeconds)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _KartuGrupFase(
          judul: 'Paksa Fase — Hari Biasa',
          anak: [
            for (final (fase, ikon, label) in LayarTesMasjid._faseBiasa)
              _tombolFase(context, fase, ikon, label, aktif: !sibuk),
          ],
        ),
        const SizedBox(height: 16),
        _KartuGrupFase(
          judul: 'Paksa Fase — Hari Jumat',
          anak: [
            for (final (fase, ikon, label) in LayarTesMasjid._faseJumat)
              _tombolFase(
                context,
                fase,
                ikon,
                label,
                aktif: !sibuk && !tanpaJumat,
              ),
            if (tanpaJumat)
              Text(
                'Nonaktif: konfigurasi TV tidak memakai shalat '
                'Jumat. Nyalakan "Shalat Jumat" di Pengaturan untuk '
                'menguji fase Khutbah.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.error,
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Catatan: fase masuk dengan durasi penuh dari konfigurasi. '
          'Setelah selesai uji, tekan "Normal (Standby)" untuk '
          'kembali ke dashboard.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _tombolFase(
    BuildContext context,
    PrayerPhase fase,
    IconData ikon,
    String label, {
    required bool aktif,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.tonalIcon(
          onPressed: aktif ? () => paksaFase(context, fase) : null,
          icon: Icon(ikon),
          label: Text(label),
        ),
      ),
    );
  }
}

class _KartuGrupFase extends StatelessWidget {
  const _KartuGrupFase({required this.judul, required this.anak});

  final String judul;
  final List<Widget> anak;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              judul,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ...anak,
          ],
        ),
      ),
    );
  }
}
