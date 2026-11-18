/// Pembangun paket perintah remote → display (protokol Nekios v1)
/// sebagai fungsi murni supaya logikanya — terutama "lompat ke bel
/// berikutnya" — bisa diuji tanpa WebSocket.
library;

import 'package:nekios_core/nekios_core.dart';

import '../model/snapshot.dart';

/// `ping` — cek hidup; display membalas ack + state.snapshot.
NekiosPacket perintahPing() => NekiosPacket.ping();

/// `mading.set` — [teks] kosong berarti kembali ke sambutan bawaan.
NekiosPacket perintahAturMading(String teks) =>
    NekiosPacket(type: TipePaket.madingSet, payload: {'text': teks});

/// `logo.set` — [imageBase64] adalah gambar ter-encode base64;
/// string kosong menghapus logo di display.
NekiosPacket perintahAturLogo(String imageBase64) => NekiosPacket(
  type: TipePaket.logoSet,
  payload: {'imageBase64': imageBase64},
);

/// `logo.set` dengan payload kosong — hapus logo di display.
NekiosPacket perintahHapusLogo() => perintahAturLogo('');

/// `clock.simulate` ke momen absolut [pada].
NekiosPacket perintahSimulasiKe(DateTime pada) => NekiosPacket(
  type: TipePaket.clockSimulate,
  payload: {'at': pada.toIso8601String()},
);

/// Tombol sakti: lompat ke bel berikutnya.
///
/// Momen bel berikutnya diambil dari snapshot terakhir
/// (`belBerikutnya`, jam efektif display) lalu dikirim sebagai
/// `clock.simulate {at}` — display mengubahnya menjadi offset dari
/// jam sistemnya. Mengembalikan null bila snapshot tidak punya bel
/// berikutnya (mis. sudah pulang / tidak ada jadwal) — UI menonaktifkan
/// tombol pada keadaan itu.
NekiosPacket? perintahLompatKeBelBerikutnya(SnapshotDisplay snapshot) {
  final bel = snapshot.belBerikutnya;
  if (bel == null) return null;
  return perintahSimulasiKe(bel);
}

/// `clock.simulate` ke jam [jam]:[menit] pada TANGGAL yang sama dengan
/// jam efektif display saat ini (dari snapshot), detik dinolkan.
NekiosPacket perintahSimulasiKeJam(
  SnapshotDisplay snapshot, {
  required int jam,
  required int menit,
}) {
  final dasar = snapshot.jamEfektif;
  if (dasar == null) {
    throw StateError('Snapshot belum punya jam efektif.');
  }
  return perintahSimulasiKe(
    DateTime(dasar.year, dasar.month, dasar.day, jam, menit),
  );
}

/// `clock.clear` — akhiri simulasi, display kembali ke jam nyata.
NekiosPacket perintahKembaliKeJamNyata() =>
    const NekiosPacket(type: TipePaket.clockClear);

/// `schedule.replace` — payload adalah objek jadwal utuh.
NekiosPacket perintahGantiJadwal(Map<String, dynamic> jadwal) =>
    NekiosPacket(type: TipePaket.scheduleReplace, payload: jadwal);
