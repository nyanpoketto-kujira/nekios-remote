import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../masjid/model_masjid.dart';
import '../state/store_masjid.dart';
import 'layar_beranda_masjid.dart' show formatRupiah;
import 'widget_bersama.dart';

/// Pemilih tanggal untuk transaksi kas baru. Terinjeksi demi
/// tes; null memakai pemilih tanggal Material bawaan.
typedef PemilihTanggalKas =
    Future<DateTime?> Function(BuildContext context, DateTime awal);

Future<DateTime?> _pilihTanggalBawaan(BuildContext context, DateTime awal) {
  final kini = DateTime.now();
  return showDatePicker(
    context: context,
    initialDate: awal,
    firstDate: DateTime(2020),
    lastDate: DateTime(kini.year, kini.month, kini.day),
  );
}

const _bulanKas = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'Mei',
  'Jun',
  'Jul',
  'Agu',
  'Sep',
  'Okt',
  'Nov',
  'Des',
];

String _dua(int n) => n.toString().padLeft(2, '0');

/// `14 Agu 2026, 09:30` — format tanggal transaksi kas (repo ini
/// tidak memakai intl; nama bulan ditulis manual).
String formatTanggalKas(DateTime t) =>
    '${t.day} ${_bulanKas[t.month - 1]} ${t.year}, '
    '${_dua(t.hour)}:${_dua(t.minute)}';

/// `14 Agu 2026` — tanggal saja, untuk baris pemilih di dialog.
String formatTanggalKasSingkat(DateTime t) =>
    '${t.day} ${_bulanKas[t.month - 1]} ${t.year}';

/// Editor Kas masjid (Konten masjid, tahap A2c) — pola salinan
/// kerja ADR-006/007 seperti editor daftar A2b: daftar di-seed
/// dari snapshot TV, SETIAP mutasi (tambah/hapus) langsung
/// mengirim daftar PENUH terbaru lewat [MasjidStore.perbaruiKas]
/// dan snapshot bukti menjadi seed baru. Selama perintah
/// menunggu bukti (`store.sedangMengirim`) semua kontrol
/// membeku; kirim yang gagal menahan salinan kerja apa adanya.
///
/// Paritas mobile_remote: transaksi TIDAK bisa disunting —
/// mengoreksi = hapus lalu tambah ulang. Berbeda dari
/// mobile_remote, tanggal bisa dipilih (keputusan #10: bawaan
/// hari ini, boleh mundur — kebutuhan mencatat infaq yang baru
/// disetor); jamnya mengikuti jam saat menyimpan. Daftar tampil
/// dan terkirim persis urutan TV (transaksi baru ditambahkan di
/// akhir, sama seperti mobile_remote).
///
/// Kas adalah data paling sensitif di TV (kirim = ganti
/// seluruhnya): selama snapshot belum tiba editor menahan diri
/// di keadaan "belum ada data dari TV" dan tidak pernah
/// mengirim daftar hasil seed yang gagal.
class LayarKasMasjid extends StatefulWidget {
  const LayarKasMasjid({super.key, required this.store, this.pemilihTanggal});

  final MasjidStore store;
  final PemilihTanggalKas? pemilihTanggal;

  @override
  State<LayarKasMasjid> createState() => _LayarKasMasjidState();
}

class _LayarKasMasjidState extends State<LayarKasMasjid> {
  /// Salinan kerja; null sampai snapshot pertama tiba.
  List<KasTransaction>? _salinan;

  /// Snapshot yang menjadi sumber seed [_salinan] saat ini.
  StateSnapshot? _seedDari;

  MasjidStore get store => widget.store;

  /// Kirim [baru] sebagai daftar penuh terbaru dan laporkan
  /// hasilnya (pola _kirimDaftar editor A2b).
  Future<void> _kirimDaftar(List<KasTransaction> baru, String pesanSukses) async {
    setState(() => _salinan = baru);
    final hasil = await store.perbaruiKas(baru);
    if (!mounted) return;
    tampilkanHasil(context, hasil, pesanSukses);
  }

  Future<void> _tambah(BuildContext context) async {
    final transaksi = await showDialog<KasTransaction>(
      context: context,
      builder: (_) => _DialogKas(pemilihTanggal: widget.pemilihTanggal),
    );
    if (transaksi == null || !mounted) return;
    await _kirimDaftar([
      ...?_salinan,
      transaksi,
    ], 'Transaksi kas ditambahkan.');
  }

  Future<void> _hapus(int indeks) async {
    final terhapus = _salinan![indeks];
    final baru = [..._salinan!]..removeAt(indeks);
    setState(() => _salinan = baru);
    final hasil = await store.perbaruiKas(baru);
    if (!mounted) return;
    if (!hasil.sukses) {
      tampilkanHasil(context, hasil, '');
      return;
    }
    // Urungkan = kirim ulang daftar dengan transaksi
    // dikembalikan ke indeks asalnya (ADR-007).
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Transaksi dihapus.'),
        action: SnackBarAction(
          label: 'Urungkan',
          onPressed: () => _urungkanHapus(terhapus, indeks),
        ),
      ),
    );
  }

  Future<void> _urungkanHapus(KasTransaction transaksi, int indeks) async {
    final sekarang = _salinan ?? const <KasTransaction>[];
    final posisi = indeks.clamp(0, sekarang.length);
    final baru = [...sekarang]..insert(posisi, transaksi);
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
          _salinan = List.of(snapshot.kasTransactions);
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
                      'Catatan uang masuk dan keluar kas masjid. '
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
            _KartuRingkasanKas(
              ringkasan: KasSummary.fromTransactions(daftar),
            ),
            Expanded(
              child: daftar.isEmpty
                  ? const _DaftarKosong()
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      itemCount: daftar.length,
                      itemBuilder: (context, i) => _BarisKas(
                        transaksi: daftar[i],
                        sibuk: sibuk,
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

/// Kartu ringkasan tetap di atas daftar: Saldo besar, lalu
/// Pemasukan/Pengeluaran — dihitung dari salinan kerja supaya
/// selalu konsisten dengan daftar yang sedang tampil.
class _KartuRingkasanKas extends StatelessWidget {
  const _KartuRingkasanKas({required this.ringkasan});

  final KasSummary ringkasan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.account_balance_wallet_outlined,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text('Saldo Kas', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  Text(
                    formatRupiah(ringkasan.saldo),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: scheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _StatKas(
                      ikon: Icons.arrow_downward,
                      label: 'Pemasukan',
                      nilai: ringkasan.totalMasuk,
                    ),
                  ),
                  Expanded(
                    child: _StatKas(
                      ikon: Icons.arrow_upward,
                      label: 'Pengeluaran',
                      nilai: ringkasan.totalKeluar,
                    ),
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

class _StatKas extends StatelessWidget {
  const _StatKas({required this.ikon, required this.label, required this.nilai});

  final IconData ikon;
  final String label;
  final int nilai;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(ikon, size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              formatRupiah(nilai),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Keadaan daftar kosong yang SAH (TV memang belum punya
/// catatan kas): ringkasan tetap tampil nol, tambah bisa jalan.
class _DaftarKosong extends StatelessWidget {
  const _DaftarKosong();

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
              Icons.receipt_long_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'Belum ada catatan kas di TV. Tambahkan lewat '
              'tombol Tambah di atas.',
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

class _BarisKas extends StatelessWidget {
  const _BarisKas({
    required this.transaksi,
    required this.sibuk,
    required this.onHapus,
  });

  final KasTransaction transaksi;
  final bool sibuk;
  final VoidCallback onHapus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final masuk = transaksi.type == KasType.masuk;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: masuk
                  ? scheme.primaryContainer
                  : scheme.errorContainer,
              child: Icon(
                masuk ? Icons.arrow_downward : Icons.arrow_upward,
                size: 18,
                color: masuk
                    ? scheme.onPrimaryContainer
                    : scheme.onErrorContainer,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    transaksi.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${masuk ? 'Masuk' : 'Keluar'} · '
                    '${formatTanggalKas(transaksi.date)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              masuk
                  ? '+${formatRupiah(transaksi.amount)}'
                  : formatRupiah(-transaksi.amount),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: masuk ? null : scheme.error,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Hapus transaksi',
              onPressed: sibuk ? null : onHapus,
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialog layar penuh tambah transaksi kas: jenis
/// (Masuk/Keluar), nominal (digit saja, wajib > 0), keterangan
/// (wajib), dan tanggal (keputusan #10 — bawaan hari ini, boleh
/// mundur; jam mengikuti saat menyimpan). Tidak ada mode
/// sunting: paritas mobile_remote.
class _DialogKas extends StatefulWidget {
  const _DialogKas({this.pemilihTanggal});

  final PemilihTanggalKas? pemilihTanggal;

  @override
  State<_DialogKas> createState() => _DialogKasState();
}

class _DialogKasState extends State<_DialogKas> {
  final TextEditingController _nominal = TextEditingController();
  final TextEditingController _keterangan = TextEditingController();
  KasType _tipe = KasType.masuk;
  late DateTime _tanggal;

  @override
  void initState() {
    super.initState();
    final kini = DateTime.now();
    _tanggal = DateTime(kini.year, kini.month, kini.day);
  }

  @override
  void dispose() {
    _nominal.dispose();
    _keterangan.dispose();
    super.dispose();
  }

  int get _nominalAngka => int.tryParse(_nominal.text) ?? 0;

  bool get _sah => _nominalAngka > 0 && _keterangan.text.trim().isNotEmpty;

  String? get _galatNominal {
    if (_nominal.text.isEmpty) return 'Nominal tidak boleh kosong.';
    if (_nominalAngka <= 0) return 'Nominal harus lebih dari Rp0.';
    return null;
  }

  Future<void> _pilihTanggal() async {
    final pilih = widget.pemilihTanggal ?? _pilihTanggalBawaan;
    final hasil = await pilih(context, _tanggal);
    if (hasil == null || !mounted) return;
    setState(
      () => _tanggal = DateTime(hasil.year, hasil.month, hasil.day),
    );
  }

  void _simpan() {
    final kini = DateTime.now();
    Navigator.pop(
      context,
      KasTransaction(
        id: kini.millisecondsSinceEpoch.toString(),
        type: _tipe,
        amount: _nominalAngka,
        description: _keterangan.text.trim(),
        // Tanggal dari pemilih, jam dari saat menyimpan.
        date: DateTime(
          _tanggal.year,
          _tanggal.month,
          _tanggal.day,
          kini.hour,
          kini.minute,
          kini.second,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Batal',
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('Tambah Transaksi Kas'),
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
            SegmentedButton<KasType>(
              segments: const [
                ButtonSegment(
                  value: KasType.masuk,
                  icon: Icon(Icons.arrow_downward),
                  label: Text('Masuk'),
                ),
                ButtonSegment(
                  value: KasType.keluar,
                  icon: Icon(Icons.arrow_upward),
                  label: Text('Keluar'),
                ),
              ],
              selected: {_tipe},
              onSelectionChanged: (pilihan) =>
                  setState(() => _tipe = pilihan.first),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _nominal,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nominal (Rp)',
                hintText: 'Contoh: 500000',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (_galatNominal != null) ...[
              const SizedBox(height: 8),
              Text(
                _galatNominal!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ] else if (_nominalAngka > 0) ...[
              const SizedBox(height: 8),
              Text(
                'Terbaca: ${formatRupiah(_nominalAngka)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _keterangan,
              decoration: const InputDecoration(
                labelText: 'Keterangan',
                hintText: 'Contoh: Infaq Jumat dari kotak amal',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (_keterangan.text.trim().isEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Keterangan tidak boleh kosong.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 20),
            Text('Tanggal', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    formatTanggalKasSingkat(_tanggal),
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _pilihTanggal,
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: const Text('Pilih tanggal'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Tanggal boleh dimundurkan, misalnya untuk mencatat '
              'infaq yang baru disetor hari ini.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
