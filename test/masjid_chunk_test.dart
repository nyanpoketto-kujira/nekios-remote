import 'package:flutter_test/flutter_test.dart';
import 'package:nekios_remote/masjid/model_masjid.dart';
import 'package:nekios_remote/masjid/paket_masjid.dart';
import 'package:nekios_remote/masjid/transfer_chunk.dart';

/// Paket `updateBackgroundImages` dengan satu gambar base64 besar —
/// cara praktis melewati ambang chunking 64 KB.
SyncPacket paketBesar({int ukuranBase64 = 90000}) => SyncPacket(
  action: SyncAction.updateBackgroundImages,
  payload: {
    'images': [
      BackgroundImage(id: 'bg1', base64Image: 'A' * ukuranBase64).toMap(),
    ],
  },
);

void main() {
  group('encodeChunkedTransfer', () {
    test('paket kecil tidak di-chunk (apa adanya)', () {
      const paket = SyncPacket(
        action: SyncAction.setMuted,
        payload: {'muted': true},
      );
      final hasil = encodeChunkedTransfer(paket);
      expect(hasil.chunked, isFalse);
      expect(hasil.packets, [paket]);
    });

    test('paket besar dipecah 32 KB dengan metadata berurutan', () {
      final paket = paketBesar();
      final hasil = encodeChunkedTransfer(paket, transferId: 'tx-uji');
      expect(hasil.chunked, isTrue);
      final totalDiharapkan = (paket.toJson().length / kChunkDataLength).ceil();
      expect(hasil.packets, hasLength(totalDiharapkan));
      for (var i = 0; i < hasil.packets.length; i++) {
        final chunk = hasil.packets[i];
        expect(chunk.action, SyncAction.chunkedData);
        expect(chunk.payload['transferId'], 'tx-uji');
        expect(chunk.payload['action'], 'updateBackgroundImages');
        expect(chunk.payload['seq'], i);
        expect(chunk.payload['total'], totalDiharapkan);
        expect(
          (chunk.payload['data'] as String).length,
          lessThanOrEqualTo(kChunkDataLength),
        );
      }
    });
  });

  group('ChunkReassembler', () {
    test('rangkaian lengkap mengembalikan paket asli', () {
      final paket = paketBesar();
      final encoding = encodeChunkedTransfer(paket, transferId: 'tx-bulat');
      final perangkai = ChunkReassembler();
      SyncPacket? selesai;
      for (final chunk in encoding.packets) {
        selesai = perangkai.addChunk(chunk) ?? selesai;
      }
      expect(selesai, isNotNull);
      expect(selesai!.action, SyncAction.updateBackgroundImages);
      expect(selesai.toJson(), paket.toJson());
      expect(perangkai.hasPendingTransfer, isFalse);
      expect(perangkai.lastError, isNull);
    });

    test('chunk datang tidak berurutan tetap terangkai', () {
      final paket = paketBesar(ukuranBase64: 70000);
      final encoding = encodeChunkedTransfer(paket, transferId: 'tx-acak');
      final perangkai = ChunkReassembler();
      SyncPacket? selesai;
      for (final chunk in encoding.packets.reversed) {
        selesai = perangkai.addChunk(chunk) ?? selesai;
      }
      expect(selesai?.toJson(), paket.toJson());
    });

    test('bukan paket chunkedData ditolak', () {
      final perangkai = ChunkReassembler();
      expect(
        perangkai.addChunk(
          const SyncPacket(action: SyncAction.setMuted, payload: {}),
        ),
        isNull,
      );
      expect(perangkai.lastError, contains('bukan paket chunkedData'));
    });

    test('total di luar batas ditolak', () {
      final perangkai = ChunkReassembler();
      final chunk = SyncPacket(
        action: SyncAction.chunkedData,
        payload: {
          'transferId': 'tx-x',
          'action': 'updateLogo',
          'seq': 0,
          'total': kMaxChunksPerTransfer + 1,
          'data': 'abc',
        },
      );
      expect(perangkai.addChunk(chunk), isNull);
      expect(perangkai.lastError, contains('di luar batas'));
    });

    test('metadata berubah di tengah transfer membatalkan', () {
      final paket = paketBesar();
      final encoding = encodeChunkedTransfer(paket, transferId: 'tx-meta');
      final perangkai = ChunkReassembler();
      perangkai.addChunk(encoding.packets.first);
      final menyimpang = SyncPacket(
        action: SyncAction.chunkedData,
        payload: {
          ...encoding.packets[1].payload,
          'total': encoding.packets.length + 5,
        },
      );
      expect(perangkai.addChunk(menyimpang), isNull);
      expect(perangkai.lastError, contains('metadata berubah'));
      expect(perangkai.hasPendingTransfer, isFalse);
    });

    test('duplikat identik diabaikan; duplikat beda isi membatalkan', () {
      final paket = paketBesar();
      final encoding = encodeChunkedTransfer(paket, transferId: 'tx-dup');
      final perangkai = ChunkReassembler();
      perangkai.addChunk(encoding.packets[0]);
      expect(perangkai.addChunk(encoding.packets[0]), isNull);
      expect(perangkai.lastError, isNull);
      expect(perangkai.receivedCount, 1);

      final beda = SyncPacket(
        action: SyncAction.chunkedData,
        payload: {...encoding.packets[0].payload, 'data': 'ZZZ'},
      );
      expect(perangkai.addChunk(beda), isNull);
      expect(perangkai.lastError, contains('duplikat'));
    });

    test('transfer baru menggantikan transfer menggantung', () {
      final lama = encodeChunkedTransfer(paketBesar(), transferId: 'tx-lama');
      final baruPaket = paketBesar(ukuranBase64: 80000);
      final baru = encodeChunkedTransfer(baruPaket, transferId: 'tx-baru');
      final perangkai = ChunkReassembler();
      perangkai.addChunk(lama.packets.first);
      SyncPacket? selesai;
      for (final chunk in baru.packets) {
        selesai = perangkai.addChunk(chunk) ?? selesai;
      }
      expect(selesai?.toJson(), baruPaket.toJson());
    });

    test('seq di luar rentang ditolak', () {
      final perangkai = ChunkReassembler();
      final chunk = SyncPacket(
        action: SyncAction.chunkedData,
        payload: {
          'transferId': 'tx-seq',
          'action': 'updateLogo',
          'seq': 7,
          'total': 3,
          'data': 'abc',
        },
      );
      expect(perangkai.addChunk(chunk), isNull);
      expect(perangkai.lastError, contains('di luar rentang'));
    });
  });
}
