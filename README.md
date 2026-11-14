# Gang Salju

Scene noir malam bersalju dari sudut pandang orang pertama, bergaya grafis realistis awal 2000-an:
tekstur foto, lampu jalan sodium, neon, jendela menyala, uap dari saluran, salju turun, film grain,
dan efek gerak lambat. Dirancang untuk Android box kelas Mali-G31 (renderer Compatibility, Godot 4.3).

## Kontrol (remote)

| Tombol | Fungsi |
|---|---|
| Atas / Bawah | Jalan maju / mundur |
| Kiri / Kanan | Menoleh |
| OK | Gerak lambat (nyala/mati) |
| Menu | Grafis: otomatis, 360p, 480p, 540p, 720p |
| Back 2x | Keluar |

Diam 10 detik: **mode hantu**. Kamera melayang sendiri menyusuri jalan dan gang, pandangan berbayang. Tekan tombol apa saja untuk kembali.

## Musik

Ambient synth generatif buatan sendiri: pad akor (Cm9, Abmaj7, Fm9, Bb6/9) yang berganti pelan, bel FM acak dari pentatonik minor C, drone C, dan dengung kota. Sampel disintesis oleh `tools/make_audio.py`; urutan nadanya disusun acak oleh `scripts/music.gd`, jadi tidak pernah berulang persis. Saat gerak lambat, musik ikut melambat dan teredam.

## Kredit

Tekstur: Poly Haven (polyhaven.com), lisensi CC0. Musik dan suara: disintesis sendiri. Diunduh oleh `.github/workflows/fetch_textures.yml`.
Scene, gedung, dan efek dibuat sendiri; tidak memakai karakter atau lokasi dari game mana pun.
