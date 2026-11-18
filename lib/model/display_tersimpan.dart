/// Jenis display yang bisa dikendalikan remote pusat.
enum TipeDisplay {
  /// nekios-school: protokol nekios-core lewat WebSocket port 8920.
  sekolah,

  /// tv_display masjid-you: protokol warisan masjid (Rute A) lewat
  /// WebSocket port 8080 atau Bluetooth Classic.
  masjid,
}

/// Transport untuk display masjid (display sekolah selalu WebSocket
/// nekios-core — tidak ada pilihan).
enum TransportMasjid { wifi, bluetooth }

/// Satu display TV yang disimpan pengguna di layar Koneksi.
///
/// Display [TipeDisplay.sekolah]: hanya [nama] + [ip] yang dipakai;
/// port selalu `kNekiosPort` nekios_core (8920).
///
/// Display [TipeDisplay.masjid]: [transport] memilih jalur —
/// Wi-Fi memakai [ip] (port warisan 8080), Bluetooth memakai
/// [alamatBluetooth]/[namaBluetooth] dan [pinBluetooth] (PIN 4 digit
/// TV masjid untuk handshake RFCOMM; disimpan lokal apa adanya
/// seperti pola penyimpanan yang ada dan TIDAK pernah dicatat ke log).
///
/// Entri lama (JSON tanpa field `tipe`) dibaca sebagai display
/// sekolah — perilaku persis sebelum Rute A.
class DisplayTersimpan {
  const DisplayTersimpan({
    required this.nama,
    required this.ip,
    this.tipe = TipeDisplay.sekolah,
    this.transport = TransportMasjid.wifi,
    this.alamatBluetooth = '',
    this.namaBluetooth = '',
    this.pinBluetooth = '',
  });

  final String nama;
  final String ip;
  final TipeDisplay tipe;
  final TransportMasjid transport;

  /// Alamat MAC perangkat Bluetooth TV masjid (transport Bluetooth).
  final String alamatBluetooth;

  /// Nama Bluetooth TV masjid saat disimpan (untuk label daftar).
  final String namaBluetooth;

  /// PIN 4 digit handshake Bluetooth TV masjid. Kosong = belum diisi;
  /// TV menolak paket data sebelum auth, jadi koneksi BT tanpa PIN
  /// akan berhenti di tahap autentikasi.
  final String pinBluetooth;

  bool get adalahMasjid => tipe == TipeDisplay.masjid;

  bool get pakaiBluetooth =>
      adalahMasjid && transport == TransportMasjid.bluetooth;

  /// Alamat ringkas untuk subjudul daftar display.
  String get alamatRingkas => pakaiBluetooth
      ? (namaBluetooth.isNotEmpty
            ? '$namaBluetooth · $alamatBluetooth'
            : alamatBluetooth)
      : ip;

  factory DisplayTersimpan.fromJson(Map<String, dynamic> json) =>
      DisplayTersimpan(
        nama: json['nama'] as String? ?? '',
        ip: json['ip'] as String? ?? '',
        tipe:
            TipeDisplay.values.asNameMap()[json['tipe']] ?? TipeDisplay.sekolah,
        transport:
            TransportMasjid.values.asNameMap()[json['transport']] ??
            TransportMasjid.wifi,
        alamatBluetooth: json['alamatBluetooth'] as String? ?? '',
        namaBluetooth: json['namaBluetooth'] as String? ?? '',
        pinBluetooth: json['pinBluetooth'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
    'nama': nama,
    'ip': ip,
    'tipe': tipe.name,
    'transport': transport.name,
    'alamatBluetooth': alamatBluetooth,
    'namaBluetooth': namaBluetooth,
    'pinBluetooth': pinBluetooth,
  };

  DisplayTersimpan copyWith({
    String? nama,
    String? ip,
    TipeDisplay? tipe,
    TransportMasjid? transport,
    String? alamatBluetooth,
    String? namaBluetooth,
    String? pinBluetooth,
  }) => DisplayTersimpan(
    nama: nama ?? this.nama,
    ip: ip ?? this.ip,
    tipe: tipe ?? this.tipe,
    transport: transport ?? this.transport,
    alamatBluetooth: alamatBluetooth ?? this.alamatBluetooth,
    namaBluetooth: namaBluetooth ?? this.namaBluetooth,
    pinBluetooth: pinBluetooth ?? this.pinBluetooth,
  );

  @override
  bool operator ==(Object other) =>
      other is DisplayTersimpan &&
      other.nama == nama &&
      other.ip == ip &&
      other.tipe == tipe &&
      other.transport == transport &&
      other.alamatBluetooth == alamatBluetooth &&
      other.namaBluetooth == namaBluetooth &&
      other.pinBluetooth == pinBluetooth;

  @override
  int get hashCode => Object.hash(
    nama,
    ip,
    tipe,
    transport,
    alamatBluetooth,
    namaBluetooth,
    pinBluetooth,
  );
}
