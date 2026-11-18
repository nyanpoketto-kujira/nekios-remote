import 'package:flutter_test/flutter_test.dart';
import 'package:nekios_remote/model/display_tersimpan.dart';

void main() {
  group('DisplayTersimpan', () {
    test('entri lama tanpa tipe dibaca sebagai sekolah Wi-Fi', () {
      final lama = DisplayTersimpan.fromJson(const {
        'nama': 'TV Pameran',
        'ip': '192.168.1.20',
      });
      expect(lama.tipe, TipeDisplay.sekolah);
      expect(lama.transport, JalurMasjid.wifi);
      expect(lama.adalahMasjid, isFalse);
      expect(lama.pakaiBluetooth, isFalse);
      expect(lama.alamatRingkas, '192.168.1.20');
    });

    test('display masjid Bluetooth pulang-pergi utuh', () {
      const display = DisplayTersimpan(
        nama: 'TV Masjid',
        ip: '',
        tipe: TipeDisplay.masjid,
        transport: JalurMasjid.bluetooth,
        alamatBluetooth: 'AA:BB:CC:DD:EE:FF',
        namaBluetooth: 'Masjid You TV',
        pinBluetooth: '1234',
      );
      final lagi = DisplayTersimpan.fromJson(display.toJson());
      expect(lagi, display);
      expect(lagi.pakaiBluetooth, isTrue);
      expect(lagi.alamatRingkas, 'Masjid You TV · AA:BB:CC:DD:EE:FF');
    });

    test('display masjid Wi-Fi memakai ip + port warisan', () {
      const display = DisplayTersimpan(
        nama: 'TV Masjid',
        ip: '192.168.1.30',
        tipe: TipeDisplay.masjid,
      );
      expect(display.adalahMasjid, isTrue);
      expect(display.pakaiBluetooth, isFalse);
      expect(display.alamatRingkas, '192.168.1.30');
      expect(DisplayTersimpan.fromJson(display.toJson()), display);
    });

    test('tipe/transport rusak jatuh ke bawaan aman', () {
      final rusak = DisplayTersimpan.fromJson(const {
        'nama': 'X',
        'ip': '1.2.3.4',
        'tipe': 'proyektor',
        'transport': 'kabel',
      });
      expect(rusak.tipe, TipeDisplay.sekolah);
      expect(rusak.transport, JalurMasjid.wifi);
    });
  });
}
