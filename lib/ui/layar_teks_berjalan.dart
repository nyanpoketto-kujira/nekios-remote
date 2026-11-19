import 'package:flutter/material.dart';

import '../masjid/model_masjid.dart';
import '../state/store_masjid.dart';
import 'widget_bersama.dart';

/// Kategori tetap teks berjalan (paritas mobile_remote).
const kKategoriTeksBerjalan = <String>[
  'Pengumuman',
  'Kajian',
  'Kas',
  'Himbauan',
  'Infaq',
  'Umum',
];

/// Editor Teks Berjalan (Konten masjid, tahap A2b) — pola
/// salinan kerja ADR-006/007: daftar di-seed dari snapshot TV,
/// SETIAP mutasi (tambah/ubah/hapus/urutan/sakelar) langsung
/// mengirim daftar PENUH terbaru lewat
/// [MasjidStore.perbaruiRunningText] dan snapshot bukti menjadi
/// seed baru. Selama perintah menunggu bukti
/// (`store.sedangMengirim`) semua kontrol membeku; kirim yang
/// gagal menahan salinan kerja apa adanya (tidak di-rollback).
///
/// Berbeda dari mobile_remote, sakelar `isActive` DITAMPILKAN
/// (keputusan #11): teks nonaktif tetap tersimpan di TV tetapi
/// tidak ikut berjalan di layar.
class LayarTeksBerjalan extends StatefulWidget {
  const LayarTeksBerjalan({super.key, required this.store});

  final MasjidStore store;

  @override
  State<LayarTeksBerjalan> createState() => _LayarTeksBerjalanState();
}

class _LayarTeksBerjalanState extends State<LayarTeksBerjalan> {
  /// Salinan kerja; null sampai snapshot pertama tiba.
  List<RunningTextMessage>? _salinan;

  /// Snapshot yang menjadi sumber seed [_salinan] saat ini —
  /// identitas objeknya penanda "snapshot baru = seed ulang".
  StateSnapshot? _seedDari;

  MasjidStore get store => widget.store;

  /// Kirim [baru] sebagai daftar penuh terbaru dan laporkan
  /// hasilnya. Salinan kerja diganti lebih dulu supaya UI
  /// langsung mencerminkan niat pengguna; snapshot bukti yang
  /// tiba kemudian menggantikannya lagi (TV = trust source).
  Future<void> _kirimDaftar(
    List<RunningTextMessage> baru,
    String pesanSukses,
  ) async {
    setState(() => _salinan = baru);
    final hasil = await store.perbaruiRunningText(baru);
    if (!mounted) return;
    tampilkanHasil(context, hasil, pesanSukses);
  }

  Future<void> _tambah(BuildContext context) async {
    final pesan = await showDialog<RunningTextMessage>(
      context: context,
      builder: (_) => const _DialogTeksBerjalan(),
    );
    if (pesan == null || !mounted) return;
    await _kirimDaftar([
      ...?_salinan,
      pesan,
    ], 'Teks berjalan ditambahkan.');
  }

  Future<void> _sunting(BuildContext context, int indeks) async {
    final lama = _salinan![indeks];
    final pesan = await showDialog<RunningTextMessage>(
      context: context,
      builder: (_) => _DialogTeksBerjalan(awal: lama),
    );
    if (pesan == null || !mounted) return;
    final baru = [..._salinan!]..[indeks] = pesan;
    await _kirimDaftar(baru, 'Teks berjalan diperbarui.');
  }

  Future<void> _aturAktif(int indeks, bool aktif) async {
    final lama = _salinan![indeks];
    final ganti = RunningTextMessage(
      id: lama.id,
      content: lama.content,
      isActive: aktif,
      category: lama.category,
    );
    final baru = [..._salinan!]..[indeks] = ganti;
    await _kirimDaftar(
      baru,
      aktif ? 'Teks diaktifkan.' : 'Teks dinonaktifkan.',
    );
  }

  Future<void> _susunUlang(int lama, int tujuan) async {
    if (store.sedangMengirim || tujuan == lama) return;
    final daftar = [..._salinan!];
    final item = daftar.removeAt(lama);
    daftar.insert(tujuan, item);
    await _kirimDaftar(daftar, 'Urutan teks berjalan diperbarui.');
  }

  Future<void> _hapus(int indeks) async {
    final terhapus = _salinan![indeks];
    final baru = [..._salinan!]..removeAt(indeks);
    setState(() => _salinan = baru);
    final hasil = await store.perbaruiRunningText(baru);
    if (!mounted) return;
    if (!hasil.sukses) {
      tampilkanHasil(context, hasil, '');
      return;
    }
    // Urungkan = kirim ulang daftar dengan item dikembalikan ke
    // indeks asalnya (ADR-007): penghapusan sudah terlanjur
    // sampai TV, jadi pembatalannya pun perintah sungguhan.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Teks berjalan dihapus.'),
        action: SnackBarAction(
          label: 'Urungkan',
          onPressed: () => _urungkanHapus(terhapus, indeks),
        ),
      ),
    );
  }

  Future<void> _urungkanHapus(RunningTextMessage pesan, int indeks) async {
    final sekarang = _salinan ?? const <RunningTextMessage>[];
    final posisi = indeks.clamp(0, sekarang.length);
    final baru = [...sekarang]..insert(posisi, pesan);
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
          _salinan = List.of(snapshot.runningTexts);
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
                      'Teks yang berjalan di baris bawah layar TV. '
                      'Setiap perubahan langsung dikirim ke TV.',
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
                  ? const _DaftarKosong(
                      pesan:
                          'Belum ada teks berjalan di TV. Tambahkan '
                          'lewat tombol Tambah di atas.',
                    )
                  : ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      itemCount: daftar.length,
                      onReorderItem: _susunUlang,
                      itemBuilder: (context, i) => _BarisTeks(
                        key: ValueKey(daftar[i].id),
                        nomor: i + 1,
                        pesan: daftar[i],
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

/// Keadaan daftar kosong yang SAH (snapshot TV memang tidak
/// berisi teks): pesan ramah, tambah tetap bisa dari header.
class _DaftarKosong extends StatelessWidget {
  const _DaftarKosong({required this.pesan});

  final String pesan;

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
              Icons.subtitles_off_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              pesan,
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

class _BarisTeks extends StatelessWidget {
  const _BarisTeks({
    super.key,
    required this.nomor,
    required this.pesan,
    required this.indeks,
    required this.sibuk,
    required this.onAktif,
    required this.onSunting,
    required this.onHapus,
  });

  final int nomor;
  final RunningTextMessage pesan;
  final int indeks;
  final bool sibuk;
  final ValueChanged<bool> onAktif;
  final VoidCallback onSunting;
  final VoidCallback onHapus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: scheme.secondaryContainer,
              child: Text(
                '$nomor',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSecondaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pesan.content,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: pesan.isActive
                          ? null
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Chip(
                        label: Text(pesan.category),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                      ),
                      if (!pesan.isActive) ...[
                        const SizedBox(width: 6),
                        Text(
                          'Nonaktif',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Switch(
              value: pesan.isActive,
              onChanged: sibuk ? null : onAktif,
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Ubah teks',
              onPressed: sibuk ? null : onSunting,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Hapus teks',
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
      ),
    );
  }
}

/// Dialog layar penuh tambah/ubah satu teks berjalan: isi
/// (wajib terisi) + kategori dari daftar tetap.
class _DialogTeksBerjalan extends StatefulWidget {
  const _DialogTeksBerjalan({this.awal});

  /// Pesan yang disunting; null = tambah baru.
  final RunningTextMessage? awal;

  @override
  State<_DialogTeksBerjalan> createState() => _DialogTeksBerjalanState();
}

class _DialogTeksBerjalanState extends State<_DialogTeksBerjalan> {
  late final TextEditingController _isi;
  late String _kategori;

  @override
  void initState() {
    super.initState();
    _isi = TextEditingController(text: widget.awal?.content ?? '');
    _kategori = widget.awal?.category ?? 'Umum';
  }

  @override
  void dispose() {
    _isi.dispose();
    super.dispose();
  }

  bool get _sah => _isi.text.trim().isNotEmpty;

  void _simpan() {
    final awal = widget.awal;
    Navigator.pop(
      context,
      RunningTextMessage(
        id: awal?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        content: _isi.text.trim(),
        isActive: awal?.isActive ?? true,
        category: _kategori,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Kategori warisan di luar daftar tetap tetap bisa dipilih
    // ulang apa adanya (jangan diam-diam diganti saat menyunting).
    final kategori = <String>[
      ...kKategoriTeksBerjalan,
      if (widget.awal != null &&
          !kKategoriTeksBerjalan.contains(widget.awal!.category))
        widget.awal!.category,
    ];
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Batal',
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            widget.awal == null
                ? 'Tambah Teks Berjalan'
                : 'Ubah Teks Berjalan',
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
              controller: _isi,
              minLines: 3,
              maxLines: 5,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Isi teks',
                hintText: 'Tulis teks yang akan berjalan di TV…',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (!_sah) ...[
              const SizedBox(height: 8),
              Text(
                'Isi teks tidak boleh kosong.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 20),
            Text('Kategori', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final k in kategori)
                  ChoiceChip(
                    label: Text(k),
                    selected: _kategori == k,
                    onSelected: (_) => setState(() => _kategori = k),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
