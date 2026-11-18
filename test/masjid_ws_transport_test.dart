import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nekios_remote/masjid/paket_masjid.dart';
import 'package:nekios_remote/masjid/transport_masjid.dart';
import 'package:nekios_remote/model/display_tersimpan.dart';

/// Transport WebSocket masjid diuji terhadap server WebSocket
/// `dart:io` sungguhan di loopback (perilaku meniru server warisan
/// tv_display: menerima getInitialState → membalas stateSnapshot).
void main() {
  test('sambung, minta snapshot, terima balasan, putus', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final diterimaServer = <String>[];
    final langgananServer = server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      socket.listen((data) {
        if (data is String) {
          diterimaServer.add(data);
          final paket = SyncPacket.fromJson(data);
          if (paket.action == SyncAction.getInitialState) {
            socket.add(
              jsonEncode({
                'action': 'stateSnapshot',
                'payload': {'hasData': true},
              }),
            );
          }
        }
      });
    });
    addTearDown(() async {
      await langgananServer.cancel();
      await server.close(force: true);
    });

    final transport = TransportMasjidWs(port: server.port);
    await transport.sambung(
      const DisplayTersimpan(
        nama: 'TV Masjid',
        ip: '127.0.0.1',
        tipe: TipeDisplay.masjid,
      ),
    );
    expect(transport.terhubung, isTrue);

    final balasan = transport.paketMasuk.first;
    transport.kirim(
      const SyncPacket(action: SyncAction.getInitialState, payload: {}),
    );
    final paket = await balasan.timeout(const Duration(seconds: 5));
    expect(paket.action, SyncAction.stateSnapshot);
    expect(paket.payload['hasData'], isTrue);
    expect(diterimaServer, hasLength(1));

    await transport.putus();
    expect(transport.terhubung, isFalse);
  });

  test('sambung ke port mati melempar pesan manusiawi', () async {
    final transport = TransportMasjidWs(port: 1);
    await expectLater(
      transport.sambung(
        const DisplayTersimpan(
          nama: 'TV Masjid',
          ip: '127.0.0.1',
          tipe: TipeDisplay.masjid,
        ),
      ),
      throwsA(predicate((e) => e.toString().contains('Tidak bisa menyambung'))),
    );
    expect(transport.terhubung, isFalse);
  });
}
