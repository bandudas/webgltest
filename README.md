# Pulau

Game jelajah kepulauan yang santai untuk Android box (dirancang untuk GPU kelas Mali-G31 dan RAM 2 GB).
Berlayar di antara 14 pulau buatan prosedural, dengan siklus siang-malam (satu hari = 6 menit),
lalu temukan peti harta di setiap pulau. Pilar cahaya kuning menandai peti yang belum dibuka.

## Kontrol (remote)

| Tombol | Fungsi |
|---|---|
| Atas | Maju / tambah kecepatan |
| Bawah | Rem, lalu mundur |
| Kiri / Kanan | Belok |
| OK | Buka peti (kalau dekat), selain itu ganti kamera (normal, jauh, dekat air) |
| Menu | Grafis: tinggi (720p + bayangan) / ringan (540p tanpa bayangan) |
| Back 2x | Keluar |

Keyboard dan gamepad juga bisa dipakai (panah/WASD, Enter/Spasi, M/Tab).

## Isi

- Laut dengan gelombang di vertex shader, air dangkal berwarna toska di sekitar pulau.
- Pulau prosedural low-poly (pasir, rumput, batu) dari seed tetap, dihiasi pohon palem, batu, rumput,
  menara, dermaga, bangkai kapal, bendera, peti (MultiMesh supaya ringan).
- Kapal-kapal lain berlayar di sekeliling kepulauan, perahu nelayan, dan kapal hantu yang hanya muncul malam hari.
- Langit buatan sendiri: matahari, bulan, bintang, warna fajar dan senja.

## Build

GitHub Actions (`.github/workflows/build.yml`) mengekspor APK dengan Godot 4.3 (renderer Compatibility)
dan menerbitkannya di Release `pulau-latest`.

Dibuka di Godot 4.3: Project > Export > Android.

## Kredit aset

Model 3D: **Kenney** (www.kenney.nl), Pirate Kit dan Watercraft Kit, lisensi CC0.
Diunduh oleh `.github/workflows/fetch_assets.yml`, disimpan di `assets/`.
