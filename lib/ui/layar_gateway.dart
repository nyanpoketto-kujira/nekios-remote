import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nekios_core/nekios_core.dart';

import '../masjid/tautan_bt.dart';
import '../model/display_tersimpan.dart';
import '../state/sesi.dart';
import 'widget_bersama.dart';

/// Layar Gateway — akar aplikasi selama BELUM ada display yang
/// terhubung (connection guard, ADR-004; meniru alur gateway
/// mobile_remote masjid-you). Isinya:
/// * pemberitahuan (gagal deteksi/sambung, putus tak terduga +
///   tombol sambungkan ulang),
/// * kartu Bluetooth: perangkat dikenal (riwayat BT) + pencarian
///   perangkat baru (discovery → dialog PIN → auth TV masjid),
/// * kartu Wi-Fi: cukup alamat IP — jenis display DIDETEKSI
///   otomatis lewat probing paralel dua protokol, bukan dipilih,
/// * daftar display Wi-Fi tersimpan (riwayat hasil deteksi).
///
/// Dashboard (shell sekolah/masjid) hanya bisa dicapai setelah
/// salah satu store terhubung; lihat LayarUtama di app.dart.
class LayarGateway extends StatefulWidget {
  const LayarGateway({super.key, required this.sesi, required this.tautan});

  final SesiRemote sesi;
  final TautanBluetooth tautan;

  @override
  State<LayarGateway> createState() => _LayarGatewayState();
}

class _LayarGatewayState extends State<LayarGateway> {
  late final TextEditingController _ipController;
  final List<PerangkatBt> _ditemukan = [];
  bool _mencari = false;
  StreamSubscription<KejadianBt>? _langgananBt;

  SesiRemote get sesi => widget.sesi;

  @override
  void initState() {
    super.initState();
    _ipController = TextEditingController(
      text: sesi.storeSekolah.ipTerakhir ?? '',
    );
    _langgananBt = widget.tautan.kejadian.listen((kejadian) {
      if (!mounted) return;
      switch (kejadian) {
        case BtDitemukan(:final perangkat):
          setState(() {
            if (!_ditemukan.contains(perangkat)) _ditemukan.add(perangkat);
          });
        case BtDiscoverySelesai():
          setState(() => _mencari = false);
        default:
          break;
      }
    });
  }

  @override
  void dispose() {
    _ipController.dispose();
    _langgananBt?.cancel();
    unawaited(widget.tautan.berhentiDiscovery());
    super.dispose();
  }

  Future<void> _cariBluetooth() async {
    if (_mencari) {
      await widget.tautan.berhentiDiscovery();
      if (mounted) setState(() => _mencari = false);
      return;
    }
    try {
      if (!await widget.tautan.punyaIzin()) await widget.tautan.mintaIzin();
      if (!await widget.tautan.aktif()) await widget.tautan.mintaAktif();
      setState(() => _mencari = true);
      await widget.tautan.mulaiDiscovery();
    } catch (_) {
      if (mounted) setState(() => _mencari = false);
    }
  }

  Future<void> _ketukPerangkatBt(PerangkatBt perangkat) async {
    // Perangkat yang sudah dikenal (MAC tersimpan): langsung
    // sambung memakai PIN tersimpan, tanpa dialog.
    for (final d in sesi.storeSekolah.daftarDisplay) {
      if (d.pakaiBluetooth && d.alamatBluetooth == perangkat.alamat) {
        await sesi.sambungDisplay(d);
        return;
      }
    }
    final pin = await showDialog<String>(
      context: context,
      builder: (context) => const _DialogPin(),
    );
    if (pin == null) return;
    await sesi.sambungBluetooth(perangkat, pin);
  }

  Future<void> _ubahDisplay(DisplayTersimpan display) async {
    final hasil = await showDialog<DisplayTersimpan>(
      context: context,
      builder: (context) => _DialogUbahDisplay(awal: display),
    );
    if (hasil == null) return;
    final indeks = sesi.storeSekolah.daftarDisplay.indexOf(display);
    if (indeks >= 0) await sesi.storeSekolah.ubahDisplay(indeks, hasil);
  }

  Future<void> _hapusDisplay(DisplayTersimpan display) async {
    final yakin = await mintaKonfirmasi(
      context,
      judul: 'Hapus display?',
      isi:
          '“${display.nama}” (${display.alamatRingkas}) akan dihapus '
          'dari riwayat.',
      tombolSetuju: 'Hapus',
    );
    if (!yakin) return;
    final indeks = sesi.storeSekolah.daftarDisplay.indexOf(display);
    if (indeks >= 0) await sesi.storeSekolah.hapusDisplay(indeks);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nekios Remote')),
      body: ListenableBuilder(
        listenable: Listenable.merge([
          sesi,
          sesi.storeSekolah,
          sesi.storeMasjid,
        ]),
        builder: (context, _) {
          final theme = Theme.of(context);
          final skema = theme.colorScheme;
          final daftar = sesi.storeSekolah.daftarDisplay;
          final dikenalBt = [
            for (final d in daftar)
              if (d.pakaiBluetooth) d,
          ];
          final wifiTersimpan = [
            for (final d in daftar)
              if (!d.pakaiBluetooth) d,
          ];
          final macDikenal = {for (final d in dikenalBt) d.alamatBluetooth};
          final ditemukanBaru = [
            for (final p in _ditemukan)
              if (!macDikenal.contains(p.alamat)) p,
          ];
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const SizedBox(height: 8),
              Icon(Icons.tv_rounded, size: 56, color: skema.primary),
              const SizedBox(height: 16),
              Text(
                'Selamat Datang di Nekios Remote',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Sambungkan dulu ke display untuk membuka dashboard. '
                'Jenis display (sekolah / masjid) dikenali otomatis — '
                'kamu tidak perlu memilih.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: skema.onSurfaceVariant,
                ),
              ),
              if (sesi.pesan != null) ...[
                const SizedBox(height: 20),
                Card(
                  color: skema.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sesi.pesan!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: skema.onErrorContainer,
                          ),
                        ),
                        if (sesi.displayTerakhir != null) ...[
                          const SizedBox(height: 12),
                          FilledButton.tonalIcon(
                            onPressed: sesi.sibuk
                                ? null
                                : () => sesi.sambungUlang(),
                            icon: const Icon(Icons.replay),
                            label: const Text('Sambungkan ulang'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              _kartuBluetooth(
                context,
                dikenalBt: dikenalBt,
                ditemukanBaru: ditemukanBaru,
              ),
              const SizedBox(height: 16),
              _kartuWifi(context),
              if (wifiTersimpan.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(
                  'Display tersimpan',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Riwayat hasil deteksi — ketuk untuk menyambung '
                  'langsung.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: skema.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                for (final d in wifiTersimpan) _kartuDisplay(context, d),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _kartuBluetooth(
    BuildContext context, {
    required List<DisplayTersimpan> dikenalBt,
    required List<PerangkatBt> ditemukanBaru,
  }) {
    final theme = Theme.of(context);
    final skema = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bluetooth_searching, color: skema.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Koneksi Bluetooth',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: sesi.sibuk ? null : _cariBluetooth,
                  icon: _mencari
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.radar),
                  label: Text(_mencari ? 'Stop' : 'Cari Display'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Jalur penyelamat tanpa router Wi-Fi: pairing langsung '
              'ke TV, lalu masukkan PIN yang tampil di TV.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: skema.onSurfaceVariant,
              ),
            ),
            if (dikenalBt.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Perangkat Dikenal',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              for (final d in dikenalBt) _kartuDisplay(context, d),
            ],
            const SizedBox(height: 12),
            if (ditemukanBaru.isEmpty)
              Text(
                _mencari
                    ? 'Mencari display di sekitar…'
                    : 'Belum ada perangkat ditemukan.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: skema.onSurfaceVariant,
                ),
              )
            else
              for (final p in ditemukanBaru)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    color: skema.surfaceContainerHigh,
                    child: ListTile(
                      leading: const Icon(Icons.tv_outlined),
                      title: Text(p.nama.isEmpty ? '(tanpa nama)' : p.nama),
                      subtitle: Text(p.alamat),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: sesi.sibuk ? null : () => _ketukPerangkatBt(p),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _kartuWifi(BuildContext context) {
    final theme = Theme.of(context);
    final skema = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.wifi_rounded, color: skema.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Koneksi Wi-Fi',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Masukkan IP display bila HP dan TV berada di jaringan '
              'yang sama. Remote akan memeriksa port sekolah '
              '($kNekiosPort) dan port masjid (8080) sekaligus dan '
              'mengenali jenisnya sendiri.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: skema.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ipController,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Alamat IP display',
                hintText: 'Mis. 192.168.1.20',
                prefixIcon: Icon(Icons.link),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: sesi.sibuk
                    ? null
                    : () => sesi.sambungIp(_ipController.text),
                icon: sesi.sibuk
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.connect_without_contact),
                label: Text(sesi.sibuk ? 'Mendeteksi…' : 'Sambungkan'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kartuDisplay(BuildContext context, DisplayTersimpan display) {
    final subjudul = switch ((display.tipe, display.transport)) {
      (TipeDisplay.sekolah, _) => 'Sekolah · Wi-Fi · ${display.ip}:$kNekiosPort',
      (TipeDisplay.masjid, JalurMasjid.wifi) =>
        'Masjid · Wi-Fi · ${display.ip}:8080',
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
            if (pilihan == 'ubah') _ubahDisplay(display);
            if (pilihan == 'hapus') _hapusDisplay(display);
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'ubah', child: Text('Ubah')),
            PopupMenuItem(value: 'hapus', child: Text('Hapus')),
          ],
        ),
        onTap: sesi.sibuk ? null : () => sesi.sambungDisplay(display),
      ),
    );
  }
}

/// Dialog PIN Bluetooth TV (4 digit, tampil di menu admin TV /
/// Mode Pairing). Mengembalikan PIN atau null bila batal.
class _DialogPin extends StatefulWidget {
  const _DialogPin();

  @override
  State<_DialogPin> createState() => _DialogPinState();
}

class _DialogPinState extends State<_DialogPin> {
  final _pin = TextEditingController();

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('PIN Bluetooth TV'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Masukkan PIN 4 digit yang tampil di TV (menu admin / '
            'Mode Pairing). PIN berganti setiap TV dinyalakan ulang.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _pin,
            decoration: const InputDecoration(
              labelText: 'PIN (4 digit)',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            maxLength: 4,
            obscureText: true,
            autofocus: true,
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _pin.text.trim().length == 4
              ? () => Navigator.pop(context, _pin.text.trim())
              : null,
          child: const Text('Sambungkan'),
        ),
      ],
    );
  }
}

/// Dialog ubah entri riwayat: nama selalu bisa diubah; IP untuk
/// display Wi-Fi; PIN untuk display Bluetooth. Jenis display &
/// transport TIDAK diubah di sini — keduanya hasil deteksi/bukti
/// koneksi, bukan pilihan.
class _DialogUbahDisplay extends StatefulWidget {
  const _DialogUbahDisplay({required this.awal});

  final DisplayTersimpan awal;

  @override
  State<_DialogUbahDisplay> createState() => _DialogUbahDisplayState();
}

class _DialogUbahDisplayState extends State<_DialogUbahDisplay> {
  late final TextEditingController _nama;
  late final TextEditingController _ip;
  late final TextEditingController _pin;

  @override
  void initState() {
    super.initState();
    _nama = TextEditingController(text: widget.awal.nama);
    _ip = TextEditingController(text: widget.awal.ip);
    _pin = TextEditingController(text: widget.awal.pinBluetooth);
  }

  @override
  void dispose() {
    _nama.dispose();
    _ip.dispose();
    _pin.dispose();
    super.dispose();
  }

  bool get _valid =>
      _nama.text.trim().isNotEmpty &&
      (widget.awal.pakaiBluetooth || _ip.text.trim().isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final awal = widget.awal;
    return AlertDialog(
      title: const Text('Ubah display'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nama,
              decoration: const InputDecoration(
                labelText: 'Nama display',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            if (!awal.pakaiBluetooth)
              TextField(
                controller: _ip,
                decoration: const InputDecoration(
                  labelText: 'Alamat IP',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
                onChanged: (_) => setState(() {}),
              )
            else
              TextField(
                controller: _pin,
                decoration: const InputDecoration(
                  labelText: 'PIN Bluetooth TV (4 digit)',
                  helperText: 'Berganti tiap TV dinyalakan ulang.',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                maxLength: 4,
                obscureText: true,
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _valid
              ? () => Navigator.pop(
                  context,
                  awal.copyWith(
                    nama: _nama.text.trim(),
                    ip: awal.pakaiBluetooth ? awal.ip : _ip.text.trim(),
                    pinBluetooth: _pin.text.trim(),
                  ),
                )
              : null,
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}
