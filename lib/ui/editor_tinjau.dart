import 'package:flutter/material.dart';

import '../domain/editor_jadwal.dart';
import '../domain/perintah.dart';
import '../domain/validasi_jadwal.dart';
import '../state/remote_store.dart';
import 'editor_plotting.dart' show kapital;
import 'widget_bersama.dart';

/// Layar Tinjau & Kirim Editor Jadwal: rakit dokumen utuh dari
/// sesi editor (kelas lain dari berkas asal dipertahankan apa
/// adanya; hanya kelas tersentuh yang diganti entrinya), jalankan
/// validator §7, tampilkan ringkasan perubahan per hari untuk
/// kelas aktif, lalu kirim lewat alur R2a (konfirmasi →
/// `schedule.replace` → tunggu ack/error).
class LayarTinjauKirim extends StatefulWidget {
  const LayarTinjauKirim({
    super.key,
    required this.store,
    required this.editor,
  });

  final RemoteStore store;
  final DokumenEditor editor;

  @override
  State<LayarTinjauKirim> createState() => _LayarTinjauKirimState();
}

class _LayarTinjauKirimState extends State<LayarTinjauKirim> {
  late final Map<String, dynamic> _dokumen = widget.editor.rakitDokumen();
  late final HasilValidasiJadwal _hasil = validasiJadwalJson(_dokumen);
  bool _mengirim = false;

  RemoteStore get store => widget.store;

  Future<void> _kirim() async {
    final ringkasan = _hasil.ringkasan;
    if (ringkasan == null) return;
    final yakin = await mintaKonfirmasi(
      context,
      judul: 'Ganti jadwal di TV?',
      isi:
          'Jadwal aktif akan diganti dengan "${ringkasan.judul}" '
          '(${ringkasan.jumlahKelas} kelas, ${ringkasan.jumlahHari} hari, '
          '${ringkasan.totalSlot} slot) hasil editor. Jadwal lama '
          'tidak disimpan.',
      tombolSetuju: 'Ganti jadwal',
    );
    if (!yakin) return;
    setState(() => _mengirim = true);
    final hasil = await store.kirimPerintah(perintahGantiJadwal(_dokumen));
    if (!mounted) return;
    setState(() => _mengirim = false);
    tampilkanHasil(context, hasil, 'Jadwal hasil editor aktif di TV.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final editor = widget.editor;
    final namaKelas =
        editor.daftarKelas
            .where((k) => k.id == editor.kelasAktif)
            .firstOrNull
            ?.nama ??
        editor.kelasAktif;
    final ringkasanHari = editor.ringkasanKelas(editor.kelasAktif);
    final totalKosong = ringkasanHari.fold(0, (a, r) => a + r.kosong);
    return Scaffold(
      appBar: AppBar(title: const Text('Tinjau & Kirim')),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Perubahan kelas $namaKelas',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Kelas lain dari berkas asal dipertahankan apa adanya; '
                'guru & mapel mengikuti master data hasil edit.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final r in ringkasanHari)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 80,
                                child: Text(kapital(r.namaHari)),
                              ),
                              Text(
                                '${r.terisi}/${r.totalPelajaran} slot terisi',
                              ),
                              if (r.kosong > 0) ...[
                                const SizedBox(width: 8),
                                Text(
                                  '(${r.kosong} kosong)',
                                  style: TextStyle(
                                    color: theme.colorScheme.error,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (totalKosong > 0) ...[
                const SizedBox(height: 12),
                Text(
                  'Masih ada $totalKosong slot pelajaran kosong untuk '
                  'kelas ini — validator §7 menolak jadwal yang slot '
                  'pelajarannya belum lengkap, jadi lengkapi dulu di '
                  'plotting sebelum mengirim.',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              if (_hasil.valid)
                Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    const Text('Dokumen rakitan lolos validasi §7.'),
                  ],
                )
              else ...[
                Row(
                  children: [
                    Icon(Icons.error_outline, color: theme.colorScheme.error),
                    const SizedBox(width: 8),
                    Text(
                      '${_hasil.kesalahan.length} masalah validasi',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                for (final pesan in _hasil.kesalahan.take(50))
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.error_outline, size: 18),
                    title: Text(pesan),
                  ),
                if (_hasil.kesalahan.length > 50)
                  Text('…dan ${_hasil.kesalahan.length - 50} masalah lain.'),
              ],
              const SizedBox(height: 20),
              if (!store.terhubung)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Belum terhubung ke display — sambungkan dulu dari '
                    'tab Koneksi untuk bisa mengirim.',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              FilledButton.icon(
                onPressed: _mengirim || !_hasil.valid || !store.terhubung
                    ? null
                    : _kirim,
                icon: const Icon(Icons.upload),
                label: const Text('Kirim & ganti jadwal di TV'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
