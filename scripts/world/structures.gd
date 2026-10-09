class_name Structures
extends Node3D
## Structures — tudo o que o jogador constrói.
##
## Uma lista plana + nós na cena. Guardar só (id, posição, rotação, aceso) é o
## que torna o save minúsculo: o mundo reconstrói-se, as construções recriam-se.

var list: Array = []          # {id, pos, rot, lit, node, light}
var species: SpeciesKit
var mats: Materials
var _fire_material: StandardMaterial3D


func _ready() -> void:
	name = "Structures"
	Game.register_saver(self)


func setup(p_species: SpeciesKit, p_mats: Materials) -> void:
	species = p_species
	mats = p_mats
	_fire_material = StandardMaterial3D.new()
	_fire_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fire_material.albedo_color = Color(1.0, 0.62, 0.22)


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
	l.light_color = Color(1.0, 0.62, 0.28)
	l.light_energy = 2.4
	l.omni_range = st.light
	l.omni_attenuation = 1.6
	l.shadow_enabled = false
	l.position = Vector3(0, st.size.y * 0.7 + 0.3, 0)
	(entry["node"] as Node3D).add_child(l)
	entry["light"] = l
	# chama visível
	var flame := MeshInstance3D.new()
	flame.mesh = MeshKit.blob(RandomNumberGenerator.new(), 0.22, 1, 0.3,
		Vector3(0.8, 1.5, 0.8), Color(1, 1, 1))
	flame.material_override = _fire_material
	flame.position = Vector3(0, st.size.y * 0.42, 0)
	(entry["node"] as Node3D).add_child(flame)
	Sfx.loop("fire", "fire_loop", -18.0)


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
