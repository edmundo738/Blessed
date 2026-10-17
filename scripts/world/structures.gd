class_name Structures
extends Node3D
## Structures — tudo o que o jogador constrói.
##
## Uma lista plana + nós na cena. Guardar só (id, posição, rotação, aceso) é o
## que torna o save minúsculo: o mundo reconstrói-se, as construções recriam-se.

var list: Array = []          # {id, pos, rot, lit, node, light}
var species: SpeciesKit
var mats: Materials
var _fire_material: ShaderMaterial
var _fire_core_material: ShaderMaterial
var _smoke_material: StandardMaterial3D
var _ember_material: StandardMaterial3D
var _smoke_mesh: QuadMesh
var _ember_mesh: SphereMesh

const SMOKE_PATH := "res://content/fx/kenney/particles/smoke_02.png"


func _ready() -> void:
	name = "Structures"
	Game.register_saver(self)


## Fogo vivo: a luz de uma fogueira não é uma lâmpada. Sem este tremer, a
## fogueira ficava com luz fixa e o efeito era o de uma lâmpada laranja no chão
## — uma das razões de o fogo parecer mal feito.
func _process(delta: float) -> void:
	if list.is_empty():
		return
	var t := float(Time.get_ticks_msec()) * 0.001
	# Combustível: um fogo aceso gasta-se em horas de jogo, não em segundos.
	var spent := delta * Game.hours_per_second()
	for e in list:
		# (o laço abaixo salta entradas sem luz; o combustível é tratado antes
		#  para uma fogueira sem luz — qualidade baixa — não ficar eterna)
		if str(e["id"]) == "campfire" and bool(e.get("lit", false)):
			var fuel := float(e.get("fuel", 0.0)) - spent
			e["fuel"] = fuel
			if fuel <= 0.0:
				_burn_out(e)
				continue
			var warn := Db.fire_num("warn_hours", 1.0)
			if fuel <= warn and not bool(e.get("warned", false)):
				e["warned"] = true
				var at: Vector3 = e.get("pos", Vector3.ZERO)
				_whisper(at, Loc.t("msg.fire_low"), 3.0)
		var l: OmniLight3D = e.get("light")
		if l == null or not is_instance_valid(l):
			continue
		# Duas frequências diferentes (uma lenta, uma rápida) para o tremido não
		# ser um pisca-pisca regular.
		var f := 0.86 + 0.10 * sin(t * 7.7) + 0.06 * sin(t * 17.3 + 1.7)
		var base := float(species.structures[str(e["id"])].light) * 0.055 if species != null else 1.0
		l.light_energy = maxf(0.35, base * f * 1.35)
		l.light_color = Color(1.0, 0.70 + 0.06 * sin(t * 9.1), 0.44 + 0.05 * sin(t * 13.3))
		l.position.y = float(species.structures[str(e["id"])].size.y) * 0.7 + 0.30 \
			+ 0.02 * sin(t * 11.0)


func setup(p_species: SpeciesKit, p_mats: Materials) -> void:
	species = p_species
	mats = p_mats
	_fire_material = _make_flame_material(1.0, 1.35, 0.62, 1.0)
	_fire_core_material = _make_flame_material(1.35, 1.55, 0.30, 2.1)
	_smoke_material = _make_smoke_material()
	_ember_material = _make_ember_material()
	_smoke_mesh = _make_smoke_mesh()
	_ember_mesh = _make_ember_mesh()


func place(id: String, pos: Vector3, rot_y: float, lit: bool = false) -> Dictionary:
	var entry := {"id": id, "pos": pos, "rot": rot_y, "lit": lit, "node": null, "light": null}
	if id == "campfire" and lit:
		# Pousada já acesa (save/carregamento): tem de trazer combustível,
		# senão apagava-se no primeiro frame.
		entry["fuel"] = Db.fire_num("hours_per_load", 5.0)
	_spawn(entry)
	list.append(entry)
	Bus.structure_placed.emit(id, pos)
	if id == "campfire" and lit:
		Game.bump("light_campfire")
	return entry


func remove(entry: Dictionary) -> void:
	if entry.get("node") != null and is_instance_valid(entry["node"]):
		(entry["node"] as Node3D).queue_free()
	if entry.get("light") != null and is_instance_valid(entry["light"]):
		(entry["light"] as Node3D).queue_free()
	list.erase(entry)
	Bus.structure_removed.emit(str(entry["id"]), entry["pos"])


func light(entry: Dictionary) -> void:
	entry["lit"] = true
	entry["fuel"] = Db.fire_num("hours_per_load", 5.0)
	entry["warned"] = false
	if is_instance_valid(entry.get("node")):
		_attach_light(entry)
	Game.bump("light_campfire")


## Meter madeira no fogo. Devolve as horas que a fogueira passou a ter; 0 se
## não estava acesa.
func feed(entry: Dictionary) -> float:
	if not bool(entry.get("lit", false)):
		return 0.0
	var gain := Db.fire_num("wood_hours", 1.4)
	entry["fuel"] = float(entry.get("fuel", 0.0)) + gain
	entry["warned"] = false
	return float(entry["fuel"])


## Consumir horas de jogo de uma vez (dormir, viajar, esperar). Uma fogueira
## sem combustível suficiente apaga-se a meio da noite — é esse risco que faz
## valer a pena juntar madeira antes de dormir.
func burn_hours(hours: float) -> void:
	for e in list:
		if str(e["id"]) != "campfire" or not bool(e.get("lit", false)):
			continue
		var fuel := float(e.get("fuel", 0.0)) - maxf(0.0, hours)
		e["fuel"] = fuel
		if fuel <= 0.0:
			_burn_out(e, false)


## Apagar a fogueira: tira a luz, as chamas e o som. `tell` só avisa se o
## jogador estiver perto (uma fogueira a morrer do outro lado do mapa não é
## assunto dele).
func _burn_out(entry: Dictionary, tell: bool = true) -> void:
	if not bool(entry.get("lit", false)):
		return
	entry["lit"] = false
	entry["fuel"] = 0.0
	entry["warned"] = false
	var l: Node = entry.get("light")
	if is_instance_valid(l):
		l.queue_free()
	entry["light"] = null
	var node: Node = entry.get("node")
	if is_instance_valid(node):
		var vfx := node.get_node_or_null("CampfireVfx")
		if vfx != null:
			vfx.queue_free()
	if lit_positions().is_empty():
		Sfx.stop_loop("fire")
	if tell:
		var at: Vector3 = entry.get("pos", Vector3.ZERO)
		_whisper(at, Loc.t("msg.fire_out"), 3.0)


## Aviso de mundo: só chega ao jogador se ele estiver ao pé.
func _whisper(pos: Vector3, text: String, secs: float) -> void:
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p == null or p.global_position.distance_to(pos) > Db.fire_num("near_radius", 14.0):
		return
	Bus.ui_message.emit(text, secs)


func _spawn(entry: Dictionary) -> void:
	if species == null or not species.structures.has(str(entry["id"])):
		return
	var st: SpeciesKit.Structure = species.structures[str(entry["id"])]
	# ── Reestruturacao .tscn: um prefab editavel no editor tem prioridade. ──
	# Se existir res://scenes/structures/<id>.tscn, usa-o (tu editas a cena no
	# Godot, sem codigo). Senao, cai no procedural abaixo (nao parte nada).
	var prefab := "res://scenes/structures/%s.tscn" % str(entry["id"])
	if ResourceLoader.exists(prefab):
		var packed = load(prefab)
		if packed != null:
			var inst = packed.instantiate()
			if inst is Node3D:
				(inst as Node3D).position = entry["pos"]
				(inst as Node3D).rotation.y = float(entry["rot"])
				add_child(inst)
				entry["node"] = inst
				if entry["lit"]:
					_attach_light(entry)
				return
	var body := StaticBody3D.new()
	body.position = entry["pos"]
	body.rotation.y = float(entry["rot"])
	var mi := MeshInstance3D.new()
	mi.mesh = st.mesh
	mi.material_override = mats.structure
	mi.position = Vector3(0, st.size.y * 0.5, 0)
	body.add_child(mi)
	if st.solid:
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = st.size
		col.shape = box
		col.position = Vector3(0, st.size.y * 0.5, 0)
		body.add_child(col)
	add_child(body)
	entry["node"] = body
	if entry["lit"]:
		_attach_light(entry)


func _attach_light(entry: Dictionary) -> void:
	var st: SpeciesKit.Structure = species.structures[str(entry["id"])]
	if st.light <= 0.0:
		return
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.74, 0.48)
	l.light_energy = 1.0
	l.omni_range = st.light
	l.omni_attenuation = 1.0
	l.shadow_enabled = false
	l.position = Vector3(0, st.size.y * 0.7 + 0.3, 0)
	(entry["node"] as Node3D).add_child(l)
	entry["light"] = l
	_add_fire_vfx(entry, st)
	Sfx.loop("fire", "fire_loop", -18.0)


func _add_fire_vfx(entry: Dictionary, st: SpeciesKit.Structure) -> void:
	var root := Node3D.new()
	root.name = "CampfireVfx"
	root.position = Vector3(0, st.size.y * 0.42, 0)
	(entry["node"] as Node3D).add_child(root)

	# Exterior → núcleo. Cada camada é mais estreita, mais clara e mais rápida.
	var camadas := [
		{"nome": "FlameOuter", "altura": 1.00, "largura": 0.58, "mat": _fire_material, "y": 0.22},
		{"nome": "FlameCore", "altura": 0.70, "largura": 0.30, "mat": _fire_core_material, "y": 0.26},
	]
	for c in camadas:
		var flame := MeshInstance3D.new()
		flame.name = str(c["nome"])
		flame.mesh = _make_flame_mesh(float(c["altura"]), float(c["largura"]))
		flame.material_override = c["mat"]
		flame.position.y = float(c["y"])
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flame.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		root.add_child(flame)

	var quality := clampi(int(Game.settings.get("quality", 1)), 0, 2)
	if quality > 0:
		var smoke := CPUParticles3D.new()
		smoke.name = "Smoke"
		smoke.amount = [0, 7, 12][quality]
		smoke.lifetime = 2.0
		smoke.preprocess = 1.2
		smoke.local_coords = true
		smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		smoke.emission_sphere_radius = 0.12
		smoke.direction = Vector3(0.0, 1.0, 0.0)
		smoke.spread = 19.0
		smoke.gravity = Vector3(0.0, 0.16, 0.0)
		smoke.initial_velocity_min = 0.10
		smoke.initial_velocity_max = 0.25
		smoke.angular_velocity_min = -12.0
		smoke.angular_velocity_max = 12.0
		smoke.scale_amount_min = 0.65
		smoke.scale_amount_max = 1.25
		smoke.mesh = _smoke_mesh
		smoke.material_override = _smoke_material
		smoke.position.y = 0.62
		root.add_child(smoke)

		var embers := CPUParticles3D.new()
		embers.name = "Embers"
		embers.amount = [0, 5, 9][quality]
		embers.lifetime = 0.85
		embers.preprocess = 0.25
		embers.local_coords = true
		embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		embers.emission_sphere_radius = 0.17
		embers.direction = Vector3(0.0, 1.0, 0.0)
		embers.spread = 32.0
		embers.gravity = Vector3(0.0, -1.6, 0.0)
		embers.initial_velocity_min = 0.25
		embers.initial_velocity_max = 0.85
		embers.scale_amount_min = 0.8
		embers.scale_amount_max = 1.35
		embers.color = Color(1.0, 0.52, 0.18, 1.0)
		embers.mesh = _ember_mesh
		embers.material_override = _ember_material
		embers.position.y = 0.55
		root.add_child(embers)


## Uma camada de chama: `altura` e `largura` em metros, `power` é a energia do
## shader. A chama é feita de VÁRIAS camadas concêntricas (exterior vermelha,
## média laranja, núcleo amarelo) — é isso que faz uma chama parecer fogo e não
## um cone laranja: as camadas mexem-se com fases diferentes.
func _make_flame_material(speed: float, power: float, slim: float, largura: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/campfire_flame.gdshader")
	m.set_shader_parameter("flame_speed", speed)
	m.set_shader_parameter("flame_energy", power)
	m.set_shader_parameter("slim", slim)
	m.set_shader_parameter("width", largura)
	return m


## Malha da chama: 8 planos radiais com UV.y 0 (base) → 1 (ponta). O perfil
## estreita com a altura, mas não até zero — o shader corta a silhueta.
func _make_flame_mesh(altura: float, largura: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var planos := 8
	for plane in planos:
		var angle := TAU * float(plane) / float(planos)
		var side := Vector3(cos(angle), 0.0, sin(angle)) * largura * 0.5
		var p0 := -side
		var p1 := side
		var p2 := side * 0.10 + Vector3(0.0, altura, 0.0)
		var p3 := -side * 0.10 + Vector3(0.0, altura, 0.0)
		for vertex in [[p0, Vector2(0, 0)], [p1, Vector2(1, 0)], [p2, Vector2(1, 1)],
				[p0, Vector2(0, 0)], [p2, Vector2(1, 1)], [p3, Vector2(0, 1)]]:
			st.set_uv(vertex[1])
			st.add_vertex(vertex[0])
	st.generate_normals()
	return st.commit()



func _make_smoke_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.albedo_texture = Assets.texture(SMOKE_PATH)
	material.albedo_color = Color(0.22, 0.24, 0.30, 0.26)
	return material


func _make_ember_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.42, 0.08)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.18, 0.025)
	material.emission_energy_multiplier = 2.2
	return material


func _make_smoke_mesh() -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.36, 0.36)
	return quad


func _make_ember_mesh() -> SphereMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 0.026
	sphere.height = 0.052
	sphere.radial_segments = 5
	sphere.rings = 2
	return sphere


## Fontes de luz acesas (o Survival e as criaturas perguntam por isto).
func lit_positions() -> Array:
	var out := []
	for e in list:
		if bool(e.get("lit", false)):
			out.append(e["pos"] as Vector3)
	return out


func near(p: Vector3, radius: float) -> Array:
	var out := []
	for e in list:
		if (e["pos"] as Vector3).distance_to(p) <= radius:
			out.append(e)
	return out


## Estruturas colocadas que fazem de estação de trabalho. Antes só a fogueira
## contava — a bancada nova era colocável mas invisível para o craft, e as
## receitas que a exigem ficavam impossíveis de fazer.
const STATION_IDS := ["workbench", "campfire"]


## Estações de trabalho disponíveis perto de um ponto.
func stations_near(p: Vector3, radius: float) -> Array:
	var out := []
	for e in near(p, radius):
		var id := str(e["id"])
		if not (id in STATION_IDS) or id in out:
			continue
		# A fogueira só é bancada quando está acesa; a bancada, sempre.
		if id == "campfire" and not bool(e.get("lit", false)):
			continue
		out.append(id)
	return out


func has_shelter(p: Vector3, radius: float) -> bool:
	var walls := 0
	for e in near(p, radius):
		if str(e["id"]) in ["wall", "floor", "pillar"]:
			walls += 1
	return walls >= 3


func save_data() -> Dictionary:
	var out := []
	for e in list:
		out.append({"id": str(e["id"]), "pos": [e["pos"].x, e["pos"].y, e["pos"].z],
			"rot": float(e["rot"]), "lit": bool(e.get("lit", false)),
			"fuel": float(e.get("fuel", 0.0))})
	return {"items": out}


func load_data(d: Dictionary) -> void:
	for e in list.duplicate():
		remove(e)
	var arr: Array = d.get("items", [])
	for it in arr:
		var p: Array = it["pos"]
		var made := place(str(it["id"]), Vector3(p[0], p[1], p[2]), float(it["rot"]),
			bool(it.get("lit", false)))
		# O combustível de uma fogueira acesa tem de sobreviver ao save: se não,
		# carregar o jogo apagava-a ou dava-lhe uma carga nova de graça.
		if made.has("fuel") and it.has("fuel"):
			made["fuel"] = float(it["fuel"])
