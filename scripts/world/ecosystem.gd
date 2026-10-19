class_name Ecosystem
extends RefCounted
## Ecosystem — decide abundância e manchas ecológicas em coordenadas globais.
## O mesmo ponto dá o mesmo resultado em qualquer chunk, sem costuras.

var seed_value := 1
var _cover_fields: Dictionary = {}
var _species_fields: Dictionary = {}
var _cfg: Dictionary = {}


func _init(p_seed: int = 1) -> void:
	seed_value = p_seed
	var value: Variant = Db.terrain_cfg.get("ecology", {})
	_cfg = value if typeof(value) == TYPE_DICTIONARY else {}
	_cover_fields["tree"] = _noise("tree_frequency", 0.009, 4, p_seed + 801)
	_cover_fields["rock"] = _noise("rock_frequency", 0.013, 3, p_seed + 802)
	_cover_fields["plant"] = _noise("plant_frequency", 0.018, 3, p_seed + 803)

	# Campos próprios por espécie criam povoamentos locais sem espalhamento
	# independente por chunk (por exemplo, manchas de pinheiros e de bétulas).
	for id in ["oak", "birch", "sakura", "pine", "willow", "bush", "mushroom",
		"fern", "flowers", "clover", "reed",
		"rock_0", "rock_1", "rock_2", "flint_node"]:
		_species_fields[id] = _noise("species_frequency", 0.0055, 3,
			p_seed ^ (str(id).hash() & 0x7fffffff))


func _noise(key: String, fallback: float, octaves: int, noise_seed: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = noise_seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.frequency = float(_cfg.get(key, fallback))
	n.fractal_octaves = octaves
	n.fractal_gain = 0.5
	n.fractal_lacunarity = 2.0
	return n


## Instâncias por 100 m², interpoladas pelos pesos dos biomas.
func density_per_100m2(kind: String, weights: PackedFloat32Array,
		x: float, z: float) -> float:
	var base := 0.0
	var count := mini(weights.size(), Terrain.BIOME_COUNT)
	for i in count:
		base += Db.biome_density(i, kind, _default_density(kind, i)) * weights[i]
	return maxf(0.0, base * cover_multiplier(kind, x, z))


## Escolhe espécie somando adequação do habitat, peso autoral e um campo de
## povoamento. Os biomas continuam graduais; as espécies não mudam numa linha.
func pick_species(pool: Dictionary, weights: PackedFloat32Array, r: float,
		x: float, z: float, geology_sample: Dictionary = {}) -> String:
	var ids: Array[String] = []
	var weighted: Array[float] = []
	var total := 0.0
	var formation := str(geology_sample.get("formation", ""))
	var ore := float(geology_sample.get("ore_potential", 0.5))
	for key in pool:
		var id := str(key)
		var s: SpeciesKit.Species = pool[key]
		var habitat := 0.0
		for biome in s.biomes:
			if biome >= 0 and biome < weights.size():
				habitat += weights[biome]
		if habitat <= 0.001:
			continue
		var w := s.weight * habitat
		if not s.geology_affinity.is_empty() and not formation.is_empty():
			w *= float(s.geology_affinity.get(formation, 0.08))
		if id == "flint_node":
			w *= lerpf(0.35, 1.85, clampf(ore, 0.0, 1.0))
		var patch: FastNoiseLite = _species_fields.get(id) as FastNoiseLite
		if patch != null:
			var field := patch.get_noise_2d(x, z) * 0.5 + 0.5
			w *= lerpf(0.42, 1.58, clampf(field, 0.0, 1.0))
		if w <= 0.0:
			continue
		ids.append(id)
		weighted.append(w)
		total += w
	if ids.is_empty() or total <= 0.0:
		return ""
	var choice := clampf(r, 0.0, 0.999999) * total
	for i in ids.size():
		choice -= weighted[i]
		if choice <= 0.0:
			return ids[i]
	return ids.back()


func cover_multiplier(kind: String, x: float, z: float) -> float:
	var field: FastNoiseLite = _cover_fields.get(kind) as FastNoiseLite
	if field == null:
		return 1.0
	# Multiplicador médio próximo de 1: concentra crescimento em manchas e abre
	# clareiras, sem aumentar a contagem total de forma explosiva.
	return clampf(1.0 + field.get_noise_2d(x, z) * 0.82, 0.18, 1.82)


func _default_density(kind: String, biome: int) -> float:
	if kind == "tree":
		return SpeciesKit.tree_density(biome)
	if kind == "grass":
		return SpeciesKit.grass_density(biome)
	if kind == "rock":
		return 0.30
	if kind == "plant":
		return 0.55
	return 0.0
