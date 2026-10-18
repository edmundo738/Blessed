class_name Geology
extends RefCounted
## Geology — províncias rochosas contínuas que dão causa ao relevo, à água e
## aos recursos. Não cria cavernas por si só; fornece os campos determinísticos
## que uma futura CavePatch usa para escolher locais plausíveis.

const FORMATIONS := ["alluvium", "sandstone", "limestone", "granite", "basalt"]
const FORMATION_COLORS := [
	Color(0.53, 0.42, 0.29),  # aluvião
	Color(0.69, 0.40, 0.23),  # arenito
	Color(0.70, 0.65, 0.52),  # calcário
	Color(0.43, 0.47, 0.50),  # granito
	Color(0.29, 0.33, 0.38),  # basalto
]
const HARDNESS := [0.18, 0.38, 0.52, 0.91, 0.79]
const PERMEABILITY := [0.82, 0.53, 0.86, 0.22, 0.37]
const KARST := [0.02, 0.10, 0.92, 0.03, 0.02]
const ORE := [0.08, 0.30, 0.40, 0.78, 0.63]

var seed_value := 1
var _province: FastNoiseLite
var _fracture: FastNoiseLite
var _strata: FastNoiseLite
var _cfg: Dictionary = {}


func _init(p_seed: int = 1) -> void:
	seed_value = p_seed
	var value: Variant = Db.terrain_cfg.get("geology", {})
	_cfg = value if typeof(value) == TYPE_DICTIONARY else {}
	_province = _noise("province_frequency", 0.00052, 4, p_seed + 701)
	_fracture = _noise("fracture_frequency", 0.0038, 3, p_seed + 702)
	_fracture.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_strata = _noise("strata_frequency", 0.010, 2, p_seed + 703)


func _noise(key: String, fallback: float, octaves: int, noise_seed: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = noise_seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.frequency = float(_cfg.get(key, fallback))
	n.fractal_octaves = octaves
	n.fractal_gain = 0.5
	n.fractal_lacunarity = 2.0
	return n


func province_value(x: float, z: float) -> float:
	return clampf(_province.get_noise_2d(x, z) * 0.5 + 0.5, 0.0, 1.0)


func formation_index_at(x: float, z: float) -> int:
	var p := province_value(x, z)
	if p < 0.20: return 0
	if p < 0.40: return 1
	if p < 0.62: return 2
	if p < 0.83: return 3
	return 4


func formation_at(x: float, z: float) -> String:
	return FORMATIONS[formation_index_at(x, z)]


func hardness_at(x: float, z: float) -> float:
	return _palette(province_value(x, z), HARDNESS)


func permeability_at(x: float, z: float) -> float:
	var p := province_value(x, z)
	var fault := fracture_at(x, z)
	return clampf(_palette(p, PERMEABILITY) + fault * 0.10, 0.02, 0.98)


func karst_at(x: float, z: float) -> float:
	return _palette(province_value(x, z), KARST) * (0.45 + fracture_at(x, z) * 0.55)


func ore_potential_at(x: float, z: float) -> float:
	return clampf(_palette(province_value(x, z), ORE) * (0.72 + fracture_at(x, z) * 0.28), 0.0, 1.0)


func fracture_at(x: float, z: float) -> float:
	var ridged := 1.0 - absf(_fracture.get_noise_2d(x, z))
	return clampf(pow(ridged, 1.6), 0.0, 1.0)


func strata_at(x: float, z: float) -> float:
	return clampf(_strata.get_noise_2d(x, z) * 0.5 + 0.5, 0.0, 1.0)


func exposure_at(x: float, z: float, height: float, slope: float) -> float:
	var altitude := _smooth(28.0, 115.0, height)
	var steepness := _smooth(0.20, 0.68, slope)
	var hard_rock := _smooth(0.38, 0.82, hardness_at(x, z))
	return clampf(steepness * 0.52 + altitude * 0.23 + hard_rock * 0.25, 0.0, 1.0)


## Potencial de caverna, não uma caverna já escavada. Favorece calcário e
## fraturas; a geometria final pertence ao sistema de patches volumétricos.
func cave_potential_at(x: float, z: float) -> float:
	return clampf(karst_at(x, z) * (0.35 + fracture_at(x, z) * 0.65), 0.0, 1.0)


func surface_color(x: float, z: float) -> Color:
	var p := province_value(x, z)
	var section := p * float(FORMATION_COLORS.size() - 1)
	var index := mini(int(floorf(section)), FORMATION_COLORS.size() - 2)
	var t := section - float(index)
	t = t * t * (3.0 - 2.0 * t)
	return FORMATION_COLORS[index].lerp(FORMATION_COLORS[index + 1], t)


func sample(x: float, z: float) -> Dictionary:
	var formation_index := formation_index_at(x, z)
	return {
		"formation": FORMATIONS[formation_index],
		"formation_index": formation_index,
		"hardness": hardness_at(x, z),
		"permeability": permeability_at(x, z),
		"fracture": fracture_at(x, z),
		"karst": karst_at(x, z),
		"ore_potential": ore_potential_at(x, z),
		"cave_potential": cave_potential_at(x, z),
		"strata": strata_at(x, z),
	}


func _palette(p: float, values: Array) -> float:
	var pos := clampf(p, 0.0, 1.0) * float(values.size() - 1)
	var i := mini(int(floorf(pos)), values.size() - 2)
	var t := pos - float(i)
	t = t * t * (3.0 - 2.0 * t)
	return lerpf(float(values[i]), float(values[i + 1]), t)


func _smooth(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
