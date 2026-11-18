/// Codec paket protokol masjid-you — PORT PERSIS dari
/// `packages/shared_models/lib/src/sync_packet.dart` repo masjid-you
/// (Rute A, ADR-003).
///
/// Envelope wire: JSON `{"action": "<nama>", "payload": {…}}` — tanpa
/// field versi, tanpa request-id/ack umum. Semua aksi fire-and-forget;
/// keberhasilan dibuktikan oleh `stateSnapshot`/`stateUpdate` susulan
/// dari TV (lihat kontrak di store masjid & ADR-003).
library;

import 'dart:convert';

import 'model_masjid.dart';

enum SyncAction {
  updateConfig,
  updateRunningText,
  updateBanners,
  updateKas,

  /// Remote -> TV: daftar kartu gambar khusus slot samping TV
  /// (payload: `images`, lihat `SpecialImage`).
  updateSideImages,

  /// Remote -> TV: daftar gambar latar TV untuk slideshow
  /// (payload: `images`, lihat `BackgroundImage`). Interval slideshow
  /// adalah field config `backgroundSlideSeconds`.
  updateBackgroundImages,

  /// Remote -> TV: logo masjid untuk header TV (payload: `logoBase64`,
  /// string base64 gambar asli; `null`/hilang = logo dihapus).
  updateLogo,

  /// Transfer ter-chunk untuk payload besar via Bluetooth: satu
  /// potongan string JSON paket lain (payload: `transferId`,
  /// `action`, `seq`, `total`, `data` — lihat `transfer_chunk.dart`).
  /// Paket ini tidak pernah diteruskan ke handler aplikasi; penerima
  /// merangkainya kembali menjadi paket asli lebih dulu.
  chunkedData,
  triggerBeep,
  getInitialState,
  stateUpdate,

  /// Snapshot lengkap dari TV (TV -> Remote). Lihat `StateSnapshot`.
  stateSnapshot,
  skipAdhan,
  startIqomah,
  startShalat,
  finishShalat,
  forcePhase,

  /// Remote -> TV: nyalakan/matikan mode senyap TV (payload: `muted`).
  setMuted,

  /// Remote -> TV: nyalakan/matikan standby TV (payload: `standby`).
  setStandby,

  /// TV -> Remote: minta autentikasi PIN (payload: `nonce`). Dikirim
  /// begitu koneksi RFCOMM terbentuk, sebelum paket data apa pun.
  authChallenge,

  /// Remote -> TV: jawab challenge dengan PIN (payload: `pin`, `nonce`).
  authResponse,

  /// TV -> Remote: PIN benar, jalur siap dipakai (payload: kosong).
  authSuccess,

  /// TV -> Remote: PIN salah / nonce tidak valid (payload: `error`).
  authFailure,
}

class SyncPacket {
  final SyncAction action;
  final Map<String, dynamic> payload;

  const SyncPacket({required this.action, required this.payload});

  Map<String, dynamic> toMap() => {'action': action.name, 'payload': payload};

  factory SyncPacket.fromMap(Map<String, dynamic> map) {
    final actionName = map['action'] is String ? map['action'] as String : '';
    final action = SyncAction.values.firstWhere(
      (e) => e.name == actionName,
      // Fallback senyap sumber: nama aksi tak dikenal menjadi
      // `stateUpdate`. Dipertahankan persis demi paritas decode.
      orElse: () => SyncAction.stateUpdate,
    );
    return SyncPacket(action: action, payload: _parsePayload(map['payload']));
  }

  static Map<String, dynamic> _parsePayload(Object? raw) {
    if (raw is Map) {
      return {for (final entry in raw.entries) '${entry.key}': entry.value};
    }
    return const {};
  }

  String toJson() => json.encode(toMap());

  factory SyncPacket.fromJson(String source) =>
      SyncPacket.fromMap(json.decode(source));

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncPacket &&
          other.action == action &&
          _mapsEqual(other.payload, payload);

  static bool _mapsEqual(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || b[key] != a[key]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(action, Object.hashAll(payload.keys.toList()..sort()));

  @override
  String toString() => 'SyncPacket(action: ${action.name}, payload: $payload)';
}

/// Isi payload `SyncAction.stateUpdate` (TV -> Remote), di-broadcast
/// TV setiap `PrayerStateMachine`-nya berubah dan setelah
/// `setMuted`/`setStandby` diterapkan.
///
/// Di shared_models masjid-you payload ini tidak punya kelas sendiri
/// (di-parse inline oleh mobile_remote); kelas ini adalah pemodelan
/// dialek nekios-remote atas field-field wire yang sama persis:
/// `phase`, `prayer`, `remainingSeconds`, `totalSeconds`, `muted`,
/// `standby` (dibangun TV di `_broadcastState`).
class StatusTvMasjid {
  const StatusTvMasjid({
    this.phase = PrayerPhase.normal,
    this.prayer,
    this.remainingSeconds = 0,
    this.totalSeconds = 0,
    this.muted = false,
    this.standby = false,
  });

  /// Fase siklus shalat TV saat ini.
  final PrayerPhase phase;

  /// Shalat yang terkait fase ini (mis. shalat yang sedang dihitung
  /// mundurnya); null saat TV tidak mengaitkan shalat (fase normal
  /// sebelum jadwal dihitung).
  final PrayerType? prayer;

  /// Sisa detik fase berjalan saat paket dibuat.
  final int remainingSeconds;

  /// Total detik fase berjalan.
  final int totalSeconds;

  final bool muted;
  final bool standby;

  factory StatusTvMasjid.fromPayload(Map<String, dynamic> payload) {
    final rawPrayer = payload['prayer'];
    return StatusTvMasjid(
      phase: PrayerPhase.fromName(
        payload['phase'] is String ? payload['phase'] as String : null,
      ),
      prayer: rawPrayer is String
          ? PrayerType.values.where((t) => t.name == rawPrayer).firstOrNull
          : null,
      remainingSeconds: payload['remainingSeconds'] is num
          ? (payload['remainingSeconds'] as num).toInt()
          : 0,
      totalSeconds: payload['totalSeconds'] is num
          ? (payload['totalSeconds'] as num).toInt()
          : 0,
      muted: payload['muted'] is bool ? payload['muted'] as bool : false,
      standby: payload['standby'] is bool ? payload['standby'] as bool : false,
    );
  }

  Map<String, dynamic> toPayload() => {
    'phase': phase.name,
    'prayer': prayer?.name,
    'remainingSeconds': remainingSeconds,
    'totalSeconds': totalSeconds,
    'muted': muted,
    'standby': standby,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StatusTvMasjid &&
          other.phase == phase &&
          other.prayer == prayer &&
          other.remainingSeconds == remainingSeconds &&
          other.totalSeconds == totalSeconds &&
          other.muted == muted &&
          other.standby == standby;

  @override
  int get hashCode => Object.hash(
    phase,
    prayer,
    remainingSeconds,
    totalSeconds,
    muted,
    standby,
  );

  @override
  String toString() =>
      'StatusTvMasjid(phase: ${phase.name}, prayer: ${prayer?.name}, '
      'remainingSeconds: $remainingSeconds, totalSeconds: $totalSeconds, '
      'muted: $muted, standby: $standby)';
}
