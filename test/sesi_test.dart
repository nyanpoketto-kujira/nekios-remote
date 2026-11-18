import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nekios_remote/layanan/penyimpanan.dart';
import 'package:nekios_remote/layanan/penyelidik.dart';
import 'package:nekios_remote/masjid/tautan_bt.dart';
import 'package:nekios_remote/model/display_tersimpan.dart';
import 'package:nekios_remote/state/remote_store.dart';
import 'package:nekios_remote/state/sesi.dart';
import 'package:nekios_remote/state/store_masjid.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'klien_palsu.dart';
import 'masjid_palsu.dart';

/// Test orkestrasi sesi (ADR-004): gateway ↔ auto-detect ↔ shell.
/// Memakai store sungguhan di atas klien/transport palsu.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RemoteStore store;
  late MasjidStore storeMasjid;
  late TransportMasjidPalsu transportMasjid;
  late SesiRemote sesi;
  var panggilanSekolah = 0;
  var panggilanMasjid = 0;
  String? jawabanSekolah;
  String? jawabanMasjid;

  Future<void> siapkan({List<Object> daftarAwal = const []}) async {
    SharedPreferences.setMockInitialValues({
      if (daftarAwal.isNotEmpty)
        PenyimpananDisplay.kunciDaftar: jsonEncode(daftarAwal),
    });
    panggilanSekolah = 0;
    panggilanMasjid = 0;
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
    sesi = SesiRemote(
      storeSekolah: store,
      storeMasjid: storeMasjid,
      pendeteksi: PendekteksiDisplay(
        selidikiSekolah: (_) async {
          panggilanSekolah++;
          return jawabanSekolah;
        },
        selidikiMasjid: (_) async {
          panggilanMasjid++;
          return jawabanMasjid;
        },
      ),
    );
  }

  Future<void> bersihkan() async {
    await sesi.putuskan();
    sesi.dispose();
    store.dispose();
    storeMasjid.dispose();
  }

  test('sambungIp: terdeteksi sekolah → masuk + riwayat tersimpan', () async {
    await siapkan();
    jawabanSekolah = 'SMKN 1 Ukui';

    await sesi.sambungIp('192.168.1.20');

    expect(store.terhubung, isTrue);
    expect(sesi.diDalam, isTrue);
    expect(sesi.tipeAktif, TipeDisplay.sekolah);
    expect(sesi.pesan, isNull);
    expect(store.daftarDisplay, hasLength(1));
    final tersimpan = store.daftarDisplay.single;
    expect(tersimpan.nama, 'SMKN 1 Ukui');
    expect(tersimpan.tipe, TipeDisplay.sekolah);
    expect(tersimpan.ip, '192.168.1.20');
    await bersihkan();
  });

  test('sambungIp: terdeteksi masjid → masuk + riwayat tersimpan', () async {
    await siapkan();
    jawabanMasjid = 'Masjid Al-Hikmah';

    await sesi.sambungIp('192.168.1.30');

    expect(storeMasjid.terhubung, isTrue);
    expect(sesi.tipeAktif, TipeDisplay.masjid);
    expect(store.daftarDisplay, hasLength(1));
    final tersimpan = store.daftarDisplay.single;
    expect(tersimpan.nama, 'Masjid Al-Hikmah');
    expect(tersimpan.tipe, TipeDisplay.masjid);
    expect(tersimpan.transport, JalurMasjid.wifi);
    await bersihkan();
  });

  test('sambungIp: tidak terdeteksi → pesan jujur, tanpa riwayat', () async {
    await siapkan();

    await sesi.sambungIp('192.168.1.99');

    expect(sesi.diDalam, isFalse);
    expect(sesi.pesan, contains('Tidak ada display Nekios'));
    expect(store.daftarDisplay, isEmpty);
    expect(panggilanSekolah, 1);
    expect(panggilanMasjid, 1);
    await bersihkan();
  });

  test('sambungIp: IP tersimpan → jalur cepat tanpa deteksi ulang', () async {
    await siapkan(
      daftarAwal: [
        {'nama': 'TV Pameran', 'ip': '192.168.1.20'},
      ],
    );

    await sesi.sambungIp('192.168.1.20');

    expect(store.terhubung, isTrue);
    expect(panggilanSekolah, 0);
    expect(panggilanMasjid, 0);
    expect(store.daftarDisplay, hasLength(1)); // tidak diduplikasi
    await bersihkan();
  });

  test('sambungBluetooth: perangkat baru tersimpan setelah berhasil', () async {
    await siapkan();

    await sesi.sambungBluetooth(
      const PerangkatBt(nama: 'Masjid You TV', alamat: 'AA:BB:CC:DD:EE:FF'),
      '1234',
    );

    expect(storeMasjid.terhubung, isTrue);
    expect(store.daftarDisplay, hasLength(1));
    final tersimpan = store.daftarDisplay.single;
    expect(tersimpan.pakaiBluetooth, isTrue);
    expect(tersimpan.alamatBluetooth, 'AA:BB:CC:DD:EE:FF');
    expect(tersimpan.pinBluetooth, '1234');
    expect(transportMasjid.displayTerakhir?.pinBluetooth, '1234');
    await bersihkan();
  });

  test('putus tak terduga → pemberitahuan + sambung ulang bekerja', () async {
    await siapkan();
    const display = DisplayTersimpan(
      nama: 'TV Masjid Wi-Fi',
      ip: '192.168.1.30',
      tipe: TipeDisplay.masjid,
    );
    await sesi.sambungDisplay(display);
    expect(sesi.diDalam, isTrue);
    expect(sesi.pesan, isNull);

    transportMasjid.picuKesalahan('Koneksi Wi-Fi ke TV masjid terputus.');
    // Beri kesempatan rantai listener berjalan.
    await Future<void>.delayed(Duration.zero);

    expect(sesi.diDalam, isFalse);
    expect(sesi.pesan, 'Koneksi Wi-Fi ke TV masjid terputus.');
    expect(sesi.displayTerakhir?.nama, 'TV Masjid Wi-Fi');

    await sesi.sambungUlang();
    expect(storeMasjid.terhubung, isTrue);
    expect(sesi.diDalam, isTrue);
    await bersihkan();
  });

  test('putuskan sengaja → kembali bersih tanpa pemberitahuan', () async {
    await siapkan();
    jawabanSekolah = 'SMKN 1 Ukui';
    await sesi.sambungIp('192.168.1.20');
    expect(sesi.diDalam, isTrue);

    await sesi.putuskan();

    expect(sesi.diDalam, isFalse);
    expect(sesi.pesan, isNull);
    await bersihkan();
  });
}
