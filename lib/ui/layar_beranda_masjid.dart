import 'package:flutter/material.dart';

import '../masjid/model_masjid.dart';
import '../model/snapshot.dart' show formatSisaDetik;
import '../state/remote_store.dart';
import '../state/store_masjid.dart';
import 'widget_bersama.dart';

/// Format rupiah ringkas: 1750000 → `Rp1.750.000`.
String formatRupiah(int nilai) {
  final negatif = nilai < 0;
  final digit = nilai.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digit.length; i++) {
    if (i > 0 && (digit.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digit[i]);
  }
  return '${negatif ? '-' : ''}Rp$buffer';
}

/// Layar Beranda untuk display MASJID (Rute A tahap A1): cermin
/// keadaan TV dari `stateSnapshot` + `stateUpdate` — fase shalat &
/// hitung mundur, status senyap/standby, ringkasan kas — plus aksi
/// cepat fase & mode. Editor konten/pengaturan menyusul tahap
/// berikutnya; TV tetap sumber kebenaran (snapshot menggantikan
/// cermin setiap kali tiba).
class LayarBerandaMasjid extends StatelessWidget {
  const LayarBerandaMasjid({super.key, required this.store});

  final MasjidStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (!store.terhubung) return const BadanBelumTerhubung();
        if (store.snapshot == null && store.statusTv == null) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Menunggu kabar dari TV masjid…'),
              ],
            ),
          );
        }
        return _IsiBerandaMasjid(store: store);
      },
    );
  }
}

class _IsiBerandaMasjid extends StatelessWidget {
  const _IsiBerandaMasjid({required this.store});

  final MasjidStore store;

  Future<void> _aksiFase(
    BuildContext context, {
    required String judul,
    required String isi,
    required Future<HasilPerintah> Function() kirim,
    required String pesanSukses,
  }) async {
    final yakin = await mintaKonfirmasi(
      context,
      judul: judul,
      isi: isi,
      tombolSetuju: 'Kirim',
    );
    if (!yakin || !context.mounted) return;
    final hasil = await kirim();
    if (context.mounted) tampilkanHasil(context, hasil, pesanSukses);
  }

  Future<void> _aksiMode(
    BuildContext context, {
    required Future<HasilPerintah> Function() kirim,
    required String pesanSukses,
  }) async {
    final hasil = await kirim();
    if (context.mounted) tampilkanHasil(context, hasil, pesanSukses);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final snapshot = store.snapshot;
    final status = store.statusTv;
    final kas = store.ringkasanKas;
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
                        snapshot?.config.name ?? 'TV Masjid',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    if (status?.standby ?? false)
                      Chip(
                        avatar: const Icon(Icons.bedtime_outlined, size: 16),
                        label: const Text('STANDBY'),
                        backgroundColor: scheme.tertiaryContainer,
                        labelStyle: TextStyle(
                          color: scheme.onTertiaryContainer,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    if (status?.muted ?? false) ...[
                      const SizedBox(width: 8),
                      Chip(
                        avatar: const Icon(Icons.volume_off_outlined, size: 16),
                        label: const Text('SENYAP'),
                        backgroundColor: scheme.tertiaryContainer,
                        labelStyle: TextStyle(
                          color: scheme.onTertiaryContainer,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ],
                ),
                if (snapshot != null)
                  Text(
                    snapshot.config.address,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  status?.phase.label ?? 'Menunggu status fase…',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                if (status?.prayer != null)
                  Text(
                    'Shalat ${status!.prayer!.displayName}',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                if (status != null && status.totalSeconds > 0) ...[
                  const SizedBox(height: 4),
                  BerjalanTiapDetik(
                    builder: (context) {
                      final sisa = store.sisaDetikFase;
                      return Text(
                        sisa == null ? '--:--' : formatSisaDetik(sisa),
                        style: theme.textTheme.displayMedium?.copyWith(
                          color: scheme.onPrimaryContainer,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
        if (store.tvBelumPunyaData) ...[
          const SizedBox(height: 12),
          Card(
            color: scheme.errorContainer,
            child: ListTile(
              leading: Icon(
                Icons.warning_amber_outlined,
                color: scheme.onErrorContainer,
              ),
              title: Text(
                'TV belum punya data',
                style: TextStyle(color: scheme.onErrorContainer),
              ),
              subtitle: Text(
                'Snapshot TV melaporkan hasData = false (TV baru / '
                'setelah reset). Editor konten masjid menyusul tahap '
                'berikutnya; untuk sekarang isi data lewat remote lama '
                'atau menu TV.',
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Aksi cepat', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () => _aksiFase(
                        context,
                        judul: 'Lewati azan?',
                        isi:
                            'TV akan melewati fase azan yang sedang '
                            'berjalan dan lanjut ke jeda ikamah.',
                        kirim: store.lewatiAdhan,
                        pesanSukses: 'Perintah lewati azan terkirim.',
                      ),
                      icon: const Icon(Icons.skip_next_outlined),
                      label: const Text('Lewati Azan'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => _aksiFase(
                        context,
                        judul: 'Mulai ikamah sekarang?',
                        isi:
                            'TV akan masuk fase jeda ikamah untuk '
                            'shalat terkait saat ini.',
                        kirim: store.mulaiIqomah,
                        pesanSukses: 'Perintah mulai ikamah terkirim.',
                      ),
                      icon: const Icon(Icons.timer_outlined),
                      label: const Text('Mulai Ikamah'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => _aksiFase(
                        context,
                        judul: 'Mulai shalat sekarang?',
                        isi: 'TV akan masuk fase shalat berlangsung.',
                        kirim: store.mulaiShalat,
                        pesanSukses: 'Perintah mulai shalat terkirim.',
                      ),
                      icon: const Icon(Icons.play_arrow_outlined),
                      label: const Text('Mulai Shalat'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => _aksiFase(
                        context,
                        judul: 'Selesaikan shalat?',
                        isi:
                            'TV akan menutup fase shalat dan kembali '
                            'ke tampilan normal.',
                        kirim: store.selesaiShalat,
                        pesanSukses: 'Perintah selesai shalat terkirim.',
                      ),
                      icon: const Icon(Icons.stop_outlined),
                      label: const Text('Selesai Shalat'),
                    ),
                  ],
                ),
                const Divider(height: 24),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.volume_off_outlined),
                  title: const Text('Senyap (mute)'),
                  subtitle: const Text('Matikan bunyi azan & bel di TV'),
                  value: status?.muted ?? false,
                  onChanged: status == null
                      ? null
                      : (nilai) => _aksiMode(
                          context,
                          kirim: () => store.aturSenyap(nilai),
                          pesanSukses: nilai
                              ? 'TV disenyapkan.'
                              : 'Bunyi TV dinyalakan.',
                        ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.bedtime_outlined),
                  title: const Text('Standby'),
                  subtitle: const Text('Layar TV masuk mode standby'),
                  value: status?.standby ?? false,
                  onChanged: status == null
                      ? null
                      : (nilai) => _aksiMode(
                          context,
                          kirim: () => store.aturStandby(nilai),
                          pesanSukses: nilai
                              ? 'TV masuk standby.'
                              : 'TV keluar dari standby.',
                        ),
                ),
              ],
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
                    const Icon(Icons.account_balance_wallet_outlined),
                    const SizedBox(width: 8),
                    Text('Kas masjid', style: theme.textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 8),
                _barisKas('Total masuk', kas.totalMasuk),
                _barisKas('Total keluar', kas.totalKeluar),
                const Divider(height: 16),
                _barisKas('Saldo', kas.saldo, tebal: true),
              ],
            ),
          ),
        ),
        if (snapshot != null) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.info_outline),
                      const SizedBox(width: 8),
                      Text('Konten di TV', style: theme.textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${snapshot.runningTexts.where((t) => t.isActive).length} '
                    'teks berjalan aktif • '
                    '${snapshot.banners.where((b) => b.isActive).length} '
                    'banner aktif',
                  ),
                  Text(
                    '${snapshot.sideImages.length} gambar khusus • '
                    '${snapshot.backgroundImages.length} gambar latar • '
                    '${snapshot.kasTransactions.length} transaksi kas',
                  ),
                  Text(
                    snapshot.mosqueLogo != null
                        ? 'Logo masjid terpasang di TV'
                        : 'Belum ada logo masjid di TV',
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _barisKas(String label, int nilai, {bool tebal = false}) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        Text(
          formatRupiah(nilai),
          style: TextStyle(
            fontWeight: tebal ? FontWeight.bold : null,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
