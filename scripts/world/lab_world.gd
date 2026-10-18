class_name LabWorld
extends RefCounted
## LabWorld — nucleo causal do laboratorio de mecanicas (400x400 m).
##
## Nao substitui Terrain: vive ao lado, finito e rodeado de oceano, para cada
## mecanica se provar isolada antes de entrar no mundo grande.
##
## Cadeia causal (uma so autoridade de dados, varios leitores):
##   relevo -> chuva/temperatura -> D8 (fluxo) -> rios/lagos (escavados)
##   -> humidade do solo / distancia a agua -> bioma -> especies por afinidade
## Escavar grava deltas na grelha e recompoe fluxo/agua: cavar abaixo do
## nivel da agua enche; aterrar um curso pode desvia-lo. Sem texto de solucao:
## o jogador descobre pelo efeito.

const SIZE := 400.0
const CELL := 5.0
const N := 81  # SIZE / CELL + 1
const SEA := 0.0
const DRY := -100000.0
const STREAM_MIN_ACCUM := 48.0

const B_OCEAN := 0
const B_BEACH := 1
const B_MEADOW := 2
const B_FOREST := 3
const B_GROVE := 4
const B_ROCK := 5
const B_MARSH := 6
const B_DRY := 7

var seed_value: int = 1337
var _n_hills: FastNoiseLite
var _n_detail: FastNoiseLite
var _n_moist: FastNoiseLite
var _n_temp: FastNoiseLite
var _n_patch_a: FastNoiseLite
var _n_patch_b: FastNoiseLite

var _base := PackedFloat32Array()
var _final := PackedFloat32Array()
var _rain := PackedFloat32Array()
var _temp := PackedFloat32Array()
var _moist := PackedFloat32Array()
var _accum := PackedFloat32Array()
var _carve := PackedFloat32Array()
var _water_level := PackedFloat32Array()
var _water_kind := PackedInt32Array()  # 0 seco, 1 oceano, 2 rio, 3 lago
var _water_dist := PackedFloat32Array()
var _fresh_dist := PackedFloat32Array()
var _filled := PackedFloat32Array()
var _dig_delta := PackedFloat32Array()
var _flow_dir := PackedInt32Array()
var stations: Array = []


func _init(p_seed: int = 1337) -> void:
	seed_value = p_seed
	_n_hills = _noise(0.012, 3, p_seed + 21)
	_n_detail = _noise(0.045, 2, p_seed + 22)
	_n_moist = _noise(0.006, 3, p_seed + 23)
	_n_temp = _noise(0.005, 2, p_seed + 24)
	_n_patch_a = _noise(0.010, 3, p_seed + 25)
	_n_patch_b = _noise(0.010, 3, p_seed + 26)
	_load_stations()
	_build_base()
	_rebuild()


func _noise(freq: float, oct: int, s: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = s
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.frequency = freq
	n.fractal_octaves = oct
	n.fractal_gain = 0.5
	n.fractal_lacunarity = 2.0
	return n


func _load_stations() -> void:
	stations.clear()
	var path := "res://data/lab.json"
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		for st in parsed.get("stations", []):
			stations.append(st)


func idx(i: int, j: int) -> int:
	return j * N + i


func grid_pos(i: int, j: int) -> Vector2:
	return Vector2(-SIZE * 0.5 + float(i) * CELL, -SIZE * 0.5 + float(j) * CELL)


func _cell_of(x: float, z: float) -> Vector2i:
	var i := clampi(int(round((x + SIZE * 0.5) / CELL)), 0, N - 1)
	var j := clampi(int(round((z + SIZE * 0.5) / CELL)), 0, N - 1)
	return Vector2i(i, j)


func _build_base() -> void:
	_base.resize(N * N)
	_dig_delta.resize(N * N)
	for j in N:
		for i in N:
			var p := grid_pos(i, j)
			_base[idx(i, j)] = _relief(p.x, p.y)


## Relevo com causa: ilha radial no oceano, montanha a NW (barlavento),
## bacia de lago a SE. Nada de cones de ruido empilhado sem papel.
func _relief(x: float, z: float) -> float:
	var r := Vector2(x, z).length()
	var island_t := clampf((208.0 - r) / 150.0, 0.0, 1.0)
	island_t = island_t * island_t * (3.0 - 2.0 * island_t)
	var land := lerpf(-19.0, 12.5, pow(island_t, 1.25))
	var dm := Vector2(x + 80.0, z + 70.0).length()
	var mountain := 34.0 * exp(-(dm * dm) / (2.0 * 62.0 * 62.0))
	var dl := Vector2(x - 85.0, z - 78.0).length()
	var lake_dep := 5.5 * exp(-(dl * dl) / (2.0 * 30.0 * 30.0))
	# Planalto da bacia: sem ele o centro fica abaixo do mar e vira laguna.
	var lake_uplift := 6.0 * exp(-(dl * dl) / (2.0 * 45.0 * 45.0))
	# Bordo da bacia: sem ele o bowl abre na encosta e nunca fecha lago.
	var lake_rim := 3.2 * exp(-pow(dl - 31.0, 2.0) / (2.0 * 9.0 * 9.0))
	# Vale principal: da montanha para a costa sul. E ele que torna a bacia
	# convergente — sem vale, uma ilha radial so tem drenagem radial miuda.
	var valley_x := -80.0 + (z + 70.0) * 0.42 + sin(z * 0.018) * 14.0
	var valley_d := absf(x - valley_x)
	var valley_t := clampf((z + 95.0) / 265.0, 0.0, 1.0)
	var valley := 4.2 * exp(-(valley_d * valley_d) / (2.0 * 26.0 * 26.0)) * sin(PI * clampf(valley_t, 0.02, 0.98))
	var hills := _n_hills.get_noise_2d(x, z) * 3.2 * island_t
	var detail := _n_detail.get_noise_2d(x, z) * 0.6
	var h := land + mountain + hills + detail - lake_dep + lake_rim + lake_uplift - valley
	# Cratera do lago: perfil radial que domina o ruido local. Sem isto as
	# colinas abrem uma brecha no bordo e a bacia drena como ribeiro.
	if dl < 48.0:
		var crater := 6.8 + dl * dl * 0.0062
		var blend := clampf((52.0 - dl) / 8.0, 0.0, 1.0)
		h = lerpf(h, crater, blend * blend)
	return h


func _rebuild() -> void:
	_final.resize(N * N)
	_rain.resize(N * N)
	_temp.resize(N * N)
	_moist.resize(N * N)
	_accum.resize(N * N)
	_carve.resize(N * N)
	_water_level.resize(N * N)
	_water_kind.resize(N * N)
	_water_dist.resize(N * N)
	_fresh_dist.resize(N * N)
	_filled.resize(N * N)
	_flow_dir.resize(N * N)
	var filled := PackedFloat32Array()
	filled.resize(N * N)
	for k in N * N:
		var h := _base[k] - _dig_delta[k]
		filled[k] = h
		_final[k] = h
		_water_level[k] = DRY
		_water_kind[k] = 0
		_carve[k] = 0.0
		_accum[k] = 1.0
	# clima por celula (altitude arrefece; barlavento a oeste chove mais)
	for j in N:
		for i in N:
			var p := grid_pos(i, j)
			var k := idx(i, j)
			var alt := filled[k]
			_temp[k] = clampf(0.80 - alt * 0.011 + _n_temp.get_noise_2d(p.x, p.y) * 0.10, 0.0, 1.0)
			_rain[k] = clampf(0.52 + _n_moist.get_noise_2d(p.x, p.y) * 0.34
					+ (-p.x / SIZE) * 0.55 + alt * 0.004, 0.05, 1.0)
	# Depression fill por priority-flood (relaxacao a partir das bordas):
	# o interior comeca em +infinito e baixa para max(relevo, melhor saida).
	# Levantar so minimos locais um passo nunca enche uma bacia inteira.
	for j in N:
		for i in N:
			var k := idx(i, j)
			if i == 0 or j == 0 or i == N - 1 or j == N - 1 or filled[k] <= SEA:
				pass
			else:
				filled[k] = 1e6
	var _pf_pass := 0
	var _pf_changed := true
	while _pf_changed and _pf_pass < 400:
		_pf_changed = false
		_pf_pass += 1
		for j in range(1, N - 1):
			for i in range(1, N - 1):
				var k := idx(i, j)
				if filled[k] <= SEA and (_base[k] - _dig_delta[k]) <= SEA:
					continue
				var mn := 1e9
				for dj in [-1, 0, 1]:
					for di in [-1, 0, 1]:
						if di == 0 and dj == 0:
							continue
						mn = minf(mn, filled[idx(i + di, j + dj)])
				var target: float = maxf(_base[k] - _dig_delta[k], mn)
				if target < filled[k] - 0.001:
					filled[k] = target
					_pf_changed = true
	for k in N * N:
		_filled[k] = filled[k]
	# D8: cada celula drena para o vizinho preenchido mais baixo
	var order: Array[int] = []
	order.resize(N * N)
	for k in N * N:
		order[k] = k
		_flow_dir[k] = -1
	for j in N:
		for i in N:
			var k := idx(i, j)
			var best := -1
			var best_h := filled[k]
			for dj in [-1, 0, 1]:
				for di in [-1, 0, 1]:
					if di == 0 and dj == 0:
						continue
					var ni: int = i + di
					var nj: int = j + dj
					if ni < 0 or nj < 0 or ni >= N or nj >= N:
						continue
					var nk := idx(ni, nj)
					if filled[nk] < best_h:
						best_h = filled[nk]
						best = nk
			_flow_dir[k] = best
	order.sort_custom(func(a: int, b: int) -> bool: return filled[a] > filled[b])
	for k in order:
		var d := _flow_dir[k]
		if d >= 0:
			_accum[d] += _accum[k]
	# rios escavam o proprio leito; lagos nascem em depressoes (sem saida)
	for j in N:
		for i in N:
			var k := idx(i, j)
			var h := _base[k] - _dig_delta[k]
			if h < SEA:
				_water_kind[k] = 1
				_water_level[k] = SEA
			elif _accum[k] >= STREAM_MIN_ACCUM:
				_carve[k] = clampf(0.45 + sqrt(_accum[k]) * 0.15, 0.5, 2.1)
				_water_kind[k] = 2
			elif filled[k] - h > 0.5:
				# depressao preenchida = lago: o nivel e o do extravasamento
				_water_kind[k] = 3
				_water_level[k] = filled[k]
	for k in N * N:
		_final[k] = (_base[k] - _dig_delta[k]) - _carve[k]
		if _water_kind[k] == 2:
			_water_level[k] = _final[k] + _carve[k] * 0.55
	# distancia a agua (BFS 8-vizinhos) e humidade do solo
	_bfs_water_distance()
	_bfs_fresh_distance()
	for k in N * N:
		var near := clampf(1.0 - _water_dist[k] / 45.0, 0.0, 1.0)
		_moist[k] = clampf(_rain[k] * 0.62 + near * 0.48, 0.0, 1.0)


func _bfs_water_distance() -> void:
	var queue: Array[int] = []
	for k in N * N:
		if _water_kind[k] > 0:
			_water_dist[k] = 0.0
			queue.append(k)
		else:
			_water_dist[k] = 1e9
	var head := 0
	while head < queue.size():
		var k: int = queue[head]
		head += 1
		var i := k % N
		var j := k / N
		for dj in [-1, 0, 1]:
			for di in [-1, 0, 1]:
				if di == 0 and dj == 0:
					continue
				var ni: int = i + di
				var nj: int = j + dj
				if ni < 0 or nj < 0 or ni >= N or nj >= N:
					continue
				var nk := idx(ni, nj)
				var nd := _water_dist[k] + (CELL * 1.4142 if di != 0 and dj != 0 else CELL)
				if nd < _water_dist[nk]:
					_water_dist[nk] = nd
					queue.append(nk)


func _bfs_fresh_distance() -> void:
	var queue: Array[int] = []
	for k in N * N:
		if _water_kind[k] == 2 or _water_kind[k] == 3:
			_fresh_dist[k] = 0.0
			queue.append(k)
		else:
			_fresh_dist[k] = 1e9
	var head := 0
	while head < queue.size():
		var k: int = queue[head]
		head += 1
		var i := k % N
		var j := k / N
		for dj in [-1, 0, 1]:
			for di in [-1, 0, 1]:
				if di == 0 and dj == 0:
					continue
				var ni: int = i + di
				var nj: int = j + dj
				if ni < 0 or nj < 0 or ni >= N or nj >= N:
					continue
				var nk := idx(ni, nj)
				var nd := _fresh_dist[k] + (CELL * 1.4142 if di != 0 and dj != 0 else CELL)
				if nd < _fresh_dist[nk]:
					_fresh_dist[nk] = nd
					queue.append(nk)


func height(x: float, z: float) -> float:
	var fx := clampf((x + SIZE * 0.5) / CELL, 0.0, float(N - 2))
	var fz := clampf((z + SIZE * 0.5) / CELL, 0.0, float(N - 2))
	var i := int(fx)
	var j := int(fz)
	var tx := fx - float(i)
	var tz := fz - float(j)
	var a := _final[idx(i, j)]
	var b := _final[idx(i + 1, j)]
	var c := _final[idx(i, j + 1)]
	var d := _final[idx(i + 1, j + 1)]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)


func slope(x: float, z: float) -> float:
	var e := 2.0
	var dx := height(x + e, z) - height(x - e, z)
	var dz := height(x, z + e) - height(x, z - e)
	return Vector2(dx, dz).length() / (2.0 * e)


func biome_at(x: float, z: float) -> int:
	var c := _cell_of(x, z)
	var k := idx(c.x, c.y)
	var h := height(x, z)
	if _water_kind[k] == 1:
		return B_OCEAN
	if h < 0.7:
		return B_BEACH
	if slope(x, z) > 0.55 or h > 34.0:
		return B_ROCK
	if _water_dist[k] < 14.0 and _moist[k] > 0.68:
		return B_MARSH
	if Vector2(x - 55.0, z + 55.0).length() < 42.0 and _moist[k] > 0.45:
		return B_GROVE
	if _rain[k] < 0.40 and _water_dist[k] > 18.0:
		return B_DRY
	var patch := _n_patch_a.get_noise_2d(x, z)
	if patch > 0.08 and _moist[k] > 0.42:
		return B_FOREST
	return B_MEADOW


## Densidade 0..1 por especie: habitat (campos) x mancha (patch) x afinidade.
## Mesma especie agrupa porque a mancha e o habitat sao espaciais — nao ha
## sorteio independente por celula a decidir sozinho.
func species_density(x: float, z: float, species: String) -> float:
	var c := _cell_of(x, z)
	var k := idx(c.x, c.y)
	var h := height(x, z)
	if _water_kind[k] == 1 or h < 0.5:
		return 0.0
	var moist := _moist[k]
	var temp := _temp[k]
	var wd := _water_dist[k]
	var pa := _n_patch_a.get_noise_2d(x, z) * 0.5 + 0.5
	var pb := _n_patch_b.get_noise_2d(x, z) * 0.5 + 0.5
	match species:
		"oak":
			return clampf(0.85 * pa * smoothstep(0.35, 0.65, moist), 0.0, 1.0)
		"birch":
			return clampf(0.80 * pb * smoothstep(0.30, 0.60, moist) * smoothstep(0.25, 0.55, temp), 0.0, 1.0)
		"sakura":
			var g := clampf(1.0 - Vector2(x - 55.0, z + 55.0).length() / 46.0, 0.0, 1.0)
			return clampf(0.95 * g * pa, 0.0, 1.0)
		"pine":
			return clampf(0.85 * pb * smoothstep(8.0, 22.0, h), 0.0, 1.0)
		"willow":
			return clampf(0.90 * exp(-_fresh_dist[k] / 16.0) * smoothstep(0.45, 0.70, moist), 0.0, 1.0)
	return 0.0


func vegetation_present(x: float, z: float, species: String) -> bool:
	var c := _cell_of(x, z)
	var h := int(posmod(c.x * 374761393 + c.y * 668265263
			+ species.hash() * 17 + seed_value * 362437, 100000)) / 100000.0
	return h < species_density(x, z, species) * 0.62


## Consulta unica do mundo de teste. Render, gameplay e save leem daqui;
## nenhum leitor inventa altura, agua ou bioma por sua conta.
func sample(x: float, z: float) -> Dictionary:
	var c := _cell_of(x, z)
	var k := idx(c.x, c.y)
	var h := height(x, z)
	var wl := _water_level[k]
	return {
		"height": h,
		"slope": slope(x, z),
		"temperature": _temp[k],
		"rainfall": _rain[k],
		"moisture": _moist[k],
		"flow_accum": _accum[k],
		"water_kind": _water_kind[k],
		"water_level": wl,
		"water_depth": (wl - h) if wl > DRY * 0.5 else 0.0,
		"water_dist": _water_dist[k],
		"fresh_dist": _fresh_dist[k],
		"depression": _filled[k] - (_base[k] - _dig_delta[k]),
		"biome": biome_at(x, z),
	}


## Escava: grava delta, recompoe fluxo/agua e devolve o solo removido (m3 aprox).
func dig(x: float, z: float, radius_m: float, depth_m: float) -> float:
	var c := _cell_of(x, z)
	var r_cells := int(ceil(radius_m / CELL))
	var removed := 0.0
	for dj in range(-r_cells, r_cells + 1):
		for di in range(-r_cells, r_cells + 1):
			var ni: int = c.x + di
			var nj: int = c.y + dj
			if ni < 0 or nj < 0 or ni >= N or nj >= N:
				continue
			var p := grid_pos(ni, nj)
			var d := Vector2(p.x - x, p.y - z).length()
			if d > radius_m:
				continue
			var fall := 1.0 - (d / maxf(radius_m, 0.01)) * 0.55
			var amt := depth_m * fall
			_dig_delta[idx(ni, nj)] += amt
			removed += amt * CELL * CELL
	_rebuild()
	return removed


func buildable(x: float, z: float) -> Dictionary:
	var s := sample(x, z)
	var sl: float = s["slope"]
	return {
		"ok": sl < 0.45 and int(s["water_kind"]) == 0,
		"slope": sl,
		"needs_stilts": sl >= 0.16 and sl < 0.45,
		"in_water": int(s["water_kind"]) > 0,
	}
