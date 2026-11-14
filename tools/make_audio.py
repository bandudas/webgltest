"""Sintesis sampel untuk musik ambient generatif (karya sendiri, tanpa sampel luar).
Hasil: audio/*.wav (22.05 kHz, mono, 16-bit). Urutan nada disusun acak oleh game (scripts/music.gd)."""
import numpy as np, wave, os
SR = 22050
rng = np.random.default_rng(11)
os.makedirs("audio", exist_ok=True)

def save(name, x, peak=0.5):
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    with wave.open(f"audio/{name}.wav", "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype("<i2").tobytes())

def onepole(x, cutoff):
    cutoff = np.broadcast_to(cutoff, x.shape)
    y = np.zeros_like(x); s = 0.0
    a = 1 - np.exp(-2 * np.pi * cutoff / SR)
    for i in range(len(x)):
        s += a[i] * (x[i] - s); y[i] = s
    return y

def saw(f, t, phase):
    return 2 * ((f * t + phase) % 1.0) - 1

# Pad hangat: 4 saw sedikit fals + sub sinus, filter yang perlahan menutup, attack/release panjang.
def pad():
    dur = 7.0; t = np.arange(int(SR * dur)) / SR; f = 130.81
    x = sum(saw(f * (1 + d), t, rng.random()) for d in (-0.006, -0.0022, 0.0025, 0.0065)) / 4
    x += 0.35 * np.sin(2 * np.pi * f / 2 * t)
    cut = 1100 - 500 * (t / dur) + 120 * np.sin(2 * np.pi * 0.3 * t)
    x = onepole(onepole(x, cut), cut)
    env = np.minimum(1, t / 2.0) ** 1.5
    rel = np.clip((t - 3.8) / (dur - 3.8), 0, 1)
    env *= 0.5 * (1 + np.cos(np.pi * rel))
    save("pad", x * env, 0.45)

# Bel FM: logam lembut dengan indeks modulasi yang meluruh.
def bell():
    dur = 5.0; t = np.arange(int(SR * dur)) / SR; f = 523.25
    idx = 2.8 * np.exp(-t / 0.6)
    x = np.sin(2 * np.pi * f * t + idx * np.sin(2 * np.pi * f * 3.5 * t))
    x += 0.25 * np.sin(2 * np.pi * f * 2.01 * t) * np.exp(-t / 0.4)
    env = (1 - np.exp(-t / 0.004)) * np.exp(-t / 1.3)
    save("bell", x * env, 0.4)

# Drone C2 yang berulang mulus: semua frekuensi bulat siklusnya dalam 8 detik.
def drone():
    dur = 8.0; t = np.arange(int(SR * dur)) / SR
    x = np.sin(2 * np.pi * 65.375 * t) + np.sin(2 * np.pi * 65.5 * t)
    x += 0.45 * np.sin(2 * np.pi * 98.0 * t) + 0.2 * np.sin(2 * np.pi * 130.75 * t) * (0.6 + 0.4 * np.sin(2 * np.pi * 0.125 * t))
    save("drone", x, 0.45)

# Dengung kota: noise cokelat + dengung listrik, ujungnya disambung silang supaya loop mulus.
def hum():
    dur = 8.0; n = int(SR * dur); fade = int(SR * 1.0)
    w = rng.standard_normal(n + fade)
    b = np.cumsum(w); b -= onepole(b, 0.5)
    b = onepole(b, 380)
    tt = np.arange(n + fade) / SR
    b = b / np.max(np.abs(b)) + 0.06 * np.sin(2 * np.pi * 60 * tt) + 0.03 * np.sin(2 * np.pi * 120 * tt)
    head = b[:fade]; tail = b[n:n + fade]
    k = np.linspace(0, 1, fade)
    out = b[:n].copy(); out[:fade] = head * k + tail * (1 - k)
    save("hum", out, 0.4)

pad(); bell(); drone(); hum()
print("selesai", os.listdir("audio"))
