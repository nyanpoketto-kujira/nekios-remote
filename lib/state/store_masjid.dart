import 'dart:async';

import 'package:flutter/foundation.dart';

import '../masjid/model_masjid.dart';
import '../masjid/paket_masjid.dart';
import '../masjid/transport_masjid.dart';
import '../model/display_tersimpan.dart';
import 'remote_store.dart';

/// Pabrik transport per display (Wi-Fi atau Bluetooth) — diinjeksi
/// dari main agar store bisa diuji dengan transport palsu.
typedef PabrikTransportMasjid = TransportMasjid Function(
  DisplayTersimpan display,
);

/// Penyedia data lokal untuk bootstrap: dipanggil SEKALI bila TV
/// melaporkan snapshot `hasData == false` (TV baru/factory-reset).
/// Mengembalikan snapshot yang isinya didorong sebagai paket-paket
/// `update*`. Tahap A1 belum punya dataset lokal masjid di remote —
/// bawaan null (tidak ada yang didorong); mekanismenya sendiri diuji.
typedef PenyediaBootstrapMasjid = StateSnapshot Function();

/// Store untuk display MASJID (protokol warisan masjid-you, Rute A).
///
/// KONTRAK FIRE-AND-FORGET (keputusan ADR-003): protokol masjid tidak
/// mengenal ack. Metode perintah di store ini karenanya menyelesaikan
/// [HasilPerintah] dari BUKTI SUSULAN yang disiarkan TV:
/// - perintah data (`kirimData`) → `stateSnapshot` berikutnya;
/// - perintah kontrol (`kirimKontrol` & aksi cepat) → `stateUpdate`
///   atau `stateSnapshot` berikutnya (TV menyiarkan stateUpdate pada
///   setiap perubahan state machine, termasuk akibat perintah fase
///   dan setMuted/setStandby).
/// Bukti tak kunjung tiba dalam [batasBukti] = gagal lokal. Satu
/// perintah menunggu bukti pada satu waktu (v1, sama seperti store
/// sekolah).
class MasjidStore extends ChangeNotifier {
  MasjidStore({
    required this._buatTransport,
    this.penyediaBootstrap,
    this.batasBukti = const Duration(seconds: 6),
  });

  final PabrikTransportMasjid _buatTransport;

  /// Lihat [PenyediaBootstrapMasjid]; null = bootstrap nonaktif.
  final PenyediaBootstrapMasjid? penyediaBootstrap;

  /// Batas menunggu bukti susulan sebelum perintah dianggap gagal.
  final Duration batasBukti;

  // --- Koneksi ---------------------------------------------------------

  StatusKoneksi statusKoneksi = StatusKoneksi.terputus;

  /// Pesan kesalahan koneksi terakhir (manusiawi, layak tampil).
  String? pesanKoneksi;

  /// Display masjid yang sedang aktif disambung.
  DisplayTersimpan? displayAktif;

  bool get terhubung => statusKoneksi == StatusKoneksi.terhubung;

  TransportMasjid? _transport;
  StreamSubscription<SyncPacket>? _langgananPaket;
  StreamSubscription<String>? _langgananKesalahan;

  Future<void> sambungkan(DisplayTersimpan display) async {
    if (statusKoneksi == StatusKoneksi.menyambung) return;
    await putuskan(senyap: true);
    statusKoneksi = StatusKoneksi.menyambung;
    pesanKoneksi = null;
    displayAktif = display;
    notifyListeners();

    final transport = _buatTransport(display);
    _transport = transport;
    _langgananPaket = transport.paketMasuk.listen(_tanganiPaket);
    _langgananKesalahan = transport.kesalahan.listen(_tanganiKesalahan);
    try {
      await transport.sambung(display);
    } catch (e) {
      statusKoneksi = StatusKoneksi.terputus;
      pesanKoneksi = e is Exception
          ? e.toString().replaceFirst('Exception: ', '')
          : 'Gagal menyambung ke TV masjid.';
      notifyListeners();
      return;
    }
    if (_transport != transport) return; // Sudah diganti di tengah jalan.
    statusKoneksi = StatusKoneksi.terhubung;
    _bootstrapTerkirim = false;
    notifyListeners();
    // Sambut dengan permintaan snapshot perdana; hasilnya tiba
    // sebagai paket stateSnapshot biasa.
    unawaited(mintaSnapshot());
  }

  /// Selesaikan penunggu snapshot perdana (dipakai putuskan &
  /// tangani-kesalahan): tanpa ini, `mintaSnapshot` menggantung
  /// sampai timeout-nya dan timer timeout-nya bocor melewati
  /// pemutusan (di test: "Timer is still pending" saat teardown).
  void _selesaikanPenungguSnapshot() {
    if (_penungguSnapshot != null && !_penungguSnapshot!.isCompleted) {
      _penungguSnapshot!.complete();
    }
    _penungguSnapshot = null;
  }

  /// Putuskan sambungan dan bersihkan cermin state.
  Future<void> putuskan({bool senyap = false}) async {
    _selesaikanPenunggu(const HasilPerintah.gagal('Koneksi terputus.'));
    _selesaikanPenungguSnapshot();
    // Cancel langganan TIDAK di-await: future cancel langganan
    // broadcast bisa tidak pernah selesai di zona fake-async
    // (deadlock yang membekukan widget test koneksi/beranda masjid)
    // dan teardown stream memang tidak perlu menahan pemutusan.
    // Pola sama seperti RemoteStore.dispose.
    unawaited(_langgananPaket?.cancel() ?? Future<void>.value());
    _langgananPaket = null;
    unawaited(_langgananKesalahan?.cancel() ?? Future<void>.value());
    _langgananKesalahan = null;
    await _transport?.putus();
    _transport = null;
    statusKoneksi = StatusKoneksi.terputus;
    snapshot = null;
    statusTv = null;
    waktuStatus = null;
    if (!senyap) notifyListeners();
  }

  void _tanganiKesalahan(String pesan) {
    if (statusKoneksi == StatusKoneksi.terputus) return;
    statusKoneksi = StatusKoneksi.terputus;
    pesanKoneksi = pesan;
    _selesaikanPenunggu(HasilPerintah.gagal(pesan));
    _selesaikanPenungguSnapshot();
    snapshot = null;
    statusTv = null;
    waktuStatus = null;
    notifyListeners();
  }

  // --- Cermin state TV ---------------------------------------------------

  /// Snapshot data terakhir dari TV (TV = sumber kebenaran);
  /// null sebelum snapshot pertama.
  StateSnapshot? snapshot;

  /// Status fase terakhir dari paket `stateUpdate`.
  StatusTvMasjid? statusTv;

  /// Waktu lokal saat [statusTv] diterima — basis hitung mundur
  /// lokal di antara dua broadcast.
  DateTime? waktuStatus;

  /// Ringkasan kas dari snapshot (nol bila belum ada snapshot).
  KasSummary get ringkasanKas => KasSummary.fromTransactions(
    snapshot?.kasTransactions ?? const <KasTransaction>[],
  );

  /// TV terhubung tetapi belum punya data sama sekali (snapshot
  /// `hasData == false`) — remote sumber data seharusnya mendorong
  /// datanya (bootstrap).
  bool get tvBelumPunyaData => snapshot != null && !snapshot!.hasData;

  /// Sisa detik fase berjalan, dihitung lokal dari [statusTv] +
  /// [waktuStatus] agar angka terus bergerak di antara broadcast.
  int? get sisaDetikFase {
    final status = statusTv;
    final sejak = waktuStatus;
    if (status == null || sejak == null || status.totalSeconds <= 0) {
      return null;
    }
    final berlalu = DateTime.now().difference(sejak).inSeconds;
    final sisa = status.remainingSeconds - berlalu;
    return sisa < 0 ? 0 : sisa;
  }

  // --- Perintah ------------------------------------------------------------

  Completer<HasilPerintah>? _penungguBukti;
  Completer<void>? _penungguSnapshot;
  bool _bootstrapTerkirim = false;

  void _selesaikanPenunggu(HasilPerintah hasil) {
    if (_penungguBukti != null && !_penungguBukti!.isCompleted) {
      _penungguBukti!.complete(hasil);
    }
    _penungguBukti = null;
  }

  /// Minta snapshot segar (`getInitialState`) dan tunggu kedatangannya.
  Future<HasilPerintah> mintaSnapshot() async {
    if (!terhubung || _transport == null) {
      return const HasilPerintah.gagal('Belum terhubung ke TV masjid.');
    }
    final penunggu = Completer<void>();
    _penungguSnapshot = penunggu;
    _transport!.kirim(
      const SyncPacket(action: SyncAction.getInitialState, payload: {}),
    );
    try {
      await penunggu.future.timeout(batasBukti);
      // Penunggu juga diselesaikan oleh putuskan()/kesalahan —
      // dalam kasus itu koneksi sudah putus, jadi laporkan gagal,
      // bukan berhasil.
      return terhubung
          ? const HasilPerintah.berhasil()
          : const HasilPerintah.gagal('Koneksi terputus.');
    } on TimeoutException {
      return const HasilPerintah.gagal(
        'TV tidak mengirim snapshot. Periksa koneksi lalu coba lagi.',
      );
    } finally {
      if (_penungguSnapshot == penunggu) _penungguSnapshot = null;
    }
  }

  /// Kirim paket DATA (update*) — bukti keberhasilan = stateSnapshot
  /// susulan dari TV.
  Future<HasilPerintah> kirimData(SyncPacket paket) =>
      _kirimDenganBukti(paket, tungguSnapshot: true);

  /// Kirim paket KONTROL (fase/mute/standby) — bukti keberhasilan =
  /// stateUpdate (atau snapshot) susulan dari TV.
  Future<HasilPerintah> kirimKontrol(SyncPacket paket) =>
      _kirimDenganBukti(paket, tungguSnapshot: false);

  Future<HasilPerintah> _kirimDenganBukti(
    SyncPacket paket, {
    required bool tungguSnapshot,
  }) async {
    if (!terhubung || _transport == null) {
      return const HasilPerintah.gagal('Belum terhubung ke TV masjid.');
    }
    if (_penungguBukti != null) {
      return const HasilPerintah.gagal(
        'Perintah sebelumnya masih menunggu jawaban TV.',
      );
    }
    final penunggu = Completer<HasilPerintah>();
    _penungguBukti = penunggu;
    if (tungguSnapshot) _penungguSnapshot = Completer<void>();
    _transport!.kirim(paket);
    final hasil = await penunggu.future.timeout(
      batasBukti,
      onTimeout: () => const HasilPerintah.gagal(
        'TV tidak memberi kabar susulan. Perintah mungkin tidak '
        'diterapkan — periksa tampilan TV.',
      ),
    );
    if (identical(_penungguBukti, penunggu)) _penungguBukti = null;
    _penungguSnapshot = null;
    return hasil;
  }

  // --- Aksi cepat Beranda ---------------------------------------------------

  Future<HasilPerintah> lewatiAdhan() =>
      kirimKontrol(const SyncPacket(action: SyncAction.skipAdhan, payload: {}));

  Future<HasilPerintah> mulaiIqomah() => kirimKontrol(
    const SyncPacket(action: SyncAction.startIqomah, payload: {}),
  );

  Future<HasilPerintah> mulaiShalat() => kirimKontrol(
    const SyncPacket(action: SyncAction.startShalat, payload: {}),
  );

  Future<HasilPerintah> selesaiShalat() => kirimKontrol(
    const SyncPacket(action: SyncAction.finishShalat, payload: {}),
  );

  Future<HasilPerintah> aturSenyap(bool senyap) => kirimKontrol(
    SyncPacket(action: SyncAction.setMuted, payload: {'muted': senyap}),
  );

  Future<HasilPerintah> aturStandby(bool standby) => kirimKontrol(
    SyncPacket(action: SyncAction.setStandby, payload: {'standby': standby}),
  );

  // --- Paket masuk ---------------------------------------------------------

  void _tanganiPaket(SyncPacket paket) {
    switch (paket.action) {
      case SyncAction.stateSnapshot:
        snapshot = StateSnapshot.fromMap(paket.payload);
        if (_penungguSnapshot != null && !_penungguSnapshot!.isCompleted) {
          _penungguSnapshot!.complete();
        }
        _selesaikanPenunggu(const HasilPerintah.berhasil());
        _cekBootstrap();
        notifyListeners();
      case SyncAction.stateUpdate:
        statusTv = StatusTvMasjid.fromPayload(paket.payload);
        waktuStatus = DateTime.now();
        _selesaikanPenunggu(const HasilPerintah.berhasil());
        notifyListeners();
      default:
        break; // Paket lain (auth dsb.) urusan transport.
    }
  }

  /// Mekanisme bootstrap mobile_remote: TV dengan `hasData == false`
  /// menerima SATU dorongan data lokal per koneksi.
  void _cekBootstrap() {
    final penyedia = penyediaBootstrap;
    final snap = snapshot;
    if (penyedia == null || snap == null || snap.hasData) return;
    if (_bootstrapTerkirim || _transport == null) return;
    _bootstrapTerkirim = true;
    final data = penyedia();
    final transport = _transport!;
    transport.kirim(
      // Payload updateConfig adalah map config itu sendiri
      // (TV: MosqueConfig.fromMap(packet.payload)).
      SyncPacket(action: SyncAction.updateConfig, payload: data.config.toMap()),
    );
    transport.kirim(
      SyncPacket(
        action: SyncAction.updateRunningText,
        payload: {
          'messages': [for (final m in data.runningTexts) m.toMap()],
        },
      ),
    );
    transport.kirim(
      SyncPacket(
        action: SyncAction.updateBanners,
        payload: {
          'banners': [for (final b in data.banners) b.toMap()],
        },
      ),
    );
    transport.kirim(
      SyncPacket(
        action: SyncAction.updateKas,
        payload: {
          'transactions': [for (final t in data.kasTransactions) t.toMap()],
        },
      ),
    );
    transport.kirim(
      SyncPacket(
        action: SyncAction.updateSideImages,
        payload: {
          'images': [for (final g in data.sideImages) g.toMap()],
        },
      ),
    );
    transport.kirim(
      SyncPacket(
        action: SyncAction.updateBackgroundImages,
        payload: {
          'images': [for (final g in data.backgroundImages) g.toMap()],
        },
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_langgananPaket?.cancel() ?? Future<void>.value());
    unawaited(_langgananKesalahan?.cancel() ?? Future<void>.value());
    super.dispose();
  }
}
