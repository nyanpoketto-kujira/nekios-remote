import 'dart:async';

import 'package:nekios_core/nekios_core.dart';

import '../domain/perintah.dart';
import '../masjid/model_masjid.dart';
import '../masjid/paket_masjid.dart';
import '../masjid/transport_masjid.dart';
import '../model/display_tersimpan.dart';
import '../model/snapshot.dart';
import 'klien_remote.dart';

/// Hasil deteksi identitas display pada satu alamat IP (auto-detect
/// ADR-004): pengguna TIDAK memilih jenis display — display sendiri
/// yang memberi tahu identitasnya lewat protokol yang menjawab.
sealed class HasilDeteksi {
  const HasilDeteksi();
}

/// Yang menjawab adalah display SEKOLAH (nekios-core, port 8920).
class TerdeteksiSekolah extends HasilDeteksi {
  const TerdeteksiSekolah(this.namaSekolah);

  /// Nama sekolah dari ringkasan jadwal pada snapshot perdana.
  final String namaSekolah;
}

/// Yang menjawab adalah TV MASJID (protokol warisan, port 8080).
class TerdeteksiMasjid extends HasilDeteksi {
  const TerdeteksiMasjid(this.namaMasjid);

  /// Nama masjid dari konfigurasi pada snapshot perdana TV.
  final String namaMasjid;
}

/// Tidak ada display Nekios yang menjawab di alamat itu.
class TidakTerdeteksi extends HasilDeteksi {
  const TidakTerdeteksi();
}

/// Penyelidik satu protokol: mengembalikan nama identitas display
/// bila protokolnya menjawab di [ip], null bila senyap/gagal.
typedef PenyelidikProtokol = Future<String?> Function(String ip);

/// Pendeteksi jenis display lewat probing PARALEL dua protokol
/// (keputusan ADR-004): nekios-core di 8920 dan protokol warisan
/// masjid di 8080 diselidiki bersamaan; jawaban valid pertama
/// menentukan identitas. Kedua-duanya senyap = [TidakTerdeteksi].
class PendekteksiDisplay {
  const PendekteksiDisplay({
    required this.selidikiSekolah,
    required this.selidikiMasjid,
  });

  /// Pendeteksi dengan penyelidik sungguhan (jaringan asli).
  factory PendekteksiDisplay.bawaan() => PendekteksiDisplay(
    selidikiSekolah: selidikiSekolahNekios,
    selidikiMasjid: selidikiMasjidWs,
  );

  final PenyelidikProtokol selidikiSekolah;
  final PenyelidikProtokol selidikiMasjid;

  Future<HasilDeteksi> deteksi(String ip) {
    final selesai = Completer<HasilDeteksi>();
    var sisa = 2;
    void catat(HasilDeteksi? hasil) {
      if (hasil != null && !selesai.isCompleted) {
        selesai.complete(hasil);
      }
      sisa--;
      if (sisa == 0 && !selesai.isCompleted) {
        selesai.complete(const TidakTerdeteksi());
      }
    }

    unawaited(
      selidikiSekolah(ip).then(
        (nama) => catat(nama == null ? null : TerdeteksiSekolah(nama)),
        onError: (_) => catat(null),
      ),
    );
    unawaited(
      selidikiMasjid(ip).then(
        (nama) => catat(nama == null ? null : TerdeteksiMasjid(nama)),
        onError: (_) => catat(null),
      ),
    );
    return selesai.future;
  }
}

/// Penyelidik sekolah sungguhan: sambung nekios-core ke [ip], kirim
/// `ping`, tunggu `state.snapshot` pertama. Nama identitas = nama
/// sekolah pada ringkasan jadwal snapshot. Koneksi penyelidikan
/// selalu ditutup lagi — sesi sungguhan dibuka oleh store.
Future<String?> selidikiSekolahNekios(
  String ip, {
  Duration batas = const Duration(seconds: 3),
}) async {
  final klien = KlienRemoteNekios();
  try {
    await klien.sambung(ip).timeout(batas);
    final masaDepanSnapshot = klien.paketMasuk
        .firstWhere((paket) => paket.type == TipePaket.stateSnapshot)
        .timeout(batas);
    klien.kirim(perintahPing());
    final paket = await masaDepanSnapshot;
    final payload = paket.payload;
    if (payload == null) return null;
    // Snapshot yang tiba SUDAH membuktikan identitas nekios-core;
    // nama sekolah boleh kosong (jadwal belum termuat) — kembalikan
    // '' (menjawab, nama tak diketahui), bukan null (senyap).
    return SnapshotDisplay.fromPayload(payload).jadwal?.sekolah ?? '';
  } catch (_) {
    return null;
  } finally {
    await klien.putus();
  }
}

/// Penyelidik masjid sungguhan: sambung WebSocket warisan ke [ip],
/// kirim `getInitialState`, tunggu `stateSnapshot` pertama. Nama
/// identitas = nama masjid pada konfigurasi snapshot.
Future<String?> selidikiMasjidWs(
  String ip, {
  Duration batas = const Duration(seconds: 3),
}) async {
  final transport = TransportMasjidWs();
  try {
    await transport
        .sambung(
          DisplayTersimpan(nama: '', ip: ip, tipe: TipeDisplay.masjid),
        )
        .timeout(batas);
    final masaDepanSnapshot = transport.paketMasuk
        .firstWhere((paket) => paket.action == SyncAction.stateSnapshot)
        .timeout(batas);
    transport.kirim(
      const SyncPacket(action: SyncAction.getInitialState, payload: {}),
    );
    final paket = await masaDepanSnapshot;
    return StateSnapshot.fromMap(paket.payload).config.name;
  } catch (_) {
    return null;
  } finally {
    await transport.putus();
  }
}
