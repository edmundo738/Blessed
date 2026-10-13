class_name Terrain
extends RefCounted
## Terrain — o mundo como função pura.
##
## Regra: `height(x, z)` e `biome_weights(x, z)` são deterministas e não guardam
## estado. Quem quer que pergunte — o chunk, a relva, uma árvore, a água, o
## save — recebe a mesma resposta. É isto que permite gerar à volta do jogador e
## apagar atrás dele sem costuras.
##
## Ordem das camadas (baixo → cima):
##   continente (fbm)  →  montanhas (ridgido, com máscara)  →  detalhe
##   →  rio (curva de nível de um ruído)  →  caminho (achatado)  →  aldeia

const SEA_LEVEL := 0.0
const RIVER_WIDTH := 0.038
const RIVER_BED := -3.2
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
const BIOME_COUNT := 11

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


func _init(p_seed: int = 1) -> void:
	seed_value = p_seed
	n_continent = _noise(FastNoiseLite.TYPE_SIMPLEX, 0.0016, 5, 0.5, 2.0, p_seed + 1)
	n_detail = _noise(FastNoiseLite.TYPE_PERLIN, 0.021, 3, 0.5, 2.0, p_seed + 2)
	n_mountain = _noise(FastNoiseLite.TYPE_SIMPLEX, 0.0035, 5, 0.5, 2.2, p_seed + 3)
	n_mountain.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	n_mask = _noise(FastNoiseLite.TYPE_SIMPLEX, 0.0011, 3, 0.5, 2.0, p_seed + 4)
	n_moist = _noise(FastNoiseLite.TYPE_SIMPLEX, 0.0022, 3, 0.5, 2.0, p_seed + 5)
	n_temp = _noise(FastNoiseLite.TYPE_SIMPLEX, 0.0013, 3, 0.5, 2.0, p_seed + 6)
	n_grove = _noise(FastNoiseLite.TYPE_SIMPLEX, 0.0062, 2, 0.5, 2.0, p_seed + 7)
	n_river = _noise(FastNoiseLite.TYPE_SIMPLEX, 0.0026, 4, 0.5, 2.4, p_seed + 8)
	n_tint = _noise(FastNoiseLite.TYPE_PERLIN, 0.09, 2, 0.5, 2.0, p_seed + 9)
	n_warp = _noise(FastNoiseLite.TYPE_SIMPLEX, 0.0009, 2, 0.5, 2.0, p_seed + 10)
	n_erosion = _noise(FastNoiseLite.TYPE_SIMPLEX, 0.0019, 3, 0.5, 2.0, p_seed + 11)


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
# ══════════════════════════════════════════════════════════════════════════
func height(x: float, z: float) -> float:
	var h := _land(x, z, true)
	# rio: a curva de nível zero de um ruído forma uma rede de vales
	var rv := absf(n_river.get_noise_2d(x, z))
	if rv < RIVER_WIDTH:
		var t := 1.0 - _smooth(0.0, RIVER_WIDTH, rv)
		h = lerpf(h, minf(h, RIVER_BED), t * 0.94)
	# caminho
	var d := path_distance(x, z)
	if d < PATH_SOFT:
		var w := 1.0 - _smooth(PATH_HALF_WIDTH, PATH_SOFT, d)
		h = lerpf(h, path_height(x), w * 0.92)
	# aldeia: clareira plana
	var vd := village_distance(x, z)
	if vd < VILLAGE_RADIUS * 1.8:
		var w := 1.0 - _smooth(VILLAGE_RADIUS, VILLAGE_RADIUS * 1.8, vd)
		h = lerpf(h, village_height(), w * 0.9)
	return h


## Terreno "cru", sem rio/caminho/aldeia.
func _land(x: float, z: float, detail: bool = true) -> float:
	# DOMAIN WARPING: desloca as coordenadas com um ruído antes de amostrar =>
	# formas orgânicas e menos repetitivas (técnica dos terrenos AAA).
	var wx := n_warp.get_noise_2d(x, z) * 70.0
	var wz := n_warp.get_noise_2d(x + 311.7, z - 177.3) * 70.0
	var c := n_continent.get_noise_2d(x + wx, z + wz)
	# média positiva: mundo maioritariamente acima do mar, com lagos nos vales.
	var h := c * 24.0 + 6.0
	# EROSION: 0 = escarpado/montanhoso, 1 = plano/suave (estilo Minecraft 1.18).
	var er := clampf(n_erosion.get_noise_2d(x, z) * 0.5 + 0.5, 0.0, 1.0)
	var m := clampf((n_mask.get_noise_2d(x + wx, z + wz) + 0.18) * 1.5, 0.0, 1.0)
	var ridge := clampf(n_mountain.get_noise_2d(x + wx, z + wz), 0.0, 1.0)
	# montanhas mais dramáticas onde a erosão é baixa
	var mount_amp := 118.0 * (1.0 - er * 0.72)
	h += pow(ridge, 2.2) * mount_amp * m * m
	# onde a erosão é alta, puxa para colinas suaves
	h = lerpf(h, c * 14.0 + 5.0, er * 0.35)
	if detail:
		h += n_detail.get_noise_2d(x, z) * (1.2 + (1.0 - er) * 1.6)
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
	var moist := n_moist.get_noise_2d(x, z)
	var temp := n_temp.get_noise_2d(x, z) - h * 0.0055
	var above := h - SEA_LEVEL
	# clima normalizado 0..1 — t: 0 frio, 1 quente; m: 0 seco, 1 húmido
	var t := clampf(temp * 1.3 + 0.5, 0.0, 1.0)
	var m := clampf(moist * 1.3 + 0.5, 0.0, 1.0)
	var grove_n := n_grove.get_noise_2d(x, z)
	var tint_n := n_tint.get_noise_2d(x, z)
	var flat := 1.0 - _smooth(0.40, 0.70, sl)   # biomas de superfície só em terreno plano

	for i in BIOME_COUNT:
		out[i] = 0.0

	# altitude / declive (independentes do clima)
	out[B_SAND] = 1.0 - _smooth(-0.3, 1.8, above)
	out[B_SNOW] = _smooth(28.0, 46.0, h) * 1.3 + _smooth(0.34, 0.10, t) * 0.7
	out[B_ROCK] = _smooth(0.34, 0.66, sl) * 1.5 + _smooth(22.0, 34.0, h) * 0.5

	# clima (Whittaker): quente+seco => deserto/badlands; quente+médio => savana;
	# húmido => floresta/pântano; temperado => prado; seco+temperado => terra nua.
	out[B_MARSH] = _smooth(0.62, 0.82, m) * (1.0 - _smooth(1.0, 3.0, above)) * 1.7
	out[B_DESERT] = _smooth(0.60, 0.80, t) * (1.0 - _smooth(0.34, 0.54, m)) * flat * 1.7
	out[B_BADLANDS] = _smooth(0.68, 0.88, t) * (1.0 - _smooth(0.20, 0.40, m)) \
		* _smooth(0.10, 0.40, grove_n) * flat * 1.6
	out[B_SAVANNA] = _smooth(0.52, 0.72, t) * _smooth(0.30, 0.48, m) * (1.0 - _smooth(0.52, 0.70, m)) * flat * 1.5
	out[B_DIRT] = (1.0 - _smooth(0.40, 0.60, m)) * _smooth(0.36, 0.56, t) * _smooth(0.15, 0.45, tint_n) * flat * 1.1
	out[B_GROVE] = _smooth(0.20, 0.42, grove_n) * _smooth(0.48, 0.68, m) * (1.0 - _smooth(6.0, 22.0, h)) * 1.6
	out[B_FOREST] = _smooth(0.56, 0.76, m) * _smooth(0.28, 0.56, t) * (1.0 - _smooth(14.0, 30.0, h)) * 1.8
	# prado: base, mas suprimido em clima quente+seco (para o deserto/savana lerem bem)
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
		c += BIOME_COLOR[i] * buf[i]
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
	return height(x, z) < SEA_LEVEL - 0.15


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
