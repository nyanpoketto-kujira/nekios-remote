import 'package:flutter_test/flutter_test.dart';
import 'package:nekios_remote/domain/perintah.dart';
import 'package:nekios_remote/layanan/penyimpanan.dart';
import 'package:nekios_remote/model/display_tersimpan.dart';
import 'package:nekios_remote/state/remote_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'klien_palsu.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late KlienPalsu klien;
  late RemoteStore store;

  Future<RemoteStore> buatStore({
    Duration batas = const Duration(seconds: 6),
  }) async {
    SharedPreferences.setMockInitialValues({});
    klien = KlienPalsu();
    store = RemoteStore(
      klien: klien,
      penyimpanan: PenyimpananDisplay(await SharedPreferences.getInstance()),
      jedaPing: const Duration(minutes: 5),
      batasBalasan: batas,
    );
    return store;
  }

  tearDown(() async {
    await store.putuskan();
    store.dispose();
  });

  test(
    'sambungkan: terhubung, snapshot perdana masuk, IP ter-auto-save',
    () async {
      final s = await buatStore();
      await s.sambungkan(
        const DisplayTersimpan(nama: 'TV Pameran', ip: '192.168.1.20'),
      );
      // Balasan fake tiba lewat microtask; beri satu putaran event loop.
      await Future<void>.delayed(Duration.zero);
      expect(s.statusKoneksi, StatusKoneksi.terhubung);
      expect(s.snapshot, isNotNull);
      expect(s.snapshot!.statusMentah, 'pelajaran');
      expect(s.waktuSnapshot, isNotNull);
      expect(s.ipTerakhir, '192.168.1.20');
      expect(klien.terkirim.first.type, 'ping');
    },
  );

  test('sambungkan gagal: status terputus + pesan manusiawi', () async {
    final s = await buatStore();
    klien.gagalSambung = true;
    await s.sambungkan(const DisplayTersimpan(nama: 'TV', ip: '192.168.1.99'));
    expect(s.statusKoneksi, StatusKoneksi.terputus);
    expect(s.pesanKoneksi, isNotNull);
    expect(s.pesanKoneksi, contains('menolak sambungan'));
  });

  test('perintah berhasil diselesaikan oleh ack', () async {
    final s = await buatStore();
    await s.sambungkan(const DisplayTersimpan(nama: 'TV', ip: '192.168.1.20'));
    final hasil = await s.kirimPerintah(perintahAturMading('Halo TV'));
    expect(hasil.sukses, isTrue);
    expect(klien.terkirim.last.type, 'mading.set');
  });

  test('perintah gagal membawa pesan error dari display', () async {
    final s = await buatStore();
    await s.sambungkan(const DisplayTersimpan(nama: 'TV', ip: '192.168.1.20'));
    klien.balasError = true;
    klien.pesanError = 'Jadwal tidak valid: slot tumpang tindih.';
    final hasil = await s.kirimPerintah(perintahAturMading('Halo'));
    expect(hasil.sukses, isFalse);
    expect(hasil.pesan, 'Jadwal tidak valid: slot tumpang tindih.');
  });

  test('perintah tanpa balasan gagal karena timeout', () async {
    final s = await buatStore(batas: const Duration(milliseconds: 100));
    await s.sambungkan(const DisplayTersimpan(nama: 'TV', ip: '192.168.1.20'));
    klien.senyap = true;
    final hasil = await s.kirimPerintah(perintahAturMading('Halo'));
    expect(hasil.sukses, isFalse);
    expect(hasil.pesan, contains('tidak menjawab'));
  });

  test('perintah saat terputus langsung gagal', () async {
    final s = await buatStore();
    final hasil = await s.kirimPerintah(perintahAturMading('Halo'));
    expect(hasil.sukses, isFalse);
    expect(hasil.pesan, contains('Belum terhubung'));
  });
}
