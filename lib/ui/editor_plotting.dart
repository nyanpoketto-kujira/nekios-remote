import 'package:flutter/material.dart';

import '../domain/editor_jadwal.dart';
import 'editor_master_data.dart' show warnaDariHex;
import 'widget_bersama.dart';

String kapital(String teks) =>
    teks.isEmpty ? teks : teks[0].toUpperCase() + teks.substring(1);

/// Tahap 2 Editor Jadwal: Plotting.
///
/// TabBar per hari (Senin–Jumat) + daftar slot vertikal. Slot
/// non-pelajaran tampil redup dan tidak bisa di-assign; slot
/// pelajaran menampilkan chip mapel + nama guru, atau ajakan
/// mengisi bila kosong. Ketuk slot pelajaran membuka Bottom Sheet
/// tap-to-assign (mapel, guru, rentang 1–4 jam, kosongkan).
class PlottingView extends StatefulWidget {
  const PlottingView({
    super.key,
    required this.editor,
    required this.onBerubah,
  });

  final DokumenEditor editor;
  final VoidCallback onBerubah;

  @override
  State<PlottingView> createState() => _PlottingViewState();
}

class _PlottingViewState extends State<PlottingView>
    with SingleTickerProviderStateMixin {
  late TabController _tabHari;

  DokumenEditor get editor => widget.editor;

  @override
  void initState() {
    super.initState();
    _tabHari = TabController(length: editor.templatHari.length, vsync: this);
  }

  @override
  void dispose() {
    _tabHari.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tabHari,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            for (final h in editor.templatHari) Tab(text: kapital(h.nama)),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabHari,
            children: [
              for (var h = 0; h < editor.templatHari.length; h++)
                _DaftarSlotHari(
                  editor: editor,
                  indeksHari: h,
                  onBerubah: widget.onBerubah,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DaftarSlotHari extends StatelessWidget {
  const _DaftarSlotHari({
    required this.editor,
    required this.indeksHari,
    required this.onBerubah,
  });

  final DokumenEditor editor;
  final int indeksHari;
  final VoidCallback onBerubah;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final slots = editor.templatHari[indeksHari].slots;
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: slots.length,
      itemBuilder: (context, s) {
        final slot = slots[s];
        final jam = '${slot.mulai} – ${slot.selesai}';
        if (!slot.adalahPelajaran) {
          return Card(
            color: theme.colorScheme.surfaceContainerLowest,
            child: ListTile(
              enabled: false,
              leading: const Icon(Icons.local_cafe_outlined),
              title: Text(slot.label ?? kapital(slot.tipe)),
              subtitle: Text(jam),
            ),
          );
        }
        final entri = editor.entriAktif(indeksHari, s);
        final mapel = entri == null
            ? null
            : editor.master.mapelDariKode(entri.kodeMapel);
        final guru = entri == null ? null : editor.master.guruDariKg(entri.kg);
        return Card(
          child: ListTile(
            title: Text(jam),
            subtitle: entri == null
                ? Text(
                    'Kosong — ketuk untuk mengisi',
                    style: TextStyle(
                      color: theme.colorScheme.error,
                      fontStyle: FontStyle.italic,
                    ),
                  )
                : Text(
                    '${mapel?.namaPanjang ?? entri.kodeMapel}'
                    ' • ${guru?.nama ?? 'KG ${entri.kg}'}',
                  ),
            trailing: entri == null
                ? const Icon(Icons.add_circle_outline)
                : Chip(
                    avatar: CircleAvatar(
                      radius: 6,
                      backgroundColor: warnaDariHex(
                        mapel?.warna ?? '',
                        theme.colorScheme.primary,
                      ),
                    ),
                    label: Text(entri.kodeMapel),
                    visualDensity: VisualDensity.compact,
                  ),
            onTap: () => _bukaAssign(context, indeksHari, s),
          ),
        );
      },
    );
  }

  Future<void> _bukaAssign(
    BuildContext context,
    int indeksHari,
    int indeksSlot,
  ) async {
    final berubah = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _LembarAssign(
        editor: editor,
        indeksHari: indeksHari,
        indeksSlot: indeksSlot,
      ),
    );
    if (berubah == true) onBerubah();
  }
}

/// Bottom Sheet tap-to-assign: pilih mapel (chip), pilih guru
/// (chip — yang berelasi dengan mapel diutamakan & bertanda bintang,
/// tapi guru lain tetap boleh dipilih: relasi = panduan, bukan
/// kunci), stepper rentang 1–4 jam, Terapkan & Kosongkan.
class _LembarAssign extends StatefulWidget {
  const _LembarAssign({
    required this.editor,
    required this.indeksHari,
    required this.indeksSlot,
  });

  final DokumenEditor editor;
  final int indeksHari;
  final int indeksSlot;

  @override
  State<_LembarAssign> createState() => _LembarAssignState();
}

class _LembarAssignState extends State<_LembarAssign> {
  String? _kodeMapel;
  int? _kg;
  int _rentang = 1;

  DokumenEditor get editor => widget.editor;
  SlotTemplat get _slot =>
      editor.templatHari[widget.indeksHari].slots[widget.indeksSlot];
  EntriSlot? get _entriLama =>
      editor.entriAktif(widget.indeksHari, widget.indeksSlot);

  @override
  void initState() {
    super.initState();
    _kodeMapel = _entriLama?.kodeMapel;
    _kg = _entriLama?.kg;
  }

  void _gagal(String pesan) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(pesan)));
  }

  Future<void> _terapkan() async {
    final kode = _kodeMapel;
    final kg = _kg;
    if (kode == null || kg == null) {
      _gagal('Pilih mapel dan guru dulu.');
      return;
    }
    if (_rentang <= 1) {
      final hasil = editor.assignSlot(
        widget.indeksHari,
        widget.indeksSlot,
        kodeMapel: kode,
        kg: kg,
      );
      if (!hasil.sukses) {
        _gagal(hasil.pesan!);
        return;
      }
      if (mounted) Navigator.pop(context, true);
      return;
    }
    final pratinjau = editor.pratinjauRentang(
      widget.indeksHari,
      widget.indeksSlot,
      _rentang,
    );
    var izinkanTimpa = false;
    if (pratinjau.adaTimpa) {
      final yakin = await mintaKonfirmasi(
        context,
        judul: 'Timpa slot yang sudah terisi?',
        isi:
            'Rentang $_rentang jam ini menimpa '
            '${pratinjau.indeksSlot.length} slot, sebagian sudah berisi '
            'mapel lain. Lanjutkan?',
        tombolSetuju: 'Timpa',
      );
      if (!yakin || !mounted) return;
      izinkanTimpa = true;
    }
    final hasil = editor.assignRentang(
      widget.indeksHari,
      widget.indeksSlot,
      kodeMapel: kode,
      kg: kg,
      jumlahJam: _rentang,
      izinkanTimpa: izinkanTimpa,
    );
    if (!hasil.sukses) {
      _gagal(hasil.pesan!);
      return;
    }
    if (mounted) {
      if (hasil.pesan != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(hasil.pesan!)));
      }
      Navigator.pop(context, true);
    }
  }

  Future<void> _kosongkan() async {
    final hasil = editor.kosongkanSlot(widget.indeksHari, widget.indeksSlot);
    if (!hasil.sukses) {
      _gagal(hasil.pesan!);
      return;
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final master = editor.master;
    final namaHari = kapital(editor.templatHari[widget.indeksHari].nama);
    final mapelTerurut = master.mapelDiurutkanUntukGuru(_kg);
    final guruTerurut = master.guruDiurutkanUntukMapel(_kodeMapel);
    final pratinjau = _rentang > 1
        ? editor.pratinjauRentang(
            widget.indeksHari,
            widget.indeksSlot,
            _rentang,
          )
        : null;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$namaHari • ${_slot.mulai} – ${_slot.selesai}',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Text('Mapel', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final m in mapelTerurut)
                    ChoiceChip(
                      label: Text(m.kode),
                      avatar:
                          _kg != null &&
                              master.mapelUntukGuru(_kg!).contains(m.kode)
                          ? const Icon(Icons.star, size: 14)
                          : null,
                      selected: _kodeMapel == m.kode,
                      onSelected: (_) => setState(() => _kodeMapel = m.kode),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Guru', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final g in guruTerurut)
                    ChoiceChip(
                      label: Text(g.nama),
                      avatar:
                          _kodeMapel != null &&
                              master.mapelUntukGuru(g.kg).contains(_kodeMapel)
                          ? const Icon(Icons.star, size: 14)
                          : null,
                      selected: _kg == g.kg,
                      onSelected: (_) => setState(() => _kg = g.kg),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text('Rentang', style: theme.textTheme.titleSmall),
                  const SizedBox(width: 12),
                  IconButton.filledTonal(
                    tooltip: 'Kurangi rentang',
                    icon: const Icon(Icons.remove),
                    onPressed: _rentang > 1
                        ? () => setState(() => _rentang--)
                        : null,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      '$_rentang jam',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Tambah rentang',
                    icon: const Icon(Icons.add),
                    onPressed: _rentang < 4
                        ? () => setState(() => _rentang++)
                        : null,
                  ),
                ],
              ),
              if (pratinjau != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    pratinjau.indeksSlot.isEmpty
                        ? 'Tidak ada slot pelajaran yang bisa diisi.'
                        : 'Akan mengisi ${pratinjau.indeksSlot.length} slot'
                              '${pratinjau.mentok ? ' (terpotong jeda/akhir hari)' : ''}'
                              '${pratinjau.adaTimpa ? ' — sebagian menimpa isi lama' : ''}.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              if (_entriLama != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _kosongkan,
                    icon: Icon(Icons.clear, color: theme.colorScheme.error),
                    label: Text(
                      'Kosongkan slot ini',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Batal'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _terapkan,
                    child: const Text('Terapkan'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
