import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nekios_remote/masjid/model_masjid.dart';
import 'package:nekios_remote/masjid/paket_masjid.dart';
import 'package:nekios_remote/state/remote_store.dart';
import 'package:nekios_remote/state/store_masjid.dart';
import 'package:nekios_remote/model/display_tersimpan.dart';

import 'masjid_palsu.dart';

SyncPacket paketFixture(String nama) =>
    SyncPacket.fromJson(File('test/fixtures/$nama').readAsStringSync());

const displayMasjid = DisplayTersimpan(
  nama: 'TV Masjid',
  ip: '192.168.1.30',
  tipe: TipeDisplay.masjid,
);

Future<void> jeda() => Future<void>.delayed(Duration.zero);

void main() {
  late TransportMasjidPalsu transport;
  late MasjidStore store;

  setUp(() {
    transport = TransportMasjidPalsu();
    store = MasjidStore(
      buatTransport: (_) => transport,
      batasBukti: const Duration(milliseconds: 300),
    );
  });

  tearDown(() => store.dispose());

  group('koneksi & snapshot', () {
    test('sambungkan: status beralih & getInitialState diminta', () async {
      await store.sambungkan(displayMasjid);
      expect(store.statusKoneksi, StatusKoneksi.terhubung);
      expect(store.displayAktif, displayMasjid);
      expect(
        transport.terkirim.map((p) => p.action),
        contains(SyncAction.getInitialState),
      );
    });

    test('snapshot fixture mengisi cermin + ringkasan kas', () async {
      await store.sambungkan(displayMasjid);
      transport.terima(paketFixture('paket_snapshot_masjid.json'));
      await jeda();
      expect(store.snapshot?.config.name, 'Masjid Al-Hikmah');
      expect(store.ringkasanKas.totalMasuk, 2500000);
      expect(store.ringkasanKas.saldo, 1750000);
      expect(store.tvBelumPunyaData, isFalse);
    });

    test('stateUpdate fixture mengisi fase + hitung mundur lokal', () async {
      await store.sambungkan(displayMasjid);
      transport.terima(paketFixture('paket_state_update_masjid.json'));
      await jeda();
      expect(store.statusTv?.phase, PrayerPhase.preIqomah);
      expect(store.statusTv?.prayer, PrayerType.dhuhr);
      expect(store.statusTv?.standby, isTrue);
      expect(store.sisaDetikFase, inInclusiveRange(750, 754));
    });

    test('sambung gagal: status terputus + pesan tampil', () async {
      transport.gagalSambung = true;
      await store.sambungkan(displayMasjid);
      expect(store.statusKoneksi, StatusKoneksi.terputus);
      expect(store.pesanKoneksi, contains('Sengaja gagal'));
    });

    test('kesalahan jalur saat terhubung menjatuhkan status', () async {
      await store.sambungkan(displayMasjid);
      transport.picuKesalahan('Koneksi Bluetooth ke TV terputus.');
      await jeda();
      expect(store.statusKoneksi, StatusKoneksi.terputus);
      expect(store.pesanKoneksi, contains('terputus'));
      expect(store.snapshot, isNull);
    });

    test('putuskan membersihkan cermin state', () async {
      await store.sambungkan(displayMasjid);
      transport.terima(paketFixture('paket_snapshot_masjid.json'));
      await jeda();
      await store.putuskan();
      expect(store.statusKoneksi, StatusKoneksi.terputus);
      expect(store.snapshot, isNull);
      expect(store.statusTv, isNull);
    });
  });

  group('kontrak fire-and-forget (bukti susulan)', () {
    test('aksi kontrol berhasil saat stateUpdate susulan tiba', () async {
      await store.sambungkan(displayMasjid);
      final masa = store.mulaiIqomah();
      expect(
        transport.terkirim.map((p) => p.action),
        contains(SyncAction.startIqomah),
      );
      transport.terima(paketFixture('paket_state_update_masjid.json'));
      final hasil = await masa;
      expect(hasil.sukses, isTrue);
    });

    test('aksi kontrol gagal lokal bila TV diam (timeout bukti)', () async {
      await store.sambungkan(displayMasjid);
      final hasil = await store.mulaiShalat();
      expect(hasil.sukses, isFalse);
      expect(hasil.pesan, contains('kabar susulan'));
    });

    test('kirimData menunggu snapshot susulan', () async {
      await store.sambungkan(displayMasjid);
      final masa = store.kirimData(
        const SyncPacket(
          action: SyncAction.updateKas,
          payload: {'transactions': []},
        ),
      );
      transport.terima(paketFixture('paket_snapshot_masjid.json'));
      expect((await masa).sukses, isTrue);
    });

    test('perintah saat terputus langsung gagal', () async {
      final hasil = await store.lewatiAdhan();
      expect(hasil.sukses, isFalse);
    });

    test('aturSenyap/aturStandby membawa payload yang benar', () async {
      await store.sambungkan(displayMasjid);
      final m1 = store.aturSenyap(true);
      final senyap = transport.terkirim.last;
      expect(senyap.action, SyncAction.setMuted);
      expect(senyap.payload, {'muted': true});
      transport.terima(paketFixture('paket_state_update_masjid.json'));
      expect((await m1).sukses, isTrue);

      final m2 = store.aturStandby(false);
      final standby = transport.terkirim.last;
      expect(standby.action, SyncAction.setStandby);
      expect(standby.payload, {'standby': false});
      transport.terima(paketFixture('paket_state_update_masjid.json'));
      expect((await m2).sukses, isTrue);
    });
  });

  group('bootstrap hasData=false', () {
    final paketKosong = SyncPacket(
      action: SyncAction.stateSnapshot,
      payload: const StateSnapshot().toMap(),
    );

    test('tanpa penyedia: tidak ada dorongan, status terbaca', () async {
      await store.sambungkan(displayMasjid);
      transport.terkirim.clear();
      transport.terima(paketKosong);
      await jeda();
      expect(store.tvBelumPunyaData, isTrue);
      expect(transport.terkirim, isEmpty);
    });

    test('dengan penyedia: 6 paket update didorong SEKALI', () async {
      var panggilan = 0;
      final storeBootstrap = MasjidStore(
        buatTransport: (_) => transport,
        batasBukti: const Duration(milliseconds: 300),
        penyediaBootstrap: () {
          panggilan++;
          return const StateSnapshot(
            config: MosqueConfig(name: 'Masjid Lokal'),
            hasData: true,
          );
        },
      );
      addTearDown(storeBootstrap.dispose);
      await storeBootstrap.sambungkan(displayMasjid);
      transport.terkirim.clear();
      transport.terima(paketKosong);
      await jeda();
      expect(panggilan, 1);
      expect(transport.terkirim.map((p) => p.action).toList(), [
        SyncAction.updateConfig,
        SyncAction.updateRunningText,
        SyncAction.updateBanners,
        SyncAction.updateKas,
        SyncAction.updateSideImages,
        SyncAction.updateBackgroundImages,
      ]);
      // Payload updateConfig adalah map config itu sendiri.
      expect(transport.terkirim.first.payload['name'], 'Masjid Lokal');

      // Snapshot kosong kedua tidak memicu dorongan ulang.
      transport.terima(paketKosong);
      await jeda();
      expect(panggilan, 1);
      expect(transport.terkirim, hasLength(6));
    });
  });

  test('mintaSnapshot round-trip lewat getInitialState', () async {
    await store.sambungkan(displayMasjid);
    transport.terima(paketFixture('paket_snapshot_masjid.json'));
    await jeda();
    final masa = store.mintaSnapshot();
    transport.terima(paketFixture('paket_snapshot_masjid.json'));
    expect((await masa).sukses, isTrue);
    expect(
      jsonEncode(transport.terkirim.last.toMap()),
      '{"action":"getInitialState","payload":{}}',
    );
  });
}
