/// Transport Bluetooth Classic menuju tv_display masjid-you
/// (Rute A, ADR-003) — meniru perilaku `bluetooth_client_service`
/// mobile_remote di atas plugin lokal `bluetooth_rfcomm`:
///
/// - socket RFCOMM insecure, UUID layanan tetap masjid-you;
/// - framing 4-byte big-endian + satu JSON per bingkai (di Dart,
///   lihat `bingkai_bt.dart`);
/// - handshake PIN: TV mengirim `authChallenge{nonce}` begitu socket
///   tersambung; transport menjawab `authResponse{pin, nonce}` dengan
///   PIN dari display tersimpan; paket data sebelum `authSuccess`
///   DIBUANG (kedua sisi menegakkan ini di sumbernya);
/// - paket keluar besar dipecah `chunkedData` (32 KB per potongan,
///   ambang 64 KB) setelah kompresi gambar latar/logo; paket masuk
///   ter-chunk dirakit ulang sebelum diteruskan.
///
/// Android saja (plugin tidak terdaftar di platform lain → sambungan
/// gagal dengan pesan manusiawi).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../model/display_tersimpan.dart';
import 'bingkai_bt.dart';
import 'kompresi_gambar.dart';
import 'paket_masjid.dart';
import 'tautan_bt.dart';
import 'transfer_chunk.dart';
import 'transport_masjid.dart';

class TransportMasjidBt implements TransportMasjid {
  TransportMasjidBt(
    this._tautan, {
    this._kirimTanpaKompresiLatar = false,
    this._batasSambung = const Duration(seconds: 20),
    this._batasAuth = const Duration(seconds: 10),
  });

  final TautanBluetooth _tautan;

  /// Cermin preferensi `bg_send_uncompressed` mobile_remote: `true`
  /// = gambar latar dikirim asli (tetap di-chunk bila besar).
  final bool _kirimTanpaKompresiLatar;

  final Duration _batasSambung;
  final Duration _batasAuth;

  StreamSubscription<KejadianBt>? _langganan;
  final PenguraiBingkaiBt _pengurai = PenguraiBingkaiBt();
  final ChunkReassembler _perangkai = ChunkReassembler();

  final StreamController<SyncPacket> _paketMasuk =
      StreamController<SyncPacket>.broadcast();
  final StreamController<String> _kesalahan =
      StreamController<String>.broadcast();

  bool _socketTerhubung = false;
  bool _terotentikasi = false;
  String _pin = '';
  String? _nonceTertunda;
  Completer<void>? _penungguSambung;
  Completer<void>? _penungguAuth;

  @override
  bool get terhubung => _socketTerhubung && _terotentikasi;

  @override
  Stream<SyncPacket> get paketMasuk => _paketMasuk.stream;

  @override
  Stream<String> get kesalahan => _kesalahan.stream;

  @override
  Future<void> sambung(DisplayTersimpan display) async {
    await putus();
    _pin = display.pinBluetooth;
    _langganan = _tautan.kejadian.listen(_tanganiKejadian);
    try {
      final penungguSambung = Completer<void>();
      _penungguSambung = penungguSambung;
      final mulai = await _tautan.sambungkan(display.alamatBluetooth);
      if (!mulai) {
        throw Exception('Gagal memulai koneksi Bluetooth ke TV masjid.');
      }
      await penungguSambung.future.timeout(
        _batasSambung,
        onTimeout: () => throw Exception(
          'Koneksi Bluetooth ke TV timeout. Pastikan TV menyala, '
          'sudah ter-bond, atau sedang dalam Mode Pairing.',
        ),
      );
      final penungguAuth = Completer<void>();
      _penungguAuth = penungguAuth;
      await penungguAuth.future.timeout(
        _batasAuth,
        onTimeout: () => throw Exception(
          'TV tidak menyelesaikan autentikasi PIN. Coba sambungkan lagi.',
        ),
      );
    } catch (e) {
      await putus();
      if (e is Exception) rethrow;
      throw Exception(
        'Bluetooth tidak tersedia di perangkat ini '
        '(transport Bluetooth hanya didukung di Android).',
      );
    }
  }

  @override
  void kirim(SyncPacket paket) {
    if (!terhubung) return;
    var siap = paket;
    if (paket.action == SyncAction.updateBackgroundImages &&
        !_kirimTanpaKompresiLatar) {
      siap = compressedBackgroundPacket(paket);
    } else if (paket.action == SyncAction.updateLogo) {
      siap = compressedLogoPacket(paket);
    }
    for (final potongan in encodeChunkedTransfer(siap).packets) {
      _kirimMentah(potongan);
    }
  }

  void _kirimMentah(SyncPacket paket) {
    unawaited(
      _tautan
          .kirim(bingkaiBtEncode(utf8.encode(paket.toJson())))
          .catchError((Object _) {}),
    );
  }

  @override
  Future<void> putus() async {
    _socketTerhubung = false;
    _terotentikasi = false;
    _nonceTertunda = null;
    _pengurai.reset();
    _perangkai.reset();
    _gagalkanPenunggu('Koneksi Bluetooth ditutup.');
    await _langganan?.cancel();
    _langganan = null;
    try {
      await _tautan.putuskan();
    } catch (_) {
      // Plugin tidak ada (non-Android) — tidak ada yang diputus.
    }
  }

  void _gagalkanPenunggu(String pesan) {
    if (_penungguSambung != null && !_penungguSambung!.isCompleted) {
      _penungguSambung!.completeError(Exception(pesan));
    }
    if (_penungguAuth != null && !_penungguAuth!.isCompleted) {
      _penungguAuth!.completeError(Exception(pesan));
    }
    _penungguSambung = null;
    _penungguAuth = null;
  }

  // --- Kejadian tautan -------------------------------------------------

  void _tanganiKejadian(KejadianBt kejadian) {
    switch (kejadian) {
      case BtTerhubung():
        _socketTerhubung = true;
        if (_penungguSambung != null && !_penungguSambung!.isCompleted) {
          _penungguSambung!.complete();
        }
        _penungguSambung = null;
      case BtData(:final bytes):
        _olahBytes(bytes);
      case BtTerputus():
        _jalurBerakhir('Koneksi Bluetooth ke TV terputus.');
      case BtGagal(:final pesan):
        _jalurBerakhir(pesan);
      case BtDitemukan():
      case BtDiscoverySelesai():
        break; // Urusan layar Koneksi, bukan transport.
    }
  }

  void _jalurBerakhir(String pesan) {
    final pernahAktif = _socketTerhubung || _penungguSambung != null;
    _socketTerhubung = false;
    _terotentikasi = false;
    _gagalkanPenunggu(pesan);
    if (pernahAktif) _kesalahan.add(pesan);
  }

  // --- Aliran paket ------------------------------------------------------

  void _olahBytes(Uint8List bytes) {
    final List<Uint8List> bingkai;
    try {
      bingkai = _pengurai.masukkan(bytes);
    } on FormatException {
      _jalurBerakhir('Aliran data Bluetooth korup. Koneksi ditutup.');
      unawaited(_tautan.putuskan().catchError((Object _) {}));
      return;
    }
    for (final b in bingkai) {
      final SyncPacket paket;
      try {
        paket = SyncPacket.fromJson(utf8.decode(b));
      } catch (_) {
        continue; // Bingkai tak ter-decode dibuang (paritas sumber).
      }
      if (paket.action == SyncAction.chunkedData) {
        final utuh = _perangkai.addChunk(paket);
        if (utuh != null) _prosesPaket(utuh);
      } else {
        _prosesPaket(paket);
      }
    }
  }

  void _prosesPaket(SyncPacket paket) {
    switch (paket.action) {
      case SyncAction.authChallenge:
        final nonce = paket.payload['nonce'];
        if (nonce is String && nonce.isNotEmpty) {
          // Nonce TIDAK dibersihkan oleh peristiwa 'connected' —
          // challenge bisa tiba sebelum/sesudahnya (paritas sumber).
          _nonceTertunda = nonce;
          _jawabChallenge();
        }
      case SyncAction.authSuccess:
        _terotentikasi = true;
        _nonceTertunda = null;
        if (_penungguAuth != null && !_penungguAuth!.isCompleted) {
          _penungguAuth!.complete();
        }
        _penungguAuth = null;
      case SyncAction.authFailure:
        final alasan = paket.payload['error'] as String? ?? 'PIN salah.';
        _terotentikasi = false;
        if (_penungguAuth != null && !_penungguAuth!.isCompleted) {
          _penungguAuth!.completeError(
            Exception(
              'Autentikasi Bluetooth gagal: $alasan Periksa PIN 4 digit '
              'pada display tersimpan (PIN tampil di menu admin TV).',
            ),
          );
          _penungguAuth = null;
        } else {
          _kesalahan.add('Autentikasi Bluetooth gagal: $alasan');
        }
      default:
        // Paket data sebelum authSuccess dibuang — TV menegakkan hal
        // yang sama untuk arah sebaliknya.
        if (!_terotentikasi) return;
        _paketMasuk.add(paket);
    }
  }

  void _jawabChallenge() {
    final nonce = _nonceTertunda;
    if (nonce == null) return;
    if (_pin.isEmpty) {
      if (_penungguAuth != null && !_penungguAuth!.isCompleted) {
        _penungguAuth!.completeError(
          Exception(
            'PIN Bluetooth belum diisi untuk display ini. Edit display '
            'tersimpan lalu isi PIN 4 digit dari menu admin TV.',
          ),
        );
        _penungguAuth = null;
      }
      return;
    }
    _kirimMentah(
      SyncPacket(
        action: SyncAction.authResponse,
        payload: {'pin': _pin, 'nonce': nonce},
      ),
    );
  }
}
