import 'dart:async';

import 'package:flutter/material.dart';

import '../state/remote_store.dart';

/// Chip ringkas keadaan koneksi (dipakai di AppBar & layar Koneksi).
class ChipStatusKoneksi extends StatelessWidget {
  const ChipStatusKoneksi({super.key, required this.store});

  final RemoteStore store;

  @override
  Widget build(BuildContext context) =>
      ChipStatusDari(status: store.statusKoneksi);
}

/// Chip status dari nilai [StatusKoneksi] mentah — dipakai untuk
/// store mana pun (sekolah / masjid).
class ChipStatusDari extends StatelessWidget {
  const ChipStatusDari({super.key, required this.status});

  final StatusKoneksi status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (warna, teks) = switch (status) {
      StatusKoneksi.terhubung => (scheme.primary, 'Terhubung'),
      StatusKoneksi.menyambung => (scheme.tertiary, 'Menyambung…'),
      StatusKoneksi.terputus => (scheme.error, 'Terputus'),
    };
    return Chip(
      avatar: Icon(Icons.circle, size: 10, color: warna),
      label: Text(teks),
      visualDensity: VisualDensity.compact,
    );
  }
}

/// Isi tab yang belum dibangun pada tahap berjalan (Rute A:
/// editor Konten/Pengaturan masjid menyusul tahap A2 berikutnya).
class LayarTahapBerikut extends StatelessWidget {
  const LayarTahapBerikut({
    super.key,
    required this.judul,
    required this.keterangan,
  });

  final String judul;
  final String keterangan;

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
              Icons.construction_outlined,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              judul,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              keterangan,
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

/// Membangun ulang [builder] setiap detik — basis jam efektif &
/// hitung mundur yang tetap berjalan di antara snapshot.
class BerjalanTiapDetik extends StatefulWidget {
  const BerjalanTiapDetik({super.key, required this.builder});

  final WidgetBuilder builder;

  @override
  State<BerjalanTiapDetik> createState() => _BerjalanTiapDetikState();
}

class _BerjalanTiapDetikState extends State<BerjalanTiapDetik> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

/// Isi tab saat remote belum terhubung ke display mana pun.
class BadanBelumTerhubung extends StatelessWidget {
  const BadanBelumTerhubung({super.key});

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
              Icons.tv_off_outlined,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'Belum terhubung ke display',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Sambungkan dulu ke TV dari tab Koneksi — pastikan HP dan '
              'TV berada di Wi-Fi yang sama.',
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

/// Isi editor daftar saat TV belum mengirim snapshot sama sekali.
///
/// Editor Konten bersifat full-replace: daftar yang dikirim
/// MENGGANTI seluruh isi TV. Selama snapshot belum tiba, editor
/// menahan diri di keadaan ini — tidak pernah menebak atau
/// mengarang daftar kosong yang bisa terlanjur terkirim.
class BadanBelumAdaDataTv extends StatelessWidget {
  const BadanBelumAdaDataTv({super.key});

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
              Icons.hourglass_empty,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'Belum ada data dari TV',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Daftar ini mengikuti data yang ada di TV. Tunggu '
              'sebentar sampai TV mengirim datanya — bila tetap '
              'kosong, periksa lagi koneksi ke TV.',
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

/// Dialog konfirmasi singkat; true bila pengguna menyetujui.
Future<bool> mintaKonfirmasi(
  BuildContext context, {
  required String judul,
  required String isi,
  required String tombolSetuju,
}) async {
  final hasil = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(judul),
      content: Text(isi),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(tombolSetuju),
        ),
      ],
    ),
  );
  return hasil ?? false;
}

/// Umpan balik standar hasil perintah: SnackBar sukses/gagal.
void tampilkanHasil(
  BuildContext context,
  HasilPerintah hasil,
  String pesanSukses,
) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        hasil.sukses ? pesanSukses : (hasil.pesan ?? 'Perintah gagal.'),
      ),
    ),
  );
}

/// Format jam `HH:MM:SS` dari DateTime.
String formatJam(DateTime waktu) {
  String dua(int n) => n.toString().padLeft(2, '0');
  return '${dua(waktu.hour)}:${dua(waktu.minute)}:${dua(waktu.second)}';
}

/// Format jam `HH:MM` dari DateTime.
String formatJamMenit(DateTime waktu) {
  String dua(int n) => n.toString().padLeft(2, '0');
  return '${dua(waktu.hour)}:${dua(waktu.minute)}';
}
