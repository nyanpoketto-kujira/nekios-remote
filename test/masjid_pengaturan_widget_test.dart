import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nekios_remote/layanan/lokasi_gps.dart';
import 'package:nekios_remote/masjid/paket_masjid.dart';
import 'package:nekios_remote/model/display_tersimpan.dart';
import 'package:nekios_remote/state/store_masjid.dart';
import 'package:nekios_remote/tema.dart';
import 'package:nekios_remote/ui/layar_pengaturan_masjid.dart';

import 'masjid_palsu.dart';

SyncPacket paketFixture(String nama) =>
    SyncPacket.fromJson(File('test/fixtures/$nama').readAsStringSync());

/// Snapshot fixture yang payload-nya diubah [ubah] lebih dulu —
/// untuk mensimulasikan bukti susulan TV setelah simpan.
SyncPacket snapshotDengan(void Function(Map<String, dynamic> payload) ubah) {
  final mentah =
      jsonDecode(
            File('test/fixtures/paket_snapshot_masjid.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  ubah(mentah['payload'] as Map<String, dynamic>);
  return SyncPacket.fromJson(jsonEncode(mentah));
}

const displayMasjid = DisplayTersimpan(
  nama: 'TV Masjid',
  ip: '192.168.1.30',
  tipe: TipeDisplay.masjid,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TransportMasjidPalsu transport;
  late MasjidStore store;

  setUp(() {
    transport = TransportMasjidPalsu();
    store = MasjidStore(
      buatTransport: (_) => transport,
      batasBukti: const Duration(seconds: 5),
    );
  });

  tearDown(() => store.dispose());

  Widget bungkus(Widget anak) => MaterialApp(
    theme: temaNekios(Brightness.light),
    home: Scaffold(body: anak),
  );

  Future<void> tampil(
    WidgetTester tester,
    Widget anak, {
    bool denganSnapshot = true,
  }) async {
    tester.view.physicalSize = const Size(1080, 3400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await store.sambungkan(displayMasjid);
    if (denganSnapshot) {
      transport.terima(paketFixture('paket_snapshot_masjid.json'));
    }
    await tester.pumpWidget(bungkus(anak));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> selesai(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  List<SyncPacket> paketConfig() => transport.terkirim
      .where((p) => p.action == SyncAction.updateConfig)
      .toList();

  // Payload updateConfig ADALAH map config itu sendiri
  // (perbaruiConfig mengirim config.toMap() langsung).
  Map<String, dynamic> configTerakhir() => paketConfig().last.payload;

  Finder fieldLabel(String label) => find.widgetWithText(TextField, label);

  // Satu-satunya FilledButton di layar ini adalah tombol
  // Simpan (labelnya berganti antara dua keadaan).
  FilledButton tombolSimpan(WidgetTester tester) =>
      tester.widget(find.byType(FilledButton));

  // ------------------------------------------------------------------

  testWidgets('pengaturan: seed dari config TV + belum ada perubahan', (
    tester,
  ) async {
    await tampil(tester, LayarPengaturanMasjid(store: store));
    expect(
      tester.widget<TextField>(fieldLabel('Nama masjid')).controller?.text,
      'Masjid Al-Hikmah',
    );
    expect(
      tester
          .widget<TextField>(fieldLabel('Lintang (latitude)'))
          .controller
          ?.text,
      '-6.1754',
    );
    expect(find.text('+2 menit'), findsOneWidget); // geser Subuh
    expect(find.text('-1 menit'), findsOneWidget); // geser Isya
    expect(find.text('25 menit'), findsOneWidget); // khutbah
    expect(find.textContaining('UTC+7'), findsOneWidget);
    expect(find.text('Belum ada perubahan'), findsOneWidget);
    expect(tombolSimpan(tester).onPressed, isNull);
    expect(paketConfig(), isEmpty);
    await selesai(tester);
  });

  testWidgets('pengaturan: ubah nama lalu Simpan mengirim config utuh', (
    tester,
  ) async {
    await tampil(tester, LayarPengaturanMasjid(store: store));
    await tester.enterText(
      fieldLabel('Nama masjid'),
      'Masjid Al-Hikmah Raya',
    );
    await tester.pump();
    expect(find.text('Simpan & Update Ke TV'), findsOneWidget);
    expect(tombolSimpan(tester).onPressed, isNotNull);

    await tester.tap(find.text('Simpan & Update Ke TV'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(paketConfig(), hasLength(1));
    final config = configTerakhir();
    expect(config['name'], 'Masjid Al-Hikmah Raya');
    // Field yang tidak diedit ikut apa adanya.
    expect(config['latitude'], -6.1754);
    expect(config['backgroundSlideSeconds'], 45);
    expect(config['utcOffsetHours'], 7);
    expect(config['prayerOffsets']['fajr'], 2);

    transport.terima(
      snapshotDengan((p) {
        (p['config'] as Map<String, dynamic>)['name'] =
            'Masjid Al-Hikmah Raya';
      }),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Pengaturan tersimpan ke TV.'), findsOneWidget);
    expect(find.text('Belum ada perubahan'), findsOneWidget);
    await selesai(tester);
  });

  testWidgets('pengaturan: koordinat tidak sah mengunci tombol Simpan', (
    tester,
  ) async {
    await tampil(tester, LayarPengaturanMasjid(store: store));
    await tester.enterText(fieldLabel('Lintang (latitude)'), '91');
    await tester.pump();
    expect(find.text('Lintang harus antara -90 dan 90.'), findsOneWidget);
    expect(tombolSimpan(tester).onPressed, isNull);

    await tester.enterText(fieldLabel('Bujur (longitude)'), 'abc');
    await tester.pump();
    expect(find.textContaining('Isi dengan angka'), findsOneWidget);
    expect(tombolSimpan(tester).onPressed, isNull);
    expect(paketConfig(), isEmpty);

    // Koma desimal Indonesia diterima.
    await tester.enterText(fieldLabel('Lintang (latitude)'), '-6,1754');
    await tester.enterText(fieldLabel('Bujur (longitude)'), '106,8272');
    await tester.pump();
    expect(find.text('Belum ada perubahan'), findsOneWidget);
    await selesai(tester);
  });

  testWidgets('pengaturan: GPS mengisi koordinat dan menandai berubah', (
    tester,
  ) async {
    await tampil(
      tester,
      LayarPengaturanMasjid(
        store: store,
        pengambilKoordinat: () async =>
            const KoordinatGps(latitude: -6.2, longitude: 106.9),
      ),
    );
    await tester.tap(find.text('Ambil Koordinat dari GPS'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      tester
          .widget<TextField>(fieldLabel('Lintang (latitude)'))
          .controller
          ?.text,
      '-6.2',
    );
    expect(
      tester
          .widget<TextField>(fieldLabel('Bujur (longitude)'))
          .controller
          ?.text,
      '106.9',
    );
    expect(find.textContaining('Koordinat terisi dari GPS'), findsOneWidget);
    expect(find.text('Simpan & Update Ke TV'), findsOneWidget);
    await selesai(tester);
  });

  testWidgets('pengaturan: GPS gagal menampilkan pesan manusiawi', (
    tester,
  ) async {
    await tampil(
      tester,
      LayarPengaturanMasjid(
        store: store,
        pengambilKoordinat: () async =>
            throw Exception('Lokasi HP sedang mati.'),
      ),
    );
    await tester.tap(find.text('Ambil Koordinat dari GPS'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('Lokasi HP sedang mati.'), findsOneWidget);
    expect(find.text('Belum ada perubahan'), findsOneWidget);
    await selesai(tester);
  });

  testWidgets('pengaturan: stepper geser Subuh terkirim di config', (
    tester,
  ) async {
    await tampil(tester, LayarPengaturanMasjid(store: store));
    // Grup Penyesuaian muncul sebelum grup Ikamah: .first = geser.
    await tester.tap(find.byTooltip('Tambah Subuh').first);
    await tester.pump();
    expect(find.text('+3 menit'), findsOneWidget);
    await tester.tap(find.text('Simpan & Update Ke TV'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(configTerakhir()['prayerOffsets']['fajr'], 3);
    transport.terima(
      snapshotDengan((p) {
        ((p['config'] as Map<String, dynamic>)['prayerOffsets']
            as Map<String, dynamic>)['fajr'] = 3;
      }),
    );
    await tester.pump();
    await selesai(tester);
  });

  testWidgets('pengaturan: tanpa Jumat menonaktifkan petugas + khutbah', (
    tester,
  ) async {
    await tampil(tester, LayarPengaturanMasjid(store: store));
    final sakelarJumat = find.ancestor(
      of: find.text('Ada shalat Jumat'),
      matching: find.byType(SwitchListTile),
    );
    await tester.tap(sakelarJumat);
    await tester.pump();
    expect(
      tester.widget<TextField>(fieldLabel('Khatib Jumat')).enabled,
      isFalse,
    );
    expect(
      tester.widget<TextField>(fieldLabel('Muadzin Jumat')).enabled,
      isFalse,
    );
    final tambahKhutbah = tester.widget<IconButton>(
      // IconButton MEMBUNGKUS Tooltip-nya: tombol adalah
      // leluhur tooltip, bukan keturunannya.
      find.ancestor(
        of: find.byTooltip('Tambah Khutbah Jumat (menit)'),
        matching: find.byType(IconButton),
      ),
    );
    expect(tambahKhutbah.onPressed, isNull);
    await selesai(tester);
  });

  testWidgets('pengaturan: snapshot kosong menahan form', (tester) async {
    await tampil(
      tester,
      LayarPengaturanMasjid(store: store),
      denganSnapshot: false,
    );
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Simpan & Update Ke TV'), findsNothing);
    // TV akhirnya menjawab: penunggu snapshot store harus
    // tuntas supaya tidak ada timer menggantung di teardown.
    transport.terima(paketFixture('paket_snapshot_masjid.json'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await selesai(tester);
  });
}
