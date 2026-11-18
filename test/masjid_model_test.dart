import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nekios_remote/masjid/model_masjid.dart';
import 'package:nekios_remote/masjid/paket_masjid.dart';

/// Fixture di `test/fixtures/` DIBANGUN DARI serialisasi
/// `shared_models` masjid-you asli (objek contoh yang sama dengan
/// `state_snapshot_test.dart` masjid-you, di-encode lewat
/// `SyncPacket.toJson()` sumbernya) — bukan JSON karangan. Test ini
/// menjaga paritas wire port dialek di `lib/masjid/`.
Map<String, dynamic> bacaFixture(String nama) =>
    jsonDecode(File('test/fixtures/$nama').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  group('fixture paket stateSnapshot dari shared_models asli', () {
    final fixture = bacaFixture('paket_snapshot_masjid.json');

    test('decode: aksi + seluruh field snapshot terbaca persis', () {
      final paket = SyncPacket.fromMap(fixture);
      expect(paket.action, SyncAction.stateSnapshot);

      final snapshot = StateSnapshot.fromMap(paket.payload);
      expect(snapshot.hasData, isTrue);
      expect(snapshot.config.name, 'Masjid Al-Hikmah');
      expect(snapshot.config.address, 'Jl. Pemuda No. 45');
      expect(snapshot.config.latitude, -6.1754);
      expect(snapshot.config.longitude, 106.8272);
      expect(snapshot.config.utcOffsetHours, 7);
      expect(snapshot.config.iqamahDuration.fajr, 12);
      expect(snapshot.config.iqamahDuration.isha, 15);
      expect(snapshot.config.offsetFor(PrayerType.fajr), 2);
      expect(snapshot.config.offsetFor(PrayerType.isha), -1);
      expect(snapshot.config.offsetFor(PrayerType.asr), 0);
      expect(snapshot.config.preAdhanMinutes, 20);
      expect(snapshot.config.adhanMinutes, 3);
      expect(snapshot.config.preIqomahMinutes, 2);
      expect(snapshot.config.shalatMinutes, 12);
      expect(snapshot.config.khutbahMinutes, 25);
      expect(snapshot.config.fridayKhatib, 'Ustadz Ahmad');
      expect(snapshot.config.fridayMuadzin, 'Ustadz Bilal');
      expect(snapshot.config.showKas, isTrue);
      expect(snapshot.config.hasFridayPrayer, isTrue);
      expect(snapshot.config.backgroundSlideSeconds, 45);

      expect(snapshot.runningTexts, hasLength(2));
      expect(snapshot.runningTexts[0].content, 'Kajian rutin Sabtu');
      expect(snapshot.runningTexts[0].category, 'Kajian');
      expect(snapshot.runningTexts[1].isActive, isFalse);

      expect(snapshot.banners, hasLength(2));
      expect(snapshot.banners[0].header, 'DONASI');
      expect(snapshot.banners[0].base64Image, 'abc123');
      expect(snapshot.banners[1].base64Image, isNull);

      expect(snapshot.kasTransactions, hasLength(2));
      expect(snapshot.kasTransactions[0].type, KasType.masuk);
      expect(snapshot.kasTransactions[1].type, KasType.keluar);
      expect(snapshot.kasTransactions[1].date, DateTime(2026, 8, 15, 10));
      final ringkasan = KasSummary.fromTransactions(snapshot.kasTransactions);
      expect(ringkasan.totalMasuk, 2500000);
      expect(ringkasan.totalKeluar, 750000);
      expect(ringkasan.saldo, 1750000);

      expect(snapshot.sideImages.single.caption, 'Renovasi tempat wudhu');
      expect(snapshot.backgroundImages, hasLength(2));
      expect(snapshot.backgroundImages[1].isActive, isFalse);
      expect(snapshot.mosqueLogo, 'bG9nbw==');
    });

    test('round-trip: toMap() mengembalikan payload yang identik', () {
      final paket = SyncPacket.fromMap(fixture);
      final snapshot = StateSnapshot.fromMap(paket.payload);
      // Bandingkan sebagai JSON: urutan kunci & nilai harus sama
      // persis dengan serialisasi sumbernya.
      expect(jsonEncode(snapshot.toMap()), jsonEncode(fixture['payload']));
      final paketLagi = SyncPacket(
        action: SyncAction.stateSnapshot,
        payload: snapshot.toMap(),
      );
      expect(jsonEncode(paketLagi.toMap()), jsonEncode(fixture));
    });
  });

  group('fixture paket stateUpdate', () {
    test('StatusTvMasjid terbaca persis dari payload TV', () {
      final fixture = bacaFixture('paket_state_update_masjid.json');
      final paket = SyncPacket.fromMap(fixture);
      expect(paket.action, SyncAction.stateUpdate);
      final status = StatusTvMasjid.fromPayload(paket.payload);
      expect(status.phase, PrayerPhase.preIqomah);
      expect(status.prayer, PrayerType.dhuhr);
      expect(status.remainingSeconds, 754);
      expect(status.totalSeconds, 900);
      expect(status.muted, isFalse);
      expect(status.standby, isTrue);
      expect(status.toPayload(), fixture['payload']);
    });

    test('payload kosong/rusak jatuh ke nilai aman', () {
      final status = StatusTvMasjid.fromPayload(const {});
      expect(status.phase, PrayerPhase.normal);
      expect(status.prayer, isNull);
      expect(status.remainingSeconds, 0);
      expect(status.muted, isFalse);
    });
  });

  group('round-trip model per model', () {
    test('MosqueConfig bawaan pulang-pergi utuh', () {
      const config = MosqueConfig();
      final lagi = MosqueConfig.fromMap(config.toMap());
      expect(lagi, config);
      expect(lagi.hashCode, config.hashCode);
    });

    test('MosqueConfig: offset warisan prayerCorrectionMinutes', () {
      final config = MosqueConfig.fromMap(const {'prayerCorrectionMinutes': 3});
      for (final type in kAllPrayerTypes) {
        expect(config.offsetFor(type), 3);
      }
    });

    test('MosqueConfig: backgroundSlideSeconds di-clamp 5..300', () {
      expect(
        MosqueConfig.fromMap(const {'backgroundSlideSeconds': 9999})
            .backgroundSlideSeconds,
        300,
      );
      expect(
        MosqueConfig.fromMap(const {'backgroundSlideSeconds': 1})
            .backgroundSlideSeconds,
        5,
      );
    });

    test('RunningTextMessage, MediaBanner (subtitle lama), gambar', () {
      const teks = RunningTextMessage(
        id: 'a',
        content: 'Halo',
        isActive: false,
        category: 'Kas',
      );
      expect(RunningTextMessage.fromMap(teks.toMap()), teks);

      // Payload lama memakai `subtitle` untuk isi banner.
      final banner = MediaBanner.fromMap(const {
        'id': 'b',
        'subtitle': 'Isi lama',
      });
      expect(banner.content, 'Isi lama');
      expect(banner.header, 'INFO MASJID');

      const khusus = SpecialImage(id: 's', base64Image: 'eA==', caption: 'K');
      expect(SpecialImage.fromMap(khusus.toMap()), khusus);
      const latar = BackgroundImage(id: 'g', base64Image: 'eQ==');
      expect(BackgroundImage.fromMap(latar.toMap()), latar);
    });

    test('snapshot kosong: hasData=false & daftar kosong', () {
      const kosong = StateSnapshot();
      final lagi = StateSnapshot.fromMap(kosong.toMap());
      expect(lagi, kosong);
      expect(lagi.hasData, isFalse);
    });

    test('payload snapshot rusak tidak melempar (paritas sumber)', () {
      final parsed = StateSnapshot.fromMap(const {
        'config': 'bukan-map',
        'runningTexts': 'bukan-list',
        'banners': [1, 'x', null],
        'kasTransactions': [
          {'id': 'k1', 'type': 'masuk', 'amount': 5000},
        ],
        'hasData': 'bukan-bool',
      });
      expect(parsed.config, const MosqueConfig());
      expect(parsed.runningTexts, isEmpty);
      expect(parsed.banners, isEmpty);
      expect(parsed.kasTransactions.single.amount, 5000);
      expect(parsed.hasData, isFalse);
    });
  });
}
