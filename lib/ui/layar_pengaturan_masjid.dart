import 'package:flutter/material.dart';

import '../layanan/lokasi_gps.dart';
import '../masjid/model_masjid.dart';
import '../state/store_masjid.dart';
import 'widget_bersama.dart';

/// Editor Pengaturan masjid (A2e): seluruh [MosqueConfig]
/// dengan pola DRAF + SIMPAN (keputusan A2 #6, ADR-006) —
/// berbeda dari editor Konten yang kirim seketika. Form
/// menampung salinan config dari snapshot TV; tombol tempel
/// "Simpan & Update Ke TV" hanya aktif bila draf berbeda dari
/// config TV (dirty dihitung dari `==` penuh MosqueConfig) dan
/// semua field sah. Satu ketukan mengirim SATU `updateConfig`
/// berisi config utuh; snapshot bukti menjadi seed draf
/// berikutnya.
///
/// Yang SENGAJA tidak bisa diubah dari sini (keputusan #3):
/// `utcOffsetHours` hanya ditampilkan (diatur di TV), dan
/// interval slideshow diatur di Gambar Latar (keputusan #5).
class LayarPengaturanMasjid extends StatefulWidget {
  const LayarPengaturanMasjid({
    super.key,
    required this.store,
    this.pengambilKoordinat,
  });

  final MasjidStore store;

  /// Pengambil koordinat GPS (disuntikkan demi tes); null =
  /// [ambilKoordinatGeolocator].
  final PengambilKoordinatGps? pengambilKoordinat;

  @override
  State<LayarPengaturanMasjid> createState() =>
      _LayarPengaturanMasjidState();
}

class _LayarPengaturanMasjidState extends State<LayarPengaturanMasjid> {
  final _nama = TextEditingController();
  final _alamat = TextEditingController();
  final _lat = TextEditingController();
  final _long = TextEditingController();
  final _khatib = TextEditingController();
  final _muadzin = TextEditingController();

  StateSnapshot? _seedDari;
  Map<PrayerType, int> _offsets = const {};
  Map<PrayerType, int> _iqamah = const {};
  int _preAdhan = 0;
  int _adhan = 0;
  int _preIqomah = 0;
  int _shalat = 0;
  int _khutbah = 0;
  bool _showKas = true;
  bool _hasFriday = true;
  bool _mengambilGps = false;

  MasjidStore get _store => widget.store;

  @override
  void initState() {
    super.initState();
    _store.addListener(_berubah);
    for (final c in [_nama, _alamat, _lat, _long, _khatib, _muadzin]) {
      c.addListener(_fieldBerubah);
    }
    _seedUlang();
  }

  @override
  void dispose() {
    _store.removeListener(_berubah);
    for (final c in [_nama, _alamat, _lat, _long, _khatib, _muadzin]) {
      c.removeListener(_fieldBerubah);
      c.dispose();
    }
    super.dispose();
  }

  void _berubah() {
    if (!mounted) return;
    _seedUlang();
    setState(() {});
  }

  void _fieldBerubah() {
    if (mounted) setState(() {});
  }

  void _seedUlang() {
    final snapshot = _store.snapshot;
    if (snapshot == null || identical(snapshot, _seedDari)) return;
    _seedDari = snapshot;
    final c = snapshot.config;
    _nama.text = c.name;
    _alamat.text = c.address;
    _lat.text = _formatKoordinat(c.latitude);
    _long.text = _formatKoordinat(c.longitude);
    _khatib.text = c.fridayKhatib;
    _muadzin.text = c.fridayMuadzin;
    _offsets = {for (final t in kAllPrayerTypes) t: c.offsetFor(t)};
    _iqamah = {
      PrayerType.fajr: c.iqamahDuration.fajr,
      PrayerType.dhuhr: c.iqamahDuration.dhuhr,
      PrayerType.asr: c.iqamahDuration.asr,
      PrayerType.maghrib: c.iqamahDuration.maghrib,
      PrayerType.isha: c.iqamahDuration.isha,
    };
    _preAdhan = c.preAdhanMinutes;
    _adhan = c.adhanMinutes;
    _preIqomah = c.preIqomahMinutes;
    _shalat = c.shalatMinutes;
    _khutbah = c.khutbahMinutes;
    _showKas = c.showKas;
    _hasFriday = c.hasFridayPrayer;
  }

  static String _formatKoordinat(double nilai) {
    var teks = nilai.toStringAsFixed(6);
    if (teks.contains('.')) {
      teks = teks.replaceFirst(RegExp(r'0+$'), '');
      teks = teks.replaceFirst(RegExp(r'\.$'), '');
    }
    return teks;
  }

  /// Parse koordinat yang ditoleransi koma desimal Indonesia.
  static double? _parseKoordinat(String teks) =>
      double.tryParse(teks.trim().replaceAll(',', '.'));

  String? get _galatNama =>
      _nama.text.trim().isEmpty ? 'Nama masjid tidak boleh kosong.' : null;

  String? get _galatLat {
    final nilai = _parseKoordinat(_lat.text);
    if (nilai == null) return 'Isi dengan angka, contoh: -6.2088';
    if (nilai < -90 || nilai > 90) return 'Lintang harus antara -90 dan 90.';
    return null;
  }

  String? get _galatLong {
    final nilai = _parseKoordinat(_long.text);
    if (nilai == null) return 'Isi dengan angka, contoh: 106.8456';
    if (nilai < -180 || nilai > 180) {
      return 'Bujur harus antara -180 dan 180.';
    }
    return null;
  }

  /// Draf config utuh dari form saat ini; null bila ada field
  /// yang belum sah. Dibangun dari config seed supaya field
  /// yang tidak diedit di sini (zona waktu, interval slideshow)
  /// ikut apa adanya.
  MosqueConfig? _draf() {
    final seed = _seedDari?.config;
    if (seed == null) return null;
    if (_galatNama != null || _galatLat != null || _galatLong != null) {
      return null;
    }
    return seed.copyWith(
      name: _nama.text.trim(),
      address: _alamat.text.trim(),
      latitude: _parseKoordinat(_lat.text),
      longitude: _parseKoordinat(_long.text),
      prayerOffsets: Map.of(_offsets),
      iqamahDuration: IqamahDuration(
        fajr: _iqamah[PrayerType.fajr] ?? 0,
        dhuhr: _iqamah[PrayerType.dhuhr] ?? 0,
        asr: _iqamah[PrayerType.asr] ?? 0,
        maghrib: _iqamah[PrayerType.maghrib] ?? 0,
        isha: _iqamah[PrayerType.isha] ?? 0,
      ),
      preAdhanMinutes: _preAdhan,
      adhanMinutes: _adhan,
      preIqomahMinutes: _preIqomah,
      shalatMinutes: _shalat,
      khutbahMinutes: _khutbah,
      fridayKhatib: _khatib.text.trim(),
      fridayMuadzin: _muadzin.text.trim(),
      showKas: _showKas,
      hasFridayPrayer: _hasFriday,
    );
  }

  Future<void> _simpan() async {
    final draf = _draf();
    if (draf == null) return;
    final hasil = await _store.perbaruiConfig(draf);
    if (!mounted) return;
    tampilkanHasil(context, hasil, 'Pengaturan tersimpan ke TV.');
  }

  Future<void> _ambilGps() async {
    setState(() => _mengambilGps = true);
    try {
      final ambil = widget.pengambilKoordinat ?? ambilKoordinatGeolocator;
      final koordinat = await ambil();
      if (!mounted) return;
      _lat.text = _formatKoordinat(koordinat.latitude);
      _long.text = _formatKoordinat(koordinat.longitude);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Koordinat terisi dari GPS. Periksa lagi, lalu Simpan.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is Exception
                ? e.toString().replaceFirst('Exception: ', '')
                : 'Tidak bisa mengambil posisi GPS.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _mengambilGps = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _store.snapshot;
    if (snapshot == null) return const BadanBelumAdaDataTv();
    final tema = Theme.of(context);
    final draf = _draf();
    final dirty = draf != null && draf != snapshot.config;
    final bisaSimpan = dirty && !_store.sedangMengirim;
    final labelDzuhur = PrayerType.dhuhr.displayNameForDate(
      DateTime.now(),
      hasFridayPrayer: _hasFriday,
    );
    String namaShalat(PrayerType t) =>
        t == PrayerType.dhuhr ? labelDzuhur : t.displayName;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
            children: [
              _Grup(
                judul: 'Masjid',
                anak: [
                  TextField(
                    controller: _nama,
                    decoration: InputDecoration(
                      labelText: 'Nama masjid',
                      errorText: _galatNama,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _alamat,
                    decoration: const InputDecoration(
                      labelText: 'Alamat',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              _Grup(
                judul: 'Lokasi & Jadwal',
                anak: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _lat,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Lintang (latitude)',
                            errorText: _galatLat,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _long,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Bujur (longitude)',
                            errorText: _galatLong,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: _mengambilGps ? null : _ambilGps,
                      icon: _mengambilGps
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.my_location),
                      label: Text(
                        _mengambilGps
                            ? 'Mengambil posisi…'
                            : 'Ambil Koordinat dari GPS',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Zona waktu TV: UTC'
                    '${snapshot.config.utcOffsetHours >= 0 ? '+' : ''}'
                    '${snapshot.config.utcOffsetHours} — diatur dari '
                    'TV, tidak diubah dari sini.',
                    style: tema.textTheme.bodySmall?.copyWith(
                      color: tema.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              _Grup(
                judul: 'Penyesuaian Waktu Shalat',
                keterangan:
                    'Geser jadwal shalat maju atau mundur beberapa '
                    'menit dari hasil hitungan, misalnya mengikuti '
                    'jadwal resmi setempat.',
                anak: [
                  for (final t in kAllPrayerTypes)
                    _BarisStepper(
                      label: namaShalat(t),
                      nilai: _offsets[t] ?? 0,
                      formatNilai: _formatGeser,
                      min: -60,
                      maks: 60,
                      onGanti: (v) =>
                          setState(() => _offsets = {..._offsets, t: v}),
                    ),
                ],
              ),
              _Grup(
                judul: 'Durasi Fase TV',
                anak: [
                  _BarisStepper(
                    label: 'Persiapan azan (menit)',
                    nilai: _preAdhan,
                    min: 0,
                    maks: 60,
                    onGanti: (v) => setState(() => _preAdhan = v),
                  ),
                  _BarisStepper(
                    label: 'Azan (menit)',
                    nilai: _adhan,
                    min: 0,
                    maks: 30,
                    onGanti: (v) => setState(() => _adhan = v),
                  ),
                  _BarisStepper(
                    label: 'Persiapan ikamah (menit)',
                    nilai: _preIqomah,
                    min: 0,
                    maks: 30,
                    onGanti: (v) => setState(() => _preIqomah = v),
                  ),
                  _BarisStepper(
                    label: 'Shalat (menit)',
                    nilai: _shalat,
                    min: 0,
                    maks: 60,
                    onGanti: (v) => setState(() => _shalat = v),
                  ),
                  _BarisStepper(
                    label: 'Khutbah Jumat (menit)',
                    nilai: _khutbah,
                    min: 0,
                    maks: 120,
                    aktif: _hasFriday,
                    onGanti: (v) => setState(() => _khutbah = v),
                  ),
                ],
              ),
              _Grup(
                judul: 'Durasi Ikamah',
                keterangan:
                    'Hitung mundur antara azan dan ikamah untuk '
                    'tiap waktu shalat.',
                anak: [
                  for (final t in const [
                    PrayerType.fajr,
                    PrayerType.dhuhr,
                    PrayerType.asr,
                    PrayerType.maghrib,
                    PrayerType.isha,
                  ])
                    _BarisStepper(
                      label: namaShalat(t),
                      nilai: _iqamah[t] ?? 0,
                      min: 0,
                      maks: 60,
                      onGanti: (v) =>
                          setState(() => _iqamah = {..._iqamah, t: v}),
                    ),
                ],
              ),
              _Grup(
                judul: 'Petugas & Tampilan',
                keterangan:
                    'Kartu di sisi layar TV bergiliran: Kas, lalu '
                    'Petugas Jumat, lalu Gambar Khusus.',
                anak: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Ada shalat Jumat'),
                    value: _hasFriday,
                    onChanged: (v) => setState(() => _hasFriday = v),
                  ),
                  TextField(
                    controller: _khatib,
                    enabled: _hasFriday,
                    decoration: const InputDecoration(
                      labelText: 'Khatib Jumat',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _muadzin,
                    enabled: _hasFriday,
                    decoration: const InputDecoration(
                      labelText: 'Muadzin Jumat',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Tampilkan kartu kas'),
                    value: _showKas,
                    onChanged: (v) => setState(() => _showKas = v),
                  ),
                ],
              ),
            ],
          ),
        ),
        Material(
          elevation: 8,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: bisaSimpan ? _simpan : null,
                icon: const Icon(Icons.save_outlined),
                label: Text(
                  dirty
                      ? 'Simpan & Update Ke TV'
                      : 'Belum ada perubahan',
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  static String _formatGeser(int nilai) {
    if (nilai > 0) return '+$nilai menit';
    if (nilai < 0) return '$nilai menit';
    return '0 menit';
  }
}

/// Kartu grup pengaturan bertajuk.
class _Grup extends StatelessWidget {
  const _Grup({required this.judul, required this.anak, this.keterangan});

  final String judul;
  final String? keterangan;
  final List<Widget> anak;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(judul, style: tema.textTheme.titleMedium),
            if (keterangan != null) ...[
              const SizedBox(height: 4),
              Text(
                keterangan!,
                style: tema.textTheme.bodySmall?.copyWith(
                  color: tema.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 12),
            ...anak,
          ],
        ),
      ),
    );
  }
}

/// Satu baris stepper: label, tombol kurang, nilai, tombol
/// tambah. Nilai di-clamp ke [min]..[maks] oleh tombolnya.
class _BarisStepper extends StatelessWidget {
  const _BarisStepper({
    required this.label,
    required this.nilai,
    required this.min,
    required this.maks,
    required this.onGanti,
    this.formatNilai,
    this.aktif = true,
  });

  final String label;
  final int nilai;
  final int min;
  final int maks;
  final ValueChanged<int> onGanti;
  final String Function(int nilai)? formatNilai;
  final bool aktif;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: tema.textTheme.bodyLarge?.copyWith(
                color: aktif
                    ? null
                    : tema.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            tooltip: 'Kurangi $label',
            onPressed: (!aktif || nilai <= min)
                ? null
                : () => onGanti(nilai - 1),
          ),
          SizedBox(
            width: 76,
            child: Text(
              formatNilai?.call(nilai) ?? '$nilai menit',
              textAlign: TextAlign.center,
              style: tema.textTheme.bodyMedium,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Tambah $label',
            onPressed: (!aktif || nilai >= maks)
                ? null
                : () => onGanti(nilai + 1),
          ),
        ],
      ),
    );
  }
}
