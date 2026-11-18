import 'package:flutter/material.dart';

import '../domain/editor_jadwal.dart';
import 'widget_bersama.dart';

/// Warna aksen mapel dari data jadwal (#RRGGBB) sebagai titik kecil;
/// data tidak terbaca jatuh ke warna skema.
Color warnaDariHex(String hex, Color cadangan) {
  try {
    return Color(int.parse(hex.substring(1), radix: 16) + 0xFF000000);
  } catch (_) {
    return cadangan;
  }
}

/// Tahap 1 Editor Jadwal: Master Data guru & mapel + relasinya.
///
/// Daftar ringkas per seksi; ketuk item membuka lembar edit
/// (nama + checklist relasi pihak seberang). Tambah lewat tombol +
/// di kepala seksi. Hapus dijaga domain: yang masih dipakai entri
/// jadwal mana pun ditolak dengan pesan jelas.
class MasterDataView extends StatelessWidget {
  const MasterDataView({
    super.key,
    required this.editor,
    required this.onBerubah,
  });

  final DokumenEditor editor;
  final VoidCallback onBerubah;

  MasterData get _master => editor.master;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Guru (${_master.guru.length})',
                style: theme.textTheme.titleMedium,
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'Tambah guru',
              icon: const Icon(Icons.add),
              onPressed: () => _bukaLembarGuru(context),
            ),
          ],
        ),
        const SizedBox(height: 4),
        for (final g in _master.guru)
          Card(
            child: ListTile(
              title: Text(g.nama),
              subtitle: Text(
                'KG ${g.kg}'
                '${_master.mapelUntukGuru(g.kg).isEmpty ? '' : ' • ${_master.mapelUntukGuru(g.kg).join(', ')}'}',
              ),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _bukaLembarGuru(context, guru: g),
            ),
          ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Text(
                'Mapel (${_master.mapel.length})',
                style: theme.textTheme.titleMedium,
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'Tambah mapel',
              icon: const Icon(Icons.add),
              onPressed: () => _bukaLembarMapel(context),
            ),
          ],
        ),
        const SizedBox(height: 4),
        for (final m in _master.mapel)
          Card(
            child: ListTile(
              leading: CircleAvatar(
                radius: 8,
                backgroundColor: warnaDariHex(
                  m.warna,
                  theme.colorScheme.primary,
                ),
              ),
              title: Text('${m.kode} — ${m.namaPanjang}'),
              subtitle: Text(
                _master.guruUntukMapel(m.kode).isEmpty
                    ? 'Belum ada guru pengajar'
                    : _master
                          .guruUntukMapel(m.kode)
                          .map((g) => g.nama)
                          .join(', '),
              ),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _bukaLembarMapel(context, mapel: m),
            ),
          ),
        const SizedBox(height: 12),
        Text(
          'Relasi guru ↔ mapel bebas: satu guru bisa mengajar banyak '
          'mapel, satu mapel bisa diajar banyak guru (team-teaching). '
          'Relasi hanya panduan saat plotting — bukan kunci.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Future<void> _bukaLembarGuru(BuildContext context, {GuruMaster? guru}) async {
    final berubah = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _LembarGuru(editor: editor, guru: guru),
    );
    if (berubah == true) onBerubah();
  }

  Future<void> _bukaLembarMapel(
    BuildContext context, {
    MapelMaster? mapel,
  }) async {
    final berubah = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _LembarMapel(editor: editor, mapel: mapel),
    );
    if (berubah == true) onBerubah();
  }
}

/// Lembar tambah/edit guru: nama (+ KG saat tambah) dan checklist
/// mapel yang diajarnya.
class _LembarGuru extends StatefulWidget {
  const _LembarGuru({required this.editor, this.guru});

  final DokumenEditor editor;
  final GuruMaster? guru;

  @override
  State<_LembarGuru> createState() => _LembarGuruState();
}

class _LembarGuruState extends State<_LembarGuru> {
  late final TextEditingController _nama = TextEditingController(
    text: widget.guru?.nama ?? '',
  );
  late final TextEditingController _kg = TextEditingController(
    text: widget.guru?.kg.toString() ?? '',
  );
  late final Set<String> _mapelDipilih = {
    if (widget.guru != null)
      ...widget.editor.master.mapelUntukGuru(widget.guru!.kg),
  };

  MasterData get _master => widget.editor.master;

  void _gagal(String pesan) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(pesan)));
  }

  Future<void> _simpan() async {
    final guruLama = widget.guru;
    if (guruLama == null) {
      final kg = int.tryParse(_kg.text.trim());
      if (kg == null) {
        _gagal('KG harus berupa angka.');
        return;
      }
      final hasil = _master.tambahGuru(kg, _nama.text);
      if (!hasil.sukses) {
        _gagal(hasil.pesan!);
        return;
      }
      _master.aturRelasiGuru(kg, _mapelDipilih);
    } else {
      final hasil = _master.ubahNamaGuru(guruLama.kg, _nama.text);
      if (!hasil.sukses) {
        _gagal(hasil.pesan!);
        return;
      }
      _master.aturRelasiGuru(guruLama.kg, _mapelDipilih);
    }
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _hapus() async {
    final guru = widget.guru!;
    final yakin = await mintaKonfirmasi(
      context,
      judul: 'Hapus guru?',
      isi: '${guru.nama} (KG ${guru.kg}) akan dihapus dari master data.',
      tombolSetuju: 'Hapus',
    );
    if (!yakin || !mounted) return;
    final hasil = widget.editor.hapusGuru(guru.kg);
    if (!hasil.sukses) {
      _gagal(hasil.pesan!);
      return;
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sedangEdit = widget.guru != null;
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              sedangEdit ? 'Edit guru' : 'Tambah guru',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 96,
                  child: TextField(
                    controller: _kg,
                    enabled: !sedangEdit,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'KG',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _nama,
                    decoration: const InputDecoration(
                      labelText: 'Nama guru',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Mapel yang diajar', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final m in _master.mapel)
                    CheckboxListTile(
                      dense: true,
                      title: Text('${m.kode} — ${m.namaPanjang}'),
                      value: _mapelDipilih.contains(m.kode),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _mapelDipilih.add(m.kode);
                        } else {
                          _mapelDipilih.remove(m.kode);
                        }
                      }),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (sedangEdit)
                  TextButton.icon(
                    onPressed: _hapus,
                    icon: Icon(
                      Icons.delete_outline,
                      color: theme.colorScheme.error,
                    ),
                    label: Text(
                      'Hapus',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Batal'),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _simpan, child: const Text('Simpan')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Lembar tambah/edit mapel: kode (saat tambah), nama panjang,
/// warna aksen dari palet data, dan checklist guru pengajar
/// (multi-pilih — mendukung team-teaching).
class _LembarMapel extends StatefulWidget {
  const _LembarMapel({required this.editor, this.mapel});

  final DokumenEditor editor;
  final MapelMaster? mapel;

  @override
  State<_LembarMapel> createState() => _LembarMapelState();
}

class _LembarMapelState extends State<_LembarMapel> {
  late final TextEditingController _kode = TextEditingController(
    text: widget.mapel?.kode ?? '',
  );
  late final TextEditingController _nama = TextEditingController(
    text: widget.mapel?.namaPanjang ?? '',
  );
  late String _warna = widget.mapel?.warna ?? kPaletWarnaMapel.first;
  late final Set<int> _guruDipilih = {
    if (widget.mapel != null)
      ...widget.editor.master
          .guruUntukMapel(widget.mapel!.kode)
          .map((g) => g.kg),
  };

  MasterData get _master => widget.editor.master;

  void _gagal(String pesan) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(pesan)));
  }

  Future<void> _simpan() async {
    final mapelLama = widget.mapel;
    if (mapelLama == null) {
      final hasil = _master.tambahMapel(_kode.text, _nama.text, _warna);
      if (!hasil.sukses) {
        _gagal(hasil.pesan!);
        return;
      }
      _master.aturRelasiMapel(_kode.text.trim(), _guruDipilih);
    } else {
      final hasil = _master.ubahMapel(
        mapelLama.kode,
        namaPanjang: _nama.text,
        warna: _warna,
      );
      if (!hasil.sukses) {
        _gagal(hasil.pesan!);
        return;
      }
      _master.aturRelasiMapel(mapelLama.kode, _guruDipilih);
    }
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _hapus() async {
    final mapel = widget.mapel!;
    final yakin = await mintaKonfirmasi(
      context,
      judul: 'Hapus mapel?',
      isi:
          '${mapel.kode} (${mapel.namaPanjang}) akan dihapus dari master data.',
      tombolSetuju: 'Hapus',
    );
    if (!yakin || !mounted) return;
    final hasil = widget.editor.hapusMapel(mapel.kode);
    if (!hasil.sukses) {
      _gagal(hasil.pesan!);
      return;
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sedangEdit = widget.mapel != null;
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              sedangEdit ? 'Edit mapel' : 'Tambah mapel',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _kode,
                    enabled: !sedangEdit,
                    decoration: const InputDecoration(
                      labelText: 'Kode',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _nama,
                    decoration: const InputDecoration(
                      labelText: 'Nama panjang',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Warna aksen (data jadwal)',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final w in kPaletWarnaMapel)
                  ChoiceChip(
                    label: const SizedBox(width: 8, height: 8),
                    avatar: CircleAvatar(
                      radius: 8,
                      backgroundColor: warnaDariHex(
                        w,
                        theme.colorScheme.primary,
                      ),
                    ),
                    selected: _warna == w,
                    onSelected: (_) => setState(() => _warna = w),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Guru pengajar', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final g in _master.guru)
                    CheckboxListTile(
                      dense: true,
                      title: Text(g.nama),
                      subtitle: Text('KG ${g.kg}'),
                      value: _guruDipilih.contains(g.kg),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _guruDipilih.add(g.kg);
                        } else {
                          _guruDipilih.remove(g.kg);
                        }
                      }),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (sedangEdit)
                  TextButton.icon(
                    onPressed: _hapus,
                    icon: Icon(
                      Icons.delete_outline,
                      color: theme.colorScheme.error,
                    ),
                    label: Text(
                      'Hapus',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Batal'),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _simpan, child: const Text('Simpan')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
