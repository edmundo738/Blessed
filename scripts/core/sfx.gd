extends Node
## Sfx — áudio 100% sintetizado em runtime.
##
## Zero ficheiros de som: cada efeito é gerado como PCM e embrulhado num
## AudioStreamWAV. Mantém o projeto sem imports (corre em .pck feito por script),
## pesa ~0 bytes em disco e dá identidade sonora ao mundo.
##
## Tudo o que ouvimos aqui é feito com ruído filtrado, senoides e envelopes.

const RATE := 22050
const MAX_3D := 12

var _cache: Dictionary = {}
var _players_3d: Array[AudioStreamPlayer3D] = []
var _loops: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var master_db: float = -6.0


func _ready() -> void:
	_rng.seed = 20260101
	for i in MAX_3D:
		var p := AudioStreamPlayer3D.new()
		p.max_distance = 60.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.unit_size = 6.0
		add_child(p)
		_players_3d.append(p)
	AudioServer.set_bus_volume_db(0, master_db)


func set_volume_db(db: float) -> void:
	master_db = db
	AudioServer.set_bus_volume_db(0, db)


# ── síntese ──────────────────────────────────────────────────────────────────
func _to_wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v := clampf(samples[i], -1.0, 1.0)
		var s := int(v * 32767.0)
		bytes.encode_s16(i * 2, s)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


func _buf(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * RATE)
	var a := PackedFloat32Array()
	a.resize(n)
	return a


func _noise_into(a: PackedFloat32Array, gain: float, offset: int = 0) -> void:
	for i in range(offset, a.size()):
		a[i] = _rng.randf_range(-gain, gain)


func _one_pole(a: PackedFloat32Array, cut: float) -> void:
	# Filtro passa-baixo simples (um polo). `cut` em Hz.
	var rc := 1.0 / (TAU * cut)
	var dt := 1.0 / float(RATE)
	var alpha := dt / (rc + dt)
	var prev := 0.0
	for i in a.size():
		prev = prev + alpha * (a[i] - prev)
		a[i] = prev


func _decay(a: PackedFloat32Array, seconds: float, offset: int = 0) -> void:
	var n := a.size() - offset
	if n <= 0:
		return
	for i in range(offset, a.size()):
		var t := float(i - offset) / float(n)
		a[i] *= exp(-4.0 * t * (1.0 / maxf(seconds, 0.01)))


func _tone_into(a: PackedFloat32Array, freq: float, gain: float, offset: int = 0, end: int = -1) -> void:
	var last := end if end > 0 else a.size()
	var ph := 0.0
	var step := TAU * freq / float(RATE)
	for i in range(offset, mini(last, a.size())):
		a[i] += sin(ph) * gain
		ph += step


func _sweep_into(a: PackedFloat32Array, f0: float, f1: float, gain: float) -> void:
	var ph := 0.0
	var n := a.size()
	for i in n:
		var t := float(i) / float(n)
		var f := lerpf(f0, f1, t)
		a[i] += sin(ph) * gain * (1.0 - t)
		ph += TAU * f / float(RATE)


# ── receitas de som ──────────────────────────────────────────────────────────
func _build(name: String) -> AudioStreamWAV:
	var a := PackedFloat32Array()
	match name:
		"step_grass":
			a = _buf(0.13); _noise_into(a, 0.5); _one_pole(a, 1400.0); _decay(a, 0.09)
		"step_stone":
			a = _buf(0.10); _noise_into(a, 0.6); _one_pole(a, 2600.0); _decay(a, 0.06)
			_tone_into(a, 320.0, 0.15, 0, int(0.03 * RATE))
		"step_wood":
			a = _buf(0.11); _noise_into(a, 0.35); _one_pole(a, 900.0); _decay(a, 0.08)
			_tone_into(a, 180.0, 0.25, 0, int(0.05 * RATE))
		"step_water":
			a = _buf(0.22); _noise_into(a, 0.4); _one_pole(a, 700.0); _decay(a, 0.18)
		"chop":
			a = _buf(0.28); _noise_into(a, 0.8); _one_pole(a, 1800.0); _decay(a, 0.14)
			_sweep_into(a, 240.0, 90.0, 0.35)
		"mine":
			a = _buf(0.24); _noise_into(a, 0.9); _one_pole(a, 3600.0); _decay(a, 0.10)
			_tone_into(a, 620.0, 0.2, 0, int(0.04 * RATE))
			_tone_into(a, 910.0, 0.12, 0, int(0.06 * RATE))
		"pick":
			a = _buf(0.16); _noise_into(a, 0.5); _one_pole(a, 2200.0); _decay(a, 0.12)
		"craft":
			a = _buf(0.3)
			_tone_into(a, 523.0, 0.25, 0, int(0.09 * RATE))
			_tone_into(a, 784.0, 0.22, int(0.08 * RATE), int(0.2 * RATE))
			_decay(a, 0.3)
		"place":
			a = _buf(0.2); _noise_into(a, 0.5); _one_pole(a, 700.0); _decay(a, 0.15)
			_tone_into(a, 140.0, 0.3, 0, int(0.1 * RATE))
		"eat":
			a = _buf(0.2); _noise_into(a, 0.4); _one_pole(a, 500.0); _decay(a, 0.16)
		"drink":
			a = _buf(0.3); _noise_into(a, 0.35); _one_pole(a, 380.0); _decay(a, 0.25)
		"splash":
			a = _buf(0.5); _noise_into(a, 0.7); _one_pole(a, 900.0); _decay(a, 0.4)
		"ui_click":
			a = _buf(0.07); _tone_into(a, 880.0, 0.25); _decay(a, 0.05)
		"ui_open":
			a = _buf(0.16); _tone_into(a, 660.0, 0.2); _tone_into(a, 990.0, 0.14, int(0.06 * RATE)); _decay(a, 0.14)
		"blessing":
			a = _buf(1.6)
			_tone_into(a, 392.0, 0.18); _tone_into(a, 523.0, 0.16); _tone_into(a, 784.0, 0.12)
			_decay(a, 1.4)
		"growl":
			a = _buf(1.1); _noise_into(a, 0.7); _one_pole(a, 220.0)
			_sweep_into(a, 70.0, 42.0, 0.6); _decay(a, 0.9)
		"scream":
			a = _buf(1.0); _noise_into(a, 0.5); _one_pole(a, 1600.0)
			_sweep_into(a, 900.0, 240.0, 0.5); _decay(a, 0.85)
		"heartbeat":
			a = _buf(0.9)
			_sweep_into(a, 90.0, 45.0, 0.7)
			var off := int(0.35 * RATE)
			for i in range(off, a.size()):
				var t := float(i - off) / float(a.size() - off)
				a[i] += sin(TAU * 60.0 * float(i) / float(RATE)) * 0.5 * exp(-8.0 * t)
			_one_pole(a, 200.0)
		"fire_loop":
			a = _buf(2.0); _noise_into(a, 0.35); _one_pole(a, 480.0)
			for i in a.size():
				a[i] *= 0.75 + 0.25 * sin(TAU * 1.7 * float(i) / float(RATE))
			return _to_wav(a, true)
		"wind_loop":
			a = _buf(3.0); _noise_into(a, 0.3); _one_pole(a, 300.0)
			for i in a.size():
				a[i] *= 0.6 + 0.4 * sin(TAU * 0.33 * float(i) / float(RATE))
			return _to_wav(a, true)
		"night_drone":
			a = _buf(4.0)
			_tone_into(a, 55.0, 0.30); _tone_into(a, 82.5, 0.18); _tone_into(a, 110.0, 0.08)
			_noise_into(a, 0.06); _one_pole(a, 260.0)
			return _to_wav(a, true)
		"water_loop":
			a = _buf(2.5); _noise_into(a, 0.3); _one_pole(a, 1200.0)
			for i in a.size():
				a[i] *= 0.7 + 0.3 * sin(TAU * 2.3 * float(i) / float(RATE))
			return _to_wav(a, true)
		_:
			a = _buf(0.08); _tone_into(a, 440.0, 0.2); _decay(a, 0.06)
	return _to_wav(a, false)


func stream(name: String) -> AudioStreamWAV:
	if not _cache.has(name):
		_cache[name] = _build(name)
	return _cache[name]


# ── reprodução ───────────────────────────────────────────────────────────────
func play(name: String, db: float = 0.0, pitch: float = 1.0) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = stream(name)
	p.volume_db = db
	p.pitch_scale = pitch
	p.finished.connect(p.queue_free)
	add_child(p)
	p.play()


func play_at(name: String, pos: Vector3, db: float = 0.0, pitch: float = 1.0) -> void:
	for p in _players_3d:
		if not p.playing:
			p.stream = stream(name)
			p.volume_db = db
			p.pitch_scale = pitch
			p.global_position = pos
			p.play()
			return


## Loop ambiente (vento, água, fogo, drone noturno). `id` identifica o canal.
func loop(id: String, name: String, db: float = -12.0) -> void:
	if _loops.has(id):
		var old: AudioStreamPlayer = _loops[id]
		old.stop()
		old.queue_free()
		_loops.erase(id)
	if name.is_empty():
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream(name)
	p.volume_db = db
	add_child(p)
	p.play()
	_loops[id] = p


func loop_volume(id: String, db: float) -> void:
	if _loops.has(id):
		(_loops[id] as AudioStreamPlayer).volume_db = db


func stop_loop(id: String) -> void:
	loop(id, "", 0.0)
