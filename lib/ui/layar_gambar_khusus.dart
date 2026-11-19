import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../layanan/gambar_banner.dart';
import '../masjid/model_masjid.dart';
import '../state/store_masjid.dart';
import 'layar_banner_masjid.dart' show PemilihGambarMentah;
import 'widget_bersama.dart';

/// Editor Gambar Khusus (Konten A2d): daftar gambar yang tampil
/// bergantian di slot samping TV, sesudah kartu Kas dan Petugas
/// Jumat. Pola editor daftar ADR-007: salinan kerja di-seed dari
/// snapshot TV, setiap perubahan (tambah/sakelar/urutan/hapus)
/// langsung mengirim daftar penuh terbaru dan menunggu snapshot
/// bukti; hapus bisa diurungkan dari SnackBar (urungkan = kirim
/// ulang daftar pulih).
///
/// Gambar DIPERKECIL saat dipilih agar muat 1920×1080 JPEG q85
/// (helper yang sama dengan banner — rencana A2 §3a "maks
/// 1080p"); berkas yang tidak terbaca sebagai gambar ditolak.
/// Keterangan bersifat opsional dan tidak bisa disunting setelah
/// tersimpan (paritas mobile_remote: koreksi = hapus + tambah
/// ulang).
class LayarGambarKhusus extends StatefulWidget {
  const LayarGambarKhusus({
    super.key,
    required this.store,
    this.pemilihGambarMentah,
  });

  final MasjidStore store;

  /// Lihat [PemilihGambarMentah]; null = pemilih galeri bawaan.
  final PemilihGambarMentah? pemilihGambarMentah;

  @override
  State<LayarGambarKhusus> createState() => _LayarGambarKhususState();
}

class _LayarGambarKhususState extends State<LayarGambarKhusus> {
  List<SpecialImage> _kerja = const [];
  StateSnapshot? _seedDari;
  bool _memprosesGambar = false;

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
    _kerja = List.of(snapshot.sideImages);
  }

  Future<void> _kirimDaftar(
    List<SpecialImage> baru,
    String pesanSukses,
  ) async {
    setState(() => _kerja = baru);
    final hasil = await _store.perbaruiSideImages(baru);
    if (!mounted) return;
    tampilkanHasil(context, hasil, pesanSukses);
  }

  Future<void> _tambah() async {
    final pemilih = widget.pemilihGambarMentah ?? _pilihDariGaleri;
    final mentah = await pemilih();
    if (mentah == null || !mounted) return;
    setState(() => _memprosesGambar = true);
    final diperkecil = await perkecilUntukBanner(mentah);
    if (!mounted) return;
    setState(() => _memprosesGambar = false);
    // Helper mengembalikan bytes apa adanya bila tidak terbaca
    // sebagai gambar — berkas seperti itu ditolak di sini.
    if (identical(diperkecil, mentah)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Berkas itu tidak terbaca sebagai gambar. '
            'Pilih gambar lain.',
          ),
        ),
      );
      return;
    }
    final keterangan = await showDialog<String>(
      context: context,
      builder: (_) => _DialogKeteranganGambar(gambar: diperkecil),
    );
    if (keterangan == null || !mounted) return;
    final baru = SpecialImage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      caption: keterangan,
      base64Image: base64Encode(diperkecil),
    );
    await _kirimDaftar([..._kerja, baru], 'Gambar khusus ditambahkan.');
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
    _kirimDaftar(daftar, 'Gambar khusus diperbarui.');
  }

  Future<void> _hapus(int indeks) async {
    final terhapus = _kerja[indeks];
    final baru = List.of(_kerja)..removeAt(indeks);
    setState(() => _kerja = baru);
    final hasil = await _store.perbaruiSideImages(baru);
    if (!mounted) return;
    if (!hasil.sukses) {
      tampilkanHasil(context, hasil, '');
      return;
    }
    // Urungkan = kirim ulang daftar dengan gambar dikembalikan
    // ke indeks asalnya (ADR-007).
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Gambar khusus dihapus.'),
        action: SnackBarAction(
          label: 'Urungkan',
          onPressed: () => _urungkanHapus(terhapus, indeks),
        ),
      ),
    );
  }

  Future<void> _urungkanHapus(SpecialImage gambar, int indeks) async {
    final baru = List.of(_kerja);
    baru.insert(indeks.clamp(0, baru.length), gambar);
    await _kirimDaftar(baru, 'Penghapusan diurungkan.');
  }

  void _susunUlang(int lama, int baru) {
    final daftar = List.of(_kerja);
    final dipindah = daftar.removeAt(lama);
    daftar.insert(baru, dipindah);
    _kirimDaftar(daftar, 'Urutan gambar khusus diperbarui.');
  }

  @override
  Widget build(BuildContext context) {
    if (_store.snapshot == null) return const BadanBelumAdaDataTv();
    final sibuk = _store.sedangMengirim || _memprosesGambar;
    final tema = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  'Gambar yang tampil bergantian di sisi layar TV, '
                  'setelah kartu kas dan petugas Jumat. Setiap '
                  'perubahan langsung dikirim ke TV.',
                  style: tema.textTheme.bodyMedium,
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: sibuk ? null : _tambah,
                icon: const Icon(Icons.add),
                label: const Text('Tambah'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _kerja.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Belum ada gambar khusus. Ketuk Tambah untuk '
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
                    return _KartuGambarKhusus(
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

class _KartuGambarKhusus extends StatelessWidget {
  const _KartuGambarKhusus({
    super.key,
    required this.gambar,
    required this.nomor,
    required this.sibuk,
    required this.onAktif,
    required this.onHapus,
  });

  final SpecialImage gambar;
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
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 84,
                height: 84,
                child: bytes == null
                    ? const _GambarRusak()
                    : Image.memory(
                        bytes,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const _GambarRusak(),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Gambar $nomor',
                    style: tema.textTheme.labelMedium?.copyWith(
                      color: tema.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    gambar.caption.isEmpty
                        ? 'Tanpa keterangan'
                        : gambar.caption,
                    style: tema.textTheme.bodyLarge,
                  ),
                  Text(
                    gambar.isActive
                        ? 'Tampil di TV'
                        : 'Tidak tampil di TV',
                    style: tema.textTheme.bodySmall?.copyWith(
                      color: tema.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
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
                padding: EdgeInsets.only(top: 12),
                child: Icon(Icons.drag_handle),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GambarRusak extends StatelessWidget {
  const _GambarRusak();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.broken_image_outlined),
    );
  }
}

/// Dialog keterangan setelah gambar dipilih: pratinjau + satu
/// field opsional. Mengembalikan teks keterangan (boleh kosong)
/// atau null bila dibatalkan.
class _DialogKeteranganGambar extends StatefulWidget {
  const _DialogKeteranganGambar({required this.gambar});

  final Uint8List gambar;

  @override
  State<_DialogKeteranganGambar> createState() =>
      _DialogKeteranganGambarState();
}

class _DialogKeteranganGambarState
    extends State<_DialogKeteranganGambar> {
  final _kontrol = TextEditingController();

  @override
  void dispose() {
    _kontrol.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Gambar Khusus Baru'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              widget.gambar,
              height: 160,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _kontrol,
            decoration: const InputDecoration(
              labelText: 'Keterangan (tidak wajib)',
              hintText: 'Contoh: Renovasi tempat wudhu',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, _kontrol.text.trim()),
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}
