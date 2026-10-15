class_name Terrain
extends RefCounted
## Terrain — o mundo como função pura.
##
## Regra: `height(x, z)` e `biome_weights(x, z)` são deterministas e não guardam
## estado. Quem quer que pergunte — o chunk, uma árvore, a água, o
## save — recebe a mesma resposta. É isto que permite gerar à volta do jogador e
## apagar atrás dele sem costuras.
##
## Ordem das camadas (baixo → cima):
##   continente (fbm)  →  montanhas (ridgido, com máscara)  →  detalhe
##   →  rio (curva de nível de um ruído)  →  caminho (achatado)  →  aldeia

const SEA_LEVEL := 0.0
const RIVER_WIDTH := 0.030
const RIVER_VALLEY := 0.105
const RIVER_BED := -2.6
const PATH_HALF_WIDTH := 2.6
const PATH_SOFT := 5.2

## Índices de bioma — a ordem é a mesma em `biome_weights()`.
const B_SAND := 0
const B_MEADOW := 1
const B_FOREST := 2
const B_GROVE := 3
const B_ROCK := 4
const B_SNOW := 5
const B_MARSH := 6
const B_DESERT := 7
const B_BADLANDS := 8
const B_SAVANNA := 9
const B_DIRT := 10
const B_MUD := 11
const BIOME_COUNT := 12

## Paleta anime: cores saturadas e limpas, sem texturas.
const BIOME_COLOR := [
	Color(0.80, 0.72, 0.54),  # areia
	Color(0.34, 0.50, 0.24),  # prado
	Color(0.16, 0.38, 0.22),  # floresta
	Color(0.74, 0.52, 0.55),  # bosque de cerejeiras
	Color(0.46, 0.45, 0.47),  # rocha
	Color(0.86, 0.89, 0.94),  # neve
	Color(0.27, 0.43, 0.32),  # pântano
	Color(0.87, 0.75, 0.47),  # deserto (dunas)
	Color(0.71, 0.39, 0.21),  # badlands (laranja ferrugem)
	Color(0.60, 0.56, 0.27),  # savana (erva seca)
	Color(0.40, 0.30, 0.21),  # terra nua
	Color(0.30, 0.22, 0.15),  # lama
]

## Posição da aldeia (definida em relação ao spawn).
const VILLAGE := Vector2(96.0, 0.0)
const VILLAGE_RADIUS := 17.0

var seed_value: int = 0
var n_continent: FastNoiseLite
var n_detail: FastNoiseLite
var n_mountain: FastNoiseLite
var n_mask: FastNoiseLite
var n_moist: FastNoiseLite
var n_temp: FastNoiseLite
var n_grove: FastNoiseLite
var n_river: FastNoiseLite
var n_tint: FastNoiseLite
var n_warp: FastNoiseLite
var n_erosion: FastNoiseLite
var n_warp2: FastNoiseLite
var n_hills: FastNoiseLite
var n_mesa: FastNoiseLite
var n_dune: FastNoiseLite
var n_crag: FastNoiseLite
var _coast_axis := Vector2.RIGHT
var _coast_side := Vector2.DOWN


func _init(p_seed: int = 1) -> void:
	seed_value = p_seed
	var coast_angle := fposmod(float(p_seed) * 0.00017320508, TAU)
	_coast_axis = Vector2(cos(coast_angle), sin(coast_angle))
	_coast_side = Vector2(-_coast_axis.y, _coast_axis.x)
	# ── escala do mundo: regiões de vários km, para o mundo ter geografia e não "sal e pimenta"
	n_continent = _noise(FastNoiseLite.TYPE_SIMPLEX, Db.terrain_noise("continent", "freq", 0.00085),
		int(Db.terrain_noise("continent", "octaves", 4)), 0.5, 2.0, p_seed + 1)
	n_detail = _noise(FastNoiseLite.TYPE_PERLIN, 0.021, 3, 0.5, 2.0, p_seed + 2)
	n_mountain = _noise(FastNoiseLite.TYPE_SIMPLEX, Db.terrain_noise("mountain", "freq", 0.0030),
		int(Db.terrain_noise("mountain", "octaves", 6)), 0.5, 2.1, p_seed + 3)
	n_mountain.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	n_mask = _noise(FastNoiseLite.TYPE_SIMPLEX, 0.0011, 3, 0.5, 2.0, p_seed + 4)
	n_moist = _noise(FastNoiseLite.TYPE_SIMPLEX, 0.00075, 3, 0.5, 2.0, p_seed + 5)
	n_temp = _noise(FastNoiseLite.TYPE_SIMPLEX, 0.00055, 3, 0.5, 2.0, p_seed + 6)
	n_grove = _noise(FastNoiseLite.TYPE_SIMPLEX, 0.0040, 2, 0.5, 2.0, p_seed + 7)
	n_river = _noise(FastNoiseLite.TYPE_SIMPLEX, 0.0024, 4, 0.5, 2.4, p_seed + 8)
	n_tint = _noise(FastNoiseLite.TYPE_PERLIN, 0.09, 2, 0.5, 2.0, p_seed + 9)
	n_warp = _noise(FastNoiseLite.TYPE_SIMPLEX, 0.0009, 2, 0.5, 2.0, p_seed + 10)
	n_erosion = _noise(FastNoiseLite.TYPE_SIMPLEX, 0.0016, 3, 0.5, 2.0, p_seed + 11)
	n_warp2 = _noise(FastNoiseLite.TYPE_SIMPLEX, 0.0042, 2, 0.5, 2.0, p_seed + 12)
	n_hills = _noise(FastNoiseLite.TYPE_PERLIN, 0.0065, 4, 0.5, 2.0, p_seed + 13)
	n_mesa = _noise(FastNoiseLite.TYPE_SIMPLEX, 0.0021, 2, 0.5, 2.0, p_seed + 14)
	n_dune = _noise(FastNoiseLite.TYPE_SIMPLEX, 0.011, 2, 0.5, 2.0, p_seed + 15)
	n_crag = _noise(FastNoiseLite.TYPE_SIMPLEX, 0.0085, 3, 0.5, 2.1, p_seed + 16)
	n_crag.fractal_type = FastNoiseLite.FRACTAL_RIDGED


func _noise(t: FastNoiseLite.NoiseType, freq: float, oct: int, gain: float,
		lac: float, s: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = s
	n.noise_type = t
	n.frequency = freq
	n.fractal_octaves = oct
	n.fractal_gain = gain
	n.fractal_lacunarity = lac
	return n


# ══════════════════════════════════════════════════════════════════════════
#  ALTURA
#
#  Receita (inspirada no Minecraft 1.18+ e em terrenos AAA):
#   1. CONTINENTALIDADE (ruído de ~1 km) → spline → oceano, costa, planície, planalto
#   2. EROSÃO (0 = escarpado, 1 = plano) decide onde nascem as montanhas
#   3. PICOS: ruído ridged ao quadrado × máscara (inland × baixa erosão) → cristas até ~230 m
#   4. colinas, e rochedos finos (ridged de alta frequência) só nas montanhas
#   5. MESAS: em clima quente/seco, os patamares são quantizados (terraços) → planaltos e buttes
#   6. DUNAS: no deserto, ondas assimétricas alinhadas
#   7. rios: só em terras baixas, com vale e leito (sem fendas em montanha)
#   8. caminho e clareira da aldeia
#  Tudo é domain-warped: as formas deixam de seguir a grelha do ruído.
# ══════════════════════════════════════════════════════════════════════════
const CONT_PTS := [
	[-1.00, -46.0], [-0.62, -30.0], [-0.42, -7.0], [-0.24, 0.8], [0.00, 4.5],
	[0.25, 11.0], [0.55, 22.0], [1.00, 36.0],
]


static func _pl(x: float, pts: Array) -> float:
	if x <= float(pts[0][0]):
		return float(pts[0][1])
	for i in range(1, pts.size()):
		if x <= float(pts[i][0]):
			var t: float = (x - float(pts[i - 1][0])) / (float(pts[i][0]) - float(pts[i - 1][0]))
			t = t * t * (3.0 - 2.0 * t)
			return lerpf(float(pts[i - 1][1]), float(pts[i][1]), t)
	return float(pts[pts.size() - 1][1])


## Clima sem altitude: x = temperatura 0 frio..1 quente, y = humidade 0 seco..1 húmido.
func climate(x: float, z: float) -> Vector2:
	var wx := n_warp2.get_noise_2d(x, z) * 260.0
	var wz := n_warp2.get_noise_2d(x + 91.0, z - 57.0) * 260.0
	var t := clampf(n_temp.get_noise_2d(x + wx, z + wz) * 1.6 + 0.5, 0.0, 1.0)
	var m := clampf(n_moist.get_noise_2d(x + wx, z + wz) * 1.6 + 0.5, 0.0, 1.0)
	return Vector2(t, m)


func height(x: float, z: float) -> float:
	var h := _land(x, z, true)
	# Caminho e aldeia são aplicados primeiro. O rio passa por baixo da estrada
	# como um vau raso, em vez de a estrada voltar a encher o leito.
	var d := path_distance(x, z)
	if d < PATH_SOFT:
		var w := 1.0 - _smooth(PATH_HALF_WIDTH, PATH_SOFT, d)
		h = lerpf(h, path_height(x), w * 0.92)
	# aldeia: clareira plana
	var vd := village_distance(x, z)
	if vd < VILLAGE_RADIUS * 1.8:
		var w := 1.0 - _smooth(VILLAGE_RADIUS, VILLAGE_RADIUS * 1.8, vd)
		h = lerpf(h, village_height(), w * 0.9)

	# Costa de arranque garantida: um mar amplo nasce perto da aldeia e ocupa
	# todo o lado a jusante da costa. O ruído só quebra a linha da costa; não
	# decide onde há água, por isso o mar não vira bolsões soltos.
	var coords := _starter_coords(x, z)
	var along := coords.x
	var across := coords.y
	var coast := _coastline(across)
	var ocean := _smooth(coast - 42.0, coast + 38.0, along)
	var sea_bed := SEA_LEVEL - 22.0 + n_erosion.get_noise_2d(x * 0.7, z * 0.7) * 2.4
	h = lerpf(h, sea_bed, ocean)

	# Um único rio sinuoso, de nível descendente e largura de curso d'água,
	# atravessa o vale e entrega na costa. As margens são talhadas em seguida.
	var flow := _river_activity(along, coast)
	if flow > 0.001:
		var river_distance := absf(across - _river_center(along))
		var surface := _river_level(along, coast)
		var bank := 1.0 - _smooth(6.5, 20.0, river_distance)
		var channel := 1.0 - _smooth(3.8, 7.0, river_distance)
		h = lerpf(h, minf(h, surface + 1.25), bank * flow * 0.92)
		h = lerpf(h, minf(h, surface - 1.7), channel * flow)
	return h


func _starter_coords(x: float, z: float) -> Vector2:
	var d := Vector2(x, z) - village_center()
	return Vector2(d.dot(_coast_axis), d.dot(_coast_side))


func _coastline(across: float) -> float:
	return 142.0 + sin(across * 0.0052 + float(seed_value) * 0.013) * 24.0 \
		+ sin(across * 0.013 + float(seed_value) * 0.027) * 9.0


func _river_center(along: float) -> float:
	var phase := float(seed_value) * 0.019
	return 58.0 + sin(along * 0.008 + phase) * 15.0 \
		+ sin(along * 0.019 - phase * 0.7) * 6.0


func _river_activity(along: float, coast: float) -> float:
	return _smooth(-270.0, -210.0, along) \
		* (1.0 - _smooth(coast - 24.0, coast + 8.0, along))


func _river_level(along: float, coast: float) -> float:
	var t := clampf((along + 220.0) / maxf(coast + 220.0, 1.0), 0.0, 1.0)
	return lerpf(4.2, SEA_LEVEL + 0.12, t)


func water_info(x: float, z: float) -> Vector2:
	# x = superfície (sentinela negativa quando seco), y = coluna de água.
	var coords := _starter_coords(x, z)
	var coast := _coastline(coords.y)
	var flow := _river_activity(coords.x, coast)
	var river_candidate := flow > 0.05 \
		and absf(coords.y - _river_center(coords.x)) < 7.0
	var ocean_candidate := coords.x > coast - 42.0
	if not river_candidate and not ocean_candidate:
		return Vector2(-100000.0, 0.0)
	# Depois da faixa costeira, o leito já está totalmente abaixo do mar. Evita
	# recalcular ruído e relevo em cada vértice do oceano durante a geração.
	if not river_candidate and coords.x >= coast + 38.0:
		return Vector2(SEA_LEVEL, 22.0)
	var ground := height(x, z)
	if river_candidate:
		var river_surface := _river_level(coords.x, coast)
		if ground < river_surface + 0.05:
			return Vector2(river_surface, maxf(river_surface - ground, 0.0))
	if ground < SEA_LEVEL - 0.12:
		return Vector2(SEA_LEVEL, maxf(SEA_LEVEL - ground, 0.0))
	return Vector2(-100000.0, 0.0)


func water_surface_height(x: float, z: float) -> float:
	return water_info(x, z).x


func is_ocean(x: float, z: float) -> bool:
	var coords := _starter_coords(x, z)
	var coast := _coastline(coords.y)
	if _river_activity(coords.x, coast) > 0.05 \
			and absf(coords.y - _river_center(coords.x)) < 9.0:
		return false
	return height(x, z) < SEA_LEVEL - 0.12


func grass_coverage_s(h: float, sl: float, weights: PackedFloat32Array) -> float:
	if h < SEA_LEVEL + 0.25:
		return 0.0
	var wet_green := weights[B_MEADOW] * 0.92 + weights[B_FOREST] * 0.76 \
		+ weights[B_GROVE] * 0.84 + weights[B_MARSH] * 0.72
	var dry_green := weights[B_SAVANNA] * 0.66 + weights[B_DIRT] * 0.24 \
		+ weights[B_MUD] * 0.30
	var sparse := weights[B_SNOW] * 0.05 + weights[B_ROCK] * 0.03 \
		+ (weights[B_SAND] + weights[B_DESERT]) * 0.015 + weights[B_BADLANDS] * 0.01
	var slope_mask := 1.0 - _smooth(0.28, 0.68, sl)
	return clampf((wet_green + dry_green + sparse) * slope_mask, 0.0, 0.96)


func grass_dryness(weights: PackedFloat32Array) -> float:
	return clampf(weights[B_SAVANNA] * 0.55 + weights[B_DESERT] * 0.9 \
		+ weights[B_BADLANDS] * 0.85 + weights[B_DIRT] * 0.25, 0.0, 1.0)


## Terreno "cru", sem rio/caminho/aldeia.
func _land(x: float, z: float, detail: bool = true) -> float:
	var wx := n_warp.get_noise_2d(x, z) * 120.0 + n_warp2.get_noise_2d(x, z) * 18.0
	var wz := n_warp.get_noise_2d(x + 311.7, z - 177.3) * 120.0 + n_warp2.get_noise_2d(x - 91.0, z + 57.0) * 18.0
	var px := x + wx
	var pz := z + wz

	var c := n_continent.get_noise_2d(px, pz)
	var er := clampf(n_erosion.get_noise_2d(px, pz) * 0.5 + 0.5, 0.0, 1.0)
	# o arranque é sempre uma planície temperada e amigável (a aldeia fica aqui)
	var vc := village_center()
	var spawn := 1.0 - _smooth(160.0, 700.0, Vector2(x, z).distance_to(vc))
	c = lerpf(c, maxf(c, 0.20), spawn)
	er = lerpf(er, maxf(er, 0.78), spawn)

	var cl := climate(x, z)
	var hot_dry := _smooth(0.58, 0.78, cl.x) * (1.0 - _smooth(0.30, 0.50, cl.y)) * (1.0 - spawn)

	# 1) base pela continentalidade
	var h := _pl(c, Db.continent_spline(CONT_PTS))

	# 2) colinas suaves (mais altas onde a erosão é baixa)
	h += n_hills.get_noise_2d(px, pz) * (5.0 + 20.0 * (1.0 - er)) * _smooth(-0.15, 0.2, c)

	# 3) montanhas: inland × pouco erodido, com cristas
	var m := _smooth(0.04, 0.50, c) * pow(1.0 - er, 1.15)
	if m > 0.001:
		var ridge := clampf(n_mountain.get_noise_2d(px, pz) * 1.2 + 0.12, 0.0, 1.0)
		var peak := pow(ridge, 1.9) * Db.terrain_num("peak_height", 235.0) * m * m
		# rochedos: ridged de alta frequência, só onde já é alto (dá agulhas e degraus)
		var hi := _smooth(30.0, 120.0, peak)
		if hi > 0.0 and detail:
			peak += n_crag.get_noise_2d(px, pz) * Db.terrain_num("crag_amount", 22.0) * hi
		h += peak

	# 4) mesas / planaltos (badlands): sobe e quantiza em patamares
	var mesa_w := _smooth(0.50, 0.72, n_mesa.get_noise_2d(px, pz) * 0.5 + 0.5) * hot_dry * _smooth(0.0, 0.25, c)
	if mesa_w > 0.001:
		var step_h := Db.terrain_num("mesa_step", 12.0)
		var hh := (h + 10.0 * mesa_w) / step_h
		var f := floorf(hh)
		var sharp := _smooth(0.30, 0.55, hh - f)
		h = lerpf(h, (f + sharp) * step_h, mesa_w * 0.92)

	# 5) dunas do deserto: cristas assimétricas
	var dune_w := _smooth(0.60, 0.80, cl.x) * (1.0 - _smooth(0.26, 0.44, cl.y)) * (1.0 - mesa_w) \
		* (1.0 - _smooth(14.0, 34.0, h)) * (1.0 - spawn)
	if dune_w > 0.001:
		var dn := n_dune.get_noise_2d(px * 0.6 + pz * 0.3, pz * 1.3 - px * 0.15)
		var crest := 1.0 - absf(dn)
		h += (pow(crest, 2.4) * 7.5 - 2.0) * dune_w

	# 6) detalhe fino
	if detail:
		h += n_detail.get_noise_2d(x, z) * (0.9 + (1.0 - er) * 1.8)
	else:
		h += n_detail.get_noise_2d(x, z) * 0.45
	return h


## Inclinação 0..1 (0 = plano). Usada para relva, árvores e o bioma rochoso.
func slope(x: float, z: float) -> float:
	var e := 1.2
	var hx := height(x + e, z) - height(x - e, z)
	var hz := height(x, z + e) - height(x, z - e)
	return clampf(sqrt(hx * hx + hz * hz) / (2.0 * e) * 0.55, 0.0, 1.0)


# ── caminho ────────────────────────────────────────────────────────────────
## O caminho é uma função z = f(x), o que torna a distância O(1).
func path_z(x: float) -> float:
	return 20.0 * sin(x * 0.0075) + 9.0 * sin(x * 0.019 + 1.7)


func path_slope(x: float) -> float:
	var e := 1.0
	return (path_z(x + e) - path_z(x - e)) / (2.0 * e)


func path_distance(x: float, z: float) -> float:
	var dz := z - path_z(x)
	var s := path_slope(x)
	return absf(dz) / sqrt(1.0 + s * s)


func path_height(x: float) -> float:
	return _land(x, path_z(x), false) + 0.05


# ── aldeia ─────────────────────────────────────────────────────────────────
func village_center() -> Vector2:
	return Vector2(VILLAGE.x, path_z(VILLAGE.x))


func village_distance(x: float, z: float) -> float:
	var c := village_center()
	return Vector2(x, z).distance_to(c)


func village_height() -> float:
	var c := village_center()
	return _land(c.x, c.y, false) + 0.1


# ══════════════════════════════════════════════════════════════════════════
#  BIOMAS
# ══════════════════════════════════════════════════════════════════════════
## Escreve os pesos (normalizados) em `out`, que tem de ter BIOME_COUNT slots.
func biome_weights(x: float, z: float, h: float, out: PackedFloat32Array) -> void:
	biome_weights_s(x, z, h, slope(x, z), out)


## Variante que recebe o declive já calculado — os chunks têm a grelha de alturas
## à mão e assim poupam 4 chamadas a `height()` por vértice.
func biome_weights_s(x: float, z: float, h: float, sl: float, out: PackedFloat32Array) -> void:
	var cl := climate(x, z)
	var above := h - SEA_LEVEL
	# a altitude arrefece (≈ -0.0030 por metro): cumes frios, vales quentes
	var t := clampf(cl.x - above * 0.0030, 0.0, 1.0)
	var m := cl.y
	var grove_n := n_grove.get_noise_2d(x, z)
	var tint_n := n_tint.get_noise_2d(x, z)
	var flat := 1.0 - _smooth(0.40, 0.70, sl)   # biomas de superfície só em terreno plano
	# proximidade de rio: margens húmidas → lama
	var river_prox := 0.0
	var coords := _starter_coords(x, z)
	var coast := _coastline(coords.y)
	if _river_activity(coords.x, coast) > 0.05:
		river_prox = (1.0 - _smooth(7.0, 24.0,
			absf(coords.y - _river_center(coords.x)))) * (1.0 - _smooth(3.0, 9.0, above))

	for i in BIOME_COUNT:
		out[i] = 0.0

	# altitude / declive
	var snowline := Db.terrain_num("snowline_base", 150.0) - cl.x * Db.terrain_num("snowline_temp_scale", 70.0)
	out[B_SAND] = 1.0 - _smooth(-0.3, 1.8, above)
	out[B_SNOW] = _smooth(snowline, snowline + 36.0, h) * 1.4 + _smooth(0.20, 0.04, t) * 0.8
	out[B_ROCK] = _smooth(0.34, 0.66, sl) * 1.5 + _smooth(Db.terrain_num("rock_altitude_min", 85.0), Db.terrain_num("rock_altitude_max", 135.0), h) * 0.55

	# clima (Whittaker)
	var lowland := 1.0 - _smooth(1.0, 3.0, above)
	out[B_MARSH] = _smooth(0.62, 0.82, m) * lowland * (1.0 - _smooth(0.55, 0.75, t)) * 1.7
	out[B_MUD] = river_prox * _smooth(0.40, 0.62, m) * (1.0 - _smooth(3.0, 9.0, above)) * (0.7 + 0.5 * tint_n) * 1.9
	out[B_DESERT] = _smooth(0.60, 0.80, t) * (1.0 - _smooth(0.34, 0.54, m)) * flat * 1.7
	out[B_BADLANDS] = _smooth(0.66, 0.86, t) * (1.0 - _smooth(0.22, 0.42, m)) \
		* _smooth(0.52, 0.66, n_mesa.get_noise_2d(x, z) * 0.5 + 0.5 + above * 0.004) * 1.9
	out[B_SAVANNA] = _smooth(0.52, 0.72, t) * _smooth(0.30, 0.48, m) * (1.0 - _smooth(0.52, 0.70, m)) * flat * 1.5
	out[B_DIRT] = (1.0 - _smooth(0.40, 0.60, m)) * _smooth(0.36, 0.56, t) * _smooth(0.15, 0.45, tint_n) * flat * 1.1
	out[B_GROVE] = _smooth(0.20, 0.42, grove_n) * _smooth(0.48, 0.68, m) * (1.0 - _smooth(30.0, 90.0, h)) * 1.6
	out[B_FOREST] = _smooth(0.56, 0.76, m) * _smooth(0.28, 0.56, t) * (1.0 - _smooth(60.0, 115.0, h)) * 1.8
	out[B_MEADOW] = 1.0 - 0.72 * _smooth(0.58, 0.84, t) * (1.0 - _smooth(0.30, 0.52, m))

	var total := 0.0
	for i in BIOME_COUNT:
		out[i] = maxf(out[i], 0.0)
		total += out[i]
	if total <= 0.0:
		out[B_MEADOW] = 1.0
		return
	var inv := 1.0 / total
	for i in BIOME_COUNT:
		out[i] *= inv


## Cor do terreno num ponto (para vertex color).
func ground_color(x: float, z: float, h: float, buf: PackedFloat32Array) -> Color:
	return ground_color_s(x, z, h, slope(x, z), buf)


func ground_color_s(x: float, z: float, h: float, sl: float, buf: PackedFloat32Array) -> Color:
	biome_weights_s(x, z, h, sl, buf)
	var c := Color(0, 0, 0)
	for i in BIOME_COUNT:
		if buf[i] <= 0.001:
			continue
		c += Db.biome_color(i, BIOME_COLOR[i]) * buf[i]
	# variação local para não parecer plástico
	var t := n_tint.get_noise_2d(x, z) * 0.07
	var under := clampf(h - SEA_LEVEL, -2.0, 2.0) * 0.02
	c = c.darkened(maxf(0.0, -t - under * 0.5)).lightened(maxf(0.0, t + under * 0.5))
	# mergulhado: mais escuro e azulado
	if h < SEA_LEVEL:
		c = c.lerp(Color(0.16, 0.28, 0.26), clampf((SEA_LEVEL - h) * 0.12, 0.0, 0.65))
	return c


## Bioma dominante (para decidir árvores/relva/áudio).
func dominant(x: float, z: float, h: float) -> int:
	return dominant_s(x, z, h, slope(x, z))


func dominant_s(x: float, z: float, h: float, sl: float) -> int:
	var buf := PackedFloat32Array()
	buf.resize(BIOME_COUNT)
	biome_weights_s(x, z, h, sl, buf)
	var best := B_MEADOW
	var bv := -1.0
	for i in BIOME_COUNT:
		if buf[i] > bv:
			bv = buf[i]
			best = i
	return best


# ══════════════════════════════════════════════════════════════════════════
#  UTILITÁRIOS
# ══════════════════════════════════════════════════════════════════════════
func _smooth(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func is_water(x: float, z: float) -> bool:
	return water_surface_height(x, z) > -99999.0


## Sítio onde é seguro pôr o jogador (fora de água, inclinação aceitável).
func find_spawn(center: Vector2, radius: float = 60.0) -> Vector3:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ 0x5EED
	for i in 400:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * radius
		var x := center.x + cos(a) * r
		var z := center.y + sin(a) * r
		if path_distance(x, z) > 3.0 and slope(x, z) < 0.4 and not is_water(x, z):
			return Vector3(x, height(x, z), z)
	return Vector3(center.x, height(center.x, center.y), center.y)
