import 'package:flutter_test/flutter_test.dart';
import 'package:nekios_core/nekios_core.dart';
import 'package:nekios_remote/domain/perintah.dart';
import 'package:nekios_remote/model/snapshot.dart';

import 'klien_palsu.dart';

void main() {
  final snapshot = SnapshotDisplay.fromPayload(payloadSnapshotContoh());

  group('lompat ke bel berikutnya (tombol sakti)', () {
    test('membentuk clock.simulate ke belBerikutnya dari snapshot', () {
      final paket = perintahLompatKeBelBerikutnya(snapshot);
      expect(paket, isNotNull);
      expect(paket!.type, TipePaket.clockSimulate);
      expect(paket.payload?['at'], '2026-11-18T09:50:00.000');
    });

    test('null bila snapshot tidak punya bel berikutnya', () {
      final tanpaBel = SnapshotDisplay.fromPayload(const {
        'status': 'pulang',
        'belBerikutnya': null,
        'sisaKeBelDetik': null,
      });
      expect(perintahLompatKeBelBerikutnya(tanpaBel), isNull);
    });
  });

  group('simulasi ke jam tertentu', () {
    test('memakai tanggal jam efektif, detik dinolkan', () {
      final paket = perintahSimulasiKeJam(snapshot, jam: 13, menit: 5);
      expect(paket.type, TipePaket.clockSimulate);
      expect(paket.payload?['at'], '2026-11-18T13:05:00.000');
    });

    test('lempar StateError bila snapshot belum punya jam efektif', () {
      final kosong = SnapshotDisplay.fromPayload(const {});
      expect(
        () => perintahSimulasiKeJam(kosong, jam: 8, menit: 0),
        throwsStateError,
      );
    });
  });

  group('pembangun paket lain', () {
    test('mading.set membawa teks; kosong = sambutan bawaan', () {
      expect(perintahAturMading('Halo').type, TipePaket.madingSet);
      expect(perintahAturMading('Halo').payload?['text'], 'Halo');
      expect(perintahAturMading('').payload?['text'], '');
    });

    test('logo.set & hapus logo', () {
      expect(perintahAturLogo('QUJD').payload?['imageBase64'], 'QUJD');
      expect(perintahHapusLogo().type, TipePaket.logoSet);
      expect(perintahHapusLogo().payload?['imageBase64'], '');
    });

    test('audio.konfigurasi & audio.tes (panel bel)', () {
      final atur = perintahAturBel(false);
      expect(atur.type, TipePaket.audioKonfigurasi);
      expect(atur.payload?['belAktif'], isFalse);
      expect(perintahAturBel(true).payload?['belAktif'], isTrue);
      final tes = perintahTesBel();
      expect(tes.type, TipePaket.audioTes);
      expect(tes.payload, isNull);
    });

    test('clock.clear & ping & schedule.replace', () {
      expect(perintahKembaliKeJamNyata().type, TipePaket.clockClear);
      expect(perintahPing().type, TipePaket.ping);
      final jadwal = {'meta': <String, dynamic>{}};
      final paket = perintahGantiJadwal(jadwal);
      expect(paket.type, TipePaket.scheduleReplace);
      expect(paket.payload, same(jadwal));
    });
  });
}
