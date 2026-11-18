import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../domain/perintah.dart';
import '../domain/validasi_jadwal.dart';
import '../layanan/penyimpanan_draf.dart';
import '../state/remote_store.dart';
import 'layar_editor.dart';
import 'widget_bersama.dart';

/// Layar Jadwal: pintu masuk Editor Jadwal visual (R2b) + kirim
/// berkas JSON langsung (R2a): pilih berkas → validasi sisi remote
/// (aturan §7 yang sama dengan display) → ringkasan → konfirmasi →
/// `schedule.replace`. Editor bisa dipakai tanpa koneksi (draf
/// lokal); kirim berkas butuh koneksi seperti perintah lain.
class LayarJadwal extends StatefulWidget {
  const LayarJadwal({super.key, required this.store});

  final RemoteStore store;

  @override
  State<LayarJadwal> createState() => _LayarJadwalState();
}

class _LayarJadwalState extends State<LayarJadwal> {
  String? _namaBerkas;
  Map<String, dynamic>? _jadwal;
  HasilValidasiJadwal? _hasil;
  String? _pesanBaca;
  bool _mengirim = false;

  RemoteStore get store => widget.store;

  Future<void> _pilihBerkas() async {
    // API file_picker 13: metode statis, hasil berupa daftar berkas
    // (kosong = batal), isi dibaca lewat readAsBytes().
    final pilihan = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (pilihan.isEmpty) return;
    final berkas = pilihan.first;
    setState(() {
      _namaBerkas = berkas.name;
      _jadwal = null;
      _hasil = null;
      _pesanBaca = null;
    });
    final Uint8List bytes;
    try {
      bytes = await berkas.readAsBytes();
    } catch (_) {
      setState(() => _pesanBaca = 'Isi berkas tidak terbaca.');
      return;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      setState(() => _pesanBaca = 'Berkas bukan JSON yang valid.');
      return;
    }
    setState(() {
      _hasil = validasiJadwalJson(decoded);
      if (decoded is Map<String, dynamic>) _jadwal = decoded;
    });
  }

  Future<void> _kirim() async {
    final jadwal = _jadwal;
    final ringkasan = _hasil?.ringkasan;
    if (jadwal == null || ringkasan == null) return;
    final yakin = await mintaKonfirmasi(
      context,
      judul: 'Ganti jadwal di TV?',
      isi:
          'Jadwal aktif akan diganti dengan "${ringkasan.judul}" '
          '(${ringkasan.jumlahKelas} kelas, ${ringkasan.jumlahHari} hari, '
          '${ringkasan.totalSlot} slot). Jadwal lama tidak disimpan.',
      tombolSetuju: 'Ganti jadwal',
    );
    if (!yakin) return;
    setState(() => _mengirim = true);
    final hasil = await store.kirimPerintah(perintahGantiJadwal(jadwal));
    if (!mounted) return;
    setState(() => _mengirim = false);
    tampilkanHasil(context, hasil, 'Jadwal baru aktif di TV.');
  }

  Future<void> _bukaEditor() async {
    final penyimpananDraf = await PenyimpananDrafEditor.muat();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            LayarEditorJadwal(store: store, penyimpananDraf: penyimpananDraf),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final kartuEditor = Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Card(
            child: ListTile(
              leading: const Icon(Icons.edit_calendar_outlined),
              title: const Text('Editor Jadwal Visual'),
              subtitle: const Text(
                'Master data guru & mapel + plotting tap-to-assign '
                'langsung di HP. Bisa diedit tanpa koneksi (draf '
                'tersimpan otomatis).',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _bukaEditor,
            ),
          ),
        );
        if (!store.terhubung) {
          return Column(
            children: [
              kartuEditor,
              const Expanded(child: BadanBelumTerhubung()),
            ],
          );
        }
        final theme = Theme.of(context);
        final hasil = _hasil;
        final ringkasan = hasil?.ringkasan;
        return Column(
          children: [
            kartuEditor,
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Kirim jadwal (JSON)',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Pilih berkas jadwal berformat sama dengan jadwal bawaan '
                    'nekios-school. Berkas divalidasi dulu di sini — yang '
                    'tidak lolos tidak bisa dikirim.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _pilihBerkas,
                    icon: const Icon(Icons.folder_open_outlined),
                    label: Text(_namaBerkas ?? 'Pilih berkas JSON…'),
                  ),
                  if (_pesanBaca != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _pesanBaca!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                  if (ringkasan != null) ...[
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Ringkasan berkas',
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              ringkasan.judul,
                              style: theme.textTheme.bodyLarge,
                            ),
                            Text(
                              '${ringkasan.sekolah} • ${ringkasan.tahunPelajaran} '
                              '• Jurusan ${ringkasan.jurusan}',
                            ),
                            Text(
                              '${ringkasan.jumlahKelas} kelas • '
                              '${ringkasan.jumlahGuru} guru • '
                              '${ringkasan.jumlahMapel} mapel • '
                              '${ringkasan.jumlahHari} hari',
                            ),
                            Text(
                              '${ringkasan.totalSlot} slot '
                              '(${ringkasan.totalSlotPelajaran} slot pelajaran)',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (hasil != null && !hasil.valid) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${hasil.kesalahan.length} masalah ditemukan',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    for (final pesan in hasil.kesalahan.take(50))
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.error_outline, size: 18),
                        title: Text(pesan),
                      ),
                    if (hasil.kesalahan.length > 50)
                      Text('…dan ${hasil.kesalahan.length - 50} masalah lain.'),
                  ],
                  if (hasil != null && hasil.valid) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        const Text('Berkas lolos validasi §7.'),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _mengirim || hasil?.valid != true
                        ? null
                        : _kirim,
                    icon: const Icon(Icons.upload),
                    label: const Text('Kirim & ganti jadwal di TV'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
