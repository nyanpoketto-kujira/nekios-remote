import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../masjid/model_masjid.dart';
import '../state/store_masjid.dart';
import 'layar_banner_masjid.dart' show PemilihGambarMentah;
import 'widget_bersama.dart';

/// Editor Gambar Latar (Konten A2d): slideshow gambar latar TV.
/// Pola editor daftar ADR-007 seperti editor Konten lainnya.
///
/// Dua hal khas layar ini (paritas mobile_remote):
/// - **Interval slideshow** adalah field config
///   (`backgroundSlideSeconds`, 5–300 detik) yang diedit dari
///   sini; mengubahnya mengirim SATU `updateConfig` berisi config
///   TV saat ini dengan field itu saja yang diganti (keputusan
///   A2 #5).
/// - **Sakelar kirim tanpa kompresi** adalah preferensi lokal HP
///   untuk jalur Bluetooth (keputusan A2 #9), bukan data TV.
///
/// Berbeda dengan gambar khusus, berkas gambar latar disimpan
/// APA ADANYA (base64 dari berkas asli) — perkecilan/kompresi
/// adalah urusan transport Bluetooth saat mengirim, dan jalur
/// Wi-Fi memang selalu mengirim gambar asli.
class LayarGambarLatar extends StatefulWidget {
  const LayarGambarLatar({
    super.key,
    required this.store,
    this.pemilihGambarMentah,
  });

  final MasjidStore store;

  /// Lihat [PemilihGambarMentah]; null = pemilih galeri bawaan.
  final PemilihGambarMentah? pemilihGambarMentah;

  @override
  State<LayarGambarLatar> createState() => _LayarGambarLatarState();
}

class _LayarGambarLatarState extends State<LayarGambarLatar> {
  List<BackgroundImage> _kerja = const [];
  StateSnapshot? _seedDari;

  MasjidStore get _store => widget.store;

  @override
  void initState() {
    super.initState();
    _store.addListener(_berubah);
    _seedUlang();
  }

  @override
  void dispose() {
    _store.removeListener(_berubah);
    super.dispose();
  }

  void _berubah() {
    if (!mounted) return;
    _seedUlang();
    setState(() {});
  }

  void _seedUlang() {
    final snapshot = _store.snapshot;
    if (snapshot == null || identical(snapshot, _seedDari)) return;
    _seedDari = snapshot;
    _kerja = List.of(snapshot.backgroundImages);
  }

  Future<void> _kirimDaftar(
    List<BackgroundImage> baru,
    String pesanSukses,
  ) async {
    setState(() => _kerja = baru);
    final hasil = await _store.perbaruiBackgroundImages(baru);
    if (!mounted) return;
    tampilkanHasil(context, hasil, pesanSukses);
  }

  Future<void> _tambah() async {
    final pemilih = widget.pemilihGambarMentah ?? _pilihDariGaleri;
    final mentah = await pemilih();
    if (mentah == null || !mounted) return;
    final baru = BackgroundImage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      base64Image: base64Encode(mentah),
    );
    await _kirimDaftar([..._kerja, baru], 'Gambar latar ditambahkan.');
  }

  static Future<Uint8List?> _pilihDariGaleri() async {
    final terpilih = await ImagePicker().pickImage(
      source: ImageSource.gallery,
    );
    return terpilih?.readAsBytes();
  }

  void _gantiAktif(int indeks, bool aktif) {
    final daftar = List.of(_kerja);
    daftar[indeks] = daftar[indeks].copyWith(isActive: aktif);
    _kirimDaftar(daftar, 'Gambar latar diperbarui.');
  }

  Future<void> _hapus(int indeks) async {
    final terhapus = _kerja[indeks];
    final baru = List.of(_kerja)..removeAt(indeks);
    setState(() => _kerja = baru);
    final hasil = await _store.perbaruiBackgroundImages(baru);
    if (!mounted) return;
    if (!hasil.sukses) {
      tampilkanHasil(context, hasil, '');
      return;
    }
    // Urungkan = kirim ulang daftar dengan gambar dikembalikan
    // ke indeks asalnya (ADR-007).
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Gambar latar dihapus.'),
        action: SnackBarAction(
          label: 'Urungkan',
          onPressed: () => _urungkanHapus(terhapus, indeks),
        ),
      ),
    );
  }

  Future<void> _urungkanHapus(BackgroundImage gambar, int indeks) async {
    final baru = List.of(_kerja);
    baru.insert(indeks.clamp(0, baru.length), gambar);
    await _kirimDaftar(baru, 'Penghapusan diurungkan.');
  }

  void _susunUlang(int lama, int baru) {
    final daftar = List.of(_kerja);
    final dipindah = daftar.removeAt(lama);
    daftar.insert(baru, dipindah);
    _kirimDaftar(daftar, 'Urutan gambar latar diperbarui.');
  }

  Future<void> _gantiInterval(int detik) async {
    final config = _store.snapshot?.config;
    if (config == null) return;
    final hasil = await _store.perbaruiConfig(
      config.copyWith(backgroundSlideSeconds: detik),
    );
    if (!mounted) return;
    tampilkanHasil(
      context,
      hasil,
      'Interval slideshow diubah menjadi $detik detik.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _store.snapshot;
    final sibuk = _store.sedangMengirim;
    final tema = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _KartuInterval(
          detik: snapshot?.config.backgroundSlideSeconds,
          sibuk: sibuk,
          onGanti: _gantiInterval,
        ),
        SwitchListTile(
          title: const Text('Kirim tanpa kompresi (Bluetooth)'),
          subtitle: const Text(
            'Gambar latar dikirim apa adanya lewat Bluetooth, '
            'tanpa diperkecil dulu — paketnya jadi lebih besar. '
            'Lewat Wi-Fi gambar selalu dikirim apa adanya.',
          ),
          value: _store.kirimLatarTanpaKompresi,
          onChanged: _store.aturKirimLatarTanpaKompresi,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  'Gambar latar tampil bergantian memenuhi layar '
                  'TV. Setiap perubahan langsung dikirim ke TV.',
                  style: tema.textTheme.bodyMedium,
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: (sibuk || snapshot == null) ? null : _tambah,
                icon: const Icon(Icons.add),
                label: const Text('Tambah'),
              ),
            ],
          ),
        ),
        Expanded(
          child: snapshot == null
              ? const BadanBelumAdaDataTv()
              : _kerja.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Belum ada gambar latar. Ketuk Tambah untuk '
                      'memasang gambar pertama.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                  itemCount: _kerja.length,
                  onReorderItem: sibuk ? (_, _) {} : _susunUlang,
                  itemBuilder: (context, indeks) {
                    final gambar = _kerja[indeks];
                    return _KartuGambarLatar(
                      key: ValueKey(gambar.id),
                      gambar: gambar,
                      nomor: indeks + 1,
                      sibuk: sibuk,
                      onAktif: (v) => _gantiAktif(indeks, v),
                      onHapus: () => _hapus(indeks),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Kartu stepper interval slideshow (5–300 detik, langkah 5).
class _KartuInterval extends StatelessWidget {
  const _KartuInterval({
    required this.detik,
    required this.sibuk,
    required this.onGanti,
  });

  /// Null = snapshot TV belum tiba (stepper nonaktif).
  final int? detik;
  final bool sibuk;
  final ValueChanged<int> onGanti;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final nilai = detik;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ganti gambar latar setiap',
                    style: tema.textTheme.titleSmall,
                  ),
                  Text(
                    nilai == null
                        ? 'Menunggu data dari TV…'
                        : '$nilai detik',
                    style: tema.textTheme.bodyMedium?.copyWith(
                      color: tema.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              tooltip: 'Kurangi interval',
              onPressed: (sibuk || nilai == null || nilai <= 5)
                  ? null
                  : () => onGanti(nilai - 5),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              tooltip: 'Tambah interval',
              onPressed: (sibuk || nilai == null || nilai >= 300)
                  ? null
                  : () => onGanti(nilai + 5),
            ),
          ],
        ),
      ),
    );
  }
}

class _KartuGambarLatar extends StatelessWidget {
  const _KartuGambarLatar({
    super.key,
    required this.gambar,
    required this.nomor,
    required this.sibuk,
    required this.onAktif,
    required this.onHapus,
  });

  final BackgroundImage gambar;
  final int nomor;
  final bool sibuk;
  final ValueChanged<bool> onAktif;
  final VoidCallback onHapus;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    Uint8List? bytes;
    try {
      bytes = base64Decode(gambar.base64Image);
    } on FormatException {
      bytes = null;
    }
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 150,
            child: bytes == null
                ? const _GambarRusakLatar()
                : Image.memory(
                    bytes,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const _GambarRusakLatar(),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Gambar $nomor · '
                    '${gambar.isActive ? 'Tampil di TV' : 'Tidak tampil di TV'}',
                    style: tema.textTheme.bodyMedium,
                  ),
                ),
                Switch(
                  value: gambar.isActive,
                  onChanged: sibuk ? null : onAktif,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Hapus gambar',
                  onPressed: sibuk ? null : onHapus,
                ),
                ReorderableDragStartListener(
                  index: nomor - 1,
                  enabled: !sibuk,
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.drag_handle),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GambarRusakLatar extends StatelessWidget {
  const _GambarRusakLatar();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Center(child: Icon(Icons.broken_image_outlined)),
    );
  }
}
