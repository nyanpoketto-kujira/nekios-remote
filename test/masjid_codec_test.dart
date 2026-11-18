import 'package:flutter_test/flutter_test.dart';
import 'package:nekios_remote/masjid/model_masjid.dart';
import 'package:nekios_remote/masjid/paket_masjid.dart';

void main() {
  group('codec SyncPacket (envelope {action, payload})', () {
    test('nama aksi di kabel persis nama enum sumber', () {
      // Nama-nama ini kontrak wire dengan tv_display masjid-you;
      // daftar kunci yang dipakai remote pusat tahap A1 + auth BT.
      const diharapkan = {
        SyncAction.updateConfig: 'updateConfig',
        SyncAction.updateRunningText: 'updateRunningText',
        SyncAction.updateBanners: 'updateBanners',
        SyncAction.updateKas: 'updateKas',
        SyncAction.updateSideImages: 'updateSideImages',
        SyncAction.updateBackgroundImages: 'updateBackgroundImages',
        SyncAction.updateLogo: 'updateLogo',
        SyncAction.chunkedData: 'chunkedData',
        SyncAction.getInitialState: 'getInitialState',
        SyncAction.stateUpdate: 'stateUpdate',
        SyncAction.stateSnapshot: 'stateSnapshot',
        SyncAction.skipAdhan: 'skipAdhan',
        SyncAction.startIqomah: 'startIqomah',
        SyncAction.startShalat: 'startShalat',
        SyncAction.finishShalat: 'finishShalat',
        SyncAction.forcePhase: 'forcePhase',
        SyncAction.setMuted: 'setMuted',
        SyncAction.setStandby: 'setStandby',
        SyncAction.authChallenge: 'authChallenge',
        SyncAction.authResponse: 'authResponse',
        SyncAction.authSuccess: 'authSuccess',
        SyncAction.authFailure: 'authFailure',
      };
      diharapkan.forEach((aksi, nama) => expect(aksi.name, nama));
    });

    test('paket data pulang-pergi lewat JSON utuh', () {
      final paket = SyncPacket(
        action: SyncAction.updateKas,
        payload: {
          'transactions': [
            KasTransaction(
              id: 'k1',
              type: KasType.keluar,
              amount: 150000,
              description: 'Karpet baru',
              date: DateTime(2026, 11, 18, 8, 15),
            ).toMap(),
          ],
        },
      );
      final lagi = SyncPacket.fromJson(paket.toJson());
      expect(lagi.action, SyncAction.updateKas);
      // Kesetaraan SyncPacket sumber bersifat dangkal (nilai payload
      // dibandingkan per kunci) — untuk payload bersarang, pembuktian
      // pulang-pergi yang sah adalah JSON-nya identik.
      expect(lagi.toJson(), paket.toJson());
    });

    test('paket kontrol tanpa payload berkunci', () {
      const paket = SyncPacket(action: SyncAction.skipAdhan, payload: {});
      expect(paket.toJson(), '{"action":"skipAdhan","payload":{}}');
      expect(SyncPacket.fromJson(paket.toJson()), paket);
    });

    test('nama aksi tak dikenal jatuh ke stateUpdate (fallback sumber)', () {
      final paket = SyncPacket.fromJson(
        '{"action":"aksiMasaDepan","payload":{"phase":"adhan"}}',
      );
      expect(paket.action, SyncAction.stateUpdate);
      expect(paket.payload['phase'], 'adhan');
    });

    test('payload hilang / bukan map menjadi payload kosong', () {
      expect(SyncPacket.fromJson('{"action":"setMuted"}').payload, isEmpty);
      expect(
        SyncPacket.fromJson('{"action":"setMuted","payload":[1,2]}').payload,
        isEmpty,
      );
      expect(SyncPacket.fromJson('{}').action, SyncAction.stateUpdate);
    });

    test('paket auth: challenge & response berbentuk sesuai handshake', () {
      final challenge = SyncPacket.fromJson(
        '{"action":"authChallenge","payload":{"nonce":"ab12cd"}}',
      );
      expect(challenge.payload['nonce'], 'ab12cd');
      const response = SyncPacket(
        action: SyncAction.authResponse,
        payload: {'pin': '1234', 'nonce': 'ab12cd'},
      );
      final decoded = SyncPacket.fromJson(response.toJson());
      expect(decoded.payload['pin'], '1234');
      expect(decoded.payload['nonce'], 'ab12cd');
    });
  });
}
