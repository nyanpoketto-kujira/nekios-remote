import 'package:flutter_test/flutter_test.dart';
import 'package:nekios_remote/model/snapshot.dart';

import 'klien_palsu.dart';

void main() {
  group('SnapshotDisplay.fromPayload', () {
    test('memetakan seluruh field kontrak R1', () {
      final s = SnapshotDisplay.fromPayload(payloadSnapshotContoh());
      expect(s.status, StatusDisplay.pelajaran);
      expect(s.jamEfektif, DateTime(2026, 11, 18, 9, 20, 24));
      expect(s.simulasiAktif, isTrue);
      expect(s.mading, 'Selamat datang di pameran!');
      expect(s.hasLogo, isTrue);
      expect(s.jamKeAktif, 3);
      expect(s.slotAktif?.mulai, '09.05');
      expect(s.slotAktif?.selesai, '09.50');
      expect(s.belBerikutnya, DateTime(2026, 11, 18, 9, 50));
      expect(s.sisaKeBelDetik, 1776);
      expect(s.jadwal?.sekolah, 'SMKN 1 Ukui');
      expect(s.jadwal?.jumlahKelas, 6);
      expect(s.jadwal?.hariAktif, 'Rabu');
    });

    test('payload kosong jatuh ke nilai aman', () {
      final s = SnapshotDisplay.fromPayload(const {});
      expect(s.status, StatusDisplay.tidakDikenal);
      expect(s.jamEfektif, isNull);
      expect(s.simulasiAktif, isFalse);
      expect(s.mading, '');
      expect(s.slotAktif, isNull);
      expect(s.jadwal, isNull);
    });

    test('label status manusiawi per status', () {
      String label(Map<String, dynamic> payload) =>
          SnapshotDisplay.fromPayload(payload).labelStatus;
      expect(label(payloadSnapshotContoh()), 'Pelajaran — Jam ke-3');
      expect(label({'status': 'isoma'}), contains('ISOMA'));
      expect(label({'status': 'sebelumMasuk'}), 'Sebelum masuk');
      expect(label({'status': 'pulang'}), 'Sudah pulang');
      expect(label({'status': 'tidakAdaJadwal'}), 'Tidak ada jadwal hari ini');
      expect(
        label({
          'status': 'khusus',
          'slotAktif': {
            'mulai': '07.15',
            'selesai': '08.00',
            'tipe': 'khusus',
            'label': 'UPACARA / APEL BERSAMA',
          },
        }),
        'UPACARA / APEL BERSAMA',
      );
    });
  });

  group('detak lokal di antara snapshot', () {
    test('jam efektif maju mengikuti waktu lokal', () {
      final s = SnapshotDisplay.fromPayload(payloadSnapshotContoh());
      final diterima = DateTime(2026, 11, 18, 10, 0, 0);
      final jam = s.jamEfektifPada(
        diterima,
        diterima.add(const Duration(seconds: 90)),
      );
      expect(jam, DateTime(2026, 11, 18, 9, 21, 54));
    });

    test('sisa ke bel berkurang dan tidak negatif', () {
      final s = SnapshotDisplay.fromPayload(payloadSnapshotContoh());
      final diterima = DateTime(2026, 11, 18, 10, 0, 0);
      expect(
        s.sisaKeBelPada(diterima, diterima.add(const Duration(seconds: 90))),
        1776 - 90,
      );
      expect(
        s.sisaKeBelPada(diterima, diterima.add(const Duration(hours: 2))),
        0,
      );
    });
  });

  group('formatSisaDetik', () {
    test('format MM:SS dan J:MM:SS', () {
      expect(formatSisaDetik(1776), '29:36');
      expect(formatSisaDetik(5), '00:05');
      expect(formatSisaDetik(3661), '1:01:01');
      expect(formatSisaDetik(-3), '00:00');
    });
  });
}
