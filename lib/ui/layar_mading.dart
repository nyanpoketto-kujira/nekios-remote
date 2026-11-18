import 'package:flutter/material.dart';

import '../domain/perintah.dart';
import '../state/remote_store.dart';
import 'widget_bersama.dart';

/// Layar Mading: sunting teks pengumuman berjalan di TV.
/// Editor terisi teks aktif dari snapshot; kirim lewat `mading.set`;
/// string kosong mengembalikan display ke sambutan bawaannya.
class LayarMading extends StatefulWidget {
  const LayarMading({super.key, required this.store});

  final RemoteStore store;

  @override
  State<LayarMading> createState() => _LayarMadingState();
}

class _LayarMadingState extends State<LayarMading> {
  late final TextEditingController _controller;
  bool _mengirim = false;

  RemoteStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: store.snapshot?.mading ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _muatDariDisplay() {
    _controller.text = store.snapshot?.mading ?? '';
  }

  Future<void> _kirim(String teks, String pesanSukses) async {
    setState(() => _mengirim = true);
    final hasil = await store.kirimPerintah(perintahAturMading(teks));
    if (!mounted) return;
    setState(() => _mengirim = false);
    tampilkanHasil(context, hasil, pesanSukses);
  }

  Future<void> _kosongkan() async {
    final yakin = await mintaKonfirmasi(
      context,
      judul: 'Kosongkan mading?',
      isi:
          'Teks mading di TV akan dikosongkan dan display kembali '
          'menampilkan sambutan bawaannya.',
      tombolSetuju: 'Kosongkan',
    );
    if (!yakin) return;
    _controller.clear();
    await _kirim('', 'Mading dikosongkan — sambutan bawaan tampil lagi.');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (!store.terhubung) return const BadanBelumTerhubung();
        final theme = Theme.of(context);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Teks mading', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Teks ini berjalan di baris bawah layar TV. Perubahan '
              'tayang seketika setelah dikirim.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: 'Isi mading',
                hintText: 'Mis. Selamat datang di pameran SMKN 1 Ukui…',
                border: OutlineInputBorder(),
              ),
              minLines: 3,
              maxLines: 6,
              maxLength: 280,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _mengirim
                      ? null
                      : () => _kirim(
                          _controller.text.trim(),
                          'Mading terkirim ke TV.',
                        ),
                  icon: const Icon(Icons.send),
                  label: const Text('Kirim ke TV'),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  onPressed: _muatDariDisplay,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Muat ulang teks yang sedang tayang',
                ),
              ],
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _mengirim ? null : _kosongkan,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Kosongkan ke sambutan bawaan'),
            ),
          ],
        );
      },
    );
  }
}
