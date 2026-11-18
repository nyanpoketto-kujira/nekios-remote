import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../domain/perintah.dart';
import '../layanan/gambar_logo.dart';
import '../state/remote_store.dart';
import 'widget_bersama.dart';

/// Layar Logo: pilih gambar dari galeri, perkecil ke maks 512px
/// (pola masjid-you), kirim sebagai `logo.set` base64. Logo tampil
/// di header TV menggantikan slot kosongnya.
class LayarLogo extends StatefulWidget {
  const LayarLogo({super.key, required this.store});

  final RemoteStore store;

  @override
  State<LayarLogo> createState() => _LayarLogoState();
}

class _LayarLogoState extends State<LayarLogo> {
  Uint8List? _pratinjau;
  String? _base64Siap;
  String? _pesanOlah;
  bool _sibuk = false;

  RemoteStore get store => widget.store;

  Future<void> _pilihGambar() async {
    final berkas = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (berkas == null) return;
    setState(() {
      _sibuk = true;
      _pesanOlah = null;
    });
    try {
      final bytes = await berkas.readAsBytes();
      final base64 = await compute(olahLogoKeBase64, bytes);
      if (!mounted) return;
      setState(() {
        _pratinjau = bytes;
        _base64Siap = base64;
        _pesanOlah =
            'Siap dikirim (±${(base64.length / 1024).toStringAsFixed(0)} KB, '
            'sudah diperkecil ke maks ${kUkuranMaksLogo}px).';
      });
    } on FormatException catch (e) {
      if (!mounted) return;
      setState(() => _pesanOlah = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _pesanOlah = 'Gambar gagal diolah. Coba gambar lain.');
    } finally {
      if (mounted) setState(() => _sibuk = false);
    }
  }

  Future<void> _kirimLogo() async {
    final base64 = _base64Siap;
    if (base64 == null) return;
    setState(() => _sibuk = true);
    final hasil = await store.kirimPerintah(perintahAturLogo(base64));
    if (!mounted) return;
    setState(() => _sibuk = false);
    tampilkanHasil(context, hasil, 'Logo terkirim ke TV.');
  }

  Future<void> _hapusLogo() async {
    final yakin = await mintaKonfirmasi(
      context,
      judul: 'Hapus logo di TV?',
      isi:
          'Logo pada header TV akan dihapus. Kamu bisa memasangnya '
          'lagi kapan pun dari layar ini.',
      tombolSetuju: 'Hapus',
    );
    if (!yakin) return;
    setState(() => _sibuk = true);
    final hasil = await store.kirimPerintah(perintahHapusLogo());
    if (!mounted) return;
    setState(() => _sibuk = false);
    tampilkanHasil(context, hasil, 'Logo di TV dihapus.');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (!store.terhubung) return const BadanBelumTerhubung();
        final theme = Theme.of(context);
        final hasLogo = store.snapshot?.hasLogo ?? false;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Icon(
                  hasLogo ? Icons.check_circle_outline : Icons.cancel_outlined,
                  color: hasLogo
                      ? theme.colorScheme.primary
                      : theme.colorScheme.error,
                ),
                const SizedBox(width: 8),
                Text(
                  hasLogo ? 'TV sedang memasang logo' : 'TV belum punya logo',
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_pratinjau != null)
              Center(
                child: Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.memory(_pratinjau!, fit: BoxFit.contain),
                ),
              )
            else
              Center(
                child: Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.image_outlined,
                    size: 56,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (_pesanOlah != null) ...[
              const SizedBox(height: 8),
              Text(_pesanOlah!, textAlign: TextAlign.center),
            ],
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _sibuk ? null : _pilihGambar,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Pilih gambar dari galeri'),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _sibuk || _base64Siap == null ? null : _kirimLogo,
              icon: const Icon(Icons.send),
              label: const Text('Kirim logo ke TV'),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _sibuk || !hasLogo ? null : _hapusLogo,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Hapus logo di TV'),
            ),
          ],
        );
      },
    );
  }
}
