class_name Interaction
extends Node
## Interaction — a ponte entre o jogador e o mundo.
##
## Um só sítio decide "o que estou a olhar" e "o que acontece se carregar".
## Cada alvo devolve um contrato simples: tipo, prompt e uma ação. Assim
## acrescentar pesca, uma porta ou um NPC novo não toca em mais nada.

const REACH := 4.2
const CURIOUS_REACH_MULT := 1.35
const MAX_ANGLE := 0.62          # radianos a partir do centro do ecrã

var player: Player
var world: World
var survival: Survival
var inv: Inventory
var structures: Structures
var fx: Node3D
var npc_root: Node3D

var focus: Dictionary = {}
var progress := 0.0
var building := false
var build_rot := 0.0
var ghost: MeshInstance3D
var ghost_mat: StandardMaterial3D
var _hold := false
var _was_holding := false


func _ready() -> void:
	name = "Interaction"
	_make_ghost()
	Game.register_command("interact", self, _can_interact, _do_interact, "prompt.use")
	Game.register_command("craft", self, _can_craft, _do_craft, "tab.crafting")
	Game.register_command("place", self, _can_place, _do_place, "prompt.place")
	Game.register_command("remove_structure", self, _can_remove, _do_remove, "prompt.remove")
	Game.register_command("toggle_build", self, _can_toggle_build, _do_toggle_build, "prompt.place")


func _make_ghost() -> void:
	ghost_mat = StandardMaterial3D.new()
	ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_mat.albedo_color = Color(0.6, 0.95, 0.7, 0.45)
	ghost_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ghost = MeshInstance3D.new()
	ghost.name = "BuildGhost"
	ghost.material_override = ghost_mat
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ghost.visible = false
	add_child(ghost)


func _unhandled_input(event: InputEvent) -> void:
	if Game.paused or not Game.started:
		return
	if event.is_action_pressed("build"):
		Game.request("toggle_build")
	elif event.is_action_pressed("interact") and building:
		build_rot += PI * 0.25
		Sfx.play("ui_click", -16.0, 0.9)


func _process(delta: float) -> void:
	if Game.paused or not Game.started:
		return
	_update_focus()
	_handle_use(delta)
	_update_ghost()


# ══════════════════════════════════════════════════════════════════════════
#  O QUE ESTOU A OLHAR
# ══════════════════════════════════════════════════════════════════════════
## Alcance efetivo. A alma "curious" vê mais longe: é a promessa do prólogo
## ("Encontras mais ao explorar") tornada mecânica observável.
func reach() -> float:
	if str(Game.profile.get("soul", "")) == "curious":
		return REACH * CURIOUS_REACH_MULT
	return REACH


func _update_focus() -> void:
	var cam := player.camera
	var from := cam.global_position
	var dir := -cam.global_transform.basis.z
	var r := reach()
	var best := {}
	var best_score := 1e18

	# estruturas
	for e in structures.near(from, r):
		var p: Vector3 = e["pos"] + Vector3(0, 0.7, 0)
		var s := _score(p, from, dir, r)
		if s < best_score:
			best_score = s
			best = {"kind": "structure", "ref": e, "pos": p}

	# nós colhíveis
	for n in world.harvestables_near(from, r):
		if not bool(n.get("alive", true)):
			continue
		var p: Vector3 = (n["pos"] as Vector3) + Vector3(0, float(n["height"]) * 0.45, 0)
		var s := _score(p, from, dir, r)
		if s < best_score:
			best_score = s
			best = {"kind": "harvest", "ref": n, "pos": p}

	# pessoas
	if npc_root != null:
		for c in npc_root.get_children():
			if not (c is Node3D) or not c.has_method("interaction_target"):
				continue
			var p: Vector3 = (c as Node3D).global_position + Vector3(0, 1.4, 0)
			var s := _score(p, from, dir, r * 0.85)
			if s < best_score:
				best_score = s
				best = {"kind": "npc", "ref": c, "pos": p}

	# água (só se não houver mais nada)
	if best.is_empty():
		var hit := _ray_terrain(from, dir, r * 1.6)
		if hit != Vector3.INF and hit.y < Terrain.SEA_LEVEL + 0.25:
			best = {"kind": "water", "ref": null, "pos": hit}

	var changed := not _same(best)
	focus = best
	if changed:
		progress = 0.0
		Bus.focus_changed.emit(self, prompt_key())


func _same(other: Dictionary) -> bool:
	if other.is_empty() and focus.is_empty():
		return true
	if other.is_empty() or focus.is_empty():
		return false
	return other.get("kind") == focus.get("kind") and other.get("ref") == focus.get("ref")


func _score(p: Vector3, from: Vector3, dir: Vector3, max_d: float) -> float:
	var to := p - from
	var d := to.length()
	if d > max_d or d < 0.001:
		return 1e18
	var ang := to.normalized().angle_to(dir)
	if ang > MAX_ANGLE:
		return 1e18
	return d + ang * 5.0


func _ray_terrain(from: Vector3, dir: Vector3, max_d: float) -> Vector3:
	# marcha curta: barato e não precisa de física para o terreno
	var t := 0.0
	while t < max_d:
		var p := from + dir * t
		var g: float = world.ground_height(p.x, p.z)
		if p.y <= g + 0.1:
			return Vector3(p.x, g, p.z)
		t += 0.25
	return Vector3.INF


func prompt_key() -> String:
	if focus.is_empty():
		return ""
	match str(focus["kind"]):
		"harvest":
			var spec: Dictionary = Db.HARVEST.get(str(focus["ref"]["kind"]), {})
			return "prompt." + str(spec.get("action", "pick"))
		"structure":
			var e: Dictionary = focus["ref"]
			if str(e["id"]) == "campfire" and not bool(e.get("lit", false)):
				return "prompt.light"
			if str(e["id"]) == "bed":
				return "prompt.rest"
			return "prompt.remove"
		"npc":
			return "prompt.talk"
		"water":
			return "prompt.drink" if inv.count("bottle") == 0 else "prompt.fill"
	return "prompt.use"


func _can_interact(_a: Dictionary) -> bool:
	return not focus.is_empty()


func _do_interact(_a: Dictionary) -> Dictionary:
	return {"handled": true}


# ══════════════════════════════════════════════════════════════════════════
#  USAR (com progresso para cortar/minar)
# ══════════════════════════════════════════════════════════════════════════
func _handle_use(delta: float) -> void:
	var holding := Input.is_action_pressed("use") and not building
	if focus.is_empty():
		_hold = false
		progress = 0.0
		return
	var kind := str(focus["kind"])
	match kind:
		"npc", "water":
			if holding and not _was_holding:
				_fire_once()
			_hold = false
		"structure":
			var e: Dictionary = focus["ref"]
			if str(e["id"]) == "campfire" and not bool(e.get("lit", false)):
				if holding and not _was_holding:
					structures.light(e)
					Sfx.play("craft", -10.0, 1.3)
			else:
				_hold_work(delta, 0.9)
				if progress >= 1.0:
					Game.request("remove_structure", {"entry": e})
					progress = 0.0
		"harvest":
			_hold_work(delta, 1.0)
			if progress >= 1.0:
				_harvest_done()
				progress = 0.0
	_hold = holding
	_was_holding = holding


func _hold_work(delta: float, seconds: float) -> void:
	_hold = true
	var tool_id := inv.hotbar_id()
	var power := 1.0
	var spec: Dictionary = {}
	if not focus.is_empty() and str(focus["kind"]) == "harvest":
		spec = Db.HARVEST.get(str(focus["ref"]["kind"]), {})
		var want := str(spec.get("tool", ""))
		if not want.is_empty():
			var def: Dictionary = Db.item(tool_id)
			var pw: Dictionary = def.get("power", {})
			if pw.has(str(spec.get("action", ""))):
				power = float(pw[str(spec.get("action", ""))])
			else:
				power = 0.45   # à mão dá, mas custa
	progress += delta * power * survival.work_multiplier() / maxf(seconds, 0.05)
	if randf() < delta * 7.0:
		player.hands.swing(0.22)
		_hit_feedback()


func _hit_feedback() -> void:
	if focus.is_empty():
		return
	var p: Vector3 = focus["pos"]
	match str(focus["kind"]):
		"harvest":
			var id := str(focus["ref"]["kind"])
			if id.begins_with("tree"):
				Sfx.play_at("chop", p, -8.0, randf_range(0.95, 1.08))
				fx.burst(p, Color(0.55, 0.38, 0.24), 8)
			elif id == "rock":
				Sfx.play_at("mine", p, -8.0, randf_range(0.95, 1.1))
				fx.burst(p, Color(0.7, 0.7, 0.76), 10)
			else:
				Sfx.play_at("pick", p, -12.0)
				fx.burst(p, Color(0.45, 0.7, 0.35), 6)
		"structure":
			Sfx.play_at("chop", p, -10.0, 1.2)
			fx.burst(p, Color(0.6, 0.42, 0.28), 6)


func _harvest_done() -> void:
	var n: Dictionary = focus["ref"]
	var spec: Dictionary = Db.HARVEST.get(str(n["kind"]), {})
	var yields: Dictionary = spec.get("yields", {})
	for k in yields:
		var qty := int(yields[k])
		var bonus := 0.35 if str(Game.profile.get("soul", "")) != "curious" else 0.6
		if randf() < bonus:
			qty += 1
		inv.add(str(k), qty)
		Game.bump("item_" + str(k), qty)
	n["alive"] = false
	world.hide_harvest(n)
	Sfx.play_at("pick", focus["pos"], -4.0, 0.85)
	fx.burst(focus["pos"], Color(0.6, 0.45, 0.3), 16)
	Bus.node_harvested.emit(str(n["species"]), str(n["kind"]), focus["pos"])
	Game.bump("harvest_" + str(n["kind"]))
	progress = 0.0
	focus = {}


func _fire_once() -> void:
	match str(focus["kind"]):
		"npc":
			var npc: Node = focus["ref"]
			if npc.has_method("talk_to"):
				npc.call("talk_to")
		"water":
			if inv.count("bottle") > 0:
				inv.remove("bottle", 1)
				inv.add("water", 1)
				Sfx.play("splash", -10.0, 1.2)
				Bus.say("msg.crafted", 2.0)
			else:
				survival.drink(22.0)


# ══════════════════════════════════════════════════════════════════════════
#  CONSTRUIR
# ══════════════════════════════════════════════════════════════════════════
func _can_toggle_build(_a: Dictionary) -> bool:
	return true


func _do_toggle_build(_a: Dictionary) -> Dictionary:
	if building:
		building = false
		ghost.visible = false
		return {"building": false}
	var id := inv.hotbar_id()
	if not Db.is_placeable(id):
		# mensagem certa: não é "faltam materiais", é "isso não se coloca"
		Bus.say("prompt.blocked", 2.0)
		return {"building": false, "failed": true, "reason": "not_placeable"}
	building = true
	build_rot = snappedf(player.yaw + PI, PI * 0.25)
	return {"building": true}


func _ghost_place() -> Dictionary:
	var cam := player.camera
	var from := cam.global_position
	var dir := -cam.global_transform.basis.z
	var hit := _ray_terrain(from, dir, 8.0)
	if hit == Vector3.INF:
		var flat := from + dir * 3.0
		hit = Vector3(flat.x, world.ground_height(flat.x, flat.z), flat.z)
	hit.x = snappedf(hit.x, 0.5)
	hit.z = snappedf(hit.z, 0.5)
	return {"pos": hit, "rot": build_rot}


func _update_ghost() -> void:
	if not building:
		ghost.visible = false
		return
	var id := inv.hotbar_id()
	if not Db.is_placeable(id):
		building = false
		ghost.visible = false
		return
	var st: SpeciesKit.Structure = world.species.structures[str(Db.item(id)["place"])]
	if ghost.mesh != st.mesh:
		ghost.mesh = st.mesh
		ghost.position = Vector3.ZERO
	var place := _ghost_place()
	ghost.global_position = place["pos"] + Vector3(0, st.size.y * 0.5, 0)
	ghost.rotation.y = place["rot"]
	ghost.visible = true
	var ok := inv.count(id) > 0
	ghost_mat.albedo_color = Color(0.6, 0.95, 0.7, 0.45) if ok else Color(1.0, 0.4, 0.4, 0.45)


func _can_place(_a: Dictionary) -> bool:
	return building and inv.count(inv.hotbar_id()) > 0


func _do_place(_a: Dictionary) -> Dictionary:
	var id := inv.hotbar_id()
	var place := _ghost_place()
	if not inv.remove(id, 1):
		return {"failed": true}
	structures.place(str(Db.item(id)["place"]), place["pos"], place["rot"], false)
	Sfx.play_at("place", place["pos"], -6.0)
	Game.bump("place_" + str(Db.item(id)["place"]))
	player.hands.swing(0.2)
	if inv.count(id) <= 0:
		building = false
	return {"placed": str(id), "pos": place["pos"]}


func _can_remove(_a: Dictionary) -> bool:
	return _a.has("entry")


func _do_remove(args: Dictionary) -> Dictionary:
	var e: Dictionary = args["entry"]
	structures.remove(e)
	inv.add(str(e["id"]), 1)
	Sfx.play_at("chop", e["pos"], -8.0, 1.1)
	fx.burst(e["pos"] + Vector3(0, 0.6, 0), Color(0.6, 0.44, 0.3), 12)
	return {"removed": str(e["id"])}


# ══════════════════════════════════════════════════════════════════════════
#  BANCADA
# ══════════════════════════════════════════════════════════════════════════
func nearby_stations() -> Array:
	return structures.stations_near(player.global_position, 4.5)


func _can_craft(args: Dictionary) -> bool:
	var r := Db.recipe(str(args.get("recipe", "")))
	if r.is_empty():
		return false
	var st := str(r.get("station", ""))
	return st.is_empty() or st in nearby_stations()


func _do_craft(args: Dictionary) -> Dictionary:
	var r := Db.recipe(str(args.get("recipe", "")))
	if r.is_empty():
		return {"failed": true, "reason": "no_recipe"}
	# importante: um craft que não aconteceu TEM de vir como falha,
	# senão o OBSERVABLE RESULT mente a quem chamou o comando
	var ok := inv.craft(r)
	if not ok:
		return {"failed": true, "crafted": false, "reason": "no_materials"}
	return {"crafted": true, "result": str(r["result"])}
