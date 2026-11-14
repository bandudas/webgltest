class_name GenMusic
extends Node

## Musik ambient generatif: pad akor yang berganti pelan, bel acak dari skala pentatonik minor,
## drone C, dan dengung kota. Sampel disintesis sendiri (tools/make_audio.py).
## Waktu sequencer memakai delta biasa, jadi ikut melambat saat gerak lambat.

const PAD := preload("res://audio/pad.wav")      # C3
const BELL := preload("res://audio/bell.wav")    # C5
const DRONE := preload("res://audio/drone.wav")  # C2, loop
const HUM := preload("res://audio/hum.wav")      # loop

# Akor dalam semitone relatif C3: Cm9, Abmaj7, Fm9, Bb6/9
const CHORDS := [
	[0, 7, 10, 14, 15],
	[-4, 0, 3, 7, 10],
	[-7, -4, 3, 7, 12],
	[-2, 2, 5, 7, 14],
]
# Bel: pentatonik minor C, relatif C3
const BELL_NOTES := [12, 15, 17, 19, 22, 24, 27, 29, 31]

var rng := RandomNumberGenerator.new()
var _pads: Array = []
var _bells: Array = []
var _pad_i := 0
var _bell_i := 0
var _chord_i := 0
var _chord_t := 0.0
var _bell_t := 2.0
var _queue: Array = []   # [waktu_tunda, semitone]
var _lowpass: AudioEffectLowPassFilter
var _bus := 0
var slowmo := 0.0


func _ready() -> void:
	rng.randomize()
	_bus = AudioServer.bus_count
	AudioServer.add_bus(_bus)
	AudioServer.set_bus_name(_bus, "Musik")
	AudioServer.set_bus_send(_bus, "Master")
	var rev := AudioEffectReverb.new()
	rev.room_size = 0.85
	rev.damping = 0.45
	rev.spread = 0.8
	rev.wet = 0.42
	rev.dry = 0.75
	AudioServer.add_bus_effect(_bus, rev)
	_lowpass = AudioEffectLowPassFilter.new()
	_lowpass.cutoff_hz = 7000.0
	AudioServer.add_bus_effect(_bus, _lowpass)

	for i in 8:
		_pads.append(_player(PAD, -15.0))
	for i in 4:
		_bells.append(_player(BELL, -17.0))
	var d := _player(DRONE, -17.0)
	d.play()
	var h := _player(HUM, -21.0)
	h.bus = "Master"   # dengung kota tanpa gema
	h.play()
	_chord_i = rng.randi() % CHORDS.size()
	_play_chord()


func _player(stream: AudioStream, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	p.bus = "Musik"
	add_child(p)
	return p


func _pitch(semi: float) -> float:
	return pow(2.0, semi / 12.0) * lerpf(1.0, 0.82, slowmo)


func _play_chord() -> void:
	var chord: Array = CHORDS[_chord_i]
	var notes := chord.duplicate()
	notes.shuffle()
	var n := rng.randi_range(3, notes.size())
	for k in n:
		_queue.append([rng.randf_range(0.0, 2.2) + k * 0.15, float(notes[k]), true])


func _process(delta: float) -> void:
	_lowpass.cutoff_hz = lerpf(7000.0, 700.0, slowmo)

	_chord_t += delta
	if _chord_t > 13.0:
		_chord_t = 0.0
		# berpindah ke akor lain (kadang tetap), terasa mengambang
		if rng.randf() < 0.85:
			_chord_i = (_chord_i + rng.randi_range(1, CHORDS.size() - 1)) % CHORDS.size()
		_play_chord()

	_bell_t -= delta
	if _bell_t <= 0.0:
		_bell_t = rng.randf_range(1.6, 5.5)
		if rng.randf() < 0.75:
			var note: int = BELL_NOTES[rng.randi() % BELL_NOTES.size()]
			_queue.append([0.0, float(note), false])
			if rng.randf() < 0.3:   # gema nada kedua
				_queue.append([rng.randf_range(0.35, 0.7), float(note + [3, 5, 7, -5][rng.randi() % 4]), false])

	for i in range(_queue.size() - 1, -1, -1):
		_queue[i][0] -= delta
		if _queue[i][0] <= 0.0:
			var q: Array = _queue[i]
			_queue.remove_at(i)
			if q[2]:
				var p: AudioStreamPlayer = _pads[_pad_i]
				_pad_i = (_pad_i + 1) % _pads.size()
				p.pitch_scale = _pitch(q[1])
				p.volume_db = -15.0 + rng.randf_range(-2.5, 0.5)
				p.play()
			else:
				var b: AudioStreamPlayer = _bells[_bell_i]
				_bell_i = (_bell_i + 1) % _bells.size()
				b.pitch_scale = _pitch(q[1] - 24.0)
				b.volume_db = -17.0 + rng.randf_range(-4.0, 0.0)
				b.play()
