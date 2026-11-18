import 'package:flutter/foundation.dart';

import '../layanan/penyelidik.dart';
import '../masjid/tautan_bt.dart';
import '../model/display_tersimpan.dart';
import 'remote_store.dart';
import 'store_masjid.dart';

/// Orkestrasi sesi remote pusat (ADR-004): satu-satunya jalur masuk
/// ke dashboard. Menghubungkan tiga hal —
/// * GATEWAY: selama tidak ada store yang terhubung, aplikasi hanya
///   menampilkan layar gateway (lihat LayarGateway);
/// * AUTO-DETECT: menyambung via IP selalu lewat deteksi identitas
///   ([PendekteksiDisplay]) — pengguna tidak memilih jenis display;
/// * DYNAMIC SHELL: store yang terhubung menentukan shell yang
///   tampil (sekolah / masjid); putus → kembali ke gateway.
///
/// Daftar display tersimpan tetap milik [RemoteStore] (persistensi
/// bersama); sesi hanya membaca/menambah/mengubahnya lewat store itu.
class SesiRemote extends ChangeNotifier {
  SesiRemote({
    required this.storeSekolah,
    required this.storeMasjid,
    required this.pendeteksi,
  }) {
    storeSekolah.addListener(_ikutiStore);
    storeMasjid.addListener(_ikutiStore);
  }

  final RemoteStore storeSekolah;
  final MasjidStore storeMasjid;
  final PendekteksiDisplay pendeteksi;

  bool _sibuk = false;

  /// Sedang bekerja di gateway (mendeteksi / menyambung) — termasuk
  /// fase `menyambung` kedua store.
  bool get sibuk =>
      _sibuk ||
      storeSekolah.statusKoneksi == StatusKoneksi.menyambung ||
      storeMasjid.statusKoneksi == StatusKoneksi.menyambung;

  /// Pesan untuk ditampilkan di gateway: gagal deteksi, gagal
  /// menyambung, atau pemberitahuan putus tak terduga. Null = bersih.
  String? pesan;

  /// Display terakhir yang berhasil disambung sesi ini — bahan
  /// tombol "Sambungkan ulang" setelah putus tak terduga.
  DisplayTersimpan? displayTerakhir;

  /// Benar selama salah satu store terhubung (dashboard tampil).
  bool get diDalam => storeSekolah.terhubung || storeMasjid.terhubung;

  /// Jenis shell yang aktif; null saat di gateway.
  TipeDisplay? get tipeAktif => storeSekolah.terhubung
      ? TipeDisplay.sekolah
      : storeMasjid.terhubung
      ? TipeDisplay.masjid
      : null;

  bool _pernahDiDalam = false;
  bool _putusManual = false;

  /// Amati transisi kedua store: catat display terakhir saat masuk,
  /// dan ubah kejatuhan tak terduga (dari `terhubung`) menjadi
  /// pemberitahuan gateway — kecuali pemutusan memang diminta lewat
  /// [putuskan].
  void _ikutiStore() {
    if (diDalam) {
      _pernahDiDalam = true;
      displayTerakhir =
          storeSekolah.displayAktif ??
          storeMasjid.displayAktif ??
          displayTerakhir;
    } else if (_pernahDiDalam) {
      _pernahDiDalam = false;
      if (!_putusManual) {
        pesan =
            storeMasjid.pesanKoneksi ??
            storeSekolah.pesanKoneksi ??
            'Koneksi ke display terputus.';
      }
      _putusManual = false;
    }
    notifyListeners();
  }

  /// Sambung lewat alamat IP: deteksi identitas dulu (probing
  /// paralel 8920/8080), simpan sebagai riwayat bila identitas
  /// terbukti DAN sambungan store berhasil, lalu masuk dashboard.
  /// IP yang sudah tersimpan sebagai display Wi-Fi langsung
  /// disambungkan tanpa deteksi ulang (jalur cepat riwayat).
  Future<void> sambungIp(String ip) async {
    final alamat = ip.trim();
    if (alamat.isEmpty || _sibuk) return;
    _sibuk = true;
    pesan = null;
    notifyListeners();
    try {
      final tersimpan = _cariWifiTersimpan(alamat);
      if (tersimpan != null) {
        await _sambungkanTersimpan(tersimpan);
        return;
      }
      final hasil = await pendeteksi.deteksi(alamat);
      switch (hasil) {
        case TerdeteksiSekolah(:final namaSekolah):
          final display = DisplayTersimpan(
            nama: namaSekolah.isNotEmpty
                ? namaSekolah
                : 'Display Sekolah $alamat',
            ip: alamat,
            tipe: TipeDisplay.sekolah,
          );
          await storeSekolah.sambungkan(display);
          if (storeSekolah.terhubung) {
            await storeSekolah.tambahDisplay(display);
            displayTerakhir = display;
          } else {
            pesan = storeSekolah.pesanKoneksi;
          }
        case TerdeteksiMasjid(:final namaMasjid):
          final display = DisplayTersimpan(
            nama: namaMasjid.isNotEmpty ? namaMasjid : 'TV Masjid $alamat',
            ip: alamat,
            tipe: TipeDisplay.masjid,
            transport: JalurMasjid.wifi,
          );
          await storeMasjid.sambungkan(display);
          if (storeMasjid.terhubung) {
            await storeSekolah.tambahDisplay(display);
            displayTerakhir = display;
          } else {
            pesan = storeMasjid.pesanKoneksi;
          }
        case TidakTerdeteksi():
          pesan =
              'Tidak ada display Nekios yang menjawab di $alamat. '
              'Pastikan TV menyala dan HP berada di Wi-Fi yang sama.';
      }
    } finally {
      _sibuk = false;
      notifyListeners();
    }
  }

  /// Sambung memakai entri riwayat (ketukan kartu di gateway).
  Future<void> sambungDisplay(DisplayTersimpan display) async {
    if (_sibuk) return;
    _sibuk = true;
    pesan = null;
    notifyListeners();
    try {
      await _sambungkanTersimpan(display);
    } finally {
      _sibuk = false;
      notifyListeners();
    }
  }

  /// Sambung Bluetooth ke [perangkat] dengan [pin] (alur gateway:
  /// perangkat hasil pencarian / dikenal yang PIN-nya belum
  /// tersimpan). Kanal BT yang lolos auth PIN hari ini selalu TV
  /// masjid — satu-satunya host RFCOMM yang ada; host BT sekolah
  /// kelak mengklasifikasi lewat probing protokol di dalam kanal.
  /// Entri riwayat dibuat/diperbarui hanya bila sambungan berhasil.
  Future<void> sambungBluetooth(PerangkatBt perangkat, String pin) async {
    if (_sibuk) return;
    final daftar = storeSekolah.daftarDisplay;
    final indeks = daftar.indexWhere(
      (d) => d.pakaiBluetooth && d.alamatBluetooth == perangkat.alamat,
    );
    final display = DisplayTersimpan(
      nama: indeks >= 0
          ? daftar[indeks].nama
          : (perangkat.nama.isNotEmpty ? perangkat.nama : 'TV Masjid'),
      ip: '',
      tipe: TipeDisplay.masjid,
      transport: JalurMasjid.bluetooth,
      alamatBluetooth: perangkat.alamat,
      namaBluetooth: perangkat.nama,
      pinBluetooth: pin,
    );
    _sibuk = true;
    pesan = null;
    notifyListeners();
    try {
      await storeMasjid.sambungkan(display);
      if (storeMasjid.terhubung) {
        if (indeks >= 0) {
          await storeSekolah.ubahDisplay(indeks, display);
        } else {
          await storeSekolah.tambahDisplay(display);
        }
        displayTerakhir = display;
      } else {
        pesan = storeMasjid.pesanKoneksi;
      }
    } finally {
      _sibuk = false;
      notifyListeners();
    }
  }

  /// Sambungkan ulang display terakhir (setelah putus tak terduga).
  Future<void> sambungUlang() async {
    final display = displayTerakhir;
    if (display == null) return;
    pesan = null;
    await sambungDisplay(display);
  }

  /// Putuskan sesi secara sengaja → kembali ke gateway TANPA
  /// pemberitahuan putus.
  Future<void> putuskan() async {
    _putusManual = true;
    pesan = null;
    await storeSekolah.putuskan();
    await storeMasjid.putuskan();
    notifyListeners();
  }

  Future<void> _sambungkanTersimpan(DisplayTersimpan display) async {
    // Invariant sesi tunggal: store lawan yang masih terhubung
    // diputuskan dulu (dalam praktik tidak terjadi — sambungan
    // hanya dimulai dari gateway saat semua terputus).
    if (display.adalahMasjid) {
      if (storeSekolah.terhubung) await storeSekolah.putuskan(senyap: true);
      await storeMasjid.sambungkan(display);
      if (storeMasjid.terhubung) {
        displayTerakhir = display;
      } else {
        pesan = storeMasjid.pesanKoneksi;
      }
    } else {
      if (storeMasjid.terhubung) await storeMasjid.putuskan(senyap: true);
      await storeSekolah.sambungkan(display);
      if (storeSekolah.terhubung) {
        displayTerakhir = display;
      } else {
        pesan = storeSekolah.pesanKoneksi;
      }
    }
  }

  DisplayTersimpan? _cariWifiTersimpan(String ip) {
    for (final d in storeSekolah.daftarDisplay) {
      if (!d.pakaiBluetooth && d.ip == ip) return d;
    }
    return null;
  }

  @override
  void dispose() {
    storeSekolah.removeListener(_ikutiStore);
    storeMasjid.removeListener(_ikutiStore);
    super.dispose();
  }
}
