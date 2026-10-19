class_name Chunk
extends Node3D
## Chunk — um quadrado de mundo gerado, usado e devolvido.
##
## Um chunk tem: malha de terreno + colisão (só nos níveis perto) + MultiMesh por
## espécie (árvores, rochas, plantas) + um registo dos nós colhíveis.
## Nada aqui é guardado entre chunks: o mundo é sempre rederivado do Terrain.

const SIZE := 48.0
## Altura da saia. Era 5.0: uma parede de 5 m à volta de cada chunk, visível
## como uma grelha de muros. 1.2 m chega para tapar as costuras entre LODs e
## lê-se como sombra de contacto, não como arquitectura.
const SKIRT := 1.2
const RES := [48, 24, 12, 6]       # detalhe cai por faixa; o anel distante só desenha terreno
const TREE_CELL := 3.0
const ROCK_CELL := 6.0
const WATER_LOD_RES := [24, 24, 16, 12] # rios precisam de malha fina mesmo a média distância
## Níveis de relva (shells). A altura efetiva vem de Materials.GRASS_HEIGHT; o
## número de níveis decide o espaçamento vertical da pilha: com 0,30 m e 9
## níveis, cada corte fica a ~3,3 cm. Os anéis distantes usam menos níveis porque
## a densidade já caiu e o corte fino não se lê, mas a altura é a mesma em todos
## (a relva não muda de tamanho ao atravessar a fronteira de um chunk).
const GRASS_SHELL_LAYERS := [9, 7, 5, 5]

var cx := 0
var cz := 0
var lod := 0
var built := false

var terrain: Terrain
var species: SpeciesKit
var ecology: Ecosystem
var mats: Materials
var water_root: Node3D

## Nós colhíveis deste chunk: {pos, kind, species, hp, node}
var world: Node = null                # definido pelo World; usado para respawn
var harvest_nodes: Array = []

var _mesh_inst: MeshInstance3D
var _grass_shell_inst: MeshInstance3D
var _grass_cards_inst: MultiMeshInstance3D
## Espécies de que já se avisou faltar geometria (o aviso é uma vez por espécie,
## não uma vez por chunk × LOD).
static var _sem_geometria: Dictionary = {}
var _water_inst: MeshInstance3D
var _body: StaticBody3D
var _decor: Array = []
var _colliders: Array = []
var _buckets: Dictionary = {}


func origin() -> Vector2:
	return Vector2(cx * SIZE, cz * SIZE)


func center() -> Vector2:
	return Vector2(cx * SIZE + SIZE * 0.5, cz * SIZE + SIZE * 0.5)


func distance_to(p: Vector3) -> float:
	var c := center()
	return Vector2(p.x - c.x, p.z - c.y).length()


func build(with_collision: bool) -> void:
	if built:
		return
	built = true
	var o := origin()
	_build_ground(o, with_collision)
	_build_water(o)
	if lod < 3:
		_scatter(o, with_collision)


# ══════════════════════════════════════════════════════════════════════════
#  TERRENO
# ══════════════════════════════════════════════════════════════════════════
func _build_ground(o: Vector2, with_collision: bool) -> void:
	var res: int = RES[clampi(lod, 0, RES.size() - 1)]
	var step := SIZE / float(res)
	var n := res + 1
	var heights := PackedFloat32Array()
	heights.resize(n * n)
	var voxel_ground := world != null and bool(world.get("use_voxel_terrain"))

	# 1) alturas (a única parte cara)
	for j in n:
		for i in n:
			var x := o.x + i * step
			var z := o.y + j * step
			heights[j * n + i] = terrain.height(x, z)

	# 2) malha com cor de vértice por bioma
	var st: SurfaceTool
	if not voxel_ground:
		st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var buf := PackedFloat32Array()
	buf.resize(Terrain.BIOME_COUNT)
	var region_buf := PackedFloat32Array()
	region_buf.resize(RegionGrammar.TYPE_COUNT)
	var normals := PackedVector3Array()
	normals.resize(n * n)
	var grass_cover := PackedFloat32Array()
	grass_cover.resize(n * n)
	var grass_dryness := PackedFloat32Array()
	grass_dryness.resize(n * n)
	# Tinta da relva por ponto: é o que dá às lâminas a cor do bioma onde crescem
	# (ver Terrain.grass_tint_of). O chão e a relva ficam da mesma família.
	var grass_tint := PackedColorArray()
	grass_tint.resize(n * n)
	# normais a partir da grelha (barato e sem costuras)
	for j in n:
		for i in n:
			var hl := heights[j * n + maxi(i - 1, 0)]
			var hr := heights[j * n + mini(i + 1, n - 1)]
			var hd := heights[maxi(j - 1, 0) * n + i]
			var hu := heights[mini(j + 1, n - 1) * n + i]
			normals[j * n + i] = Vector3(hl - hr, 2.0 * step, hd - hu).normalized()

	for j in n:
		for i in n:
			var x := o.x + i * step
			var z := o.y + j * step
			var h := heights[j * n + i]
			var sl := clampf(Vector2(normals[j * n + i].x, normals[j * n + i].z).length()
				/ maxf(normals[j * n + i].y, 0.001) * 0.55, 0.0, 1.0)
			if not voxel_ground:
				st.set_normal(normals[j * n + i])
			var gc := terrain.ground_color_s(x, z, h, sl, buf, region_buf)
			grass_cover[j * n + i] = terrain.grass_coverage_s(h, sl, buf)
			grass_dryness[j * n + i] = terrain.grass_dryness(buf)
			grass_tint[j * n + i] = Terrain.grass_tint_of(gc, grass_dryness[j * n + i])
			# classes de material para o shader do terreno (ver toon_terrain.gdshader)
			if not voxel_ground:
				gc.a = clampf(buf[Terrain.B_SNOW], 0.0, 1.0)
				st.set_color(gc)
				st.set_uv(Vector2(
					buf[Terrain.B_MEADOW] + buf[Terrain.B_FOREST] + buf[Terrain.B_GROVE]
						+ buf[Terrain.B_SAVANNA] * 0.8 + buf[Terrain.B_MARSH] * 0.6,
					buf[Terrain.B_DIRT] + buf[Terrain.B_MUD] + buf[Terrain.B_MARSH] * 0.4
						+ buf[Terrain.B_SAVANNA] * 0.2))
				st.set_uv2(Vector2(
					buf[Terrain.B_SAND] + buf[Terrain.B_DESERT],
					buf[Terrain.B_BADLANDS]))
				st.add_vertex(Vector3(x, h, z))

	if not voxel_ground:
		for j in res:
			for i in res:
				var a := j * n + i
				var b := j * n + i + 1
				var c := (j + 1) * n + i + 1
				var d := (j + 1) * n + i
				st.add_index(a); st.add_index(b); st.add_index(c)
				st.add_index(a); st.add_index(c); st.add_index(d)

	# 3) SEM SAIA.
	#    A saia (parede vertical à volta do chunk) foi removida. Medida com
	#    tools/render_shot.py (o rasterizador por software que dá olhos a este
	#    projecto): de qualquer ângulo baixo ou debaixo de água, a saia aparecia
	#    como uma franja de dentes cinzentos nos limites dos chunks — exactamente
	#    o "faixas verticais que acompanham o terreno" reportado. Apontá-la para
	#    fora ou para dentro só trocava o ângulo em que fazia lixo; a única forma
	#    de a franja desaparecer é não a desenhar. As costuras entre LODs ficam
	#    tapadas pelo próprio overlap das grelhas vizinhas (passo partilhado).

	if not voxel_ground:
		var mesh := st.commit()
		mesh.surface_set_material(0, mats.terrain)
		_mesh_inst = MeshInstance3D.new()
		_mesh_inst.mesh = mesh
		_mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_mesh_inst.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(_mesh_inst)
	if lod < 3:
		# O número de níveis cai com a distância; a altura do volume e a máscara
		# são as mesmas em todos os LODs, por isso não há salto na fronteira.
		_build_grass_shells(o, res, step, heights, normals, grass_cover,
			grass_dryness, grass_tint,
			GRASS_SHELL_LAYERS[clampi(lod, 0, GRASS_SHELL_LAYERS.size() - 1)])
	if lod == 0:
		_build_grass_cards(o, n, step, heights, normals, grass_cover, grass_dryness,
			grass_tint)

	if with_collision:
		_body = StaticBody3D.new()
		_body.position = Vector3(o.x + SIZE * 0.5, 0.0, o.y + SIZE * 0.5)
		_body.collision_layer = 1
		if not voxel_ground:
			var shape := HeightMapShape3D.new()
			shape.map_width = n
			shape.map_depth = n
			shape.map_data = heights
			var col := CollisionShape3D.new()
			col.shape = shape
			_body.add_child(col)
			_colliders.append(col)
		add_child(_body)


## Relva por níveis: o terreno é re-desenhado em fatias empilhadas, cada uma
## levantada 1/N da altura do volume ao longo da normal do chão. O shader corta
## cada fatia com o campo de alturas da máscara (ver shaders/grass_shells.gdshader) — a
## silhueta das lâminas nasce daí, não de geometria por lâmina.
##
## A grelha das fatias é metade da grelha do terreno: a máscara é avaliada por
## pixel, por isso a resolução da malha só precisa de acompanhar a ALTURA do
## chão, e metade da resolução custa um quarto dos vértices.
func _build_grass_shells(o: Vector2, terrain_res: int, step: float,
		heights: PackedFloat32Array, normals: PackedVector3Array,
		coverage: PackedFloat32Array, dryness: PackedFloat32Array,
		tint: PackedColorArray, layers: int) -> void:
	var res := maxi(terrain_res / 2, 8)
	var shell_step := SIZE / float(res)
	var n := res + 1
	var world_heights := PackedFloat32Array()
	world_heights.resize(n * n)
	var world_normals := PackedVector3Array()
	world_normals.resize(n * n)
	var world_cover := PackedFloat32Array()
	world_cover.resize(n * n)
	var world_dry := PackedFloat32Array()
	world_dry.resize(n * n)
	var world_tint := PackedColorArray()
	world_tint.resize(n * n)
	var grid := terrain_res + 1
	for j in n:
		for i in n:
			var x := o.x + i * shell_step
			var z := o.y + j * shell_step
			var gx := clampi(int(round(i * float(terrain_res) / float(res))), 0, terrain_res)
			var gz := clampi(int(round(j * float(terrain_res) / float(res))), 0, terrain_res)
			var idx := j * n + i
			var gidx := gz * grid + gx
			world_heights[idx] = heights[gidx]
			world_normals[idx] = normals[gidx]
			world_cover[idx] = coverage[gidx]
			world_dry[idx] = dryness[gidx]
			world_tint[idx] = tint[gidx]

	var height := Materials.GRASS_HEIGHT
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var layer_vertices := n * n
	for layer in layers:
		var layer_t := float(layer + 1) / float(layers)
		for j in n:
			for i in n:
				var idx := j * n + i
				var x := o.x + i * shell_step
				var z := o.y + j * shell_step
				var normal := world_normals[idx]
				var pos := Vector3(x, world_heights[idx], z) + normal * height * layer_t
				st.set_normal(normal)
				# COLOR = cor da relva do bioma (o shader multiplica-a pela rampa
				# base→ponta); UV = cobertura e secura, que no shader da relva só
				# servem para o corte e para o tom do fio.
				st.set_color(Color(world_tint[idx].r, world_tint[idx].g,
					world_tint[idx].b, 1.0))
				st.set_uv(Vector2(world_cover[idx], world_dry[idx]))
				st.set_uv2(Vector2(layer_t, 0.0))
				st.add_vertex(pos)
		var base := layer * layer_vertices
		for j in res:
			for i in res:
				var a: int = base + j * n + i
				var b: int = a + 1
				var c: int = a + n + 1
				var d: int = a + n
				st.add_index(a); st.add_index(b); st.add_index(c)
				st.add_index(a); st.add_index(c); st.add_index(d)
	var mesh := st.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return
	mesh.surface_set_material(0, mats.grass_shell)
	_grass_shell_inst = MeshInstance3D.new()
	_grass_shell_inst.name = "GrassShells"
	_grass_shell_inst.mesh = mesh
	_grass_shell_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_grass_shell_inst.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_grass_shell_inst.extra_cull_margin = 0.8
	add_child(_grass_shell_inst)
	_decor.append(_grass_shell_inst)


## Folhas mais largas perto do jogador. Uma malha partilhada é desenhada por
## MultiMesh; cobertura, inclinação e secura vêm da grelha já calculada para o
## terreno, evitando amostrar ruído procedural outra vez para cada tufo.
func _build_grass_cards(o: Vector2, n: int, step: float,
		heights: PackedFloat32Array, normals: PackedVector3Array,
		coverage: PackedFloat32Array, dryness: PackedFloat32Array,
		tint: PackedColorArray) -> void:
	if mats.grass_card_mesh == null:
		return
	var quality := clampi(int(Game.settings.get("quality", 1)), 0, 2)
	var spacing: float = [1.02, 0.90, 0.80][quality]
	var cells: int = int(ceil(SIZE / spacing))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(cx, terrain.seed_value, cz))
	var transforms: Array[Transform3D] = []
	var instance_data: Array[Color] = []
	var instance_colors: Array[Color] = []
	for iz in cells:
		for ix in cells:
			var x: float = o.x + (float(ix) + rng.randf_range(0.08, 0.92)) * spacing
			var z: float = o.y + (float(iz) + rng.randf_range(0.08, 0.92)) * spacing
			if x >= o.x + SIZE or z >= o.y + SIZE:
				continue
			var field := _sample_grass_grid(coverage, n, step, x, z, o)
			if field < 0.07:
				continue
			var density := clampf((field - 0.07) / 0.48, 0.0, 1.0)
			density = density * density * (3.0 - 2.0 * density) * 0.94
			if rng.randf() > density:
				continue
			var dry := _sample_grass_grid(dryness, n, step, x, z, o)
			var height := _sample_grass_grid(heights, n, step, x, z, o)
			var normal := _sample_grass_normal(normals, n, step, x, z, o)
			var orientation := Basis(Quaternion(Vector3.UP, normal)) \
				* Basis(Vector3.UP, rng.randf() * TAU)
			var scale := rng.randf_range(0.82, 1.28)
			var height_scale := scale * lerpf(1.05, 0.78, dry) * rng.randf_range(0.92, 1.12)
			orientation = orientation.scaled(Vector3(scale, height_scale, scale))
			transforms.append(Transform3D(orientation, Vector3(x, height, z)))
			instance_data.append(Color(dry, rng.randf(), 0.0, 1.0))
			# A cor da instância é a cor da relva do bioma: a malha traz só a
			# rampa base→ponta e a cor vem daqui (COR = vcol * cor de instância).
			instance_colors.append(_sample_grass_color(tint, n, step, x, z, o))
	if transforms.is_empty():
		return
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.use_colors = true
	multimesh.mesh = mats.grass_card_mesh
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
		multimesh.set_instance_custom_data(i, instance_data[i])
		multimesh.set_instance_color(i, instance_colors[i])
	var min_height := heights[0]
	var max_height := heights[0]
	for sampled_height in heights:
		min_height = minf(min_height, sampled_height)
		max_height = maxf(max_height, sampled_height)
	multimesh.custom_aabb = AABB(Vector3(o.x - 2.0, min_height - 2.0, o.y - 2.0),
		Vector3(SIZE + 4.0, max_height - min_height + 5.0, SIZE + 4.0))
	_grass_cards_inst = MultiMeshInstance3D.new()
	_grass_cards_inst.name = "GrassCards"
	_grass_cards_inst.multimesh = multimesh
	_grass_cards_inst.material_override = mats.grass_cards
	_grass_cards_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_grass_cards_inst.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_grass_cards_inst.extra_cull_margin = 0.8
	add_child(_grass_cards_inst)
	_decor.append(_grass_cards_inst)
	ShotMeta.keep(_grass_cards_inst, transforms, instance_colors, instance_data)


func _sample_grass_grid(values: PackedFloat32Array, n: int, step: float,
		x: float, z: float, o: Vector2) -> float:
	var gx := clampf((x - o.x) / step, 0.0, float(n - 1))
	var gz := clampf((z - o.y) / step, 0.0, float(n - 1))
	var ix := mini(int(floor(gx)), n - 2)
	var iz := mini(int(floor(gz)), n - 2)
	var tx := gx - float(ix)
	var tz := gz - float(iz)
	var a := lerpf(values[iz * n + ix], values[iz * n + ix + 1], tx)
	var b := lerpf(values[(iz + 1) * n + ix], values[(iz + 1) * n + ix + 1], tx)
	return lerpf(a, b, tz)


func _sample_grass_color(values: PackedColorArray, n: int, step: float,
		x: float, z: float, o: Vector2) -> Color:
	var gx := clampf((x - o.x) / step, 0.0, float(n - 1))
	var gz := clampf((z - o.y) / step, 0.0, float(n - 1))
	var ix := mini(int(floor(gx)), n - 2)
	var iz := mini(int(floor(gz)), n - 2)
	var tx := gx - float(ix)
	var tz := gz - float(iz)
	var a := values[iz * n + ix].lerp(values[iz * n + ix + 1], tx)
	var b := values[(iz + 1) * n + ix].lerp(values[(iz + 1) * n + ix + 1], tx)
	return a.lerp(b, tz)


func _sample_grass_normal(values: PackedVector3Array, n: int, step: float,
		x: float, z: float, o: Vector2) -> Vector3:
	var gx := clampf((x - o.x) / step, 0.0, float(n - 1))
	var gz := clampf((z - o.y) / step, 0.0, float(n - 1))
	var ix := mini(int(floor(gx)), n - 2)
	var iz := mini(int(floor(gz)), n - 2)
	var tx := gx - float(ix)
	var tz := gz - float(iz)
	var a := values[iz * n + ix].lerp(values[iz * n + ix + 1], tx)
	var b := values[(iz + 1) * n + ix].lerp(values[(iz + 1) * n + ix + 1], tx)
	return a.lerp(b, tz).normalized()


## A superfície de água é recortada à altura do terreno em cada chunk. Isto
## deixa a costa visível e cria uma boca contínua para o rio, sem um plano que
## cubra o solo seco ou siga o jogador.
func _build_water(o: Vector2) -> void:
	if water_root == null or mats == null:
		return
	var water_res: int = WATER_LOD_RES[clampi(lod, 0, WATER_LOD_RES.size() - 1)]
	var n := water_res + 1
	var step := SIZE / float(water_res)
	var verts: Array[Dictionary] = []
	verts.resize(n * n)
	for j in n:
		for i in n:
			var x := o.x + i * step
			var z := o.y + j * step
			var ws := terrain.water_sample(x, z)
			if ws.is_empty():
				verts[j * n + i] = {"p": Vector2(x, z), "level": 0.0, "depth": 0.0,
					"salt": 0.0, "ex": Vector4.ZERO, "signed": -1.0, "wet": false}
				continue
			var flow: Vector2 = ws.get("flow", Vector2.ZERO)
			var depth := float(ws.get("depth", 0.0))
			verts[j * n + i] = {
				"p": Vector2(x, z),
				"level": float(ws.get("level", 0.0)),
				"salt": clampf(float(ws.get("salinity", 0.0)), 0.0, 1.0),
				"ex": Vector4(
					clampf(float(ws.get("speed", 0.0)) / 3.4, 0.0, 1.0),
					clampf(float(ws.get("turbidity", 0.0)), 0.0, 1.0),
					flow.x, flow.y),
				"depth": depth,
				"signed": depth,
				"wet": true,
			}
	# Segundo passo: os vértices SECOS que fazem fronteira com água recebem a
	# cota do vizinho e a altura do chão. Assim o recorte da margem é uma
	# interpolação linear do campo assinado — zero consultas por aresta.
	# Antes, cada aresta molhada pagava 4–7 amostras completas e um só chunk de
	# rio custava 1 segundo.
	for j in n:
		for i in n:
			var idx := j * n + i
			if bool(verts[idx]["wet"]):
				continue
			var nb := -1
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var ni := i + d.x
				var nj := j + d.y
				if ni < 0 or nj < 0 or ni >= n or nj >= n:
					continue
				if bool(verts[nj * n + ni]["wet"]):
					nb = nj * n + ni
					break
			if nb < 0:
				continue
			var p2: Vector2 = verts[idx]["p"]
			var lv := float(verts[nb]["level"])
			verts[idx]["level"] = lv
			verts[idx]["signed"] = lv - terrain.height(p2.x, p2.y)
			verts[idx]["depth"] = 0.0
			verts[idx]["salt"] = float(verts[nb]["salt"])
			verts[idx]["ex"] = verts[nb]["ex"]
	var has_water := false
	for v in verts:
		if bool(v["wet"]):
			has_water = true
			break
	if not has_water:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in water_res:
		for i in water_res:
			var a := j * n + i
			var b := a + 1
			var c := a + n + 1
			var d := a + n
			_add_clipped_water_triangle(st, verts[a], verts[b], verts[c])
			_add_clipped_water_triangle(st, verts[a], verts[c], verts[d])
	var mesh := st.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return
	mesh.surface_set_material(0, mats.water)
	_water_inst = MeshInstance3D.new()
	_water_inst.name = "WaterSurface_%d_%d" % [cx, cz]
	_water_inst.mesh = mesh
	_water_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_water_inst.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	water_root.add_child(_water_inst)


func _wet(v: Dictionary) -> bool:
	return float(v["signed"]) > 0.0


func _mix_vert(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var exa: Vector4 = a["ex"]
	var exb: Vector4 = b["ex"]
	var out_ex := exa.lerp(exb, t)
	return {
		"p": (a["p"] as Vector2).lerp(b["p"], t),
		"level": lerpf(float(a["level"]), float(b["level"]), t),
		"depth": 0.0,
		"salt": lerpf(float(a["salt"]), float(b["salt"]), t),
		"ex": out_ex,
		"signed": 0.0,
		"wet": true,
	}


func _add_clipped_water_triangle(st: SurfaceTool, a: Dictionary, b: Dictionary,
		c: Dictionary) -> void:
	var polygon: Array[Dictionary] = [a, b, c]
	var clipped: Array[Dictionary] = []
	for i in 3:
		var current: Dictionary = polygon[i]
		var next: Dictionary = polygon[(i + 1) % 3]
		var current_wet := _wet(current)
		var next_wet := _wet(next)
		if current_wet and next_wet:
			clipped.append(next)
		elif current_wet and not next_wet:
			clipped.append(_water_boundary(current, next))
		elif not current_wet and next_wet:
			clipped.append(_water_boundary(next, current))
			clipped.append(next)
	if clipped.size() < 3:
		return
	for i in range(1, clipped.size() - 1):
		_add_water_face(st, clipped[0], clipped[i], clipped[i + 1])


## Ponto onde a água encontra a terra, por interpolação do campo assinado.
func _water_boundary(wet: Dictionary, dry: Dictionary) -> Dictionary:
	var sw := float(wet["signed"])
	var sd := float(dry["signed"])
	var t := clampf(sw / maxf(sw - sd, 0.0001), 0.0, 1.0)
	return _mix_vert(wet, dry, t)


func _add_water_face(st: SurfaceTool, a: Dictionary, b: Dictionary, c: Dictionary) -> void:
	var pa: Vector2 = a["p"]
	var pb: Vector2 = b["p"]
	var pc: Vector2 = c["p"]
	var va := Vector3(pa.x, float(a["level"]), pa.y)
	var vb := Vector3(pb.x, float(b["level"]), pb.y)
	var vc := Vector3(pc.x, float(c["level"]), pc.y)
	# UV2 = (profundidade, salinidade). Salinidade 1 é mar; 0 é rio, lago ou
	# mangue. É o que separa ondas grandes de água parada — e água salgada de
	# doce para o jogo (beber, ferver, filtrar).
	# COLOR = (velocidade, turvação, corrente x, corrente z), todos 0..1.
	if (vb - va).cross(vc - va).y < 0.0:
		var swap := vb
		vb = vc
		vc = swap
		var swap_d := b
		b = c
		c = swap_d
	for v in [a, b, c]:
		var p: Vector2 = v["p"]
		var ex: Vector4 = v["ex"]
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(p.x, p.y) * 0.12)
		st.set_uv2(Vector2(float(v["depth"]), float(v["salt"])))
		st.set_color(Color(ex.x, ex.y, ex.z * 0.5 + 0.5, ex.w * 0.5 + 0.5))
		st.add_vertex(Vector3(p.x, float(v["level"]), p.y))


# ══════════════════════════════════════════════════════════════════════════
#  VEGETAÇÃO / ROCHAS
# ══════════════════════════════════════════════════════════════════════════
func _rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash(Vector2i(cx, cz)) ^ (terrain.seed_value * 7919)
	return r


func _scatter(o: Vector2, with_collision: bool) -> void:
	var rng := _rng()
	var buckets := {}      # id -> {transforms, tints, mesh, wind, height}
	var seaweed_t: Array[Transform3D] = []
	var buf := PackedFloat32Array()
	buf.resize(Terrain.BIOME_COUNT)
	var region_buf := PackedFloat32Array()
	region_buf.resize(RegionGrammar.TYPE_COUNT)
	# Densidade por perfil: q=1 é o perfil jogável numa GPU integrada; q=2
	# devolve o mundo cheio. Sem isto, 46 chunks com ~14 mil instâncias davam
	# 3 FPS numa Intel UHD 620 (medido com `-- perf` em 2026-10-19).
	var density_preset := Db.quality_preset(int(Game.settings.get("quality", 1)), {})
	var density_scale := float(density_preset.get("vegetation", 1.0))
	density_scale = clampf(density_scale, 0.2, 1.0)

	# ── árvores ───────────────────────────────────────────────────────────
	var cells := int(SIZE / TREE_CELL)
	for cj in cells:
		for ci in cells:
			var x := o.x + (ci + rng.randf()) * TREE_CELL
			var z := o.y + (cj + rng.randf()) * TREE_CELL
			# Nascer dentro de um tronco é nascer preso (ver World.SPAWN_CLEAR_RADIUS).
			if world != null and not world.is_clear_of_spawn(x, z):
				continue
			var h := terrain.height(x, z)
			var sl := terrain.slope(x, z)
			if h < Terrain.SEA_LEVEL + 0.5 or sl > 0.55:
				continue
			if terrain.path_distance(x, z) < 3.2:
				continue
			if terrain.village_distance(x, z) < Terrain.VILLAGE_RADIUS:
				continue
			terrain.biome_weights_s(x, z, h, sl, buf, region_buf)
			var density := ecology.density_per_100m2("tree", buf, x, z) if ecology != null \
				else SpeciesKit.tree_density(terrain.dominant_s(x, z, h, sl))
			if rng.randf() > density * (TREE_CELL * TREE_CELL) / 100.0 * density_scale:
				continue
			var id := ecology.pick_species(species.trees, buf, rng.randf(), x, z) if ecology != null \
				else species.pick(species.trees, terrain.dominant_s(x, z, h, sl), rng.randf())
			if id.is_empty():
				continue
			var sp: SpeciesKit.Species = species.trees[id]
			var s := rng.randf_range(sp.scale_range.x, sp.scale_range.y)
			var y := h + sp.y_offset * s
			if world != null and world.is_harvested(Vector3(x, h, z), id):
				continue
			var xform := Transform3D(Basis(Vector3.UP, rng.randf() * TAU)
				.scaled(Vector3(s, s * rng.randf_range(0.9, 1.15), s)),
				Vector3(x, y, z))
			var bi := _add(buckets, id, xform, _tint(rng), 0.0)
			var tree_collider: CollisionShape3D = null
			if with_collision:
				tree_collider = _add_collider(
					Vector3(x, h + sp.collider_scale.y * s * 0.5, z), sp.collider_scale * s)
			harvest_nodes.append({
				"pos": Vector3(x, h, z), "kind": sp.harvest, "species": id,
				"hp": int(Db.HARVEST.get(sp.harvest, {}).get("hp", 5)),
				"radius": 0.9 * s, "height": sp.height * s,
				"collider_radius": sp.collider_scale.x * s,
				"collider": tree_collider,
				"base_transform": xform,
				"alive": true, "bucket": id, "bindex": bi, "chunk": self,
			})

	# ── rochas ────────────────────────────────────────────────────────────
	var rc := int(SIZE / ROCK_CELL)
	for cj in rc:
		for ci in rc:
			var x := o.x + (ci + rng.randf()) * ROCK_CELL
			var z := o.y + (cj + rng.randf()) * ROCK_CELL
			if world != null and not world.is_clear_of_spawn(x, z):
				continue
			var h := terrain.height(x, z)
			if h < Terrain.SEA_LEVEL - 0.5:
				continue
			if terrain.path_distance(x, z) < 2.4:
				continue
			if terrain.village_distance(x, z) < Terrain.VILLAGE_RADIUS * 0.7:
				continue
			var sl := terrain.slope(x, z)
			terrain.biome_weights_s(x, z, h, sl, buf, region_buf)
			var geology_sample: Dictionary = terrain.geology.sample(x, z) if terrain.geology != null else {}
			var density := ecology.density_per_100m2("rock", buf, x, z) if ecology != null else 0.30
			var exposure := terrain.geology.exposure_at(x, z, h, sl) if terrain.geology != null else 0.5
			density *= lerpf(0.30, 1.65, exposure)
			if rng.randf() > density * (ROCK_CELL * ROCK_CELL) / 100.0 * density_scale:
				continue
			var id := ecology.pick_species(species.rocks, buf, rng.randf(), x, z, geology_sample) if ecology != null \
				else species.pick(species.rocks, terrain.dominant_s(x, z, h, sl), rng.randf())
			if id.is_empty():
				continue
			var sp: SpeciesKit.Species = species.rocks[id]
			if sp.harvest != "" and world != null and world.is_harvested(Vector3(x, h, z), id):
				continue
			var s := rng.randf_range(sp.scale_range.x, sp.scale_range.y)
			var xform := Transform3D(Basis(Vector3.UP, rng.randf() * TAU)
				.scaled(Vector3(s, s * rng.randf_range(0.7, 1.1), s)),
				Vector3(x, h + sp.y_offset * s, z))
			var bi := _add(buckets, id, xform, _tint(rng), 0.0)
			if sp.harvest != "":
				var rock_collider: CollisionShape3D = null
				if with_collision:
					rock_collider = _add_collider(Vector3(x, h + 0.3 * s, z),
						Vector3(0.9, 0.8, 0.9) * s)
				harvest_nodes.append({
					"pos": Vector3(x, h, z), "kind": sp.harvest, "species": id,
					"hp": int(Db.HARVEST.get(sp.harvest, {}).get("hp", 3)),
					"radius": 0.8 * s, "height": 0.8 * s,
					"collider": rock_collider,
					"alive": true, "bucket": id, "bindex": bi, "chunk": self,
				})

	# ── plantas ───────────────────────────────────────────────────────────
	var pc := int(SIZE / 2.5)
	for cj in pc:
		for ci in pc:
			var x := o.x + (ci + rng.randf()) * 2.5
			var z := o.y + (cj + rng.randf()) * 2.5
			if world != null and not world.is_clear_of_spawn(x, z):
				continue
			var h := terrain.height(x, z)
			if h < Terrain.SEA_LEVEL + 0.3:
				continue
			if terrain.path_distance(x, z) < 2.0:
				continue
			var sl := terrain.slope(x, z)
			terrain.biome_weights_s(x, z, h, sl, buf, region_buf)
			var density := ecology.density_per_100m2("plant", buf, x, z) if ecology != null else 0.55
			if rng.randf() > density * (2.5 * 2.5) / 100.0 * density_scale:
				continue
			var id := ecology.pick_species(species.plants, buf, rng.randf(), x, z) if ecology != null \
				else species.pick(species.plants, terrain.dominant_s(x, z, h, sl), rng.randf())
			if id.is_empty():
				continue
			var sp: SpeciesKit.Species = species.plants[id]
			if world != null and world.is_harvested(Vector3(x, h, z), id):
				continue
			var s := rng.randf_range(sp.scale_range.x, sp.scale_range.y)
			var bi := _add(buckets, id, Transform3D(Basis(Vector3.UP, rng.randf() * TAU)
				.scaled(Vector3(s, s, s)), Vector3(x, h + sp.y_offset * s, z)),
				_tint(rng), 0.0)
			if sp.harvest != "":
				harvest_nodes.append({
					"pos": Vector3(x, h, z), "kind": sp.harvest, "species": id,
					"hp": 1, "radius": 0.9, "height": sp.height * s,
					"alive": true, "bucket": id, "bindex": bi, "chunk": self,
				})

	# ── algas em prateleiras rasas ─────────────────────────────────────────
	# O asset é uma instância MultiMesh; só colocamos em profundidade onde a
	# silhueta fica abaixo da superfície e continua legível através da água.
	if lod == 0 and BlessedBlenderAssets.has_asset("seaweed_cluster"):
		for i in 40:
			var x := o.x + rng.randf() * SIZE
			var z := o.y + rng.randf() * SIZE
			var h := terrain.height(x, z)
			var depth := Terrain.SEA_LEVEL - h
			if not terrain.is_ocean(x, z) or depth < 0.8 or depth > 2.1 or rng.randf() > 0.68:
				continue
			var scale := rng.randf_range(0.55, 0.92)
			seaweed_t.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU)
				.scaled(Vector3(scale, scale, scale)), Vector3(x, h + 0.05, z)))

	# ── cria os MultiMesh ─────────────────────────────────────────────────
	_buckets = buckets
	for id in buckets:
		_make_multimesh(str(id), buckets[id])
	_seaweed_multimesh(seaweed_t)


func _tint(rng: RandomNumberGenerator) -> Color:
	var v := rng.randf_range(-0.09, 0.11)
	return Color(1.0 + v, 1.0 + v * 0.7, 1.0 + v * 0.5)


func _add(buckets: Dictionary, id: String, xform: Transform3D, tint: Color, fade: float) -> int:
	if not buckets.has(id):
		buckets[id] = {"t": [], "c": [], "fade": fade, "mm": null}
	(buckets[id]["t"] as Array).append(xform)
	(buckets[id]["c"] as Array).append(tint)
	return (buckets[id]["t"] as Array).size() - 1


func _make_multimesh(id: String, b: Dictionary) -> void:
	var t: Array = b["t"]
	var c: Array = b["c"]
	if t.is_empty():
		return
	var sp: SpeciesKit.Species = null
	var mesh: ArrayMesh = null
	if species.trees.has(id):
		sp = species.trees[id]
	elif species.rocks.has(id):
		sp = species.rocks[id]
	elif species.plants.has(id):
		sp = species.plants[id]
	if sp == null:
		return
	# Espécie sem geometria: não se cria instância nenhuma. Um MultiMesh com
	# `mesh = null` não desenha nada e ainda envenena quem lhe leia a malha
	# (o self-test chegou a morrer com um trap do wasm a lê-la). Avisa uma vez,
	# para uma espécie mal construída não passar em silêncio.
	if sp.lods.is_empty():
		if not _sem_geometria.has(id):
			_sem_geometria[id] = true
			push_warning("Chunk: espécie '%s' sem LODs — nada a instanciar" % id)
		return
	mesh = sp.lods[clampi(lod, 0, sp.lods.size() - 1)]
	# Os modelos de copa usam cartões alfa. Mantemos a máscara e os LODs do
	# artista, mas animamos os vértices por instância em vez de deixar folhas imóveis.
	var moving_vegetation := species.trees.has(id) or (species.plants.has(id) and sp.wind > 0.0)
	if sp.materials_authored and moving_vegetation:
		# A sakura do kit tem folhas de ácer vermelhas. Uma cerejeira do jogo
		# deve ser rosada; o shader puxa a matiz mantendo a máscara alfa.
		var rec := Color(1.0, 0.62, 0.77) if id == "sakura" else Color.WHITE
		var amount := 0.72 if id == "sakura" else 0.0
		mesh = mats.wind_foliage_mesh(mesh, sp.height, rec, amount)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.use_colors = true  # sem isto a cor de vértice é multiplicada por 0 => preto
	mm.mesh = mesh
	mm.instance_count = t.size()
	var tree_bounds := AABB()
	var has_tree_bounds := false
	for i in t.size():
		var xform: Transform3D = t[i]
		mm.set_instance_transform(i, xform)
		mm.set_instance_color(i, Color.WHITE)
		var tint: Color = c[i]
		mm.set_instance_custom_data(i, Color(tint.r, tint.g, tint.b, float(b["fade"])))
		if moving_vegetation:
			# O shader abana as copas para fora da caixa estática da malha; fornece
			# limites conservadores por chunk para o culling não cortar folhas ao vento.
			var scale_x := xform.basis.x.length()
			var scale_y := xform.basis.y.length()
			var scale_z := xform.basis.z.length()
			var radius := maxf(1.5, sp.height * 0.45) * maxf(scale_x, scale_z) + 0.8
			var p: Vector3 = xform.origin
			var low := Vector3(p.x - radius, p.y - 1.0, p.z - radius)
			var high := Vector3(p.x + radius, p.y + sp.height * scale_y + 1.0,
				p.z + radius)
			if not has_tree_bounds:
				tree_bounds = AABB(low, high - low)
				has_tree_bounds = true
			else:
				tree_bounds = tree_bounds.expand(low).expand(high)
	if has_tree_bounds:
		mm.custom_aabb = tree_bounds
	b["mm"] = mm
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.material_override = null if sp.materials_authored else mats.foliage
	var keeps_realtime_shadow := lod == 0 and species.trees.has(id)
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if keeps_realtime_shadow \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	inst.visibility_range_end = 0.0
	add_child(inst)
	_decor.append(inst)
	var customs: Array = []
	for i in t.size():
		var tint: Color = c[i]
		customs.append(Color(tint.r, tint.g, tint.b, float(b["fade"])))
	ShotMeta.keep(inst, t, c, customs)


func _seaweed_multimesh(transforms: Array[Transform3D]) -> void:
	if transforms.is_empty():
		return
	var mesh := BlessedBlenderAssets.mesh_for("seaweed_cluster")
	if mesh == null:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var inst := MultiMeshInstance3D.new()
	inst.name = "UnderwaterSeaweed"
	inst.multimesh = mm
	inst.material_override = mats.foliage
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(inst)
	_decor.append(inst)
	ShotMeta.keep(inst, transforms)


func _add_collider(pos: Vector3, size: Vector3) -> CollisionShape3D:
	if _body == null:
		return null
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = maxf(size.x, size.z) * 0.5
	shape.height = maxf(size.y, 0.4)
	col.shape = shape
	col.position = pos - _body.position
	_body.add_child(col)
	_colliders.append(col)
	return col


## Esconde a instância de um nó já colhido (MultiMesh não tem "hide").
func hide_harvest(n: Dictionary) -> void:
	n["alive"] = false
	if str(n.get("kind", "")).begins_with("tree"):
		if world != null and world.has_method("fell_tree"):
			world.call("fell_tree", n)
	var old_collider := n.get("collider") as CollisionShape3D
	if is_instance_valid(old_collider):
		old_collider.set_deferred("disabled", true)
		old_collider.queue_free()
		_colliders.erase(old_collider)
	var bid := str(n.get("bucket", ""))
	if not _buckets.has(bid):
		return
	var b: Dictionary = _buckets[bid]
	if b.get("mm") == null:
		return
	var mm: MultiMesh = b["mm"]
	var i := int(n.get("bindex", -1))
	if i < 0 or i >= mm.instance_count:
		return
	mm.set_instance_transform(i, Transform3D(
		Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), n["pos"]))
func set_lod(new_lod: int, with_collision: bool) -> void:
	if new_lod == lod and built:
		return
	lod = new_lod
	release()
	build(with_collision)


func release() -> void:
	for d in _decor:
		if is_instance_valid(d):
			d.queue_free()
	_decor.clear()
	if is_instance_valid(_water_inst):
		var water_parent := _water_inst.get_parent()
		if water_parent != null:
			water_parent.remove_child(_water_inst)
		_water_inst.queue_free()
		_water_inst = null
	if is_instance_valid(_mesh_inst):
		_mesh_inst.queue_free()
		_mesh_inst = null
	if is_instance_valid(_body):
		_body.queue_free()
		_body = null
	_colliders.clear()
	harvest_nodes.clear()
	_buckets.clear()
	built = false
