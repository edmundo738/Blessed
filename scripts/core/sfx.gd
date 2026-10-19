extends Node
## Sfx — áudio 100% sintetizado em runtime.
##
## Zero ficheiros de som: cada efeito é gerado como PCM e embrulhado num
## AudioStreamWAV. Mantém o projeto sem imports (corre em .pck feito por script),
## pesa ~0 bytes em disco e dá identidade sonora ao mundo.
##
## Tudo o que ouvimos aqui é feito com ruído filtrado, senoides e envelopes.

const RATE := 22050
const MAX_3D := 16
const MAX_2D := 12

var _cache: Dictionary = {}
var _players_3d: Array[AudioStreamPlayer3D] = []
var _players_2d: Array[AudioStreamPlayer] = []
var _voice_cursor := 0
var _loops: Dictionary = {}
var _loop_names: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _music_phase := ""
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
	for i in MAX_2D:
		var p2 := AudioStreamPlayer.new()
		add_child(p2)
		_players_2d.append(p2)
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
	if name.begins_with("music_"):
		return _build_music(name.trim_prefix("music_"))
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
		"jump":
			# Impulso curto de ar + grave macio; não reutiliza um passo/tambor.
			a = _buf(0.24); _noise_into(a, 0.16); _one_pole(a, 520.0)
			_sweep_into(a, 78.0, 145.0, 0.18)
			_decay(a, 0.20)
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
		"build_wood":
			# batida de madeira que encaixa: toque seco + corpo grave,
			# com um segundo toque curto (a peça assenta)
			a = _buf(0.22); _noise_into(a, 0.45); _one_pole(a, 950.0); _decay(a, 0.13)
			_tone_into(a, 165.0, 0.38, 0, int(0.07 * RATE))
			_tone_into(a, 230.0, 0.16, int(0.055 * RATE), int(0.11 * RATE))
		"build_stone":
			# pedra sobre pedra: baque surdo e pesado, quase sem agudos
			a = _buf(0.26); _noise_into(a, 0.55); _one_pole(a, 480.0); _decay(a, 0.19)
			_tone_into(a, 82.0, 0.42, 0, int(0.13 * RATE))
			_tone_into(a, 58.0, 0.25, int(0.02 * RATE), int(0.16 * RATE))
		"collapse":
			# estrondo de estrutura a cair: ruído grave longo + queda
			# de frequência + baque final (o que segurava cedeu)
			a = _buf(0.95); _noise_into(a, 0.85); _one_pole(a, 430.0)
			_sweep_into(a, 150.0, 36.0, 0.55)
			_tone_into(a, 52.0, 0.4, int(0.10 * RATE), int(0.5 * RATE))
			_decay(a, 0.85)
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
		"stomach":
			# Gorgolejo grave: um deslize de frequência e duas bolhas curtas.
			var st := _buf(0.55)
			_sweep_into(st, 96.0, 48.0, 0.35)
			for k in 2:
				var at := int(RATE * (0.08 + 0.16 * k))
				for i in int(RATE * 0.16):
					if at + i < st.size():
						var env := sin(PI * float(i) / (RATE * 0.16))
						st[at + i] += sin(TAU * (70.0 - 18.0 * k) * float(i) / RATE) * 0.22 * env
			_noise_into(st, 0.05)
			_one_pole(st, 0.16)
			_decay(st, 0.5)
		"breath":
			# Uma expiração: ruído suave, ataque curto e cauda longa.
			var br := _buf(0.7)
			_noise_into(br, 0.30)
			_one_pole(br, 0.05)
			_decay(br, 0.62)
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
	if _players_2d.is_empty():
		return
	var p: AudioStreamPlayer = null
	var chosen := _voice_cursor
	for offset in _players_2d.size():
		var i := (_voice_cursor + offset) % _players_2d.size()
		if not _players_2d[i].playing:
			p = _players_2d[i]
			chosen = i
			break
	if p == null:
		p = _players_2d[_voice_cursor]
		chosen = _voice_cursor
		p.stop()
	_voice_cursor = (chosen + 1) % _players_2d.size()
	p.stream = stream(name)
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()


func play_at(name: String, pos: Vector3, db: float = 0.0, pitch: float = 1.0) -> void:
	for p in _players_3d:
		if not p.playing:
			p.stream = stream(name)
			p.volume_db = db
			p.pitch_scale = pitch
			if p.is_inside_tree():
				p.global_position = pos
			p.play()
			return


## Loop ambiente (vento, água, fogo, drone noturno). `id` identifica o canal.
func loop(id: String, name: String, db: float = -12.0, fade_seconds: float = 0.45) -> void:
	if _loops.has(id):
		var old: AudioStreamPlayer = _loops[id]
		if _loop_names.get(id, "") == name and old.playing:
			old.volume_db = db
			return
		_loops.erase(id)
		_loop_names.erase(id)
		if is_instance_valid(old):
			var fade_out := create_tween()
			fade_out.tween_property(old, "volume_db", -48.0, fade_seconds)
			fade_out.tween_callback(func():
				if is_instance_valid(old):
					old.stop()
					old.queue_free())
	if name.is_empty():
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream(name)
	p.volume_db = -48.0
	add_child(p)
	p.play()
	var fade_in := create_tween()
	fade_in.tween_property(p, "volume_db", db, fade_seconds)
	_loops[id] = p
	_loop_names[id] = name


func loop_volume(id: String, db: float) -> void:
	if _loops.has(id):
		(_loops[id] as AudioStreamPlayer).volume_db = db


func stop_loop(id: String) -> void:
	loop(id, "", 0.0)


## Trilha original e adaptável às fases do mundo.
func set_music_phase(phase: String) -> void:
	if phase == _music_phase:
		return
	_music_phase = phase
	var track := "music_dawn"
	var level := -19.0
	match phase:
		"day":
			track = "music_day"
			level = -17.0
		"dusk":
			track = "music_dusk"
			level = -19.0
		"night":
			track = "music_night"
			level = -22.0
	loop("music", track, level, 2.4)


## Composição em camadas: harmonia sustentada e motivo agudo delicado.
## O ciclo de quatro compassos repete sem assets externos.
func _build_music(mood: String) -> AudioStreamWAV:
	const BAR := 3.2
	const BARS := 4
	var a := _buf(BAR * BARS)
	var roots := [50, 53, 57, 52] # ré menor, fá, lá menor, mi menor
	var melody := [74, 69, 72, 76, 72, 67, 71, 74]
	match mood:
		"day":
			roots = [62, 57, 59, 55]
			melody = [74, 76, 81, 78, 76, 74, 71, 69]
		"dusk":
			roots = [57, 53, 50, 52]
			melody = [76, 72, 69, 72, 74, 69, 67, 71]
		"night":
			roots = [45, 48, 43, 50]
			melody = [69, 72, 67, 74, 72, 69, 65, 67]
		"dawn":
			roots = [50, 57, 53, 52]
			melody = [74, 77, 81, 79, 77, 74, 72, 69]
	var samples_per_bar := int(BAR * RATE)
	for bar in BARS:
		var root_note := int(roots[bar])
		var start := bar * samples_per_bar
		# Notas longas com ataque lento formam a cama harmónica.
		for interval in [0, 7, 12]:
			_add_music_note(a, _midi_hz(root_note + interval - 12), start,
				samples_per_bar, 0.055 if interval == 0 else 0.026, 0.22, true)
		# Motivo curto, com bastante espaço para os sons do ambiente.
		for beat in 2:
			var note_index := bar * 2 + beat
			var note_start := start + int(float(beat) * BAR * 0.5 * RATE)
			_add_music_note(a, _midi_hz(int(melody[note_index])), note_start,
				int(BAR * 0.46 * RATE), 0.075, 0.13, false)
	return _to_wav(a, true)


func _midi_hz(note: int) -> float:
	return 440.0 * pow(2.0, float(note - 69) / 12.0)


func _add_music_note(a: PackedFloat32Array, frequency: float, start: int,
		length: int, gain: float, release: float, pad: bool) -> void:
	var finish := mini(start + length, a.size())
	var phase := 0.0
	var step := TAU * frequency / float(RATE)
	var release_samples := maxi(1, int(release * RATE))
	for i in range(start, finish):
		var local := i - start
		var envelope := 1.0
		if pad:
			envelope = minf(1.0, float(local) / float(RATE * 0.45))
			envelope *= minf(1.0, float(finish - i) / float(release_samples))
		else:
			var attack := minf(1.0, float(local) / float(RATE * 0.018))
			envelope = attack * exp(-4.6 * float(local) / float(maxi(length, 1)))
		a[i] += (sin(phase) + 0.22 * sin(phase * 2.0)) * gain * envelope
		phase += step
