/// Satu display TV yang disimpan pengguna di layar Koneksi
/// (nama bebas + alamat IP di LAN). Port selalu [kNekiosPort] dari
/// nekios_core — tidak disimpan per-display di v1.
class DisplayTersimpan {
  const DisplayTersimpan({required this.nama, required this.ip});

  final String nama;
  final String ip;

  factory DisplayTersimpan.fromJson(Map<String, dynamic> json) =>
      DisplayTersimpan(
        nama: json['nama'] as String? ?? '',
        ip: json['ip'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'nama': nama, 'ip': ip};

  DisplayTersimpan copyWith({String? nama, String? ip}) =>
      DisplayTersimpan(nama: nama ?? this.nama, ip: ip ?? this.ip);

  @override
  bool operator ==(Object other) =>
      other is DisplayTersimpan && other.nama == nama && other.ip == ip;

  @override
  int get hashCode => Object.hash(nama, ip);
}
