import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nekios_remote/layanan/penyimpanan.dart';
import 'package:nekios_remote/state/remote_store.dart';
import 'package:nekios_remote/state/store_masjid.dart';
import 'package:nekios_remote/tema.dart';
import 'package:nekios_remote/ui/layar_beranda.dart';
import 'package:nekios_remote/ui/layar_koneksi.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'klien_palsu.dart';
import 'masjid_palsu.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late KlienPalsu klien;
  late RemoteStore store;
  late MasjidStore storeMasjid;
  late TautanBluetoothPalsu tautan;

  Future<void> siapkan(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      PenyimpananDisplay.kunciDaftar: jsonEncode([
        {'nama': 'TV Pameran', 'ip': '192.168.1.20'},
      ]),
      PenyimpananDisplay.kunciIpTerakhir: '192.168.1.20',
    });
    klien = KlienPalsu();
    store = RemoteStore(
      klien: klien,
      penyimpanan: PenyimpananDisplay(await SharedPreferences.getInstance()),
      jedaPing: const Duration(minutes: 5),
    );
    tautan = TautanBluetoothPalsu();
    storeMasjid = MasjidStore(buatTransport: (_) => TransportMasjidPalsu());
  }

  Future<void> bersihkan(WidgetTester tester) async {
    await store.putuskan();
    store.dispose();
    await storeMasjid.putuskan();
    storeMasjid.dispose();
    await tester.pumpWidget(const SizedBox());
  }

  testWidgets('layar koneksi: display tersimpan tampil, ketuk menyambung', (
    tester,
  ) async {
    await siapkan(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: temaNekios(Brightness.light),
        home: Scaffold(
          body: LayarKoneksi(
            store: store,
            storeMasjid: storeMasjid,
            tautan: tautan,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('TV Pameran'), findsOneWidget);
    expect(find.text('Sekolah · 192.168.1.20:8920'), findsOneWidget);
    expect(find.text('Terputus'), findsWidgets);

    await tester.tap(find.text('TV Pameran'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(store.terhubung, isTrue);
    expect(find.text('Terhubung'), findsWidgets);

    await bersihkan(tester);
  });

  testWidgets('layar beranda: cermin snapshot + badge SIMULASI', (
    tester,
  ) async {
    await siapkan(tester);
    await store.sambungkan(store.daftarDisplay.first);
    await tester.pumpWidget(
      MaterialApp(
        theme: temaNekios(Brightness.light),
        home: Scaffold(body: LayarBeranda(store: store)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Pelajaran — Jam ke-3'), findsOneWidget);
    expect(find.text('SIMULASI'), findsOneWidget);
    expect(find.text('Selamat datang di pameran!'), findsOneWidget);
    expect(find.text('Logo terpasang di TV'), findsOneWidget);
    expect(find.text('Bel berikutnya'), findsOneWidget);

    await bersihkan(tester);
  });

  testWidgets('layar beranda saat terputus menampilkan ajakan menyambung', (
    tester,
  ) async {
    await siapkan(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: temaNekios(Brightness.light),
        home: Scaffold(body: LayarBeranda(store: store)),
      ),
    );
    await tester.pump();
    expect(find.text('Belum terhubung ke display'), findsOneWidget);
    await bersihkan(tester);
  });
}
