import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nekios_core/nekios_core.dart';

import '../masjid/tautan_bt.dart';
import '../masjid/transport_masjid.dart';
import '../model/display_tersimpan.dart';
import '../state/remote_store.dart';
import '../state/store_masjid.dart';
import 'widget_bersama.dart';

/// Layar Koneksi: status sambungan, sambung cepat via IP untuk
/// display SEKOLAH (IP terakhir terisi otomatis — auto-save), dan
/// daftar display tersimpan lintas tipe (sekolah / masjid) —
/// tambah / ubah / hapus / ketuk untuk menyambung. Display masjid
/// disambungkan lewat [MasjidStore] (Wi-Fi 8080 atau Bluetooth),
/// display sekolah lewat [RemoteStore] seperti sebelumnya.
class LayarKoneksi extends StatefulWidget {
  const LayarKoneksi({
    super.key,
    required this.store,
    required this.storeMasjid,
    required this.tautan,
  });

  final RemoteStore store;
  final MasjidStore storeMasjid;
  final TautanBluetooth tautan;

  @override
  State<LayarKoneksi> createState() => _LayarKoneksiState();
}

class _LayarKoneksiState extends State<LayarKoneksi> {
  late final TextEditingController _ipController;

  RemoteStore get store => widget.store;
  MasjidStore get storeMasjid => widget.storeMasjid;

  @override
  void initState() {
    super.initState();
    _ipController = TextEditingController(text: store.ipTerakhir ?? '');
  }

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  Future<void> _sambungCepat() async {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) return;
    final cocok = store.daftarDisplay.where(
      (d) => !d.adalahMasjid && d.ip == ip,
    );
    final display = cocok.isNotEmpty
        ? cocok.first
        : DisplayTersimpan(nama: 'Display $ip', ip: ip);
    await store.sambungkan(display);
  }

  Future<void> _sambungkanDisplay(DisplayTersimpan display) async {
    if (display.adalahMasjid) {
      await storeMasjid.sambungkan(display);
    } else {
      await store.sambungkan(display);
    }
  }

  Future<void> _dialogDisplay({int? index}) async {
    final awal = index != null ? store.daftarDisplay[index] : null;
    final hasil = await showDialog<DisplayTersimpan>(
      context: context,
      builder: (context) => _DialogDisplay(awal: awal, tautan: widget.tautan),
    );
    if (hasil == null) return;
    if (index == null) {
      await store.tambahDisplay(hasil);
    } else {
      await store.ubahDisplay(index, hasil);
    }
  }

  Future<void> _hapusDisplay(int index) async {
    final display = store.daftarDisplay[index];
    final yakin = await mintaKonfirmasi(
      context,
      judul: 'Hapus display?',
      isi:
          '“${display.nama}” (${display.alamatRingkas}) akan dihapus '
          'dari daftar.',
      tombolSetuju: 'Hapus',
    );
    if (yakin) await store.hapusDisplay(index);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([store, storeMasjid]),
      builder: (context, _) {
        final theme = Theme.of(context);
        final masjidAktif = storeMasjid.statusKoneksi != StatusKoneksi.terputus;
        final statusTampil = masjidAktif
            ? storeMasjid.statusKoneksi
            : store.statusKoneksi;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Status koneksi',
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        ChipStatusDari(status: statusTampil),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _teksStatus(masjidAktif),
                      style: theme.textTheme.bodyMedium,
                    ),
                    if (!masjidAktif && storeMasjid.terhubung)
                      Text(
                        'TV masjid juga terhubung: '
                        '${storeMasjid.displayAktif?.nama ?? ''}',
                        style: theme.textTheme.bodyMedium,
                      ),
                    if (masjidAktif && store.terhubung)
                      Text(
                        'Display sekolah juga terhubung: '
                        '${store.displayAktif?.nama ?? ''}',
                        style: theme.textTheme.bodyMedium,
                      ),
                    if ((masjidAktif
                            ? storeMasjid.pesanKoneksi
                            : store.pesanKoneksi) !=
                        null) ...[
                      const SizedBox(height: 8),
                      Text(
                        (masjidAktif
                            ? storeMasjid.pesanKoneksi
                            : store.pesanKoneksi)!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                    if (statusTampil != StatusKoneksi.terputus) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => masjidAktif
                            ? storeMasjid.putuskan()
                            : store.putuskan(),
                        icon: const Icon(Icons.link_off),
                        label: const Text('Putuskan'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Sambung cepat (display sekolah)',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _ipController,
                    decoration: InputDecoration(
                      labelText: 'Alamat IP display',
                      hintText: 'Mis. 192.168.1.20',
                      helperText:
                          'Port tetap $kNekiosPort. IP terakhir '
                          'tersimpan otomatis.',
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.url,
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: store.statusKoneksi == StatusKoneksi.menyambung
                      ? null
                      : _sambungCepat,
                  icon: const Icon(Icons.wifi),
                  label: const Text('Sambungkan'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Display tersimpan',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _dialogDisplay(),
                  icon: const Icon(Icons.add),
                  label: const Text('Tambah'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (store.daftarDisplay.isEmpty)
              Text(
                'Belum ada display tersimpan. Tambahkan TV sekolah atau '
                'TV masjid di sini supaya menyambung berikutnya tinggal '
                'ketuk.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            for (var i = 0; i < store.daftarDisplay.length; i++)
              _kartuDisplay(context, i),
          ],
        );
      },
    );
  }

  String _teksStatus(bool masjidAktif) {
    if (masjidAktif) {
      final d = storeMasjid.displayAktif;
      return switch (storeMasjid.statusKoneksi) {
        StatusKoneksi.terhubung =>
          'Terhubung ke TV masjid ${d?.nama ?? ''} '
              '(${d?.pakaiBluetooth ?? false ? '${d?.alamatRingkas} · Bluetooth' : '${d?.ip}:$kPortWsMasjid'})',
        StatusKoneksi.menyambung => 'Menyambung ke TV masjid ${d?.nama ?? ''}…',
        StatusKoneksi.terputus => 'Tidak ada display yang terhubung.',
      };
    }
    return switch (store.statusKoneksi) {
      StatusKoneksi.terhubung =>
        'Terhubung ke ${store.displayAktif?.nama ?? ''} '
            '(${store.displayAktif?.ip ?? ''}:$kNekiosPort)',
      StatusKoneksi.menyambung =>
        'Menyambung ke ${store.displayAktif?.ip ?? ''}…',
      StatusKoneksi.terputus => 'Tidak ada display yang terhubung.',
    };
  }

  Widget _kartuDisplay(BuildContext context, int i) {
    final display = store.daftarDisplay[i];
    final subjudul = switch ((display.tipe, display.transport)) {
      (TipeDisplay.sekolah, _) => 'Sekolah · ${display.ip}:$kNekiosPort',
      (TipeDisplay.masjid, JalurMasjid.wifi) =>
        'Masjid · Wi-Fi · ${display.ip}:$kPortWsMasjid',
      (TipeDisplay.masjid, JalurMasjid.bluetooth) =>
        'Masjid · Bluetooth · ${display.alamatRingkas}',
    };
    return Card(
      child: ListTile(
        leading: Icon(
          display.adalahMasjid ? Icons.mosque_outlined : Icons.school_outlined,
        ),
        title: Text(display.nama),
        subtitle: Text(subjudul),
        trailing: PopupMenuButton<String>(
          onSelected: (pilihan) {
            if (pilihan == 'ubah') _dialogDisplay(index: i);
            if (pilihan == 'hapus') _hapusDisplay(i);
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'ubah', child: Text('Ubah')),
            PopupMenuItem(value: 'hapus', child: Text('Hapus')),
          ],
        ),
        onTap: () => _sambungkanDisplay(display),
      ),
    );
  }
}

/// Dialog tambah/ubah display dengan pilihan tipe (sekolah/masjid)
/// dan — untuk masjid — pilihan transport Wi-Fi / Bluetooth + PIN.
class _DialogDisplay extends StatefulWidget {
  const _DialogDisplay({required this.awal, required this.tautan});

  final DisplayTersimpan? awal;
  final TautanBluetooth tautan;

  @override
  State<_DialogDisplay> createState() => _DialogDisplayState();
}

class _DialogDisplayState extends State<_DialogDisplay> {
  late TipeDisplay _tipe;
  late JalurMasjid _jalur;
  late final TextEditingController _nama;
  late final TextEditingController _ip;
  late final TextEditingController _mac;
  late final TextEditingController _namaBt;
  late final TextEditingController _pin;

  @override
  void initState() {
    super.initState();
    final awal = widget.awal;
    _tipe = awal?.tipe ?? TipeDisplay.sekolah;
    _jalur = awal?.transport ?? JalurMasjid.wifi;
    _nama = TextEditingController(text: awal?.nama ?? '');
    _ip = TextEditingController(text: awal?.ip ?? '');
    _mac = TextEditingController(text: awal?.alamatBluetooth ?? '');
    _namaBt = TextEditingController(text: awal?.namaBluetooth ?? '');
    _pin = TextEditingController(text: awal?.pinBluetooth ?? '');
  }

  @override
  void dispose() {
    _nama.dispose();
    _ip.dispose();
    _mac.dispose();
    _namaBt.dispose();
    _pin.dispose();
    super.dispose();
  }

  bool get _valid {
    if (_nama.text.trim().isEmpty) return false;
    if (_tipe == TipeDisplay.sekolah) return _ip.text.trim().isNotEmpty;
    if (_jalur == JalurMasjid.wifi) return _ip.text.trim().isNotEmpty;
    return _mac.text.trim().isNotEmpty;
  }

  void _simpan() {
    if (!_valid) return;
    Navigator.pop(
      context,
      DisplayTersimpan(
        nama: _nama.text.trim(),
        ip: _ip.text.trim(),
        tipe: _tipe,
        transport: _jalur,
        alamatBluetooth: _mac.text.trim().toUpperCase(),
        namaBluetooth: _namaBt.text.trim(),
        pinBluetooth: _pin.text.trim(),
      ),
    );
  }

  Future<void> _pilihPerangkat() async {
    final perangkat = await showDialog<PerangkatBt>(
      context: context,
      builder: (context) => _DialogPilihBluetooth(tautan: widget.tautan),
    );
    if (perangkat == null) return;
    setState(() {
      _mac.text = perangkat.alamat;
      if (perangkat.nama.isNotEmpty) _namaBt.text = perangkat.nama;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.awal == null ? 'Tambah display' : 'Ubah display'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<TipeDisplay>(
              segments: const [
                ButtonSegment(
                  value: TipeDisplay.sekolah,
                  icon: Icon(Icons.school_outlined),
                  label: Text('Sekolah'),
                ),
                ButtonSegment(
                  value: TipeDisplay.masjid,
                  icon: Icon(Icons.mosque_outlined),
                  label: Text('Masjid'),
                ),
              ],
              selected: {_tipe},
              onSelectionChanged: (pilihan) =>
                  setState(() => _tipe = pilihan.first),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nama,
              decoration: const InputDecoration(
                labelText: 'Nama display',
                hintText: 'Mis. TV Masjid Al-Hikmah',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            if (_tipe == TipeDisplay.masjid) ...[
              SegmentedButton<JalurMasjid>(
                segments: const [
                  ButtonSegment(
                    value: JalurMasjid.wifi,
                    icon: Icon(Icons.wifi_outlined),
                    label: Text('Wi-Fi'),
                  ),
                  ButtonSegment(
                    value: JalurMasjid.bluetooth,
                    icon: Icon(Icons.bluetooth_outlined),
                    label: Text('Bluetooth'),
                  ),
                ],
                selected: {_jalur},
                onSelectionChanged: (pilihan) =>
                    setState(() => _jalur = pilihan.first),
              ),
              const SizedBox(height: 12),
            ],
            if (_tipe == TipeDisplay.sekolah || _jalur == JalurMasjid.wifi)
              TextField(
                controller: _ip,
                decoration: InputDecoration(
                  labelText: 'Alamat IP',
                  hintText: 'Mis. 192.168.1.20',
                  helperText: _tipe == TipeDisplay.sekolah
                      ? 'Port tetap $kNekiosPort (nekios-core).'
                      : 'Port tetap $kPortWsMasjid (server warisan TV).',
                  border: const OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
                onChanged: (_) => setState(() {}),
              ),
            if (_tipe == TipeDisplay.masjid &&
                _jalur == JalurMasjid.bluetooth) ...[
              TextField(
                controller: _mac,
                decoration: const InputDecoration(
                  labelText: 'Alamat Bluetooth TV (MAC)',
                  hintText: 'Mis. AA:BB:CC:DD:EE:FF',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _pilihPerangkat,
                icon: const Icon(Icons.bluetooth_searching),
                label: const Text('Pilih dari perangkat Bluetooth'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _namaBt,
                decoration: const InputDecoration(
                  labelText: 'Nama Bluetooth TV (label)',
                  hintText: 'Mis. Masjid You TV',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pin,
                decoration: const InputDecoration(
                  labelText: 'PIN Bluetooth TV (4 digit)',
                  helperText:
                      'Tampil di menu admin TV; berganti tiap TV '
                      'dinyalakan ulang.',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                maxLength: 4,
                obscureText: true,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _valid ? _simpan : null,
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}

/// Pemilih perangkat Bluetooth: daftar bonded + discovery langsung.
class _DialogPilihBluetooth extends StatefulWidget {
  const _DialogPilihBluetooth({required this.tautan});

  final TautanBluetooth tautan;

  @override
  State<_DialogPilihBluetooth> createState() => _DialogPilihBluetoothState();
}

class _DialogPilihBluetoothState extends State<_DialogPilihBluetooth> {
  final List<PerangkatBt> _daftar = [];
  bool _memuat = true;
  bool _mencari = false;
  String? _pesan;
  StreamSubscription<KejadianBt>? _langganan;

  @override
  void initState() {
    super.initState();
    _langganan = widget.tautan.kejadian.listen((kejadian) {
      if (!mounted) return;
      switch (kejadian) {
        case BtDitemukan(:final perangkat):
          setState(() {
            if (!_daftar.contains(perangkat)) _daftar.add(perangkat);
          });
        case BtDiscoverySelesai():
          setState(() => _mencari = false);
        default:
          break;
      }
    });
    unawaited(_muatBonded());
  }

  @override
  void dispose() {
    _langganan?.cancel();
    unawaited(widget.tautan.berhentiDiscovery());
    super.dispose();
  }

  Future<void> _muatBonded() async {
    try {
      if (!await widget.tautan.punyaIzin()) await widget.tautan.mintaIzin();
      if (!await widget.tautan.aktif()) await widget.tautan.mintaAktif();
      final bonded = await widget.tautan.perangkatTerpasang();
      if (!mounted) return;
      setState(() {
        for (final p in bonded) {
          if (!_daftar.contains(p)) _daftar.add(p);
        }
        _memuat = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _memuat = false;
        _pesan = 'Bluetooth tidak tersedia di perangkat ini.';
      });
    }
  }

  Future<void> _cari() async {
    setState(() => _mencari = true);
    try {
      await widget.tautan.mulaiDiscovery();
    } catch (_) {
      if (mounted) setState(() => _mencari = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pilih TV Bluetooth'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_memuat)
              const Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              )
            else if (_pesan != null)
              Text(_pesan!)
            else if (_daftar.isEmpty)
              const Text(
                'Belum ada perangkat. Pasangkan TV lebih dulu lewat '
                'Mode Pairing di TV, atau cari perangkat sekarang.',
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final p in _daftar)
                      ListTile(
                        leading: const Icon(Icons.tv_outlined),
                        title: Text(p.nama.isEmpty ? '(tanpa nama)' : p.nama),
                        subtitle: Text(p.alamat),
                        onTap: () => Navigator.pop(context, p),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _mencari ? null : _cari,
              icon: const Icon(Icons.search),
              label: Text(_mencari ? 'Mencari…' : 'Cari perangkat'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
      ],
    );
  }
}
