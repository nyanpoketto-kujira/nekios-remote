import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nekios_core/nekios_core.dart';

import '../domain/perintah.dart';
import '../layanan/klien_remote.dart';
import '../layanan/penyimpanan.dart';
import '../model/display_tersimpan.dart';
import '../model/snapshot.dart';

/// Keadaan sambungan remote ↔ display.
enum StatusKoneksi { terputus, menyambung, terhubung }

/// Hasil satu perintah yang dikirim ke display.
class HasilPerintah {
  const HasilPerintah.berhasil()
      : sukses = true,
        pesan = null;
  const HasilPerintah.gagal(this.pesan) : sukses = false;

  final bool sukses;

  /// Pesan kegagalan (dari paket `error` display atau timeout lokal);
  /// null bila [sukses].
  final String? pesan;
}

/// Store pusat nekios-remote (satu-satunya sumber kebenaran UI):
/// daftar display tersimpan, keadaan koneksi, dan snapshot terakhir
/// dari display.
///
/// Pola balasan display (kontrak R1): perintah sukses → `ack`
/// (payload.ofType) LALU satu `state.snapshot` susulan; perintah gagal
/// → `error` (payload.message). Metode `kirim*` di bawah menunggu
/// balasan itu (dengan timeout) supaya UI bisa memberi umpan balik
/// yang jujur, bukan sekadar "terkirim".
class RemoteStore extends ChangeNotifier {
  RemoteStore({
    required KlienRemote klien,
    required PenyimpananDisplay penyimpanan,
    this.jedaPing = const Duration(seconds: 15),
    this.batasBalasan = const Duration(seconds: 6),
  })  : _klien = klien,
        _penyimpanan = penyimpanan {
    daftarDisplay = _penyimpanan.daftar();
    ipTerakhir = _penyimpanan.ipTerakhir;
    _langganan = _klien.paketMasuk.listen(_tanganiPaket);
  }

  final KlienRemote _klien;
  final PenyimpananDisplay _penyimpanan;

  /// Jeda ping berkala selama terhubung (menyegarkan snapshot).
  final Duration jedaPing;

  /// Batas menunggu ack/error sebelum perintah dianggap gagal lokal.
  final Duration batasBalasan;

  // --- Daftar display tersimpan --------------------------------------------

  List<DisplayTersimpan> daftarDisplay = [];

  /// IP terakhir yang dipakai menyambung (auto-save).
  String? ipTerakhir;

  Future<void> tambahDisplay(DisplayTersimpan display) async {
    daftarDisplay = [...daftarDisplay, display];
    await _penyimpanan.simpanDaftar(daftarDisplay);
    notifyListeners();
  }

  Future<void> ubahDisplay(int index, DisplayTersimpan display) async {
    daftarDisplay = [...daftarDisplay]..[index] = display;
    await _penyimpanan.simpanDaftar(daftarDisplay);
    notifyListeners();
  }

  Future<void> hapusDisplay(int index) async {
    daftarDisplay = [...daftarDisplay]..removeAt(index);
    await _penyimpanan.simpanDaftar(daftarDisplay);
    notifyListeners();
  }

  // --- Koneksi ---------------------------------------------------------------

  StatusKoneksi statusKoneksi = StatusKoneksi.terputus;

  /// Pesan kesalahan koneksi terakhir (manusiawi, layak tampil).
  String? pesanKoneksi;

  /// Display yang sedang aktif disambung.
  DisplayTersimpan? displayAktif;

  bool get terhubung => statusKoneksi == StatusKoneksi.terhubung;

  StreamSubscription<NekiosPacket>? _langganan;
  Timer? _timerPing;

  /// Sambungkan ke [display]. IP-nya otomatis disimpan sebagai IP
  /// terakhir (auto-save) apa pun hasil sambungannya.
  Future<void> sambungkan(DisplayTersimpan display) async {
    if (statusKoneksi == StatusKoneksi.menyambung) return;
    await putuskan(senyap: true);
    statusKoneksi = StatusKoneksi.menyambung;
    pesanKoneksi = null;
    displayAktif = display;
    ipTerakhir = display.ip;
    await _penyimpanan.simpanIpTerakhir(display.ip);
    notifyListeners();
    try {
      await _klien.sambung(display.ip);
    } catch (e) {
      statusKoneksi = StatusKoneksi.terputus;
      pesanKoneksi = _pesanKoneksiManusiawi(e, display.ip);
      notifyListeners();
      return;
    }
    statusKoneksi = StatusKoneksi.terhubung;
    notifyListeners();
    // Sambut dengan ping: display membalas ack + snapshot perdana.
    unawaited(kirimPerintah(perintahPing()));
    _timerPing = Timer.periodic(jedaPing, (_) {
      if (!_klien.terhubung) {
        unawaited(putuskan());
        return;
      }
      _klien.kirim(perintahPing());
    });
  }

  /// Putuskan sambungan dan bersihkan snapshot.
  Future<void> putuskan({bool senyap = false}) async {
    _timerPing?.cancel();
    _timerPing = null;
    for (final penunggu in _penunggu.values) {
      if (!penunggu.isCompleted) {
        penunggu.complete(const HasilPerintah.gagal('Koneksi terputus.'));
      }
    }
    _penunggu.clear();
    await _klien.putus();
    statusKoneksi = StatusKoneksi.terputus;
    snapshot = null;
    waktuSnapshot = null;
    if (!senyap) notifyListeners();
  }

  String _pesanKoneksiManusiawi(Object e, String ip) {
    final teks = e.toString();
    if (teks.contains('Connection refused')) {
      return 'Display di $ip menolak sambungan. Pastikan aplikasi '
          'nekios-school sedang berjalan di TV.';
    }
    if (teks.contains('timed out') || teks.contains('TimeoutException')) {
      return 'Tidak ada jawaban dari $ip. Periksa alamat IP dan '
          'pastikan HP & TV berada di Wi-Fi yang sama.';
    }
    if (teks.contains('Network is unreachable') ||
        teks.contains('No route to host')) {
      return 'Jaringan tidak menjangkau $ip. Pastikan HP tersambung '
          'ke Wi-Fi yang sama dengan TV.';
    }
    return 'Gagal menyambung ke $ip. Periksa alamat IP dan jaringan Wi-Fi.';
  }

  // --- Snapshot ----------------------------------------------------------------

  /// Snapshot terakhir dari display; null sebelum snapshot pertama.
  SnapshotDisplay? snapshot;

  /// Waktu lokal saat [snapshot] diterima — basis hitung mundur lokal
  /// di antara snapshot (lihat [SnapshotDisplay.jamEfektifPada]).
  DateTime? waktuSnapshot;

  // --- Perintah ------------------------------------------------------------------

  final Map<String, Completer<HasilPerintah>> _penunggu = {};

  /// Kirim [paket] perintah dan tunggu balasannya mengikuti pola
  /// kontrak: `ack` = berhasil, `error` = gagal dengan pesan display.
  /// [ping] tidak menunggu balasan (snapshot-nya tiba sebagai paket
  /// biasa). Timeout [batasBalasan] menghasilkan kegagalan lokal.
  Future<HasilPerintah> kirimPerintah(NekiosPacket paket) async {
    if (!terhubung) {
      return const HasilPerintah.gagal('Belum terhubung ke display.');
    }
    if (paket.type == TipePaket.ping) {
      _klien.kirim(paket);
      return const HasilPerintah.berhasil();
    }
    final penunggu = Completer<HasilPerintah>();
    _penunggu[paket.type] = penunggu;
    _klien.kirim(paket);
    return penunggu.future.timeout(
      batasBalasan,
      onTimeout: () {
        _penunggu.remove(paket.type);
        return const HasilPerintah.gagal(
          'Display tidak menjawab. Periksa koneksi lalu coba lagi.',
        );
      },
    );
  }

  void _tanganiPaket(NekiosPacket paket) {
    switch (paket.type) {
      case TipePaket.stateSnapshot:
        final payload = paket.payload;
        if (payload != null) {
          snapshot = SnapshotDisplay.fromPayload(payload);
          waktuSnapshot = DateTime.now();
          notifyListeners();
        }
      case TipePaket.ack:
        final ofType = paket.payload?['ofType'] as String?;
        final penunggu =
            ofType != null ? _penunggu.remove(ofType) : null;
        if (penunggu != null && !penunggu.isCompleted) {
          penunggu.complete(const HasilPerintah.berhasil());
        } else if (ofType == null) {
          // ack tanpa ofType: selesaikan penunggu tertua.
          if (_penunggu.isNotEmpty) {
            final pertama = _penunggu.remove(_penunggu.keys.first);
            if (pertama != null && !pertama.isCompleted) {
              pertama.complete(const HasilPerintah.berhasil());
            }
          }
        }
      case TipePaket.error:
        final pesan = paket.payload?['message'] as String? ??
            'Display menolak perintah.';
        // Paket error tidak membawa ofType; selesaikan semua penunggu
        // dengan kegagalan ini (v1: satu perintah dalam satu waktu).
        for (final penunggu in _penunggu.values) {
          if (!penunggu.isCompleted) penunggu.complete(HasilPerintah.gagal(pesan));
        }
        _penunggu.clear();
    }
  }

  @override
  void dispose() {
    _timerPing?.cancel();
    unawaited(_langganan?.cancel() ?? Future<void>.value());
    super.dispose();
  }
}
