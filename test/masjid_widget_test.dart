import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nekios_remote/app.dart';
import 'package:nekios_remote/layanan/penyimpanan.dart';
import 'package:nekios_remote/masjid/paket_masjid.dart';
import 'package:nekios_remote/model/display_tersimpan.dart';
import 'package:nekios_remote/state/remote_store.dart';
import 'package:nekios_remote/state/store_masjid.dart';
import 'package:nekios_remote/tema.dart';
import 'package:nekios_remote/ui/layar_beranda_masjid.dart';
import 'package:nekios_remote/ui/layar_koneksi.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'klien_palsu.dart';
import 'masjid_palsu.dart';

SyncPacket paketFixture(String nama) =>
    SyncPacket.fromJson(File('test/fixtures/$nama').readAsStringSync());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RemoteStore store;
  late MasjidStore storeMasjid;
  late TransportMasjidPalsu transportMasjid;
  late TautanBluetoothPalsu tautan;

  Future<void> siapkan(WidgetTester tester) async {
    // Viewport tinggi: seluruh isi ListView (kartu-kartu display /
    // kas / konten) ikut terbangun sehingga bisa ditemukan & diketuk.
    tester.view.physicalSize = const Size(1080, 3400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      PenyimpananDisplay.kunciDaftar: jsonEncode([
        {'nama': 'TV Pameran', 'ip': '192.168.1.20'},
        {
          'nama': 'TV Masjid Wi-Fi',
          'ip': '192.168.1.30',
          'tipe': 'masjid',
          'transport': 'wifi',
        },
        {
          'nama': 'TV Masjid BT',
          'ip': '',
          'tipe': 'masjid',
          'transport': 'bluetooth',
          'alamatBluetooth': 'AA:BB:CC:DD:EE:FF',
          'namaBluetooth': 'Masjid You TV',
          'pinBluetooth': '1234',
        },
      ]),
    });
    store = RemoteStore(
      klien: KlienPalsu(),
      penyimpanan: PenyimpananDisplay(await SharedPreferences.getInstance()),
      jedaPing: const Duration(minutes: 5),
    );
    transportMasjid = TransportMasjidPalsu();
    tautan = TautanBluetoothPalsu();
    storeMasjid = MasjidStore(
      buatTransport: (_) => transportMasjid,
      batasBukti: const Duration(seconds: 5),
    );
  }

  Future<void> bersihkan(WidgetTester tester) async {
    await store.putuskan();
    store.dispose();
    await storeMasjid.putuskan();
    storeMasjid.dispose();
    await tester.pumpWidget(const SizedBox());
  }

  Widget bungkus(Widget anak) => MaterialApp(
    theme: temaNekios(Brightness.light),
    home: Scaffold(body: anak),
  );

  testWidgets('koneksi: display masjid tampil bertipe & ketuk menyambung', (
    tester,
  ) async {
    await siapkan(tester);
    await tester.pumpWidget(
      bungkus(
        LayarKoneksi(store: store, storeMasjid: storeMasjid, tautan: tautan),
      ),
    );
    await tester.pump();

    expect(find.text('Masjid · Wi-Fi · 192.168.1.30:8080'), findsOneWidget);
    expect(
      find.text('Masjid · Bluetooth · Masjid You TV · AA:BB:CC:DD:EE:FF'),
      findsOneWidget,
    );
    expect(find.text('Sekolah · 192.168.1.20:8920'), findsOneWidget);

    await tester.tap(find.text('TV Masjid Wi-Fi'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(storeMasjid.terhubung, isTrue);
    expect(transportMasjid.displayTerakhir?.nama, 'TV Masjid Wi-Fi');
    expect(find.textContaining('Terhubung ke TV masjid'), findsOneWidget);

    await bersihkan(tester);
  });

  testWidgets('beranda masjid: cermin fase + kas + aksi cepat berkonfirmasi', (
    tester,
  ) async {
    await siapkan(tester);
    const display = DisplayTersimpan(
      nama: 'TV Masjid Wi-Fi',
      ip: '192.168.1.30',
      tipe: TipeDisplay.masjid,
    );
    await storeMasjid.sambungkan(display);
    transportMasjid.terima(paketFixture('paket_snapshot_masjid.json'));
    transportMasjid.terima(paketFixture('paket_state_update_masjid.json'));
    await tester.pumpWidget(bungkus(LayarBerandaMasjid(store: storeMasjid)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Masjid Al-Hikmah'), findsOneWidget);
    expect(find.text('Jeda Ikamah'), findsOneWidget);
    expect(find.text('Shalat Dzuhur'), findsOneWidget);
    expect(find.text('Rp1.750.000'), findsOneWidget);
    expect(find.text('Lewati Azan'), findsOneWidget);
    expect(find.text('STANDBY'), findsOneWidget);

    // Aksi fase wajib konfirmasi; setelah disetujui paket terkirim
    // dan bukti susulan (stateUpdate) menutupnya dengan sukses.
    await tester.tap(find.text('Mulai Ikamah'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Mulai ikamah sekarang?'), findsOneWidget);
    await tester.tap(find.text('Kirim'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      transportMasjid.terkirim.map((p) => p.action),
      contains(SyncAction.startIqomah),
    );
    transportMasjid.terima(paketFixture('paket_state_update_masjid.json'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Perintah mulai ikamah terkirim.'), findsOneWidget);

    await bersihkan(tester);
  });

  testWidgets('beranda masjid saat terputus menampilkan ajakan', (
    tester,
  ) async {
    await siapkan(tester);
    await tester.pumpWidget(bungkus(LayarBerandaMasjid(store: storeMasjid)));
    await tester.pump();
    expect(find.text('Belum terhubung ke display'), findsOneWidget);
    await bersihkan(tester);
  });

  testWidgets('shell utama beralih ke masjid saat display masjid menyambung', (
    tester,
  ) async {
    await siapkan(tester);
    await tester.pumpWidget(
      NekiosRemoteApp(store: store, storeMasjid: storeMasjid, tautan: tautan),
    );
    await tester.pump();
    // Shell sekolah: ada tab Jadwal, tidak ada tab Konten. (Ikon —
    // label NavigationBar hanya tampil untuk tab terpilih.)
    expect(find.byIcon(Icons.calendar_month_outlined), findsOneWidget);
    expect(find.byIcon(Icons.article_outlined), findsNothing);

    const display = DisplayTersimpan(
      nama: 'TV Masjid Wi-Fi',
      ip: '192.168.1.30',
      tipe: TipeDisplay.masjid,
    );
    await storeMasjid.sambungkan(display);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Shell masjid: tab Konten/Pengaturan/Tes menggantikan tab sekolah.
    expect(find.byIcon(Icons.article_outlined), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsWidgets);
    expect(find.byIcon(Icons.calendar_month_outlined), findsNothing);

    await bersihkan(tester);
  });
}
