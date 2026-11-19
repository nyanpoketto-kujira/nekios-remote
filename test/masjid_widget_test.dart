import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nekios_remote/app.dart';
import 'package:nekios_remote/layanan/penyimpanan.dart';
import 'package:nekios_remote/layanan/penyelidik.dart';
import 'package:nekios_remote/masjid/paket_masjid.dart';
import 'package:nekios_remote/model/display_tersimpan.dart';
import 'package:nekios_remote/state/remote_store.dart';
import 'package:nekios_remote/state/sesi.dart';
import 'package:nekios_remote/state/store_masjid.dart';
import 'package:nekios_remote/tema.dart';
import 'package:nekios_remote/ui/layar_beranda_masjid.dart';
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
  late SesiRemote sesi;

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
    sesi = SesiRemote(
      storeSekolah: store,
      storeMasjid: storeMasjid,
      pendeteksi: PendekteksiDisplay(
        selidikiSekolah: (_) async => null,
        selidikiMasjid: (_) async => null,
      ),
    );
  }

  Future<void> bersihkan(WidgetTester tester) async {
    await sesi.putuskan();
    sesi.dispose();
    store.dispose();
    storeMasjid.dispose();
    await tester.pumpWidget(const SizedBox());
  }

  Widget bungkus(Widget anak) => MaterialApp(
    theme: temaNekios(Brightness.light),
    home: Scaffold(body: anak),
  );

  testWidgets('gateway: display masjid tampil bertipe & ketuk menyambung', (
    tester,
  ) async {
    await siapkan(tester);
    await tester.pumpWidget(
      NekiosRemoteApp(
        store: store,
        storeMasjid: storeMasjid,
        sesi: sesi,
        tautan: tautan,
      ),
    );
    await tester.pump();

    expect(find.text('Masjid · Wi-Fi · 192.168.1.30:8080'), findsOneWidget);
    expect(
      find.text('Masjid · Bluetooth · Masjid You TV · AA:BB:CC:DD:EE:FF'),
      findsOneWidget,
    );
    expect(find.text('Sekolah · Wi-Fi · 192.168.1.20:8920'), findsOneWidget);

    await tester.tap(find.text('TV Masjid Wi-Fi'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(storeMasjid.terhubung, isTrue);
    expect(transportMasjid.displayTerakhir?.nama, 'TV Masjid Wi-Fi');
    expect(find.textContaining('Terhubung ke TV Masjid Wi-Fi'), findsOneWidget);

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

  testWidgets('beranda masjid: pemberitahuan data contoh berbahasa awam', (
    tester,
  ) async {
    await siapkan(tester);
    const display = DisplayTersimpan(
      nama: 'TV Masjid Wi-Fi',
      ip: '192.168.1.30',
      tipe: TipeDisplay.masjid,
    );
    await storeMasjid.sambungkan(display);
    // Snapshot yang sama dengan fixture, tetapi hasData = false
    // (TV baru / setelah reset — masih berisi data contoh bawaan).
    final mentah =
        jsonDecode(
              File(
                'test/fixtures/paket_snapshot_masjid.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    (mentah['payload'] as Map<String, dynamic>)['hasData'] = false;
    transportMasjid.terima(SyncPacket.fromJson(jsonEncode(mentah)));
    transportMasjid.terima(paketFixture('paket_state_update_masjid.json'));
    await tester.pumpWidget(bungkus(LayarBerandaMasjid(store: storeMasjid)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('TV masih memakai data contoh'), findsOneWidget);
    expect(find.textContaining('belum data masjid Anda'), findsOneWidget);
    // Bahasa teknis internal tidak boleh bocor ke pengguna awam.
    expect(find.textContaining('hasData'), findsNothing);
    expect(find.textContaining('Snapshot'), findsNothing);

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

  testWidgets('guard: gateway menahan shell, masjid menyambung → shell masjid', (
    tester,
  ) async {
    await siapkan(tester);
    await tester.pumpWidget(
      NekiosRemoteApp(
        store: store,
        storeMasjid: storeMasjid,
        sesi: sesi,
        tautan: tautan,
      ),
    );
    await tester.pump();
    // Guard (ADR-004): sebelum ada koneksi hanya gateway yang tampil —
    // tidak ada tab sekolah maupun masjid.
    expect(find.text('Selamat Datang di Nekios Remote'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byIcon(Icons.calendar_month_outlined), findsNothing);
    expect(find.byIcon(Icons.article_outlined), findsNothing);

    const display = DisplayTersimpan(
      nama: 'TV Masjid Wi-Fi',
      ip: '192.168.1.30',
      tipe: TipeDisplay.masjid,
    );
    await storeMasjid.sambungkan(display);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Shell masjid: tab Konten/Pengaturan/Tes menggantikan gateway.
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byIcon(Icons.article_outlined), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsWidgets);
    expect(find.byIcon(Icons.calendar_month_outlined), findsNothing);

    await bersihkan(tester);
  });

  testWidgets('shell masjid: tab Tes membuka layar Tes sungguhan (A2a)', (
    tester,
  ) async {
    await siapkan(tester);
    await tester.pumpWidget(
      NekiosRemoteApp(
        store: store,
        storeMasjid: storeMasjid,
        sesi: sesi,
        tautan: tautan,
      ),
    );
    await tester.pump();

    const display = DisplayTersimpan(
      nama: 'TV Masjid Wi-Fi',
      ip: '192.168.1.30',
      tipe: TipeDisplay.masjid,
    );
    await storeMasjid.sambungkan(display);
    transportMasjid.terima(paketFixture('paket_snapshot_masjid.json'));
    transportMasjid.terima(paketFixture('paket_state_update_masjid.json'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Tes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Menu Tes — Simulasi Waktu Shalat'), findsOneWidget);
    expect(find.text('Paksa Fase — Hari Biasa'), findsOneWidget);
    expect(find.text('Paksa Fase — Hari Jumat'), findsOneWidget);
    expect(find.text('Tes masjid — tahap berikutnya'), findsNothing);

    await bersihkan(tester);
  });

  testWidgets('shell masjid: tab Konten membuka kerangka sub-tab (A2b)', (
    tester,
  ) async {
    await siapkan(tester);
    await tester.pumpWidget(
      NekiosRemoteApp(
        store: store,
        storeMasjid: storeMasjid,
        sesi: sesi,
        tautan: tautan,
      ),
    );
    await tester.pump();

    const display = DisplayTersimpan(
      nama: 'TV Masjid Wi-Fi',
      ip: '192.168.1.30',
      tipe: TipeDisplay.masjid,
    );
    await storeMasjid.sambungkan(display);
    transportMasjid.terima(paketFixture('paket_snapshot_masjid.json'));
    transportMasjid.terima(paketFixture('paket_state_update_masjid.json'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Konten'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Kerangka Konten: sub-tab Teks Berjalan aktif berisi editor
    // yang ter-seed dari snapshot; teks placeholder lama hilang.
    expect(
      find.descendant(
        of: find.byType(TabBar),
        matching: find.text('Teks Berjalan'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(TabBar),
        matching: find.text('Banner'),
      ),
      findsOneWidget,
    );
    expect(find.text('Kajian rutin Sabtu'), findsOneWidget);
    expect(
      find.textContaining('Fitur untuk mengatur teks berjalan, banner'),
      findsNothing,
    );

    await bersihkan(tester);
  });
}
