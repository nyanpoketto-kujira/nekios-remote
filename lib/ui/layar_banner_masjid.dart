import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../layanan/gambar_banner.dart';
import '../masjid/model_masjid.dart';
import '../state/store_masjid.dart';
import 'widget_bersama.dart';

/// Pemilih gambar mentah untuk editor banner: mengembalikan
/// bytes berkas pilihan pengguna, atau null bila batal. Bisa
/// diinjeksi dari luar (test memakai bytes contoh kecil); bawaan
/// memakai galeri lewat [ImagePicker].
typedef PemilihGambarMentah = Future<Uint8List?> Function();

Future<Uint8List?> _pilihDariGaleri() async {
  final berkas = await ImagePicker().pickImage(source: ImageSource.gallery);
  if (berkas == null) return null;
  return berkas.readAsBytes();
}

/// Decode base64 gambar banner untuk pratinjau; null bila string
/// kosong/rusak (banner lama bisa saja menyimpan data tak valid).
Uint8List? _bytesDariBase64(String? base64) {
  if (base64 == null || base64.isEmpty) return null;
  try {
    return base64Decode(base64);
  } on FormatException {
    return null;
  }
}

/// Editor Banner / Info Masjid (Konten masjid, tahap A2b) —
/// pola salinan kerja ADR-006/007, sama seperti editor teks
/// berjalan: seed dari snapshot TV, setiap mutasi mengirim
/// daftar PENUH terbaru lewat [MasjidStore.perbaruiBanners],
/// kontrol membeku selama `store.sedangMengirim`, hapus bisa
/// diurungkan (kirim ulang), dan kirim gagal menahan salinan.
///
/// Gambar bersifat opsional; saat dipilih ia diperkecil di sisi
/// editor ke maks 1920×1080 JPEG q85 (lihat
/// [perkecilUntukBanner]) sebelum disimpan sebagai base64.
class LayarBannerMasjid extends StatefulWidget {
  const LayarBannerMasjid({
    super.key,
    required this.store,
    this.pemilihGambarMentah,
  });

  final MasjidStore store;

  /// Lihat [PemilihGambarMentah]; null = pemilih galeri bawaan.
  final PemilihGambarMentah? pemilihGambarMentah;

  @override
  State<LayarBannerMasjid> createState() => _LayarBannerMasjidState();
}

class _LayarBannerMasjidState extends State<LayarBannerMasjid> {
  /// Salinan kerja; null sampai snapshot pertama tiba.
  List<MediaBanner>? _salinan;

  /// Snapshot sumber seed [_salinan] saat ini (identitas objek
  /// = penanda seed ulang).
  StateSnapshot? _seedDari;

  MasjidStore get store => widget.store;

  Future<void> _kirimDaftar(List<MediaBanner> baru, String pesanSukses) async {
    setState(() => _salinan = baru);
    final hasil = await store.perbaruiBanners(baru);
    if (!mounted) return;
    tampilkanHasil(context, hasil, pesanSukses);
  }

  Future<void> _tambah(BuildContext context) async {
    final banner = await showDialog<MediaBanner>(
      context: context,
      builder: (_) => _DialogBanner(
        pemilihGambarMentah:
            widget.pemilihGambarMentah ?? _pilihDariGaleri,
      ),
    );
    if (banner == null || !mounted) return;
    await _kirimDaftar([...?_salinan, banner], 'Banner ditambahkan.');
  }

  Future<void> _sunting(BuildContext context, int indeks) async {
    final lama = _salinan![indeks];
    final banner = await showDialog<MediaBanner>(
      context: context,
      builder: (_) => _DialogBanner(
        awal: lama,
        pemilihGambarMentah:
            widget.pemilihGambarMentah ?? _pilihDariGaleri,
      ),
    );
    if (banner == null || !mounted) return;
    final baru = [..._salinan!]..[indeks] = banner;
    await _kirimDaftar(baru, 'Banner diperbarui.');
  }

  Future<void> _aturAktif(int indeks, bool aktif) async {
    final baru = [..._salinan!]
      ..[indeks] = _salinan![indeks].copyWith(isActive: aktif);
    await _kirimDaftar(
      baru,
      aktif ? 'Banner diaktifkan.' : 'Banner dinonaktifkan.',
    );
  }

  Future<void> _susunUlang(int lama, int tujuan) async {
    if (store.sedangMengirim || tujuan == lama) return;
    final daftar = [..._salinan!];
    final item = daftar.removeAt(lama);
    daftar.insert(tujuan, item);
    await _kirimDaftar(daftar, 'Urutan banner diperbarui.');
  }

  Future<void> _hapus(int indeks) async {
    final terhapus = _salinan![indeks];
    final baru = [..._salinan!]..removeAt(indeks);
    setState(() => _salinan = baru);
    final hasil = await store.perbaruiBanners(baru);
    if (!mounted) return;
    if (!hasil.sukses) {
      tampilkanHasil(context, hasil, '');
      return;
    }
    // Urungkan = kirim ulang dengan banner dikembalikan ke
    // indeks asalnya (ADR-007).
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Banner dihapus.'),
        action: SnackBarAction(
          label: 'Urungkan',
          onPressed: () => _urungkanHapus(terhapus, indeks),
        ),
      ),
    );
  }

  Future<void> _urungkanHapus(MediaBanner banner, int indeks) async {
    final sekarang = _salinan ?? const <MediaBanner>[];
    final posisi = indeks.clamp(0, sekarang.length);
    final baru = [...sekarang]..insert(posisi, banner);
    await _kirimDaftar(baru, 'Penghapusan diurungkan.');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (!store.terhubung) return const BadanBelumTerhubung();
        final snapshot = store.snapshot;
        if (snapshot == null) return const BadanBelumAdaDataTv();
        if (!identical(_seedDari, snapshot)) {
          _seedDari = snapshot;
          _salinan = List.of(snapshot.banners);
        }
        final daftar = _salinan!;
        final sibuk = store.sedangMengirim;
        final theme = Theme.of(context);
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Kartu info yang tampil bergantian di layar '
                      'TV. Setiap perubahan langsung dikirim ke TV.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: sibuk ? null : () => _tambah(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Tambah'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: daftar.isEmpty
                  ? const _DaftarKosong()
                  : ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      itemCount: daftar.length,
                      onReorderItem: _susunUlang,
                      itemBuilder: (context, i) => _KartuBanner(
                        key: ValueKey(daftar[i].id),
                        banner: daftar[i],
                        indeks: i,
                        sibuk: sibuk,
                        onAktif: (v) => _aturAktif(i, v),
                        onSunting: () => _sunting(context, i),
                        onHapus: () => _hapus(i),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _DaftarKosong extends StatelessWidget {
  const _DaftarKosong();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.campaign_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'Belum ada banner di TV. Tambahkan lewat tombol '
              'Tambah di atas.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _KartuBanner extends StatelessWidget {
  const _KartuBanner({
    super.key,
    required this.banner,
    required this.indeks,
    required this.sibuk,
    required this.onAktif,
    required this.onSunting,
    required this.onHapus,
  });

  final MediaBanner banner;
  final int indeks;
  final bool sibuk;
  final ValueChanged<bool> onAktif;
  final VoidCallback onSunting;
  final VoidCallback onHapus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bytes = _bytesDariBase64(banner.base64Image);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              clipBehavior: Clip.antiAlias,
              child: bytes == null
                  ? Icon(
                      Icons.image_outlined,
                      color: scheme.onSurfaceVariant,
                    )
                  : Image.memory(
                      bytes,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Icon(
                        Icons.broken_image_outlined,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (banner.header.isNotEmpty)
                    Text(
                      banner.header.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                  if (banner.title.isNotEmpty)
                    Text(
                      banner.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (banner.content.isNotEmpty)
                    Text(
                      banner.content,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (banner.footer.isNotEmpty)
                    Text(
                      banner.footer,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (!banner.isActive)
                    Text(
                      'Nonaktif',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            Column(
              children: [
                Switch(value: banner.isActive, onChanged: sibuk ? null : onAktif),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Ubah banner',
                      onPressed: sibuk ? null : onSunting,
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Hapus banner',
                      onPressed: sibuk ? null : onHapus,
                    ),
                    ReorderableDragStartListener(
                      index: indeks,
                      enabled: !sibuk,
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.drag_handle),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialog layar penuh tambah/ubah satu banner. Simpan sah bila
/// judul ATAU isi ATAU gambar terisi (paritas mobile_remote).
class _DialogBanner extends StatefulWidget {
  const _DialogBanner({this.awal, required this.pemilihGambarMentah});

  /// Banner yang disunting; null = tambah baru.
  final MediaBanner? awal;

  final PemilihGambarMentah pemilihGambarMentah;

  @override
  State<_DialogBanner> createState() => _DialogBannerState();
}

class _DialogBannerState extends State<_DialogBanner> {
  late final TextEditingController _header;
  late final TextEditingController _judul;
  late final TextEditingController _isi;
  late final TextEditingController _footer;
  String? _base64Gambar;
  bool _mengolahGambar = false;

  @override
  void initState() {
    super.initState();
    final awal = widget.awal;
    _header = TextEditingController(text: awal?.header ?? 'INFO MASJID');
    _judul = TextEditingController(text: awal?.title ?? '');
    _isi = TextEditingController(text: awal?.content ?? '');
    _footer = TextEditingController(text: awal?.footer ?? '');
    _base64Gambar = awal?.base64Image;
  }

  @override
  void dispose() {
    _header.dispose();
    _judul.dispose();
    _isi.dispose();
    _footer.dispose();
    super.dispose();
  }

  bool get _sah =>
      _judul.text.trim().isNotEmpty ||
      _isi.text.trim().isNotEmpty ||
      _base64Gambar != null;

  Future<void> _pilihGambar() async {
    final mentah = await widget.pemilihGambarMentah();
    if (mentah == null || !mounted) return;
    setState(() => _mengolahGambar = true);
    final kecil = await perkecilUntukBanner(mentah);
    if (!mounted) return;
    setState(() => _mengolahGambar = false);
    // Helper mengembalikan bytes apa adanya bila bukan gambar;
    // berkas seperti itu ditolak di sini, bukan dikirim ke TV.
    if (img.decodeImage(kecil) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Berkas yang dipilih bukan gambar yang terbaca. '
            'Coba gambar lain.',
          ),
        ),
      );
      return;
    }
    setState(() => _base64Gambar = base64Encode(kecil));
  }

  void _simpan() {
    final awal = widget.awal;
    Navigator.pop(
      context,
      MediaBanner(
        id: awal?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        header: _header.text.trim(),
        title: _judul.text.trim(),
        content: _isi.text.trim(),
        footer: _footer.text.trim(),
        isActive: awal?.isActive ?? true,
        base64Image: _base64Gambar,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bytesPratinjau = _bytesDariBase64(_base64Gambar);
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Batal',
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            widget.awal == null ? 'Tambah Banner' : 'Ubah Banner',
          ),
          actions: [
            TextButton(
              onPressed: _sah ? _simpan : null,
              child: const Text('Simpan'),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _header,
              decoration: const InputDecoration(
                labelText: 'Header (label kecil di atas judul)',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _judul,
              decoration: const InputDecoration(
                labelText: 'Judul',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _isi,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Isi',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _footer,
              decoration: const InputDecoration(
                labelText: 'Footer (catatan kecil di bawah isi)',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 20),
            Text('Gambar (tidak wajib)', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            if (bytesPratinjau != null)
              Container(
                height: 160,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.memory(
                  bytesPratinjau,
                  fit: BoxFit.contain,
                  width: double.infinity,
                  errorBuilder: (_, _, _) => Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              Container(
                height: 120,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.image_outlined,
                  size: 40,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _mengolahGambar ? null : _pilihGambar,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(
                    _mengolahGambar
                        ? 'Mengolah…'
                        : (_base64Gambar == null
                              ? 'Pilih gambar'
                              : 'Ganti gambar'),
                  ),
                ),
                const SizedBox(width: 8),
                if (_base64Gambar != null)
                  TextButton.icon(
                    onPressed: () =>
                        setState(() => _base64Gambar = null),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Hapus gambar'),
                  ),
              ],
            ),
            if (!_sah) ...[
              const SizedBox(height: 12),
              Text(
                'Isi minimal salah satu: judul, isi, atau gambar.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
