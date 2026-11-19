import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../layanan/gambar_logo.dart';
import '../state/store_masjid.dart';
import 'layar_banner_masjid.dart' show PemilihGambarMentah;
import 'widget_bersama.dart';

/// Editor Logo masjid (Konten A2d, keputusan A2 #4): pratinjau
/// 1:1 dari `snapshot.mosqueLogo`, Pilih/Ganti lewat galeri
/// (diperkecil ke maks 512px oleh [olahLogoKeBase64], paritas
/// layar Logo sekolah), dan Hapus (mengirim `logoBase64: null`).
/// Semua berlaku seketika lewat `perbaruiLogo` — bukan bagian
/// dari Simpan config Pengaturan.
class LayarLogoMasjid extends StatefulWidget {
  const LayarLogoMasjid({
    super.key,
    required this.store,
    this.pemilihGambarMentah,
  });

  final MasjidStore store;

  /// Lihat [PemilihGambarMentah]; null = pemilih galeri bawaan.
  final PemilihGambarMentah? pemilihGambarMentah;

  @override
  State<LayarLogoMasjid> createState() => _LayarLogoMasjidState();
}

class _LayarLogoMasjidState extends State<LayarLogoMasjid> {
  MasjidStore get _store => widget.store;

  @override
  void initState() {
    super.initState();
    _store.addListener(_berubah);
  }

  @override
  void dispose() {
    _store.removeListener(_berubah);
    super.dispose();
  }

  void _berubah() {
    if (mounted) setState(() {});
  }

  Future<void> _pilih() async {
    final pemilih = widget.pemilihGambarMentah ?? _pilihDariGaleri;
    final mentah = await pemilih();
    if (mentah == null || !mounted) return;
    final String logoBase64;
    try {
      logoBase64 = olahLogoKeBase64(mentah);
    } on FormatException {
      if (!mounted) return;
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
    final hasil = await _store.perbaruiLogo(logoBase64);
    if (!mounted) return;
    tampilkanHasil(context, hasil, 'Logo masjid diperbarui.');
  }

  static Future<Uint8List?> _pilihDariGaleri() async {
    final terpilih = await ImagePicker().pickImage(
      source: ImageSource.gallery,
    );
    return terpilih?.readAsBytes();
  }

  Future<void> _hapus() async {
    final yakin = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus logo masjid?'),
        content: const Text(
          'Logo akan hilang dari layar TV. Logo bisa dipasang '
          'lagi kapan saja.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (yakin != true || !mounted) return;
    final hasil = await _store.perbaruiLogo(null);
    if (!mounted) return;
    tampilkanHasil(context, hasil, 'Logo masjid dihapus.');
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _store.snapshot;
    if (snapshot == null) return const BadanBelumAdaDataTv();
    final sibuk = _store.sedangMengirim;
    final tema = Theme.of(context);
    final logo = snapshot.mosqueLogo;
    Uint8List? bytes;
    if (logo != null) {
      try {
        bytes = base64Decode(logo);
      } on FormatException {
        bytes = null;
      }
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Logo tampil di bagian atas layar TV. Gambar '
            'diperkecil otomatis supaya pas.',
            style: tema.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Center(
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(color: tema.colorScheme.outline),
                borderRadius: BorderRadius.circular(16),
                color: tema.colorScheme.surfaceContainerHighest,
              ),
              clipBehavior: Clip.antiAlias,
              child: bytes == null
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.image_outlined,
                          size: 48,
                          color: tema.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          logo == null
                              ? 'Belum ada logo'
                              : 'Logo tidak terbaca',
                          style: tema.textTheme.bodyMedium?.copyWith(
                            color: tema.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    )
                  : Image.memory(
                      bytes,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.broken_image_outlined,
                            size: 48,
                            color: tema.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 8),
                          const Text('Logo tidak terbaca'),
                        ],
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: sibuk ? null : _pilih,
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(logo == null ? 'Pilih logo' : 'Ganti logo'),
          ),
          if (logo != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: sibuk ? null : _hapus,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Hapus logo'),
            ),
          ],
        ],
      ),
    );
  }
}
