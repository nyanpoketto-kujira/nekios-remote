import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nekios_remote/app.dart';
import 'package:nekios_remote/layanan/penyimpanan.dart';
import 'package:nekios_remote/layanan/penyelidik.dart';
import 'package:nekios_remote/state/remote_store.dart';
import 'package:nekios_remote/state/sesi.dart';
import 'package:nekios_remote/state/store_masjid.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'klien_palsu.dart';
import 'masjid_palsu.dart';

/// Test gateway & shell dinamis (ADR-004) lewat aplikasi utuh:
/// guard menahan dashboard saat terputus, deteksi IP menentukan
/// shell, putus mengembalikan ke gateway.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RemoteStore store;
  late MasjidStore storeMasjid;
  late TransportMasjidPalsu transportMasjid;
  late TautanBluetoothPalsu tautan;
  late SesiRemote sesi;
  String? jawabanSekolah;
  String? jawabanMasjid;

  Future<void> siapkan(WidgetTester tester) async {
    // Viewport tinggi: seluruh isi gateway (ListView) ikut terbangun.
    tester.view.physicalSize = const Size(1080, 3400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      PenyimpananDisplay.kunciDaftar: jsonEncode([
        {'nama': 'TV Pameran', 'ip': '192.168.1.20'},
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
      PenyimpananDisplay.kunciIpTerakhir: '192.168.1.20',
    });
    jawabanSekolah = null;
    jawabanMasjid = null;
    store = RemoteStore(
      klien: KlienPalsu(),
      penyimpanan: PenyimpananDisplay(await SharedPreferences.getInstance()),
      jedaPing: const Duration(minutes: 5),
    );
    transportMasjid = TransportMasjidPalsu();
    storeMasjid = MasjidStore(
      buatTransport: (_) => transportMasjid,
      batasBukti: const Duration(milliseconds: 500),
    );
    tautan = TautanBluetoothPalsu();
    sesi = SesiRemote(
      storeSekolah: store,
      storeMasjid: storeMasjid,
      pendeteksi: PendekteksiDisplay(
        selidikiSekolah: (_) async => jawabanSekolah,
        selidikiMasjid: (_) async => jawabanMasjid,
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

  Widget aplikasi() => NekiosRemoteApp(
    store: store,
    storeMasjid: storeMasjid,
    sesi: sesi,
    tautan: tautan,
  );

  testWidgets('terputus: hanya gateway, dashboard tertahan', (tester) async {
    await siapkan(tester);
    await tester.pumpWidget(aplikasi());
    await tester.pump();

    expect(find.text('Selamat Datang di Nekios Remote'), findsOneWidget);
    expect(find.text('Koneksi Bluetooth'), findsOneWidget);
    expect(find.text('Koneksi Wi-Fi'), findsOneWidget);
    expect(find.text('Perangkat Dikenal'), findsOneWidget);
    expect(find.text('TV Masjid BT'), findsOneWidget);
    expect(find.text('TV Pameran'), findsOneWidget);
    // Guard: tidak ada bilah navigasi dashboard sama sekali.
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Sambungkan'), findsOneWidget);

    await bersihkan(tester);
  });

  testWidgets('ketuk display sekolah tersimpan → shell sekolah', (
    tester,
  ) async {
    await siapkan(tester);
    await tester.pumpWidget(aplikasi());
    await tester.pump();

    await tester.tap(find.text('TV Pameran'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(store.terhubung, isTrue);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.textContaining('Terhubung ke TV Pameran'), findsOneWidget);
    expect(find.text('Putuskan'), findsOneWidget);
    expect(find.byIcon(Icons.calendar_month_outlined), findsOneWidget);
    expect(find.text('Selamat Datang di Nekios Remote'), findsNothing);

    await bersihkan(tester);
  });

  testWidgets('putuskan dari strip → kembali ke gateway', (tester) async {
    await siapkan(tester);
    await tester.pumpWidget(aplikasi());
    await tester.pump();
    await tester.tap(find.text('TV Pameran'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(NavigationBar), findsOneWidget);

    await tester.tap(find.text('Putuskan'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(store.terhubung, isFalse);
    expect(find.text('Selamat Datang di Nekios Remote'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    // Putus sengaja: tanpa pemberitahuan kesalahan.
    expect(find.textContaining('terputus.'), findsNothing);

    await bersihkan(tester);
  });

  testWidgets('IP baru terdeteksi masjid → shell masjid', (tester) async {
    await siapkan(tester);
    jawabanMasjid = 'Masjid Al-Hikmah';
    await tester.pumpWidget(aplikasi());
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, '192.168.1.77');
    await tester.tap(find.text('Sambungkan'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(storeMasjid.terhubung, isTrue);
    expect(find.byIcon(Icons.article_outlined), findsOneWidget);
    expect(find.textContaining('Terhubung ke Masjid Al-Hikmah'), findsOneWidget);
    // Riwayat bertambah dari hasil deteksi.
    expect(
      store.daftarDisplay.any(
        (d) => d.ip == '192.168.1.77' && d.nama == 'Masjid Al-Hikmah',
      ),
      isTrue,
    );

    await bersihkan(tester);
  });

  testWidgets('deteksi gagal → pesan jujur, tetap di gateway', (tester) async {
    await siapkan(tester);
    await tester.pumpWidget(aplikasi());
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, '192.168.1.99');
    await tester.tap(find.text('Sambungkan'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(NavigationBar), findsNothing);
    expect(
      find.textContaining('Tidak ada display Nekios yang menjawab'),
      findsOneWidget,
    );

    await bersihkan(tester);
  });

  testWidgets('putus tak terduga → gateway + pemberitahuan + sambung ulang', (
    tester,
  ) async {
    await siapkan(tester);
    await tester.pumpWidget(aplikasi());
    await tester.pump();

    // Masuk lewat display BT dikenal (PIN tersimpan, tanpa dialog).
    await tester.tap(find.text('TV Masjid BT'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(storeMasjid.terhubung, isTrue);
    expect(find.byType(NavigationBar), findsOneWidget);

    transportMasjid.picuKesalahan('Koneksi Bluetooth ke TV masjid terputus.');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Selamat Datang di Nekios Remote'), findsOneWidget);
    expect(
      find.textContaining('Koneksi Bluetooth ke TV masjid terputus.'),
      findsOneWidget,
    );
    expect(find.text('Sambungkan ulang'), findsOneWidget);

    await tester.tap(find.text('Sambungkan ulang'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(storeMasjid.terhubung, isTrue);
    expect(find.byType(NavigationBar), findsOneWidget);

    await bersihkan(tester);
  });
}
