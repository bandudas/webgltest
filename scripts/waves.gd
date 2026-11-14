class_name Waves
extends RefCounted

## Fungsi gelombang yang sama persis dengan shaders/water.gdshader,
## supaya perahu naik-turun sesuai permukaan air yang terlihat.
static func height(x: float, z: float, t: float) -> float:
	return sin(x * 0.15 + t * 1.1) * 0.18 \
		+ sin(z * 0.21 - t * 0.9) * 0.14 \
		+ sin((x + z) * 0.33 + t * 1.7) * 0.06
