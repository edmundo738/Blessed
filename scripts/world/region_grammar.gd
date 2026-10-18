class_name RegionGrammar
extends RefCounted
## Gramática macro de habitats. WFC organiza os vizinhos; clima, altitude,
## água e declive continuam a decidir se uma espécie pode existir num ponto.
## Os módulos só dão ênfase regional aos biomas já permitidos pelo terreno.

const SIZE := 24
const CELL_SIZE := 224.0
const TYPE_COUNT := 8
const HYDRO_SAMPLE_RADIUS := 0.20
const NEUTRAL := 0
const MEADOW := 1
const FOREST := 2
const WETLAND := 3
const SAVANNA := 4
const DESERT := 5
const BADLANDS := 6
const HIGHLAND := 7
const TYPE_NAMES := ["neutral", "meadow", "forest", "wetland", "savanna",
	"desert", "badlands", "highland"]

var seed_value := 0
var origin := Vector2.ZERO
var tiles := PackedInt32Array()
var solved := false
var solve_attempts := 0
var contradiction_count := 0


func build(terrain: Terrain, anchor: Vector2) -> void:
	seed_value = terrain.seed_value
	# O mapa tem número par de células: alinhar a célula central ao ponto da
	# aldeia evita deslocar o prado fixo meia célula para nordeste.
	var half_extent := (float(SIZE) * 0.5 + 0.5) * CELL_SIZE
	origin = anchor - Vector2.ONE * half_extent
	var solver := WFC2D.new()
	var adjacency := _adjacency()
	var base_weights := PackedFloat32Array([0.40, 1.15, 1.0, 0.55, 0.65, 0.48, 0.42, 0.65])
	var suitability := PackedFloat32Array()
	suitability.resize(SIZE * SIZE * TYPE_COUNT)
	var fixed: Dictionary = {}

	for z in SIZE:
		for x in SIZE:
			var cell := z * SIZE + x
			var p := origin + Vector2((float(x) + 0.5) * CELL_SIZE,
				(float(z) + 0.5) * CELL_SIZE)
			var h := terrain._land(p.x, p.y, false)
			var climate := terrain.climate(p.x, p.y)
			var hot := _smooth(0.48, 0.78, climate.x)
			var dry := 1.0 - _smooth(0.32, 0.62, climate.y)
			var wet := _smooth(0.40, 0.76, climate.y)
			var lowland := 1.0 - _smooth(12.0, 70.0, h)
			var upland := _smooth(38.0, 150.0, h)
			var mesa := _smooth(0.42, 0.72,
				terrain.n_mesa.get_noise_2d(p.x, p.y) * 0.5 + 0.5)
			# O WFC lê a rede hidrológica já resolvida. Uma pequena grelha interna
			# encontra vales e zonas alagáveis mesmo quando o centro do módulo fica
			# longe do eixo do rio; a gramática não altera a própria água.
			var hydro := 0.0
			if terrain.water != null:
				for sy in range(-2, 3):
					for sx in range(-2, 3):
						var sample_x := p.x + float(sx) * CELL_SIZE * HYDRO_SAMPLE_RADIUS
						var sample_z := p.y + float(sy) * CELL_SIZE * HYDRO_SAMPLE_RADIUS
						hydro = maxf(hydro, _smooth(0.12, 1.05,
							terrain.water.carve(sample_x, sample_z)))
						if terrain.water.is_marsh(sample_x, sample_z):
							hydro = 1.0
			var values := PackedFloat32Array([
				0.24,
				0.48 + 0.42 * (1.0 - hot) + 0.14 * wet,
				0.12 + wet * (0.55 + 0.40 * (1.0 - hot)) * (1.0 - upland * 0.45),
				0.08 + wet * lowland * (0.48 + (1.0 - hot) * 0.36) + hydro * 0.92,
				(0.08 + hot * (0.24 + climate.y * 0.40) * (1.0 - dry * 0.22)) * (1.0 - hydro * 0.62),
				(0.05 + hot * dry * 0.72) * (1.0 - hydro * 0.78),
				(0.04 + hot * dry * mesa * 0.68) * (1.0 - hydro * 0.82),
				0.10 + upland * (0.42 + 0.28 * (1.0 - climate.x)),
			])
			# O mar e o chão quase ao nível da costa não são uma escolha de WFC.
			# A costa é decidida pela geografia e hidrologia; a gramática não pode
			# converter um lugar submerso em prado ou deserto.
			if h <= Terrain.SEA_LEVEL + 1.0:
				values.fill(0.001)
				values[NEUTRAL] = 1.0
			for tile in TYPE_COUNT:
				suitability[cell * TYPE_COUNT + tile] = values[tile]

			# Uma margem neutra de dois módulos evita que a solução pareça recortada
			# no limite do mapa WFC. A aldeia mantém o prado de arranque.
			if x < 2 or z < 2 or x >= SIZE - 2 or z >= SIZE - 2:
				fixed[cell] = NEUTRAL
	var center := Vector2i(SIZE / 2, SIZE / 2)
	fixed[center.y * SIZE + center.x] = MEADOW

	var result := solver.solve(SIZE, SIZE, adjacency, base_weights,
		seed_value ^ 0x6A09E667, suitability, fixed, NEUTRAL)
	tiles = result["tiles"]
	solved = bool(result["success"])
	solve_attempts = int(result["attempts"])
	contradiction_count = int(result["contradictions"])
	if not solved:
		push_warning("World WFC usou fallback neutro após %d contradições" % contradiction_count)
	else:
		print("WORLD WFC habitats=%dx%d solved attempts=%d contradictions=%d" % [
			SIZE, SIZE, solve_attempts, contradiction_count])


## Preenche uma mistura suave dos módulos em torno dos centros das células.
## A deformação é só do campo de influência; alturas e drenagem não são warpeadas.
func sample_into(x: float, z: float, out: PackedFloat32Array) -> void:
	if out.size() != TYPE_COUNT:
		out.resize(TYPE_COUNT)
	for i in TYPE_COUNT:
		out[i] = 0.0
	if tiles.size() != SIZE * SIZE:
		out[NEUTRAL] = 1.0
		return
	var wx := x + sin((z + float(seed_value) * 13.7) * 0.0028) * 18.0
	var wz := z + sin((x - float(seed_value) * 9.1) * 0.0024) * 18.0
	var gx := (wx - origin.x) / CELL_SIZE - 0.5
	var gz := (wz - origin.y) / CELL_SIZE - 0.5
	if gx < 0.0 or gz < 0.0 or gx > SIZE - 1 or gz > SIZE - 1:
		out[NEUTRAL] = 1.0
		return
	var ix := clampi(int(floor(gx)), 0, SIZE - 2)
	var iz := clampi(int(floor(gz)), 0, SIZE - 2)
	var tx := _smooth(0.0, 1.0, gx - float(ix))
	var tz := _smooth(0.0, 1.0, gz - float(iz))
	var indices := [iz * SIZE + ix, iz * SIZE + ix + 1,
		(iz + 1) * SIZE + ix, (iz + 1) * SIZE + ix + 1]
	var factors := [(1.0 - tx) * (1.0 - tz), tx * (1.0 - tz),
		(1.0 - tx) * tz, tx * tz]
	for i in 4:
		var tile := tiles[indices[i]]
		out[tile] += factors[i]
	# Um limiar subtil no campo de influência evita uma fronteira demasiado
	# regular sem transformar as regiões em manchas independentes de ruído.
	var edge := minf(minf(gx, gz), minf(SIZE - 1.0 - gx, SIZE - 1.0 - gz))
	var interior := _smooth(0.5, 2.0, edge)
	for tile in TYPE_COUNT:
		if tile != NEUTRAL:
			out[tile] *= interior
	out[NEUTRAL] = 1.0 - interior + out[NEUTRAL] * interior


func dominant_at(x: float, z: float) -> String:
	var weights := PackedFloat32Array()
	sample_into(x, z, weights)
	var best := NEUTRAL
	for i in TYPE_COUNT:
		if weights[i] > weights[best]:
			best = i
	return TYPE_NAMES[best]


func _adjacency() -> PackedInt64Array:
	var allowed := PackedInt64Array()
	allowed.resize(TYPE_COUNT * 4)
	var links := {
		NEUTRAL: [MEADOW, FOREST, WETLAND, SAVANNA, DESERT, BADLANDS, HIGHLAND],
		MEADOW: [FOREST, WETLAND, SAVANNA, HIGHLAND],
		FOREST: [WETLAND, HIGHLAND],
		WETLAND: [],
		SAVANNA: [DESERT, BADLANDS],
		DESERT: [BADLANDS],
		BADLANDS: [HIGHLAND],
		HIGHLAND: [],
	}
	for a in TYPE_COUNT:
		var mask := 1 << a
		for b in links[a]:
			mask |= 1 << int(b)
		for b in TYPE_COUNT:
			if int(links[b].find(a)) >= 0:
				mask |= 1 << b
		for direction in 4:
			allowed[a * 4 + direction] = mask
	return allowed


func _smooth(a: float, b: float, value: float) -> float:
	var t := clampf((value - a) / maxf(b - a, 0.0001), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
