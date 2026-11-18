import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nekios_remote/masjid/bingkai_bt.dart';
import 'package:nekios_remote/masjid/model_masjid.dart';
import 'package:nekios_remote/masjid/paket_masjid.dart';
import 'package:nekios_remote/masjid/tautan_bt.dart';
import 'package:nekios_remote/masjid/transfer_chunk.dart';
import 'package:nekios_remote/masjid/transport_masjid_bt.dart';
import 'package:nekios_remote/model/display_tersimpan.dart';

import 'masjid_palsu.dart';

const displayBt = DisplayTersimpan(
  nama: 'TV Masjid',
  ip: '',
  tipe: TipeDisplay.masjid,
  transport: JalurMasjid.bluetooth,
  alamatBluetooth: 'AA:BB:CC:DD:EE:FF',
  namaBluetooth: 'Masjid You TV',
  pinBluetooth: '1234',
);

Uint8List bingkaiDari(SyncPacket paket) =>
    bingkaiBtEncode(utf8.encode(paket.toJson()));

Future<void> jeda() => Future<void>.delayed(Duration.zero);

/// Jalankan urutan handshake sampai authSuccess; mengembalikan
/// transport yang sudah terhubung penuh.
Future<TransportMasjidBt> sambungSampaiAuth(
  TautanBluetoothPalsu tautan, {
  bool tanpaKompresi = false,
}) async {
  final transport = TransportMasjidBt(
    tautan,
    kirimTanpaKompresiLatar: tanpaKompresi,
    batasSambung: const Duration(seconds: 5),
    batasAuth: const Duration(seconds: 5),
  );
  final masa = transport.sambung(displayBt);
  await jeda();
  tautan.picu(
    const BtTerhubung(PerangkatBt(nama: 'Masjid You TV', alamat: 'AA:BB')),
  );
  await jeda();
  tautan.picu(
    BtData(
      bingkaiDari(
        const SyncPacket(
          action: SyncAction.authChallenge,
          payload: {'nonce': 'nonce-uji-1'},
        ),
      ),
    ),
  );
  await jeda();
  tautan.picu(
    BtData(
      bingkaiDari(
        const SyncPacket(action: SyncAction.authSuccess, payload: {}),
      ),
    ),
  );
  await masa;
  return transport;
}

void main() {
  late TautanBluetoothPalsu tautan;

  setUp(() => tautan = TautanBluetoothPalsu());

  group('handshake auth (algoritma bluetooth_sync)', () {
    test('challenge dijawab authResponse berisi PIN + nonce gema', () async {
      final transport = await sambungSampaiAuth(tautan);
      expect(transport.terhubung, isTrue);
      expect(tautan.alamatTerakhir, 'AA:BB:CC:DD:EE:FF');
      final terkirim = tautan.paketTerkirim;
      expect(terkirim, hasLength(1));
      expect(terkirim.single.action, SyncAction.authResponse);
      expect(terkirim.single.payload, {'pin': '1234', 'nonce': 'nonce-uji-1'});
      await transport.putus();
    });

    test('authFailure menggagalkan sambung dengan pesan PIN', () async {
      final transport = TransportMasjidBt(
        tautan,
        batasSambung: const Duration(seconds: 5),
        batasAuth: const Duration(seconds: 5),
      );
      final masa = transport.sambung(displayBt);
      await jeda();
      tautan.picu(const BtTerhubung(PerangkatBt(nama: 'TV', alamat: 'AA:BB')));
      await jeda();
      tautan.picu(
        BtData(
          bingkaiDari(
            const SyncPacket(
              action: SyncAction.authChallenge,
              payload: {'nonce': 'n2'},
            ),
          ),
        ),
      );
      await jeda();
      tautan.picu(
        BtData(
          bingkaiDari(
            const SyncPacket(
              action: SyncAction.authFailure,
              payload: {'error': 'PIN salah (percobaan 1 dari 3).'},
            ),
          ),
        ),
      );
      await expectLater(
        masa,
        throwsA(
          predicate(
            (e) => e.toString().contains('Autentikasi Bluetooth gagal'),
          ),
        ),
      );
      expect(transport.terhubung, isFalse);
    });

    test('PIN kosong: challenge tidak dijawab, sambung gagal jelas', () async {
      const tanpaPin = DisplayTersimpan(
        nama: 'TV Masjid',
        ip: '',
        tipe: TipeDisplay.masjid,
        transport: JalurMasjid.bluetooth,
        alamatBluetooth: 'AA:BB:CC:DD:EE:FF',
      );
      final transport = TransportMasjidBt(
        tautan,
        batasSambung: const Duration(seconds: 5),
        batasAuth: const Duration(seconds: 5),
      );
      final masa = transport.sambung(tanpaPin);
      await jeda();
      tautan.picu(const BtTerhubung(PerangkatBt(nama: 'TV', alamat: 'AA:BB')));
      await jeda();
      tautan.picu(
        BtData(
          bingkaiDari(
            const SyncPacket(
              action: SyncAction.authChallenge,
              payload: {'nonce': 'n3'},
            ),
          ),
        ),
      );
      await expectLater(
        masa,
        throwsA(
          predicate((e) => e.toString().contains('PIN Bluetooth belum diisi')),
        ),
      );
      expect(tautan.paketTerkirim, isEmpty);
    });

    test('paket data SEBELUM authSuccess dibuang', () async {
      final transport = TransportMasjidBt(
        tautan,
        batasSambung: const Duration(seconds: 5),
        batasAuth: const Duration(seconds: 5),
      );
      final diterima = <SyncPacket>[];
      final sub = transport.paketMasuk.listen(diterima.add);
      addTearDown(sub.cancel);
      final masa = transport.sambung(displayBt);
      await jeda();
      tautan.picu(const BtTerhubung(PerangkatBt(nama: 'TV', alamat: 'AA:BB')));
      await jeda();
      // TV nakal/terlalu cepat: snapshot sebelum handshake selesai.
      tautan.picu(
        BtData(
          bingkaiDari(
            SyncPacket(
              action: SyncAction.stateSnapshot,
              payload: const StateSnapshot().toMap(),
            ),
          ),
        ),
      );
      await jeda();
      expect(diterima, isEmpty);
      // Selesaikan handshake; snapshot berikutnya lolos.
      tautan.picu(
        BtData(
          bingkaiDari(
            const SyncPacket(
              action: SyncAction.authChallenge,
              payload: {'nonce': 'n4'},
            ),
          ),
        ),
      );
      await jeda();
      tautan.picu(
        BtData(
          bingkaiDari(
            const SyncPacket(action: SyncAction.authSuccess, payload: {}),
          ),
        ),
      );
      await masa;
      tautan.picu(
        BtData(
          bingkaiDari(
            SyncPacket(
              action: SyncAction.stateSnapshot,
              payload: const StateSnapshot().toMap(),
            ),
          ),
        ),
      );
      await jeda();
      expect(diterima, hasLength(1));
      await transport.putus();
    });
  });

  group('kirim & terima setelah auth', () {
    test('paket kecil keluar sebagai SATU bingkai utuh', () async {
      final transport = await sambungSampaiAuth(tautan);
      tautan.byteTerkirim.clear();
      transport.kirim(
        const SyncPacket(action: SyncAction.setMuted, payload: {'muted': true}),
      );
      await jeda();
      final terkirim = tautan.paketTerkirim;
      expect(terkirim, hasLength(1));
      expect(terkirim.single.action, SyncAction.setMuted);
      expect(terkirim.single.payload, {'muted': true});
      await transport.putus();
    });

    test('paket besar keluar ter-chunk & terangkai kembali persis', () async {
      final transport = await sambungSampaiAuth(tautan, tanpaKompresi: true);
      tautan.byteTerkirim.clear();
      final besar = SyncPacket(
        action: SyncAction.updateBackgroundImages,
        payload: {
          'images': [
            BackgroundImage(id: 'bg', base64Image: 'A' * 90000).toMap(),
          ],
        },
      );
      transport.kirim(besar);
      await jeda();
      final potongan = tautan.paketTerkirim;
      expect(potongan.length, greaterThan(1));
      expect(potongan.every((p) => p.action == SyncAction.chunkedData), isTrue);
      final perangkai = ChunkReassembler();
      SyncPacket? utuh;
      for (final p in potongan) {
        utuh = perangkai.addChunk(p) ?? utuh;
      }
      expect(utuh?.toJson(), besar.toJson());
      await transport.putus();
    });

    test('paket masuk ter-chunk dirakit sebelum diteruskan', () async {
      final transport = await sambungSampaiAuth(tautan);
      final diterima = <SyncPacket>[];
      final sub = transport.paketMasuk.listen(diterima.add);
      addTearDown(sub.cancel);
      final besar = SyncPacket(
        action: SyncAction.stateSnapshot,
        payload: {
          'config': MosqueConfig(name: 'X' * 80000).toMap(),
          'hasData': true,
        },
      );
      for (final potongan in encodeChunkedTransfer(
        besar,
        transferId: 'tx-masuk',
      ).packets) {
        tautan.picu(BtData(bingkaiDari(potongan)));
      }
      await jeda();
      expect(diterima, hasLength(1));
      expect(diterima.single.toJson(), besar.toJson());
      await transport.putus();
    });

    test('bingkai pecah antar-peristiwa data tetap terangkai', () async {
      final transport = await sambungSampaiAuth(tautan);
      final diterima = <SyncPacket>[];
      final sub = transport.paketMasuk.listen(diterima.add);
      addTearDown(sub.cancel);
      final bingkai = bingkaiDari(
        const SyncPacket(
          action: SyncAction.stateUpdate,
          payload: {'phase': 'adhan', 'prayer': 'maghrib'},
        ),
      );
      tautan.picu(BtData(Uint8List.sublistView(bingkai, 0, 3)));
      tautan.picu(BtData(Uint8List.sublistView(bingkai, 3)));
      await jeda();
      expect(diterima, hasLength(1));
      expect(diterima.single.action, SyncAction.stateUpdate);
      await transport.putus();
    });

    test('putus dari sisi TV memicu aliran kesalahan', () async {
      final transport = await sambungSampaiAuth(tautan);
      final kesalahan = <String>[];
      final sub = transport.kesalahan.listen(kesalahan.add);
      addTearDown(sub.cancel);
      tautan.picu(const BtTerputus());
      await jeda();
      expect(transport.terhubung, isFalse);
      expect(kesalahan, hasLength(1));
      await transport.putus();
    });

    test('kirim saat belum auth tidak mengirim apa pun', () async {
      final transport = TransportMasjidBt(tautan);
      transport.kirim(
        const SyncPacket(action: SyncAction.skipAdhan, payload: {}),
      );
      await jeda();
      expect(tautan.byteTerkirim, isEmpty);
    });
  });
}
