# Pulau (branch `pulau`)

Game jelajah kepulauan yang santai: perahu layar, 14 pulau prosedural, siklus siang-malam (6 menit),
14 peti harta yang ditandai pilar cahaya, kapal-kapal lain, kapal hantu di malam hari.
Godot 4.3, renderer **Compatibility**. Bahasa UI, komentar, dan commit: **Bahasa Indonesia**.

## Perangkat target

Android box: Allwinner H313 (Cortex-A53), Mali-G31 MP2, RAM 2 GB, Android 10, dikendalikan remote IR.
Versi 1.0 dapat 10 fps; **versi 1.1 (sekarang) sekitar 30 fps** di box menurut pengguna.

## Struktur

| Path | Isi |
|---|---|
| `scripts/main.gd` | Lingkungan, langit siang-malam, air, kamera, kontrol remote, HUD, kualitas otomatis, argumen uji |
| `scripts/world.gd` | Generator pulau (mesh low-poly dari noise), dekorasi MultiMesh, peti, kapal NPC, tabrakan pantai |
| `scripts/boat.gd` | Perahu pemain: fisika sederhana, naik-turun ikut gelombang, buih |
| `scripts/waves.gd` | Fungsi gelombang; **harus sama** dengan `shaders/water.gdshader` |
| `shaders/water.gdshader` | Air unshaded dengan pencahayaan manual + air dangkal di sekitar pulau |
| `shaders/sky.gdshader`, `beacon.gdshader` | Langit (matahari, bulan, bintang) dan pilar cahaya peti |
| `assets/pirate`, `assets/water` | Kenney Pirate Kit dan Watercraft Kit (CC0), glb + `Textures/colormap.png` |
| `.github/workflows/build.yml` | Build APK, terbit di Release `pulau-latest` |
| `.github/workflows/fetch_assets.yml` | Pengunduh aset Kenney (hanya jalan kalau file ini diubah) |

Model Kenney menghadap **+Z**. Ukuran penting: perahu layar sekitar 1,8 x 3,8 m, kapal 10-21 m, palem sekitar 4 m.

## Perintah

```bash
godot --headless --editor --quit --path .   # impor aset, wajib sekali setelah clone

xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 --resolution 1280x720 -- \
  shot=/tmp/a.png frames=90 tod=0.4 cam=0
```

Argumen uji: `shot=`, `frames=`, `tod=` (0..1 waktu hari), `cam=0..2`, `pos=x,z`, `yaw=` derajat,
`auto=1` (perahu jalan sendiri), `side=1` (kamera samping, cek arah haluan), `q=0..3` (kualitas tetap), `open=1`.
FPS dari renderer software tidak mewakili box.

## Build dan rilis

Push ke `pulau` membangun APK dan menerbitkannya di Release `pulau-latest`:
https://github.com/bandudas/webgltest/releases/download/pulau-latest/Pulau.apk
Naikkan `version/code` dan `version/name` di `export_presets.cfg`. Jangan kirim APK lewat chat (terpotong).

## Kontrol

Atas maju, bawah rem/mundur, kiri/kanan belok, OK buka peti (kalau dalam 13 m) atau ganti kamera,
Menu ganti grafis (otomatis, 360p, 480p, 540p, 720p + bayangan), Back dua kali keluar.

## Pelajaran

- Yang membuat 1.0 lambat: 720p + bayangan + air yang memakai pipeline lampu Godot. Skrip game hanya
  sekitar 0,25 ms per frame, jadi beban ada di GPU.
- Langit dan HUD diperbarui tiap 0,5 dan 0,25 detik, bukan tiap frame.
- HUD harus diposisikan ulang dengan anchor saat resolusi berubah (`_layout_hud`).
- Tipe dari literal array tidak bisa disimpulkan di GDScript; tulis tipe eksplisit.
- Aset hanya CC0 atau buatan sendiri.
