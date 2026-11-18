import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/editor_jadwal.dart';
import '../domain/validasi_jadwal.dart';
import '../layanan/penyimpanan_draf.dart';
import '../state/remote_store.dart';
import 'editor_master_data.dart';
import 'editor_plotting.dart';
import 'editor_tinjau.dart';

/// Label sumber untuk sesi dari aset bawaan aplikasi.
const String kLabelJadwalBawaan = 'Jadwal bawaan SMKN 1 Ukui';

/// Editor Jadwal visual (R2b) — pintu masuknya dari tab Jadwal.
///
/// Layar awal menawarkan titik mulai sesi:
/// - jadwal bawaan SMKN 1 Ukui (aset aplikasi, salinan
///   `assets/jadwal-tkj.json` nekios-school),
/// - berkas JSON jadwal dari penyimpanan HP,
/// - "Lanjutkan draf" untuk draf lokal per kelas yang tersimpan
///   otomatis setiap ada perubahan.
///
/// Sesi berjalan: pemilih kelas + dua tahap (Master Data |
/// Plotting) + tombol Tinjau & Kirim. Mengedit bisa dilakukan
/// tanpa koneksi; koneksi hanya perlu saat mengirim.
class LayarEditorJadwal extends StatefulWidget {
  const LayarEditorJadwal({
    super.key,
    required this.store,
    required this.penyimpananDraf,
    this.editorAwal,
  });

  final RemoteStore store;
  final PenyimpananDrafEditor penyimpananDraf;

  /// Sesi yang langsung dibuka (melewati layar awal) — dipakai
  /// test dan pemulihan draf.
  final DokumenEditor? editorAwal;

  @override
  State<LayarEditorJadwal> createState() => _LayarEditorJadwalState();
}

class _LayarEditorJadwalState extends State<LayarEditorJadwal> {
  DokumenEditor? _editor;
  String? _pesanMuat;

  @override
  void initState() {
    super.initState();
    _editor = widget.editorAwal;
  }

  /// Setiap perubahan sesi: bangun ulang UI + simpan draf otomatis.
  void _berubah() {
    final editor = _editor;
    if (editor == null) return;
    setState(() {});
    unawaited(widget.penyimpananDraf.simpan(editor));
  }

  void _mulaiSesi(DokumenEditor editor) {
    setState(() {
      _editor = editor;
      _pesanMuat = null;
    });
    unawaited(widget.penyimpananDraf.simpan(editor));
  }

  Future<void> _mulaiDariBawaan() async {
    try {
      final teks = await rootBundle.loadString('assets/jadwal-bawaan.json');
      final decoded = jsonDecode(teks);
      if (decoded is! Map<String, dynamic>) {
        setState(() => _pesanMuat = 'Jadwal bawaan tidak terbaca.');
        return;
      }
      _mulaiSesi(
        DokumenEditor.dariDokumen(decoded, labelSumber: kLabelJadwalBawaan),
      );
    } catch (_) {
      setState(() => _pesanMuat = 'Jadwal bawaan tidak terbaca.');
    }
  }

  Future<void> _mulaiDariBerkas() async {
    final pilihan = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (pilihan == null || pilihan.files.isEmpty) return;
    final berkas = pilihan.files.first;
    final bytes = berkas.bytes;
    if (bytes == null) {
      setState(() => _pesanMuat = 'Isi berkas tidak terbaca.');
      return;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      setState(() => _pesanMuat = 'Berkas bukan JSON yang valid.');
      return;
    }
    if (decoded is! Map<String, dynamic>) {
      setState(() => _pesanMuat = 'Berkas bukan objek JSON jadwal.');
      return;
    }
    final hasil = validasiJadwalJson(decoded);
    if (hasil.ringkasan == null) {
      setState(
        () => _pesanMuat =
            'Struktur berkas tidak terbaca sebagai jadwal '
            '(${hasil.kesalahan.firstOrNull ?? 'alasan tidak diketahui'}).',
      );
      return;
    }
    _mulaiSesi(DokumenEditor.dariDokumen(decoded, labelSumber: berkas.name));
    if (!hasil.valid && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Berkas punya ${hasil.kesalahan.length} masalah validasi §7 — '
            'tetap bisa diedit, tetapi harus beres sebelum bisa dikirim.',
          ),
        ),
      );
    }
  }

  void _lanjutkanDraf(InfoDraf info) {
    final editor = widget.penyimpananDraf.ambil(info.kelasId);
    if (editor == null) {
      setState(() => _pesanMuat = 'Draf untuk ${info.kelasId} tidak terbaca.');
      return;
    }
    setState(() {
      _editor = editor;
      _pesanMuat = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final editor = _editor;
    if (editor == null) return _bangunLayarAwal(context);
    return _bangunSesi(context, editor);
  }

  Widget _bangunLayarAwal(BuildContext context) {
    final theme = Theme.of(context);
    final draf = widget.penyimpananDraf.daftarDraf();
    return Scaffold(
      appBar: AppBar(title: const Text('Editor Jadwal')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Buat & ubah jadwal langsung di HP — bukan tabel Excel: '
            'atur master data guru & mapel dulu, lalu plotting dengan '
            'ketuk slot.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (_pesanMuat != null) ...[
            const SizedBox(height: 12),
            Text(_pesanMuat!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 20),
          Text('Mulai baru', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.school_outlined),
              title: const Text('Dari jadwal bawaan SMKN 1 Ukui'),
              subtitle: const Text(
                'Jadwal TKJ yang sama dengan bawaan nekios-school.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _mulaiDariBawaan,
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.folder_open_outlined),
              title: const Text('Muat dari berkas JSON…'),
              subtitle: const Text(
                'Master data, templat slot, dan entri terisi dari berkas.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _mulaiDariBerkas,
            ),
          ),
          if (draf.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Lanjutkan draf', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final info in draf)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.drafts_outlined),
                  title: Text('Draf ${info.kelasId}'),
                  subtitle: Text(
                    '${info.labelSumber} • terakhir diubah '
                    '${info.diubahPada.day}/${info.diubahPada.month} '
                    '${info.diubahPada.hour.toString().padLeft(2, '0')}.'
                    '${info.diubahPada.minute.toString().padLeft(2, '0')}',
                  ),
                  trailing: IconButton(
                    tooltip: 'Hapus draf',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      await widget.penyimpananDraf.hapus(info.kelasId);
                      if (mounted) setState(() {});
                    },
                  ),
                  onTap: () => _lanjutkanDraf(info),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _bangunSesi(BuildContext context, DokumenEditor editor) {
    final theme = Theme.of(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Editor Jadwal'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.people_outline), text: 'Master Data'),
              Tab(icon: Icon(Icons.grid_view_outlined), text: 'Plotting'),
            ],
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Text('Kelas: ', style: theme.textTheme.titleSmall),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButton<String>(
                      value: editor.kelasAktif,
                      isExpanded: true,
                      items: [
                        for (final k in editor.daftarKelas)
                          DropdownMenuItem(value: k.id, child: Text(k.nama)),
                      ],
                      onChanged: (id) {
                        if (id == null) return;
                        editor.pilihKelas(id);
                        _berubah();
                      },
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Sumber: ${editor.labelSumber} • draf tersimpan otomatis',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  MasterDataView(editor: editor, onBerubah: _berubah),
                  PlottingView(editor: editor, onBerubah: _berubah),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        LayarTinjauKirim(store: widget.store, editor: editor),
                  ),
                );
              },
              icon: const Icon(Icons.send_outlined),
              label: const Text('Tinjau & Kirim'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
