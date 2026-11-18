/// Model-model wire protokol masjid-you — PORT PERSIS dari
/// `packages/shared_models/lib/src/` repo masjid-you (Rute A, ADR-003).
///
/// Paritas field `toMap`/`fromMap` adalah kontrak dengan tv_display
/// masjid-you yang TIDAK diubah sama sekali: nama kunci, nilai
/// default, dan toleransi parsing harus identik dengan sumbernya.
/// Bila protokol masjid-you berubah, port ini harus diselaraskan.
///
/// Sengaja disalin (bukan dependensi lintas-repo) supaya nekios-remote
/// berdiri sendiri; sumber kebenaran tetap shared_models masjid-you.
library;

import 'dart:convert';

// ---------------------------------------------------------------------------
// PrayerType — port dari src/prayer_type.dart
// ---------------------------------------------------------------------------

enum PrayerType { fajr, sunrise, dhuhr, asr, maghrib, isha }

extension PrayerTypeX on PrayerType {
  String get displayName {
    switch (this) {
      case PrayerType.fajr:
        return 'Subuh';
      case PrayerType.sunrise:
        return 'Syuruq';
      case PrayerType.dhuhr:
        return 'Dzuhur';
      case PrayerType.asr:
        return 'Ashar';
      case PrayerType.maghrib:
        return 'Maghrib';
      case PrayerType.isha:
        return 'Isya';
    }
  }

  /// Nama tampilan yang peka tanggal: `dhuhr` menjadi "Jumat" pada
  /// hari Jumat (kecuali musholla tanpa Jumatan).
  String displayNameForDate(DateTime date, {bool hasFridayPrayer = true}) {
    if (hasFridayPrayer &&
        this == PrayerType.dhuhr &&
        date.weekday == DateTime.friday) {
      return 'Jumat';
    }
    return displayName;
  }
}

const List<PrayerType> kAllPrayerTypes = [
  PrayerType.fajr,
  PrayerType.sunrise,
  PrayerType.dhuhr,
  PrayerType.asr,
  PrayerType.maghrib,
  PrayerType.isha,
];

// ---------------------------------------------------------------------------
// Helper parsing aman — port dari src/mosque_config.dart
// ---------------------------------------------------------------------------

int _intOf(Object? raw, int fallback) => raw is num ? raw.toInt() : fallback;

double _doubleOf(Object? raw, double fallback) =>
    raw is num ? raw.toDouble() : fallback;

bool _boolOf(Object? raw, bool fallback) => raw is bool ? raw : fallback;

// ---------------------------------------------------------------------------
// IqamahDuration + MosqueConfig — port dari src/mosque_config.dart
// ---------------------------------------------------------------------------

class IqamahDuration {
  final int fajr;
  final int dhuhr;
  final int asr;
  final int maghrib;
  final int isha;

  const IqamahDuration({
    this.fajr = 10,
    this.dhuhr = 10,
    this.asr = 10,
    this.maghrib = 7,
    this.isha = 10,
  });

  Map<String, dynamic> toMap() => {
    'fajr': fajr,
    'dhuhr': dhuhr,
    'asr': asr,
    'maghrib': maghrib,
    'isha': isha,
  };

  factory IqamahDuration.fromMap(Map<String, dynamic> map) {
    return IqamahDuration(
      fajr: _intOf(map['fajr'], 10),
      dhuhr: _intOf(map['dhuhr'], 10),
      asr: _intOf(map['asr'], 10),
      maghrib: _intOf(map['maghrib'], 7),
      isha: _intOf(map['isha'], 10),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IqamahDuration &&
          other.fajr == fajr &&
          other.dhuhr == dhuhr &&
          other.asr == asr &&
          other.maghrib == maghrib &&
          other.isha == isha;

  @override
  int get hashCode => Object.hash(fajr, dhuhr, asr, maghrib, isha);

  @override
  String toString() =>
      'IqamahDuration(fajr: $fajr, dhuhr: $dhuhr, asr: $asr, '
      'maghrib: $maghrib, isha: $isha)';
}

/// Konfigurasi identitas & siklus waktu shalat masjid (immutable).
class MosqueConfig {
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final int utcOffsetHours;
  final IqamahDuration iqamahDuration;
  final Map<PrayerType, int> prayerOffsets;
  final int preAdhanMinutes;
  final int adhanMinutes;
  final int preIqomahMinutes;
  final int shalatMinutes;
  final int khutbahMinutes;
  final String fridayKhatib;
  final String fridayMuadzin;
  final bool showKas;
  final bool hasFridayPrayer;
  final int backgroundSlideSeconds;

  static const int minBackgroundSlideSeconds = 5;
  static const int maxBackgroundSlideSeconds = 300;
  static const int defaultBackgroundSlideSeconds = 30;

  static int clampBackgroundSlideSeconds(int seconds) =>
      seconds.clamp(minBackgroundSlideSeconds, maxBackgroundSlideSeconds);

  const MosqueConfig({
    this.name = 'Masjid Al-Ikhlas',
    this.address = 'Jl. Raya Masjid No. 123',
    this.latitude = -6.2088,
    this.longitude = 106.8456,
    this.utcOffsetHours = 7,
    this.iqamahDuration = const IqamahDuration(),
    this.prayerOffsets = const {},
    this.preAdhanMinutes = 15,
    this.adhanMinutes = 2,
    this.preIqomahMinutes = 1,
    this.shalatMinutes = 10,
    this.khutbahMinutes = 20,
    this.fridayKhatib = 'Ustadz Khatib',
    this.fridayMuadzin = 'Ustadz Bilal',
    this.showKas = true,
    this.hasFridayPrayer = true,
    this.backgroundSlideSeconds = defaultBackgroundSlideSeconds,
  });

  MosqueConfig._internal({
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.utcOffsetHours,
    required this.iqamahDuration,
    required Map<PrayerType, int> prayerOffsets,
    required this.preAdhanMinutes,
    required this.adhanMinutes,
    required this.preIqomahMinutes,
    required this.shalatMinutes,
    required this.khutbahMinutes,
    required this.fridayKhatib,
    required this.fridayMuadzin,
    required this.showKas,
    required this.hasFridayPrayer,
    required this.backgroundSlideSeconds,
  }) : prayerOffsets = Map.unmodifiable(prayerOffsets);

  int offsetFor(PrayerType type) => prayerOffsets[type] ?? 0;

  Map<String, dynamic> toMap() => {
    'name': name,
    'address': address,
    'latitude': latitude,
    'longitude': longitude,
    'utcOffsetHours': utcOffsetHours,
    'iqamahDuration': iqamahDuration.toMap(),
    'prayerOffsets': {
      for (final type in kAllPrayerTypes) type.name: prayerOffsets[type] ?? 0,
    },
    'preAdhanMinutes': preAdhanMinutes,
    'adhanMinutes': adhanMinutes,
    'preIqomahMinutes': preIqomahMinutes,
    'shalatMinutes': shalatMinutes,
    'khutbahMinutes': khutbahMinutes,
    'fridayKhatib': fridayKhatib,
    'fridayMuadzin': fridayMuadzin,
    'showKas': showKas,
    'hasFridayPrayer': hasFridayPrayer,
    'backgroundSlideSeconds': backgroundSlideSeconds,
  };

  factory MosqueConfig.fromMap(Map<String, dynamic> map) {
    Map<PrayerType, int> parseOffsets() {
      final result = <PrayerType, int>{};
      final raw = map['prayerOffsets'];
      if (raw is Map) {
        for (final entry in raw.entries) {
          final type = PrayerType.values
              .where((t) => t.name == entry.key)
              .firstOrNull;
          if (type != null) {
            result[type] = _intOf(entry.value, 0);
          }
        }
        return result;
      }
      final legacy = map['prayerCorrectionMinutes'];
      if (legacy is num) {
        for (final type in kAllPrayerTypes) {
          result[type] = legacy.toInt();
        }
      }
      return result;
    }

    final rawName = map['name'];
    final rawAddress = map['address'];
    final rawUtc = map['utcOffsetHours'];
    final rawIqamah = map['iqamahDuration'];
    final rawKhatib = map['fridayKhatib'];
    final rawMuadzin = map['fridayMuadzin'];

    return MosqueConfig._internal(
      name: rawName is String ? rawName : 'Masjid Al-Ikhlas',
      address: rawAddress is String ? rawAddress : '',
      latitude: _doubleOf(map['latitude'], -6.2088),
      longitude: _doubleOf(map['longitude'], 106.8456),
      utcOffsetHours: _intOf(rawUtc, 7),
      iqamahDuration: rawIqamah is Map
          ? IqamahDuration.fromMap(Map<String, dynamic>.from(rawIqamah))
          : const IqamahDuration(),
      prayerOffsets: parseOffsets(),
      preAdhanMinutes: _intOf(map['preAdhanMinutes'], 15),
      adhanMinutes: _intOf(map['adhanMinutes'], 2),
      preIqomahMinutes: _intOf(map['preIqomahMinutes'], 1),
      shalatMinutes: _intOf(map['shalatMinutes'], 10),
      khutbahMinutes: _intOf(map['khutbahMinutes'], 20),
      fridayKhatib: rawKhatib is String ? rawKhatib : 'Ustadz Khatib',
      fridayMuadzin: rawMuadzin is String ? rawMuadzin : 'Ustadz Bilal',
      showKas: _boolOf(map['showKas'], true),
      hasFridayPrayer: _boolOf(map['hasFridayPrayer'], true),
      backgroundSlideSeconds: clampBackgroundSlideSeconds(
        _intOf(map['backgroundSlideSeconds'], defaultBackgroundSlideSeconds),
      ),
    );
  }

  String toJson() => json.encode(toMap());

  factory MosqueConfig.fromJson(String source) =>
      MosqueConfig.fromMap(json.decode(source));

  MosqueConfig copyWith({
    String? name,
    String? address,
    double? latitude,
    double? longitude,
    int? utcOffsetHours,
    IqamahDuration? iqamahDuration,
    Map<PrayerType, int>? prayerOffsets,
    int? preAdhanMinutes,
    int? adhanMinutes,
    int? preIqomahMinutes,
    int? shalatMinutes,
    int? khutbahMinutes,
    String? fridayKhatib,
    String? fridayMuadzin,
    bool? showKas,
    bool? hasFridayPrayer,
    int? backgroundSlideSeconds,
  }) {
    return MosqueConfig._internal(
      name: name ?? this.name,
      address: address ?? this.address,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      utcOffsetHours: utcOffsetHours ?? this.utcOffsetHours,
      iqamahDuration: iqamahDuration ?? this.iqamahDuration,
      prayerOffsets:
          prayerOffsets ?? Map<PrayerType, int>.of(this.prayerOffsets),
      preAdhanMinutes: preAdhanMinutes ?? this.preAdhanMinutes,
      adhanMinutes: adhanMinutes ?? this.adhanMinutes,
      preIqomahMinutes: preIqomahMinutes ?? this.preIqomahMinutes,
      shalatMinutes: shalatMinutes ?? this.shalatMinutes,
      khutbahMinutes: khutbahMinutes ?? this.khutbahMinutes,
      fridayKhatib: fridayKhatib ?? this.fridayKhatib,
      fridayMuadzin: fridayMuadzin ?? this.fridayMuadzin,
      showKas: showKas ?? this.showKas,
      hasFridayPrayer: hasFridayPrayer ?? this.hasFridayPrayer,
      backgroundSlideSeconds: backgroundSlideSeconds == null
          ? this.backgroundSlideSeconds
          : clampBackgroundSlideSeconds(backgroundSlideSeconds),
    );
  }

  static bool _mapsEqual(Map<PrayerType, int> a, Map<PrayerType, int> b) {
    for (final type in kAllPrayerTypes) {
      if ((a[type] ?? 0) != (b[type] ?? 0)) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MosqueConfig &&
          other.name == name &&
          other.address == address &&
          other.latitude == latitude &&
          other.longitude == longitude &&
          other.utcOffsetHours == utcOffsetHours &&
          other.iqamahDuration == iqamahDuration &&
          _mapsEqual(other.prayerOffsets, prayerOffsets) &&
          other.preAdhanMinutes == preAdhanMinutes &&
          other.adhanMinutes == adhanMinutes &&
          other.preIqomahMinutes == preIqomahMinutes &&
          other.shalatMinutes == shalatMinutes &&
          other.khutbahMinutes == khutbahMinutes &&
          other.fridayKhatib == fridayKhatib &&
          other.fridayMuadzin == fridayMuadzin &&
          other.showKas == showKas &&
          other.hasFridayPrayer == hasFridayPrayer &&
          other.backgroundSlideSeconds == backgroundSlideSeconds;

  @override
  int get hashCode => Object.hash(
    name,
    address,
    latitude,
    longitude,
    utcOffsetHours,
    iqamahDuration,
    Object.hashAll(kAllPrayerTypes.map(offsetFor)),
    preAdhanMinutes,
    adhanMinutes,
    preIqomahMinutes,
    shalatMinutes,
    khutbahMinutes,
    fridayKhatib,
    fridayMuadzin,
    showKas,
    hasFridayPrayer,
    backgroundSlideSeconds,
  );

  @override
  String toString() =>
      'MosqueConfig(name: $name, address: $address, latitude: $latitude, '
      'longitude: $longitude, utcOffsetHours: $utcOffsetHours, '
      'iqamahDuration: $iqamahDuration, prayerOffsets: $prayerOffsets, '
      'preAdhanMinutes: $preAdhanMinutes, adhanMinutes: $adhanMinutes, '
      'preIqomahMinutes: $preIqomahMinutes, shalatMinutes: $shalatMinutes, '
      'khutbahMinutes: $khutbahMinutes, fridayKhatib: $fridayKhatib, '
      'fridayMuadzin: $fridayMuadzin, showKas: $showKas, '
      'hasFridayPrayer: $hasFridayPrayer, '
      'backgroundSlideSeconds: $backgroundSlideSeconds)';
}

// ---------------------------------------------------------------------------
// PrayerPhase — port dari src/prayer_phase.dart
// ---------------------------------------------------------------------------

/// Fase siklus waktu shalat di layar TV. Nama enum dikirim sebagai
/// string lewat protokol, jadi nama-nama ini kontrak wire.
enum PrayerPhase {
  normal,
  preAdhan,
  adhan,
  khutbah,
  preIqomah,
  shalat;

  static PrayerPhase fromName(String? name) => PrayerPhase.values.firstWhere(
    (p) => p.name == name,
    orElse: () => PrayerPhase.normal,
  );
}

extension PrayerPhaseX on PrayerPhase {
  String get label {
    switch (this) {
      case PrayerPhase.normal:
        return 'Normal (Standby)';
      case PrayerPhase.preAdhan:
        return 'Menjelang Azan';
      case PrayerPhase.adhan:
        return 'Azan';
      case PrayerPhase.khutbah:
        return 'Khutbah';
      case PrayerPhase.preIqomah:
        return 'Jeda Ikamah';
      case PrayerPhase.shalat:
        return 'Shalat Berlangsung';
    }
  }

  Duration durationFor(MosqueConfig config) {
    switch (this) {
      case PrayerPhase.normal:
        return Duration.zero;
      case PrayerPhase.preAdhan:
        return Duration(minutes: config.preAdhanMinutes);
      case PrayerPhase.adhan:
        return Duration(minutes: config.adhanMinutes);
      case PrayerPhase.khutbah:
        return Duration(minutes: config.khutbahMinutes);
      case PrayerPhase.preIqomah:
        return Duration(minutes: config.preIqomahMinutes);
      case PrayerPhase.shalat:
        return Duration(minutes: config.shalatMinutes);
    }
  }
}

// ---------------------------------------------------------------------------
// RunningTextMessage — port dari src/running_text.dart
// ---------------------------------------------------------------------------

class RunningTextMessage {
  final String id;
  final String content;
  final bool isActive;
  final String category;

  const RunningTextMessage({
    required this.id,
    required this.content,
    this.isActive = true,
    this.category = 'Umum',
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'content': content,
    'isActive': isActive,
    'category': category,
  };

  factory RunningTextMessage.fromMap(Map<String, dynamic> map) {
    final rawId = map['id'];
    final rawContent = map['content'];
    final rawCategory = map['category'];
    final rawActive = map['isActive'];
    return RunningTextMessage(
      id: rawId is String
          ? rawId
          : DateTime.now().millisecondsSinceEpoch.toString(),
      content: rawContent is String ? rawContent : '',
      isActive: rawActive is bool ? rawActive : true,
      category: rawCategory is String ? rawCategory : 'Umum',
    );
  }

  String toJson() => json.encode(toMap());

  factory RunningTextMessage.fromJson(String source) =>
      RunningTextMessage.fromMap(json.decode(source));

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RunningTextMessage &&
          other.id == id &&
          other.content == content &&
          other.isActive == isActive &&
          other.category == category;

  @override
  int get hashCode => Object.hash(id, content, isActive, category);

  @override
  String toString() =>
      'RunningTextMessage(id: $id, content: $content, isActive: $isActive, '
      'category: $category)';
}

// ---------------------------------------------------------------------------
// MediaBanner — port dari src/media_banner.dart
// ---------------------------------------------------------------------------

class MediaBanner {
  final String id;
  final String header;
  final String title;
  final String content;
  final String footer;
  final bool isActive;
  final String? base64Image;

  const MediaBanner({
    required this.id,
    required this.header,
    required this.title,
    required this.content,
    this.footer = '',
    this.isActive = true,
    this.base64Image,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'header': header,
    'title': title,
    'content': content,
    'footer': footer,
    'isActive': isActive,
    'base64Image': base64Image,
  };

  factory MediaBanner.fromMap(Map<String, dynamic> map) {
    final rawId = map['id'];
    final rawHeader = map['header'];
    final rawTitle = map['title'];
    final rawContent = map['content'];
    final rawSubtitle = map['subtitle'];
    final rawFooter = map['footer'];
    final rawActive = map['isActive'];
    final rawImage = map['base64Image'];
    return MediaBanner(
      id: rawId is String
          ? rawId
          : DateTime.now().millisecondsSinceEpoch.toString(),
      header: rawHeader is String ? rawHeader : 'INFO MASJID',
      title: rawTitle is String ? rawTitle : '',
      // Kompatibilitas mundur: payload lama memakai kunci `subtitle`.
      content: rawContent is String
          ? rawContent
          : rawSubtitle is String
          ? rawSubtitle
          : '',
      footer: rawFooter is String ? rawFooter : '',
      isActive: rawActive is bool ? rawActive : true,
      base64Image: rawImage is String && rawImage.isNotEmpty ? rawImage : null,
    );
  }

  String toJson() => json.encode(toMap());

  factory MediaBanner.fromJson(String source) =>
      MediaBanner.fromMap(json.decode(source));

  MediaBanner copyWith({
    String? id,
    String? header,
    String? title,
    String? content,
    String? footer,
    bool? isActive,
    String? base64Image,
    bool clearBase64Image = false,
  }) {
    return MediaBanner(
      id: id ?? this.id,
      header: header ?? this.header,
      title: title ?? this.title,
      content: content ?? this.content,
      footer: footer ?? this.footer,
      isActive: isActive ?? this.isActive,
      base64Image: clearBase64Image ? null : (base64Image ?? this.base64Image),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaBanner &&
          other.id == id &&
          other.header == header &&
          other.title == title &&
          other.content == content &&
          other.footer == footer &&
          other.isActive == isActive &&
          other.base64Image == base64Image;

  @override
  int get hashCode =>
      Object.hash(id, header, title, content, footer, isActive, base64Image);

  @override
  String toString() =>
      'MediaBanner(id: $id, header: $header, title: $title, '
      'content: $content, footer: $footer, isActive: $isActive, '
      'base64Image: ${base64Image == null ? 'null' : '[set]'})';
}

// ---------------------------------------------------------------------------
// KasTransaction + KasSummary — port dari src/kas_transaction.dart
// ---------------------------------------------------------------------------

enum KasType { masuk, keluar }

class KasTransaction {
  final String id;
  final KasType type;
  final int amount;
  final String description;
  final DateTime date;

  const KasTransaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.description,
    required this.date,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'type': type.name,
    'amount': amount,
    'description': description,
    'date': date.toIso8601String(),
  };

  factory KasTransaction.fromMap(Map<String, dynamic> map) {
    final rawId = map['id'];
    final rawDescription = map['description'];
    final rawDate = map['date'];
    return KasTransaction(
      id: rawId is String
          ? rawId
          : DateTime.now().millisecondsSinceEpoch.toString(),
      type: KasType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => KasType.masuk,
      ),
      amount: map['amount'] is num ? (map['amount'] as num).toInt() : 0,
      description: rawDescription is String ? rawDescription : '',
      date: rawDate is String
          ? (DateTime.tryParse(rawDate) ?? DateTime.now())
          : DateTime.now(),
    );
  }

  String toJson() => json.encode(toMap());

  factory KasTransaction.fromJson(String source) =>
      KasTransaction.fromMap(json.decode(source));

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KasTransaction &&
          other.id == id &&
          other.type == type &&
          other.amount == amount &&
          other.description == description &&
          other.date == date;

  @override
  int get hashCode => Object.hash(id, type, amount, description, date);

  @override
  String toString() =>
      'KasTransaction(id: $id, type: ${type.name}, amount: $amount, '
      'description: $description, date: $date)';
}

class KasSummary {
  final int totalMasuk;
  final int totalKeluar;
  final int saldo;

  const KasSummary({this.totalMasuk = 0, this.totalKeluar = 0, this.saldo = 0});

  factory KasSummary.fromTransactions(List<KasTransaction> transactions) {
    var masuk = 0;
    var keluar = 0;
    for (final t in transactions) {
      if (t.type == KasType.masuk) {
        masuk += t.amount;
      } else {
        keluar += t.amount;
      }
    }
    return KasSummary(
      totalMasuk: masuk,
      totalKeluar: keluar,
      saldo: masuk - keluar,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KasSummary &&
          other.totalMasuk == totalMasuk &&
          other.totalKeluar == totalKeluar &&
          other.saldo == saldo;

  @override
  int get hashCode => Object.hash(totalMasuk, totalKeluar, saldo);

  @override
  String toString() =>
      'KasSummary(totalMasuk: $totalMasuk, totalKeluar: $totalKeluar, '
      'saldo: $saldo)';
}

// ---------------------------------------------------------------------------
// SpecialImage — port dari src/special_image.dart
// ---------------------------------------------------------------------------

class SpecialImage {
  final String id;
  final String caption;
  final String base64Image;
  final bool isActive;

  const SpecialImage({
    required this.id,
    required this.base64Image,
    this.caption = '',
    this.isActive = true,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'caption': caption,
    'base64Image': base64Image,
    'isActive': isActive,
  };

  factory SpecialImage.fromMap(Map<String, dynamic> map) {
    final rawId = map['id'];
    final rawCaption = map['caption'];
    final rawImage = map['base64Image'];
    final rawActive = map['isActive'];
    return SpecialImage(
      id: rawId is String
          ? rawId
          : DateTime.now().millisecondsSinceEpoch.toString(),
      caption: rawCaption is String ? rawCaption : '',
      base64Image: rawImage is String ? rawImage : '',
      isActive: rawActive is bool ? rawActive : true,
    );
  }

  String toJson() => json.encode(toMap());

  factory SpecialImage.fromJson(String source) =>
      SpecialImage.fromMap(json.decode(source));

  SpecialImage copyWith({
    String? id,
    String? caption,
    String? base64Image,
    bool? isActive,
  }) {
    return SpecialImage(
      id: id ?? this.id,
      caption: caption ?? this.caption,
      base64Image: base64Image ?? this.base64Image,
      isActive: isActive ?? this.isActive,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpecialImage &&
          other.id == id &&
          other.caption == caption &&
          other.base64Image == base64Image &&
          other.isActive == isActive;

  @override
  int get hashCode => Object.hash(id, caption, base64Image, isActive);

  @override
  String toString() =>
      'SpecialImage(id: $id, caption: $caption, '
      'base64Image: ${base64Image.isEmpty ? 'null' : '[set]'}, '
      'isActive: $isActive)';
}

// ---------------------------------------------------------------------------
// BackgroundImage — port dari src/background_image.dart
// ---------------------------------------------------------------------------

class BackgroundImage {
  final String id;
  final String base64Image;
  final bool isActive;

  const BackgroundImage({
    required this.id,
    required this.base64Image,
    this.isActive = true,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'base64Image': base64Image,
    'isActive': isActive,
  };

  factory BackgroundImage.fromMap(Map<String, dynamic> map) {
    final rawId = map['id'];
    final rawImage = map['base64Image'];
    final rawActive = map['isActive'];
    return BackgroundImage(
      id: rawId is String
          ? rawId
          : DateTime.now().millisecondsSinceEpoch.toString(),
      base64Image: rawImage is String ? rawImage : '',
      isActive: rawActive is bool ? rawActive : true,
    );
  }

  String toJson() => json.encode(toMap());

  factory BackgroundImage.fromJson(String source) =>
      BackgroundImage.fromMap(json.decode(source));

  BackgroundImage copyWith({String? id, String? base64Image, bool? isActive}) {
    return BackgroundImage(
      id: id ?? this.id,
      base64Image: base64Image ?? this.base64Image,
      isActive: isActive ?? this.isActive,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BackgroundImage &&
          other.id == id &&
          other.base64Image == base64Image &&
          other.isActive == isActive;

  @override
  int get hashCode => Object.hash(id, base64Image, isActive);

  @override
  String toString() =>
      'BackgroundImage(id: $id, '
      'base64Image: ${base64Image.isEmpty ? 'null' : '[set]'}, '
      'isActive: $isActive)';
}

// ---------------------------------------------------------------------------
// StateSnapshot — port dari src/state_snapshot.dart
// ---------------------------------------------------------------------------

Map<String, dynamic> _stringKeyed(Map raw) => {
  for (final entry in raw.entries) '${entry.key}': entry.value,
};

List<T> _parseList<T>(
  Object? raw,
  T Function(Map<String, dynamic> map) fromMap,
) {
  if (raw is! List) return const [];
  final result = <T>[];
  for (final entry in raw) {
    if (entry is Map) {
      result.add(fromMap(_stringKeyed(entry)));
    }
  }
  return result;
}

/// Snapshot keadaan lengkap TV (`SyncAction.stateSnapshot`, TV -> Remote).
/// TV adalah **trust source**: remote menimpa cermin lokalnya dari sini.
class StateSnapshot {
  final MosqueConfig config;
  final List<RunningTextMessage> runningTexts;
  final List<MediaBanner> banners;
  final List<KasTransaction> kasTransactions;
  final List<SpecialImage> sideImages;
  final List<BackgroundImage> backgroundImages;
  final String? mosqueLogo;
  final bool hasData;

  const StateSnapshot({
    this.config = const MosqueConfig(),
    this.runningTexts = const [],
    this.banners = const [],
    this.kasTransactions = const [],
    this.sideImages = const [],
    this.backgroundImages = const [],
    this.mosqueLogo,
    this.hasData = false,
  });

  Map<String, dynamic> toMap() => {
    'config': config.toMap(),
    'runningTexts': [for (final message in runningTexts) message.toMap()],
    'banners': [for (final banner in banners) banner.toMap()],
    'kasTransactions': [
      for (final transaction in kasTransactions) transaction.toMap(),
    ],
    'sideImages': [for (final image in sideImages) image.toMap()],
    'backgroundImages': [for (final image in backgroundImages) image.toMap()],
    'mosqueLogo': mosqueLogo,
    'hasData': hasData,
  };

  factory StateSnapshot.fromMap(Map<String, dynamic> map) {
    final rawConfig = map['config'];
    final rawHasData = map['hasData'];
    return StateSnapshot(
      config: rawConfig is Map
          ? MosqueConfig.fromMap(_stringKeyed(rawConfig))
          : const MosqueConfig(),
      runningTexts: _parseList(map['runningTexts'], RunningTextMessage.fromMap),
      banners: _parseList(map['banners'], MediaBanner.fromMap),
      kasTransactions: _parseList(
        map['kasTransactions'],
        KasTransaction.fromMap,
      ),
      sideImages: _parseList(map['sideImages'], SpecialImage.fromMap),
      backgroundImages: _parseList(
        map['backgroundImages'],
        BackgroundImage.fromMap,
      ),
      mosqueLogo:
          map['mosqueLogo'] is String &&
              (map['mosqueLogo'] as String).isNotEmpty
          ? map['mosqueLogo'] as String
          : null,
      hasData: rawHasData is bool ? rawHasData : false,
    );
  }

  static bool _listsEqual<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StateSnapshot &&
          other.config == config &&
          other.hasData == hasData &&
          _listsEqual(other.runningTexts, runningTexts) &&
          _listsEqual(other.banners, banners) &&
          _listsEqual(other.kasTransactions, kasTransactions) &&
          _listsEqual(other.sideImages, sideImages) &&
          _listsEqual(other.backgroundImages, backgroundImages) &&
          other.mosqueLogo == mosqueLogo;

  @override
  int get hashCode => Object.hash(
    config,
    hasData,
    Object.hashAll(runningTexts),
    Object.hashAll(banners),
    Object.hashAll(kasTransactions),
    Object.hashAll(sideImages),
    Object.hashAll(backgroundImages),
    mosqueLogo,
  );

  @override
  String toString() =>
      'StateSnapshot(hasData: $hasData, config: $config, '
      'runningTexts: ${runningTexts.length}, banners: ${banners.length}, '
      'kasTransactions: ${kasTransactions.length}, '
      'sideImages: ${sideImages.length}, '
      'backgroundImages: ${backgroundImages.length}, '
      'mosqueLogo: ${mosqueLogo == null ? 'null' : '[set]'})';
}
