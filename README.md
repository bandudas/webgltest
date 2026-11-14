# GenArt FPS Test

Aplikasi uji OpenGL ES 3.0 untuk Android box (target: Allwinner H313, Mali-G31, Android 10).
Tujuannya mengukur batas GPU box sebelum menentukan gaya generative art.

## Kontrol (remote box)

| Tombol | Fungsi |
|---|---|
| KIRI / KANAN | Ganti mode (shader, flow field, overdraw, 3D objek, 3D bola) |
| ATAS / BAWAH | Naik / turun level beban (1-5) |
| OK / ENTER | Ganti mode resolusi: AUTO, 720p, 540p, 360p |
| MENU | Sembunyikan / tampilkan HUD |

Layar sentuh / air mouse: sepertiga kiri/kanan = ganti mode, pita atas/bawah = level, tengah = resolusi.

## Mode

1. **Shader prosedural** - fbm noise; level = jumlah oktaf (1, 2, 3, 4, 6). Menguji beban fragment shader.
2. **Flow field + jejak** - partikel disimulasikan di GPU (transform feedback) dengan jejak memudar; level = 4k, 8k, 16k, 32k, 64k partikel.
3. **Overdraw** - blob additive besar bertumpuk; level = 4, 8, 16, 32, 64 lapis. Menguji fill-rate dan bandwidth memori.
4. **3D: objek low-poly** - icosphere 80 segitiga yang di-instancing membentuk spiral berputar, flat shading + rim light + kabut; level = 64, 256, 1024, 2048, 4096 objek (5k-328k segitiga). Menguji jumlah objek dan vertex throughput.
5. **3D: bola berdeformasi** - satu icosphere yang dideformasi gelombang di vertex shader; level = subdivisi 2-6 (320-81.920 segitiga). Menguji kepadatan mesh.

Scene dirender ke framebuffer beresolusi lebih rendah lalu di-scale ke layar.
Mode AUTO menurunkan resolusi (minimum 288p) saat FPS di bawah ~93% refresh rate layar,
dan menaikkannya lagi (maksimum 720p) saat stabil.

## Cara membaca hasil

- Catat per mode: level tertinggi yang masih stabil di 60 FPS, dan resolusi scene yang dipilih AUTO.
- HUD juga menampilkan nama GPU (`GL_RENDERER`) dan versi OpenGL. Jika nama GPU bukan Mali-G31, spesifikasi box tidak sesuai iklan.
- Log yang sama ditulis ke logcat dengan tag `GenArtFps`: `adb logcat -s GenArtFps`.
- Jika refresh layar terbaca 30 Hz, target AUTO ikut 30 FPS. Ubah mode output HDMI box ke 60 Hz.

## Build

APK tidak berisi kode native, jadi satu APK jalan di box 32-bit (armeabi-v7a) maupun 64-bit.

### Opsi A - Android Studio (paling mudah)
1. Install Android Studio, pilih **Open**, arahkan ke folder ini.
2. Tunggu sinkronisasi Gradle selesai (butuh internet; Android Studio akan menawarkan SDK 34).
3. Menu **Build > Build APK(s)**. Hasil: `app/build/outputs/apk/debug/app-debug.apk`.

### Opsi B - Command line
Butuh JDK 17 dan Android SDK (platform 34, build-tools 34).
```
export ANDROID_HOME=/path/ke/android-sdk
./gradlew assembleDebug
```

### Opsi C - GitHub Actions
Unggah folder ini ke repositori GitHub. Workflow `.github/workflows/build.yml` akan membangun APK;
unduh dari tab **Actions > Artifacts**.

## Install ke box

- **Flashdisk:** salin `app-debug.apk`, colok ke box, buka File Manager, pilih APK, install
  (izinkan "Install unknown apps" untuk File Manager).
- **ADB:** aktifkan USB debugging di box, lalu
  `adb connect <IP-box>` dan `adb install -r app-debug.apk`.

Aplikasi muncul di launcher dengan nama "GenArt FPS Test" (tanpa ikon khusus).
