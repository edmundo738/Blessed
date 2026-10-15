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
var _smoke_material: StandardMaterial3D
var _ember_material: StandardMaterial3D
var _fire_mesh: ArrayMesh
var _smoke_mesh: QuadMesh
var _ember_mesh: SphereMesh

const SMOKE_TEXTURE := preload("res://content/fx/kenney/particles/smoke_02.png")


func _ready() -> void:
	name = "Structures"
	Game.register_saver(self)


func setup(p_species: SpeciesKit, p_mats: Materials) -> void:
	species = p_species
	mats = p_mats
	_fire_material = ShaderMaterial.new()
	_fire_material.shader = load("res://shaders/campfire_flame.gdshader")
	_fire_material.set_shader_parameter("flame_speed", 1.0)
	_fire_material.set_shader_parameter("flame_energy", 2.4)
	_smoke_material = _make_smoke_material()
	_ember_material = _make_ember_material()
	_fire_mesh = _make_flame_mesh()
	_smoke_mesh = _make_smoke_mesh()
	_ember_mesh = _make_ember_mesh()


func place(id: String, pos: Vector3, rot_y: float, lit: bool = false) -> Dictionary:
	var entry := {"id": id, "pos": pos, "rot": rot_y, "lit": lit, "node": null, "light": null}
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
	if is_instance_valid(entry.get("node")):
		_attach_light(entry)
	Game.bump("light_campfire")


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

	var flame := MeshInstance3D.new()
	flame.name = "LayeredFlame"
	flame.mesh = _fire_mesh
	flame.material_override = _fire_material
	flame.position.y = 0.38
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


func _make_flame_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for plane in 6:
		var angle := TAU * float(plane) / 6.0
		var side := Vector3(cos(angle), 0.0, sin(angle)) * 0.23
		var p0 := -side + Vector3(0.0, 0.0, 0.0)
		var p1 := side + Vector3(0.0, 0.0, 0.0)
		var p2 := side * 0.035 + Vector3(0.0, 0.92, 0.0)
		var p3 := -side * 0.035 + Vector3(0.0, 0.92, 0.0)
		for vertex in [[p0, Vector2(0, 0)], [p1, Vector2(1, 0)], [p2, Vector2(1, 1)],
				[p0, Vector2(0, 0)], [p2, Vector2(1, 1)], [p3, Vector2(0, 1)]]:
			st.set_uv(vertex[1])
			st.add_vertex(vertex[0])
	return st.commit()



func _make_smoke_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.albedo_texture = SMOKE_TEXTURE
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


## Estações de trabalho disponíveis perto de um ponto.
func stations_near(p: Vector3, radius: float) -> Array:
	var out := []
	for e in near(p, radius):
		var id := str(e["id"])
		if id == "campfire" and bool(e.get("lit", false)) and not (id in out):
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
			"rot": float(e["rot"]), "lit": bool(e.get("lit", false))})
	return {"items": out}


func load_data(d: Dictionary) -> void:
	for e in list.duplicate():
		remove(e)
	var arr: Array = d.get("items", [])
	for it in arr:
		var p: Array = it["pos"]
		place(str(it["id"]), Vector3(p[0], p[1], p[2]), float(it["rot"]), bool(it.get("lit", false)))
