# bluetooth_rfcomm

Plugin lokal nekios-remote: Bluetooth Classic (RFCOMM) sisi **klien**
sebagai pipa byte mentah menuju tv_display masjid-you (Rute A —
lihat `docs/DECISIONS.md` ADR-003 di repo nekios-remote).

Diport dari separuh klien plugin `bluetooth_sync` masjid-you:
kontrak channel (`id.nekios/bluetooth_rfcomm` +
`.../events`), strategi koneksi (socket bonded dulu, fallback
insecure via refleksi, watchdog 15 detik), dan alur izin runtime
sama persis. Perbedaan yang disengaja:

- **Tanpa sisi host** — aplikasi ini tidak pernah menjadi display.
- **Tanpa framing di native** — bingkai 4-byte big-endian + JSON,
  handshake PIN, dan chunking hidup di Dart (`lib/masjid/` di app)
  agar bisa diuji unit. Byte di kabel identik dengan masjid-you.
- **Android saja.** Di platform lain channel tidak terdaftar dan
  lapisan transport memperlakukannya sebagai "Bluetooth tidak
  tersedia".
