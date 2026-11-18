import 'dart:async';

import 'package:nekios_core/nekios_core.dart';
import 'package:nekios_remote/layanan/klien_remote.dart';

/// Payload `state.snapshot` contoh sesuai kontrak R1 nekios-school —
/// dipakai bersama oleh test store, snapshot, dan widget.
Map<String, dynamic> payloadSnapshotContoh() => {
  'status': 'pelajaran',
  'jamEfektif': '2026-11-18T09:20:24',
  'simulasiAktif': true,
  'mading': 'Selamat datang di pameran!',
  'hasLogo': true,
  'jamKeAktif': 3,
  'slotAktif': {
    'mulai': '09.05',
    'selesai': '09.50',
    'tipe': 'pelajaran',
    'label': null,
  },
  'belBerikutnya': '2026-11-18T09:50:00',
  'sisaKeBelDetik': 1776,
  'jadwal': {
    'sekolah': 'SMKN 1 Ukui',
    'judul': 'Jadwal Pelajaran TKJ',
    'tahunPelajaran': '2026/2027',
    'jurusan': 'TKJ',
    'jumlahKelas': 6,
    'jumlahHari': 5,
    'hariAktif': 'Rabu',
  },
};

/// Klien remote palsu yang meniru pola balasan display R1:
/// perintah sukses → `ack` lalu `state.snapshot`; `ping` → ack +
/// snapshot; mode [balasError] menjawab semua perintah dengan
/// `error`; mode [senyap] tidak menjawab apa pun (untuk timeout).
class KlienPalsu implements KlienRemote {
  final StreamController<NekiosPacket> _controller =
      StreamController<NekiosPacket>.broadcast();

  bool _terhubung = false;

  /// Semua paket yang pernah dikirim store lewat klien ini.
  final List<NekiosPacket> terkirim = [];

  /// Payload snapshot untuk balasan otomatis; null = tidak mengirim
  /// snapshot susulan.
  Map<String, dynamic>? payloadSnapshot = payloadSnapshotContoh();

  bool balasError = false;
  String pesanError = 'Perintah ditolak display.';
  bool senyap = false;
  bool gagalSambung = false;

  @override
  bool get terhubung => _terhubung;

  @override
  Stream<NekiosPacket> get paketMasuk => _controller.stream;

  @override
  Future<void> sambung(String host, {int port = kNekiosPort}) async {
    if (gagalSambung) {
      throw Exception('SocketException: Connection refused');
    }
    _terhubung = true;
  }

  @override
  void kirim(NekiosPacket paket) {
    terkirim.add(paket);
    if (senyap || !_terhubung) return;
    scheduleMicrotask(() {
      if (!_terhubung) return;
      if (balasError && paket.type != TipePaket.ping) {
        _controller.add(NekiosPacket.error(pesanError));
        return;
      }
      _controller.add(NekiosPacket.ack(ofType: paket.type));
      final snapshot = payloadSnapshot;
      if (snapshot != null) {
        _controller.add(
          NekiosPacket(type: TipePaket.stateSnapshot, payload: snapshot),
        );
      }
    });
  }

  @override
  Future<void> putus() async {
    _terhubung = false;
  }

  /// Suntik paket balasan manual dari test.
  void suntik(NekiosPacket paket) => _controller.add(paket);
}
