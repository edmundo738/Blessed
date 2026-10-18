class_name Water
extends RefCounted
## Water — o BHFS (Blessed Hybrid Fluid System), camada geográfica.
##
## A regra que este ficheiro implementa:
##
##   a água NÃO é desenhada. A água é o que o relevo faz com a chuva.
##
## Em vez de um "rio" ser uma senóide escolhida à mão (o que existia antes), o
## mundo calcula uma vez, para uma região, a REDE DE DRENAGEM do terreno:
##
##   relevo  →  cada célula desce para a mais baixa ao lado  →  acumulação
##           →  nascentes  →  rios que se juntam  →  mar
##
## Dessa rede saem três coisas que o resto do jogo consome:
##
##   1. VALES escavados — `carve(x, z)`; o terreno passa a ter o leito que a
##      água precisa, em vez de a água flutuar sobre uma colina.
##   2. AMOSTRAS — `sample(x, z)`: nível, profundidade, direção e velocidade da
##      corrente, salinidade, turvação, e o tipo (rio / lago / mangue).
##   3. FLUXO — a corrente empurra o jogador e os objetos, sem física por frame.
##
## Custo: a rede é calculada UMA vez por mundo (≈ 60 ms), com grelha grossa de
## 16 m; o que é consultado por frame é uma interpolação bilinear de 4 valores.
## Nada de simulação hidráulica: água geográfica é barata por construção.
##
## Determinismo: tudo depende de `seed_value` e da configuração geográfica.
## Duas instâncias com ambos iguais produzem a mesma rede ao bit.

# ── tipos de água ───────────────────────────────────────────────────────────
const KIND_NONE := 0
const KIND_OCEAN := 1
const KIND_RIVER := 2
const KIND_LAKE := 3
const KIND_MARSH := 4
const KIND_SPRING := 5

const DRY := -100000.0

# ── escala ──────────────────────────────────────────────────────────────────
## Passo da grelha de hidrologia. 20 m: fino o bastante para a rede ter forma,
## grosso o bastante para a bacia inteira ser calculada num instante.
const COARSE := 20.0
## Região de hidrologia (metros). O mar continua para lá disto; só a rede de
## rios é que tem de estar limitada — um mundo infinito não pode ter uma bacia
## global. 2.56 km cobrem com folga o raio onde o jogador joga; o vale desvanece
## suavemente nas bordas (FADE) para não haver corte.
const SPAN := 2560.0
const FADE := 220.0
## Raster do leito (metros por célula). 8 m é fino para um vale de 12–34 m de
## alcance e grosso o bastante para caber em 400 KB.
const CARVE_STEP := 8.0
const CARVE_N := int(SPAN / CARVE_STEP) + 1

## Acumulação (em células de 16 m) a partir da qual nasce um curso de água.
## ~40 células = ~1 hectare de bacia: é um riacho. A 90 já é um rio.
const ACC_STREAM := 34.0
const ACC_RIVER := 110.0

var seed_value := 0
var built := false
var build_ms := 0
var phase_ms := {}

var n := 0
var x0 := 0.0
var z0 := 0.0

# Grelha grossa (hidrologia)
var _h := PackedFloat32Array()          # relevo
var _filled := PackedFloat32Array()     # relevo condicionado para drenagem
var _acc := PackedFloat32Array()        # acumulação de drenagem
var _down := PackedInt32Array()         # índice da célula a jusante (-1 = sem saída)
var _lake := PackedFloat32Array()       # nível do lago (DRY = seco)
var _marsh := PackedByteArray()         # 1 = mangue/pântano

# O leito é um raster de 8 m, construído UMA vez com a rede. Consultá-lo é ler
# quatro floats: o `height()` de cada vértice de chunk não paga a busca espacial
# (foi isso que tornou a suíte 6× mais lenta quando o carve era analítico).
var _carve := PackedFloat32Array()

# Segmentos de rio (polilinhas suavizadas) — 15 floats cada:
#   ax, az, bx, bz, level_a, level_b, half_width, depth, speed, flow_x, flow_z,
#   turbidity, kind, relief_a, relief_b
const SEG_STRIDE := 15
var _seg := PackedFloat32Array()
var _seg_count := 0
var _buckets := {}                      # Vector2i -> PackedInt32Array

# Cache de consulta (evita repetir a busca espacial no mesmo frame/sítio)
var _last_key := Vector2i(2147483647, 2147483647)
var _last_hit := -1

var _lake_count := 0
var _lake_bodies := 0
var _sources := 0
var _mouth_count := 0
var _outlet_cells := 0
var _terrain: WeakRef
var _shared_key := ""

## A rede só depende da semente. Muitos `Terrain` do mesmo mundo (testes, menus,
## reinícios) partilham a mesma hidrologia em vez de a recalcular.
static var _shared := {}


# ══════════════════════════════════════════════════════════════════════════
#  CONSTRUÇÃO
# ══════════════════════════════════════════════════════════════════════════

## `terrain` é guardado por referência fraca: `Terrain` é dono de `Water`, e
## uma referência forte fecharia um ciclo que o RefCounted nunca liberta.
func build(terrain: Object, center: Vector2) -> void:
	var t0 := Time.get_ticks_msec()
	_terrain = weakref(terrain)
	seed_value = int(terrain.get("seed_value"))
	# A geologia e o escoamento são afináveis em terrain.json; cache só pela
	# semente reutilizava relevo antigo depois de mudar essas regras.
	_shared_key = "%d:%d" % [seed_value, hash(Db.terrain_cfg)]
	if _shared.has(_shared_key):
		var c: Dictionary = _shared[_shared_key]
		x0 = c["x0"]
		z0 = c["z0"]
		n = c["n"]
		_h = c["h"]
		_filled = c["filled"]
		_acc = c["acc"]
		_down = c["down"]
		_lake = c["lake"]
		_marsh = c["marsh"]
		_seg = c["seg"]
		_seg_count = c["seg_count"]
		_carve = c["carve"]
		_buckets = c["buckets"]
		_lake_count = c["lake_count"]
		_lake_bodies = c["lake_bodies"]
		_sources = c.get("sources", 0)
		_mouth_count = c.get("mouths", 0)
		_outlet_cells = c.get("outlets", 0)
		phase_ms = c.get("phases", {})
		built = true
		build_ms = 0
		return
	x0 = center.x - SPAN * 0.5
	z0 = center.y - SPAN * 0.5
	n = int(SPAN / COARSE) + 1
	_h.resize(n * n)
	_filled.resize(n * n)
	_acc.resize(n * n)
	_down.resize(n * n)
	_lake.resize(n * n)
	_marsh.resize(n * n)

	var _t := Time.get_ticks_msec()
	_sample_relief()
	phase_ms["relief"] = Time.get_ticks_msec() - _t
	_t = Time.get_ticks_msec()
	_route_flow()
	phase_ms["route"] = Time.get_ticks_msec() - _t
	_t = Time.get_ticks_msec()
	_find_lakes()
	phase_ms["lakes"] = Time.get_ticks_msec() - _t
	_t = Time.get_ticks_msec()
	_trace_rivers()
	phase_ms["trace"] = Time.get_ticks_msec() - _t
	_t = Time.get_ticks_msec()
	_build_carve()
	built = true
	_retune_levels()
	phase_ms["carve"] = Time.get_ticks_msec() - _t
	build_ms = Time.get_ticks_msec() - t0
	_shared[_shared_key] = {
		"x0": x0, "z0": z0, "n": n, "h": _h, "filled": _filled,
		"acc": _acc, "down": _down,
		"lake": _lake, "marsh": _marsh, "seg": _seg, "seg_count": _seg_count,
		"carve": _carve,
		"buckets": _buckets, "lake_count": _lake_count, "lake_bodies": _lake_bodies,
		"sources": _sources, "mouths": _mouth_count, "outlets": _outlet_cells,
		"phases": phase_ms,
	}


func _relief(x: float, z: float) -> float:
	var t: Object = _terrain.get_ref()
	if t == null:
		return 0.0
	return float(t.call("relief", x, z))


func _sample_relief() -> void:
	var terrain_obj: Object = _terrain.get_ref()
	for j in n:
		var z := z0 + float(j) * COARSE
		var row := j * n
		for i in n:
			var x := x0 + float(i) * COARSE
			var index := row + i
			_h[index] = _relief(x, z)
			# Peso de chuva que chega à superfície. Calcário poroso infiltra mais;
			# os vales húmidos alimentam os rios com maior escoamento.
			_acc[index] = float(terrain_obj.call("runoff_factor", x, z)) if terrain_obj != null else 1.0


## Cada célula desce para a vizinha mais baixa (D8). A acumulação é feita por
## ordem decrescente de altitude: quando se processa uma célula, tudo o que
## nasce acima dela já lhe passou a água.
func _route_flow() -> void:
	var count := n * n
	for i in count:
		if _acc[i] <= 0.0:
			_acc[i] = 1.0
		_down[i] = -1

	# ordenação por altitude, descendente — buckets de 2 m (rápido e estável)
	var buckets: Array = []
	buckets.resize(512)
	for i in 512:
		buckets[i] = PackedInt32Array()
	var lo := 1e20
	var hi := -1e20
	for i in count:
		lo = minf(lo, _h[i])
		hi = maxf(hi, _h[i])
	var span := maxf(hi - lo, 0.001)
	for i in count:
		var b := clampi(int((_h[i] - lo) / span * 511.0), 0, 511)
		var pa: PackedInt32Array = buckets[b]
		pa.append(i)
		buckets[b] = pa

	var order := PackedInt32Array()
	order.resize(count)
	var w := 0
	for b in range(511, -1, -1):
		for idx in (buckets[b] as PackedInt32Array):
			order[w] = idx
			w += 1

	for k in count:
		var i := order[k]
		var ci := i % n
		var cj := i / n
		var best := -1
		var best_h := _h[i]
		for dj: int in [-1, 0, 1]:
			for di: int in [-1, 0, 1]:
				if di == 0 and dj == 0:
					continue
				var ni := ci + di
				var nj := cj + dj
				if ni < 0 or nj < 0 or ni >= n or nj >= n:
					continue
				var ni_idx := nj * n + ni
				# o desempate pela diagonal evita rios "em escada" colados ao eixo
				var bias := 1.0 if (di != 0 and dj != 0) else 0.0
				if _h[ni_idx] + bias * 0.0005 < best_h:
					best_h = _h[ni_idx]
					best = ni_idx
		if best >= 0:
			_down[i] = best
			_acc[best] += _acc[i]


## Depressões sem saída tornam-se lagos. Em vez de um "priority flood" completo,
## inunda-se a bacia local a partir do poço até à cota de transbordo — é barato
## e dá lagos com a forma do terreno, que é o que se vê.
func _find_lakes() -> void:
	_lake_count = 0
	_lake_bodies = 0
	for i in n * n:
		_lake[i] = DRY
	for i in n * n:
		if _down[i] >= 0:
			continue
		var cj := i / n
		var ci := i % n
		# um poço na borda da região não é um lago: é a água a sair do mapa
		if ci == 0 or cj == 0 or ci == n - 1 or cj == n - 1:
			continue
		if _h[i] < 0.5:
			continue
		# cota de transbordo = o vizinho mais baixo; é também a SAÍDA do lago.
		# Sem esta saída, um rio morria na primeira cova que encontrava — e o
		# mundo ficava cheio de rios truncados a montante dos lagos.
		var spill := 1e20
		var out_idx := -1
		for dj: int in [-1, 0, 1]:
			for di: int in [-1, 0, 1]:
				if di == 0 and dj == 0:
					continue
				var ni := clampi(ci + di, 0, n - 1)
				var nj := clampi(cj + dj, 0, n - 1)
				var nb := nj * n + ni
				if _h[nb] > _h[i] and _h[nb] < spill:
					spill = _h[nb]
					out_idx = nb
		if spill > 1e19:
			continue
		# a água transborda: a jusante do lago o rio continua
		_down[i] = out_idx
		# superfície AO NÍVEL do ponto de transbordo: acima dele a água verteria
		var level := spill
		if level - _h[i] < 0.5:
			continue          # poço raso: poça, não lago
		_lake_bodies += 1
		# inunda a bacia: preenchimento em largura, com tecto de área
		var queue := PackedInt32Array([i])
		var seen := {i: true}
		var filled := 0
		while not queue.is_empty() and filled < 900:
			var cur := queue[queue.size() - 1]
			queue.remove_at(queue.size() - 1)
			if _h[cur] > level:
				continue
			_lake[cur] = level
			_lake_count += 1
			filled += 1
			var ccj := cur / n
			var cci := cur % n
			for dj: int in [-1, 0, 1]:
				for di: int in [-1, 0, 1]:
					var ni2 := cci + di
					var nj2 := ccj + dj
					if ni2 < 0 or nj2 < 0 or ni2 >= n or nj2 >= n:
						continue
					var nb2 := nj2 * n + ni2
					if seen.has(nb2) or _h[nb2] > level:
						continue
					seen[nb2] = true
					queue.append(nb2)


# ── rede de rios ────────────────────────────────────────────────────────────

func _height_at(x: float, z: float) -> float:
	var fx := (x - x0) / COARSE
	var fz := (z - z0) / COARSE
	var i := clampi(int(floorf(fx)), 0, n - 2)
	var j := clampi(int(floorf(fz)), 0, n - 2)
	var tx := clampf(fx - float(i), 0.0, 1.0)
	var tz := clampf(fz - float(j), 0.0, 1.0)
	var a := _h[j * n + i]
	var b := _h[j * n + i + 1]
	var c := _h[(j + 1) * n + i]
	var d := _h[(j + 1) * n + i + 1]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)


func _acc_at(x: float, z: float) -> float:
	var fx := (x - x0) / COARSE
	var fz := (z - z0) / COARSE
	var i := clampi(int(floorf(fx)), 0, n - 2)
	var j := clampi(int(floorf(fz)), 0, n - 2)
	var tx := clampf(fx - float(i), 0.0, 1.0)
	var tz := clampf(fz - float(j), 0.0, 1.0)
	var a := _acc[j * n + i]
	var b := _acc[j * n + i + 1]
	var c := _acc[(j + 1) * n + i]
	var d := _acc[(j + 1) * n + i + 1]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)


## Traça um rio a partir de uma nascente. A direção vem do gradiente do relevo
## interpolado (não do D8): por isso a linha é curva e natural em vez de
## descer em escada de 16 em 16 metros.
## Traça um rio pela rede D8 (célula → célula a jusante) e suaviza a linha.
##
## Seguir o D8 em vez do gradiente é o que garante uma ÁRVORE: dois braços que
## se juntam passam pela mesma célula, portanto o segundo termina no primeiro em
## vez de correr ao lado dele. A suavização (Chaikin) devolve a curva natural
## sem perder a topologia.
func _trace_from(idx: int) -> PackedFloat32Array:
	var cells := PackedInt32Array()
	var cur := idx
	var own := {}
	while cur >= 0 and cells.size() < 400:
		var ci := cur % n
		var cj := cur / n
		if ci <= 0 or cj <= 0 or ci >= n - 1 or cj >= n - 1:
			break
		if _h[cur] < 0.15:
			break
		if _marsh[cur] == 2 and not own.has(cur):
			cells.append(cur)
			break
		_marsh[cur] = 2
		own[cur] = true
		cells.append(cur)
		cur = _down[cur]
	if cells.size() < 2:
		return PackedFloat32Array()

	# 1) centros das células → linha quebrada de 20 em 20 m
	var xs := PackedFloat32Array()
	var zs := PackedFloat32Array()
	for c in cells:
		xs.append(x0 + float(c % n) * COARSE)
		zs.append(z0 + float(c / n) * COARSE)
	# 2) Chaikin duas vezes: corta os cantos sem afastar a linha do vale
	for it in 2:
		xs = _chaikin(xs, true)
		zs = _chaikin(zs, false)
	# 3) cada ponto leva o relevo FINO e a acumulação. O NÍVEL da água é
	#    calculado depois do leito existir (`_retune_levels`): assim a lâmina
	#    assenta no chão que o raster realmente escavou, e não no relevo ideal.
	var pts := PackedFloat32Array()
	for k in xs.size():
		pts.append(xs[k])
		pts.append(zs[k])
		pts.append(_relief(xs[k], zs[k]))
		pts.append(_acc_at(xs[k], zs[k]))
	return pts


## Um passo de Chaikin nos interiores; as pontas ficam onde estão.
func _chaikin(v: PackedFloat32Array, first: bool) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if v.size() < 3:
		return v
	out.append(v[0])
	for i in v.size() - 1:
		var a := v[i]
		var b := v[i + 1]
		out.append(a * 0.75 + b * 0.25)
		out.append(a * 0.25 + b * 0.75)
	out.append(v[v.size() - 1])
	return out


## Constrói o raster do leito a partir dos segmentos (uma vez por semente).
func _build_carve() -> void:
	_carve.resize(CARVE_N * CARVE_N)
	for i in _carve.size():
		_carve[i] = 0.0
	for sid in _seg_count:
		var base := sid * SEG_STRIDE
		var ax := _seg[base]
		var az := _seg[base + 1]
		var bx := _seg[base + 2]
		var bz := _seg[base + 3]
		var hw := _seg[base + 6]
		var depth := _seg[base + 7]
		var reach := hw * 3.3 + 4.0
		var i0 := maxi(0, int(floorf((minf(ax, bx) - reach - x0) / CARVE_STEP)))
		var i1 := mini(CARVE_N - 1, int(ceilf((maxf(ax, bx) + reach - x0) / CARVE_STEP)))
		var j0 := maxi(0, int(floorf((minf(az, bz) - reach - z0) / CARVE_STEP)))
		var j1 := mini(CARVE_N - 1, int(ceilf((maxf(az, bz) + reach - z0) / CARVE_STEP)))
		for j in range(j0, j1 + 1):
			var pz := z0 + float(j) * CARVE_STEP
			var row := j * CARVE_N
			for i in range(i0, i1 + 1):
				var px := x0 + float(i) * CARVE_STEP
				var d := _seg_dist(px, pz, ax, az, bx, bz)
				if d >= reach:
					continue
				# 1.35 e não 1.1: o leito tem de ficar ABAIXO da lâmina mesmo
				# depois da interpolação de 8 m. A 1.1 sobravam 5 cm de chão
				# acima da água em 2/3 dos segmentos e o rio aparecia aos
				# pedaços. Um rio real também tem leito mais fundo que a água.
				var cut := depth * 1.35 * pow(1.0 - d / reach, 1.7)
				if cut > _carve[row + i]:
					_carve[row + i] = cut


func _river_depth(acc: float) -> float:
	return clampf(0.55 + 0.75 * log(1.0 + acc / 55.0), 0.55, 4.2)


func _river_half_width(acc: float) -> float:
	return clampf(1.25 + 0.62 * log(1.0 + acc / 48.0), 1.25, 9.0)


func _trace_rivers() -> void:
	# nascentes: células com acumulação acima do limiar e sem vizinha a montante
	var sources: Array = []
	for j in range(1, n - 1):
		for i in range(1, n - 1):
			var idx := j * n + i
			if _acc[idx] < ACC_STREAM:
				continue
			if _h[idx] < 0.3:
				continue
			if _lake[idx] > DRY + 1.0:
				continue          # um lago não é nascente
			var upstream := false
			for dj: int in [-1, 0, 1]:
				for di: int in [-1, 0, 1]:
					if di == 0 and dj == 0:
						continue
					var nb := (j + dj) * n + (i + di)
					if _acc[nb] >= ACC_STREAM and _down[nb] == idx:
						upstream = true
			if upstream:
				continue
			sources.append(Vector3(idx, 0.0, _acc[idx]))

	# as nascentes mais fortes primeiro; um limite evita centenas de riachos
	sources.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.z > b.z)
	_sources = sources.size()
	var limit := mini(sources.size(), 40)

	for s in range(limit):
		var src: Vector3 = sources[s]
		var pts := _trace_from(int(src.x))
		if pts.size() < 6:
			continue
		_add_path(pts)

	# mangue: terreno baixo, plano e molhado perto de um rio
	for j in range(1, n - 1):
		for i in range(1, n - 1):
			var idx := j * n + i
			if _h[idx] > 1.8 or _h[idx] < -0.2:
				continue
			if _lake[idx] > DRY or _marsh[idx] == 2:
				continue
			var slope := absf(_h[idx + 1] - _h[idx - 1]) + absf(_h[idx + n] - _h[idx - n])
			if slope > 0.55:
				continue
			_marsh[idx] = 1


## Converte a polilinha traçada em segmentos com todos os dados de consulta.
func _add_path(pts: PackedFloat32Array) -> void:
	var count := pts.size() / 4
	for k in count - 1:
		var ax := pts[k * 4]
		var az := pts[k * 4 + 1]
		var ha := pts[k * 4 + 2]
		var bx := pts[(k + 1) * 4]
		var bz := pts[(k + 1) * 4 + 1]
		var hb := pts[(k + 1) * 4 + 2]
		var mx := (ax + bx) * 0.5
		var mz := (az + bz) * 0.5
		var acc := _acc_at(mx, mz)
		if acc < ACC_STREAM * 0.6:
			continue
		var hw := _river_half_width(acc)
		var depth := _river_depth(acc)
		var dx := bx - ax
		var dz := bz - az
		var dl := sqrt(dx * dx + dz * dz)
		if dl < 0.001:
			continue
		var drop := maxf(ha - hb, 0.0)
		var slope := drop / dl
		var speed := clampf(sqrt(maxf(slope, 0.0001) * 19.6) * 1.35, 0.12, 3.4)
		# mangue: água quase parada e turva
		var turb := clampf(0.25 + (1.0 - clampf(speed / 1.2, 0.0, 1.0)) * 0.55, 0.0, 0.9)
		if _marsh[(clampi(int((mz - z0) / COARSE), 0, n - 1)) * n
				+ clampi(int((mx - x0) / COARSE), 0, n - 1)] == 1:
			speed *= 0.25
			turb = 0.95
		_push_segment(ax, az, bx, bz, 0.0, 0.0, hw, depth, speed, dx / dl, dz / dl,
			turb, KIND_RIVER, ha, hb)


func _push_segment(ax: float, az: float, bx: float, bz: float, la: float, lb: float,
		hw: float, depth: float, speed: float, fx: float, fz: float, turb: float,
		kind: int, ha: float = 0.0, hb: float = 0.0) -> void:
	var base := _seg_count * SEG_STRIDE
	_seg.resize(base + SEG_STRIDE)
	_seg[base] = ax
	_seg[base + 1] = az
	_seg[base + 2] = bx
	_seg[base + 3] = bz
	_seg[base + 4] = la
	_seg[base + 5] = lb
	_seg[base + 6] = hw
	_seg[base + 7] = depth
	_seg[base + 8] = speed
	_seg[base + 9] = fx
	_seg[base + 10] = fz
	_seg[base + 11] = turb
	_seg[base + 12] = float(kind)
	_seg[base + 13] = ha
	_seg[base + 14] = hb
	_bucket_add(_seg_count, ax, az, bx, bz, hw)
	_seg_count += 1


func _bucket_add(id: int, ax: float, az: float, bx: float, bz: float,
		hw: float) -> void:
	# margem = ALCANCE DO LEITO deste segmento. Assim qualquer ponto a que este
	# rio toque está num bucket onde ele foi registado — e basta consultar o
	# bucket do ponto. Com uma margem fixa de 34 m, cada segmento entrava em 25
	# buckets e uma amostra testava 1 400 segmentos (era isto que punha os
	# chunks a 7 s).
	var margin := hw * 3.3 + 4.0
	var i0 := int(floorf((minf(ax, bx) - margin) / 32.0))
	var i1 := int(floorf((maxf(ax, bx) + margin) / 32.0))
	var j0 := int(floorf((minf(az, bz) - margin) / 32.0))
	var j1 := int(floorf((maxf(az, bz) + margin) / 32.0))
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var key := Vector2i(i, j)
			var pa: PackedInt32Array = _buckets.get(key, PackedInt32Array())
			pa.append(id)
			_buckets[key] = pa


# ── leito ───────────────────────────────────────────────────────────────────

## Distância de um ponto ao segmento (a, b).
func _seg_dist(px: float, pz: float, ax: float, az: float, bx: float, bz: float) -> float:
	var vx := bx - ax
	var vz := bz - az
	var len2 := vx * vx + vz * vz
	var t := 0.0
	if len2 > 1e-9:
		t = clampf(((px - ax) * vx + (pz - az) * vz) / len2, 0.0, 1.0)
	var dx := px - (ax + vx * t)
	var dz := pz - (az + vz * t)
	return sqrt(dx * dx + dz * dz)


## Quanto o leito foi escavado neste ponto (metros). O `Terrain` subtrai isto.
##
## O corte é `depth · 1.1 · (1 − d/reach)^1.7`: máximo no eixo, zero na borda,
## tangente horizontal na margem — a mesma curva em todo o rio, por isso as
## margens não têm degraus. O raster guarda o MÁXIMO dos segmentos, o que resolve
## confluências sem somar vales.
func carve(x: float, z: float) -> float:
	if not built:
		return 0.0
	var fx := (x - x0) / CARVE_STEP
	var fz := (z - z0) / CARVE_STEP
	if fx < 0.0 or fz < 0.0 or fx >= float(CARVE_N - 1) or fz >= float(CARVE_N - 1):
		return 0.0
	var i := int(floorf(fx))
	var j := int(floorf(fz))
	var u := fx - float(i)
	var v := fz - float(j)
	var a := _carve[j * CARVE_N + i]
	var b := _carve[j * CARVE_N + i + 1]
	var c := _carve[(j + 1) * CARVE_N + i]
	var d := _carve[(j + 1) * CARVE_N + i + 1]
	var cut := lerpf(lerpf(a, b, u), lerpf(c, d, u), v)
	# desvanece nas bordas da região: o vale não acaba num degrau
	var edge := minf(minf(x - x0, x0 + SPAN - x), minf(z - z0, z0 + SPAN - z))
	if edge < FADE:
		cut *= clampf(edge / FADE, 0.0, 1.0)
	return cut


## O nível da água nasce do LEITO, não do relevo ideal.
##
## `leito + 0,85·profundidade`: a lâmina fica dentro do vale que o raster
## escavou, com margem para o erro da interpolação de 8 m. É isto que faz o rio
## ser contínuo em vez de aparecer aos pedaços — e a superfície segue o fundo,
## como num curso de água real.
func _retune_levels() -> void:
	for id in _seg_count:
		var base := id * SEG_STRIDE
		var depth := _seg[base + 7]
		var la := _seg[base + 13] - carve(_seg[base], _seg[base + 1]) + depth * 0.85
		var lb := _seg[base + 14] - carve(_seg[base + 2], _seg[base + 3]) + depth * 0.85
		_seg[base + 4] = maxf(la, 0.08)
		_seg[base + 5] = maxf(lb, 0.08)


## Segmento mais próximo deste ponto, ou -1. Usa o índice espacial (buckets).
func _nearest_segment(x: float, z: float) -> int:
	var key := Vector2i(int(floorf(x / 32.0)), int(floorf(z / 32.0)))
	# A cache é por célula de 32 m, mas a resposta só serve se o segmento ainda
	# estiver dentro da largura NESTE ponto. Sem esta revalidação, um rio de 3 m
	# aparecia aos bolsões: o primeiro vértice da célula encontrava água e os
	# seguintes herdavam o resultado errado.
	if key == _last_key and _last_hit >= 0:
		var lb := _last_hit * SEG_STRIDE
		var ld := _seg_dist(x, z, _seg[lb], _seg[lb + 1], _seg[lb + 2], _seg[lb + 3])
		if ld <= _seg[lb + 6] * 1.15:
			return _last_hit
	var best := -1
	var best_d := 1e20
	var best_hw := 0.0
	if _buckets.has(key):
		for id in (_buckets[key] as PackedInt32Array):
			var base := id * SEG_STRIDE
			var hw := _seg[base + 6]
			var d := _seg_dist(x, z, _seg[base], _seg[base + 1],
				_seg[base + 2], _seg[base + 3])
			if d < hw * 1.15 and d < best_d:
				best_d = d
				best = id
				best_hw = hw
	_last_key = key
	_last_hit = best
	return best


## A amostra de água neste ponto. Devolve `{}` quando está seco.
##   kind, level, depth, flow (Vector2), speed, salinity, turbidity, half_width
func sample(x: float, z: float) -> Dictionary:
	if not built:
		return {}
	# 1) rio / mangue — a rede de segmentos manda
	var id := _nearest_segment(x, z)
	if id >= 0:
		var base := id * SEG_STRIDE
		var ax := _seg[base]
		var az := _seg[base + 1]
		var bx := _seg[base + 2]
		var bz := _seg[base + 3]
		var vx := bx - ax
		var vz := bz - az
		var len2 := vx * vx + vz * vz
		var t := 0.0
		if len2 > 1e-9:
			t = clampf(((x - ax) * vx + (z - az) * vz) / len2, 0.0, 1.0)
		var level := lerpf(_seg[base + 4], _seg[base + 5], t)
		var hw := _seg[base + 6]
		var cx := ax + vx * t
		var cz := az + vz * t
		var d := sqrt((x - cx) * (x - cx) + (z - cz) * (z - cz))
		if d <= hw * 1.15:
			var ground := _relief(x, z) - carve(x, z)
			var depth := level - ground
			if depth > 0.0:
				var speed := _seg[base + 8]
				return {
					"kind": int(_seg[base + 12]),
					"level": level,
					"depth": depth,
					"flow": Vector2(_seg[base + 9], _seg[base + 10]),
					"speed": speed,
					"salinity": 0.0,
					"turbidity": _seg[base + 11],
					"half_width": hw,
					"body": id,
				}
	# 2) lago — campo grosso, interpolação bilinear
	var lv := _lake_at(x, z)
	if lv > DRY + 1.0:
		var ground2 := _relief(x, z) - carve(x, z)
		var depth2 := lv - ground2
		if depth2 > 0.0:
			return {
				"kind": KIND_LAKE,
				"level": lv,
				"depth": depth2,
				"flow": Vector2.ZERO,
				"speed": 0.02,
				"salinity": 0.0,
				"turbidity": 0.55,
				"half_width": 0.0,
				"body": -1,
			}
	return {}


func _lake_at(x: float, z: float) -> float:
	if n == 0:
		return DRY
	var fx := (x - x0) / COARSE
	var fz := (z - z0) / COARSE
	if fx < 0.0 or fz < 0.0 or fx >= float(n - 1) or fz >= float(n - 1):
		return DRY
	var i := int(floorf(fx))
	var j := int(floorf(fz))
	var tx := fx - float(i)
	var tz := fz - float(j)
	var a := _lake_val(_lake[j * n + i])
	var b := _lake_val(_lake[j * n + i + 1])
	var c := _lake_val(_lake[(j + 1) * n + i])
	var d := _lake_val(_lake[(j + 1) * n + i + 1])
	var v := lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)
	if v <= 0.0:
		return DRY
	return v


func _lake_val(v: float) -> float:
	return 0.0 if v <= DRY + 1.0 else v


func is_marsh(x: float, z: float) -> bool:
	if not built:
		return false
	var i := clampi(int((x - x0) / COARSE), 0, n - 1)
	var j := clampi(int((z - z0) / COARSE), 0, n - 1)
	return _marsh[j * n + i] == 1


## Diagnóstico: que fração dos segmentos tem água ACIMA do chão escavado?
## Um segmento com nível abaixo do leito é um vale seco — o bug clássico de
## quem traça a linha mas não a escava.
func wet_report() -> Dictionary:
	var wet := 0
	var worst: Array = []
	var dmin := 1e9
	var dmax := -1e9
	for id in _seg_count:
		var base := id * SEG_STRIDE
		var mx := (_seg[base] + _seg[base + 2]) * 0.5
		var mz := (_seg[base + 1] + _seg[base + 3]) * 0.5
		var level := (_seg[base + 4] + _seg[base + 5]) * 0.5
		var ground := _relief(mx, mz) - carve(mx, mz)
		var d := level - ground
		dmin = minf(dmin, d)
		dmax = maxf(dmax, d)
		if d > 0.0:
			wet += 1
		elif worst.size() < 6:
			worst.append("(%.0f,%.0f) nível=%.2f chão=%.2f d=%.2f" % [mx, mz, level, ground, d])
	return {"segments": _seg_count, "wet": wet, "min": dmin, "max": dmax,
		"worst": worst}


## Nível de água "de rio" aqui, ou DRY. Atalho para o `Terrain.water_info`.
func level_at(x: float, z: float) -> float:
	var s := sample(x, z)
	return float(s.get("level", DRY))


## Diagnóstico (usado pelos testes e pelo relatório de arranque).
func stats() -> Dictionary:
	var river := 0
	for i in n * n:
		if _acc[i] >= ACC_STREAM * 0.6:
			river += 1
	return {
		"segments": _seg_count,
		"river_cells": river,
		"ms": build_ms,
		"phases": phase_ms,
		"lakes": _lake_bodies,
		"lake_cells": _lake_count,
		"sources": _sources,
		"grid": n,
	}
