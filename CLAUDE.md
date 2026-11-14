# Gang Salju (branch `noir`)

Scene noir malam bersalju, sudut pandang orang pertama, bergaya grafis realistis awal 2000-an.
Godot 4.3, renderer **Compatibility** (OpenGL ES 3). Bahasa UI, komentar, dan commit: **Bahasa Indonesia**.

## Perangkat target

Android box murah: Allwinner H313 (4x Cortex-A53), GPU Mali-G31 MP2, RAM 2 GB, Android 10.
APK berisi armeabi-v7a dan arm64-v8a. Dikendalikan dengan **remote IR** (D-pad, OK, Menu, Back).

Hasil di box (dilaporkan pengguna):
- Gang Salju 1.0 (OmniLight + tekstur 1K): di bawah 20 fps meski 360p.
- Gang Salju 1.1 (versi sekarang): **belum diukur di box**. Langkah pertama berikutnya: minta angka FPS.
- Game lain di repo ini (branch `pulau`): sekitar 30 fps setelah optimasi.

## Struktur

| Path | Isi |
|---|---|
| `scripts/main.gd` | Semua scene dibangun lewat kode: jalan, gedung, gang, lampu, neon, properti, salju, uap, kamera, HUD, kualitas otomatis, mode hantu, argumen uji |
| `scripts/music.gd` | Sequencer musik ambient generatif (pad, bel FM, drone, dengung kota) |
| `shaders/lit.gdshaderinc` | Pencahayaan satu pass untuk maks 10 lampu titik (pengganti OmniLight3D) |
| `shaders/surface.gdshader` | Material umum (tekstur foto + normal + roughness, atau warna polos) |
| `shaders/facade.gdshader` | Fasad gedung: bata + jendela prosedural (sebagian menyala) |
| `shaders/post.gdshader` | Post-process: grading noir, vignette, grain, efek gerak lambat dan hantu |
| `shaders/glow_pool.gdshader` | Genangan cahaya palsu di bawah lampu jalan |
| `textures/<id>/{diff,nor,rough}.jpg` | Tekstur Poly Haven CC0. `.import` diatur manual: VRAM compressed, warna 512 px, normal/rough 256 px |
| `audio/*.wav` | Sampel buatan `tools/make_audio.py` (numpy). drone dan hum di-loop lewat `.import` |
| `.github/workflows/build.yml` | Build APK, terbit di Release `noir-latest` |
| `.github/workflows/fetch_textures.yml` | Pengunduh tekstur Poly Haven (hanya jalan kalau file ini diubah) |

## Perintah

```bash
# wajib sekali setelah clone / menambah aset (mengimpor tekstur, audio, mendaftarkan class)
godot --headless --editor --quit --path .

# render screenshot uji (Linux tanpa layar; butuh xvfb + mesa)
xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 --resolution 1280x720 -- \
  shot=/tmp/a.png frames=60 q=1 pos=-2,-16 yaw=-20
```

Argumen uji (setelah `--`): `shot=` path PNG, `frames=` frame sebelum diambil, `pos=x,z`, `yaw=` derajat,
`q=0..3` (360p/480p/540p/720p, mematikan kualitas otomatis), `slow=1` gerak lambat, `ghost=1` langsung mode hantu,
`nopost=1` tanpa post-process. Output mencetak `SHOT ... fps= draws= objs= prims=`.

**FPS dari renderer software (llvmpipe) tidak mewakili box.** Pakai `draws` dan jumlah lampu sebagai indikator;
ukuran sebenarnya hanya dari box pengguna (angka FPS tampil di pojok kanan atas).

## Build dan rilis

Push ke branch `noir` akan menjalankan GitHub Actions: unduh Godot 4.3 + template ekspor, buat keystore debug,
ekspor release, lalu terbitkan APK di Release `noir-latest`. Link tetap untuk pengguna:
https://github.com/bandudas/webgltest/releases/download/noir-latest/GangSalju.apk

- Naikkan `version/code` dan `version/name` di `export_presets.cfg` tiap rilis.
- Perubahan pada `README.md`, `CLAUDE.md`, dan workflow tekstur tidak memicu build.
- Jangan kirim APK lewat chat: file besar terpotong. Selalu beri link Release.
- Pengguna memasang APK lewat flashdisk atau dengan mengunduh langsung di browser box.

## Aturan dan pelajaran

- **Lampu:** jangan pakai OmniLight3D. Compatibility menggambar ulang objek per lampu dan itu yang membuat 1.0 lambat.
  Tambah lampu lewat `_add_light()` (maks 10). Kedip neon lewat global shader `neon0..2`.
- **Geometri statis:** pakai `_bbox()` (digabung per material per blok 24 m), bukan `_box()`, kecuali objek unik.
  `_box_mesh()` membuat UV dalam meter supaya tekstur foto tidak melar.
- **Tekstur baru:** tulis `.import` dengan `compress/mode=2` dan `process/size_limit` (512 warna, 256 normal/rough),
  `compress/normal_map=1` untuk normal map.
- **GDScript:** tipe dari literal array tidak bisa disimpulkan (`var x: float = [..][i]`, bukan `:=`).
  Script dengan `class_name` belum terdaftar sampai editor import; untuk aman pakai `preload()`.
- **Shader Godot:** varying tidak boleh diisi di dalam fungsi; isi di `vertex()`.
- **Shell:** jangan `pkill -f godot` dari perintah yang teksnya mengandung "godot" (membunuh shell sendiri).
- **Remote:** semua aksi lewat InputMap (`maju`, `mundur`, `kiri`, `kanan`, `ok`, `menu`); Back ditangani lewat
  `NOTIFICATION_WM_GO_BACK_REQUEST` (tekan dua kali untuk keluar).
- **Aset:** hanya CC0 (Poly Haven, Kenney) atau buatan sendiri. Scene dan tulisan neon orisinal; jangan memakai
  karakter, nama, atau lokasi dari game/film yang ada, meski pengguna menyebut gaya "ala" game tertentu.
- Penanda launcher Android TV (LEANBACK) belum masuk ke APK (ekspor non-gradle). Aplikasi tetap muncul di daftar aplikasi.

## Ide berikutnya yang sudah dibahas

- Minta angka FPS 1.1 di box. Kalau masih di bawah 25: matikan normal map untuk objek jauh, kurangi jumlah lampu
  di shader, kecilkan salju lagi.
- Scene paling realistis untuk box ini: **interior kecil dengan cahaya di-bake** (mis. kamar apartemen malam hujan,
  lampu meja, neon dari luar jendela, kamera melayang). Uji dulu apakah LightmapGI tampil di Compatibility di box;
  kalau tidak, bake cahaya di Blender ke tekstur. Model scan Poly Haven (CC0) diturunkan polygon dan teksturnya.
