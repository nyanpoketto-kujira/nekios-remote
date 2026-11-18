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

  group('metode typed editor (A2a)', () {
    // Sambungkan lalu bersihkan paket sambutan (getInitialState)
    // agar terkirim.single benar-benar paket perintah yang diuji.
    Future<void> siap() async {
      await store.sambungkan(displayMasjid);
      transport.terima(paketFixture('paket_snapshot_masjid.json'));
      await jeda();
      transport.terkirim.clear();
    }

    void jawabSnapshot() =>
        transport.terima(paketFixture('paket_snapshot_masjid.json'));

    test('perbaruiConfig: payload = map config utuh (jalur bootstrap)',
        () async {
      await siap();
      const config = MosqueConfig(name: 'Masjid Uji', address: 'Jl. Merdeka');
      final masa = store.perbaruiConfig(config);
      expect(transport.terkirim.single.action, SyncAction.updateConfig);
      expect(transport.terkirim.single.payload, config.toMap());
      jawabSnapshot();
      expect((await masa).sukses, isTrue);
    });

    test('perbaruiRunningText: payload {messages: [toMap]}', () async {
      await siap();
      const pesan = [
        RunningTextMessage(
          id: 'rt1',
          content: 'Kajian rutin Sabtu',
          category: 'Kajian',
        ),
        RunningTextMessage(id: 'rt2', content: 'Jaga kebersihan'),
      ];
      final masa = store.perbaruiRunningText(pesan);
      expect(transport.terkirim.single.action, SyncAction.updateRunningText);
      expect(transport.terkirim.single.payload, {
        'messages': [for (final m in pesan) m.toMap()],
      });
      jawabSnapshot();
      expect((await masa).sukses, isTrue);
    });

    test('perbaruiBanners: payload {banners: [toMap]}', () async {
      await siap();
      const banners = [
        MediaBanner(
          id: 'b1',
          header: 'DONASI',
          title: 'Infaq Pembangunan',
          content: 'Salurkan untuk ruang belajar',
          footer: 'Amal Jariyah',
          base64Image: 'abc123',
        ),
      ];
      final masa = store.perbaruiBanners(banners);
      expect(transport.terkirim.single.action, SyncAction.updateBanners);
      expect(transport.terkirim.single.payload, {
        'banners': [for (final b in banners) b.toMap()],
      });
      jawabSnapshot();
      expect((await masa).sukses, isTrue);
    });

    test('perbaruiKas: payload {transactions: [toMap]}', () async {
      await siap();
      final transaksi = [
        KasTransaction(
          id: 'k1',
          type: KasType.masuk,
          amount: 2500000,
          description: 'Infaq Jumat',
          date: DateTime(2026, 8, 14, 9, 30),
        ),
      ];
      final masa = store.perbaruiKas(transaksi);
      expect(transport.terkirim.single.action, SyncAction.updateKas);
      expect(transport.terkirim.single.payload, {
        'transactions': [for (final t in transaksi) t.toMap()],
      });
      jawabSnapshot();
      expect((await masa).sukses, isTrue);
    });

    test('perbaruiSideImages: payload {images: [toMap]}', () async {
      await siap();
      const gambar = [
        SpecialImage(
          id: 's1',
          base64Image: 'c2lkZTE=',
          caption: 'Renovasi tempat wudhu',
        ),
      ];
      final masa = store.perbaruiSideImages(gambar);
      expect(transport.terkirim.single.action, SyncAction.updateSideImages);
      expect(transport.terkirim.single.payload, {
        'images': [for (final g in gambar) g.toMap()],
      });
      jawabSnapshot();
      expect((await masa).sukses, isTrue);
    });

    test('perbaruiBackgroundImages: payload {images: [toMap]}', () async {
      await siap();
      const gambar = [BackgroundImage(id: 'bg1', base64Image: 'Ymcx')];
      final masa = store.perbaruiBackgroundImages(gambar);
      expect(
        transport.terkirim.single.action,
        SyncAction.updateBackgroundImages,
      );
      expect(transport.terkirim.single.payload, {
        'images': [for (final g in gambar) g.toMap()],
      });
      jawabSnapshot();
      expect((await masa).sukses, isTrue);
    });

    test('perbaruiLogo: payload {logoBase64} — pasang & hapus', () async {
      await siap();
      final pasang = store.perbaruiLogo('bG9nbw==');
      expect(transport.terkirim.single.action, SyncAction.updateLogo);
      expect(transport.terkirim.single.payload, {'logoBase64': 'bG9nbw=='});
      jawabSnapshot();
      expect((await pasang).sukses, isTrue);

      transport.terkirim.clear();
      final hapus = store.perbaruiLogo(null);
      expect(transport.terkirim.single.payload, {'logoBase64': null});
      jawabSnapshot();
      expect((await hapus).sukses, isTrue);
    });

    test('metode data gagal bila TV diam (timeout bukti snapshot)',
        () async {
      await siap();
      final hasil = await store.perbaruiKas(const []);
      expect(hasil.sukses, isFalse);
      expect(hasil.pesan, contains('kabar susulan'));
    });

    test('perintah typed kedua ditolak selama bukti belum tiba', () async {
      await siap();
      final pertama = store.perbaruiRunningText(const []);
      final kedua = await store.perbaruiConfig(const MosqueConfig());
      expect(kedua.sukses, isFalse);
      expect(kedua.pesan, contains('masih menunggu jawaban'));
      jawabSnapshot();
      expect((await pertama).sukses, isTrue);
    });

    test('paksaFase: payload {phase: name} untuk keenam fase + bukti '
        'stateUpdate', () async {
      await siap();
      for (final fase in PrayerPhase.values) {
        transport.terkirim.clear();
        final masa = store.paksaFase(fase);
        expect(transport.terkirim.single.action, SyncAction.forcePhase);
        expect(transport.terkirim.single.payload, {'phase': fase.name});
        transport.terima(paketFixture('paket_state_update_masjid.json'));
        expect((await masa).sukses, isTrue, reason: 'fase ${fase.name}');
      }
    });

    test('paksaFase juga tuntas dibuktikan stateSnapshot', () async {
      await siap();
      final masa = store.paksaFase(PrayerPhase.adhan);
      jawabSnapshot();
      expect((await masa).sukses, isTrue);
    });

    test('sedangMengirim berdenyut true→false pada bukti & notify',
        () async {
      await siap();
      var notifikasi = 0;
      store.addListener(() => notifikasi++);
      expect(store.sedangMengirim, isFalse);
      final masa = store.perbaruiRunningText(const []);
      expect(store.sedangMengirim, isTrue);
      expect(notifikasi, greaterThan(0));
      jawabSnapshot();
      expect((await masa).sukses, isTrue);
      expect(store.sedangMengirim, isFalse);
    });

    test('sedangMengirim kembali false setelah timeout bukti', () async {
      await siap();
      final masa = store.perbaruiLogo(null);
      expect(store.sedangMengirim, isTrue);
      expect((await masa).sukses, isFalse);
      expect(store.sedangMengirim, isFalse);
    });
  });
}
