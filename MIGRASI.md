# Pindah ke Claude Code

Semua pekerjaan sudah ada di GitHub (`bandudas/webgltest`), jadi tidak ada yang perlu disalin dari chat.
Riwayat percakapan tidak ikut pindah; penggantinya adalah file `CLAUDE.md` di tiap branch, yang otomatis
dibaca Claude Code saat dijalankan di folder proyek.

## Isi repo

| Branch | Isi | APK terbaru |
|---|---|---|
| `noir` | Gang Salju: scene noir bersalju, mode hantu, musik generatif (Godot 4.3) | Release `noir-latest` |
| `pulau` | Pulau: jelajah kepulauan dengan perahu, siang-malam, peti harta (Godot 4.3) | Release `pulau-latest` |
| `genart-fps-test` | Aplikasi uji GPU (Java + OpenGL ES, tanpa engine) | file `apk/GenArtFpsTest.apk` di branch |
| `master` | Isi lama repo, tidak disentuh | - |

## Langkah di komputer Anda

1. **Pasang Claude Code** (butuh Node.js 18+):
   ```
   npm install -g @anthropic-ai/claude-code
   ```
2. **Pasang alat kerja:**
   - Git
   - Godot 4.3 (godotengine.org). Opsional tapi berguna untuk mencoba di PC; Claude Code juga bisa memakainya
     untuk menguji dan mengambil screenshot.
   - Python 3 + numpy (hanya kalau ingin membuat ulang sampel musik).
   - Untuk build APK lokal (opsional): JDK 17, Android SDK, dan template ekspor Godot 4.3.
     Tanpa ini pun tidak apa-apa: build APK tetap jalan otomatis di GitHub Actions setiap kali push.
3. **Clone dan buka proyek:**
   ```
   git clone https://github.com/bandudas/webgltest.git
   cd webgltest
   git checkout noir        # atau: pulau
   claude
   ```
4. **Kalimat pembuka yang disarankan** untuk Claude Code:
   > Baca CLAUDE.md. Gang Salju 1.1 di box saya dapat ___ fps di ___p. Lanjutkan optimasinya.

   atau
   > Baca CLAUDE.md. Buat scene baru: kamar apartemen malam hujan dengan cahaya di-bake, di branch baru.

## Perlu diketahui

- **Push ke GitHub:** Claude Code memakai login git di komputer Anda (`gh auth login` atau kredensial git).
  Setiap push ke `noir` atau `pulau` membangun APK baru dan memperbarui link Release.
- **Link APK tetap:**
  - https://github.com/bandudas/webgltest/releases/download/noir-latest/GangSalju.apk
  - https://github.com/bandudas/webgltest/releases/download/pulau-latest/Pulau.apk
- **Belum diuji di box:** Gang Salju 1.1 (pencahayaan satu pass, tekstur kecil, mode hantu, musik).
- **Lisensi aset:** tekstur Poly Haven dan model Kenney berlisensi CC0; musik disintesis sendiri.
