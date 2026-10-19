class_name DroppedItem
extends RigidBody3D
## Recurso largado: cai e assenta pela física do mundo; recolhe por contacto.

var item_id := ""
var amount := 1
var inv: Node
var player_ref: Node
var launch_direction := Vector3.ZERO

var _age := 0.0
var _attempt_t := 0.0
var _full_notice_sent := false
var _label: Label3D
var _display: Node3D
var _frozen := false
var _bob_t := 0.0

const PICKUP_DISTANCE := 1.15
const MAX_PICKUP_HEIGHT := 2.2
## Íman: o item é atraído a partir daqui. Sem isto, o jogador tinha de acertar
## com o corpo no item (`1,08 m`) — e um recurso que cai num arbusto ou na
## encosta era praticamente impossível de apanhar.
##
## 2,6 m (era 2,1) parece pouco, mas é a diferença entre um arbusto colhido a
## andar e uma caça aos pickups: o arremesso inicial do item pode levá-lo para
## fora do alcance antigo antes de ele assentar. O raio maior não "puxa" itens
## do outro lado de uma parede — o íman só age depois de 0,25 s e a recolha
## continua a exigir linha de proximidade.
const MAGNET_DISTANCE := 2.6
## A partir deste tempo, um item já perto não espera que a física o deixe
## assentar: é levado diretamente ao peito. É o que faz a recolha parecer
## imediata em vez de "o item decidiu fugir".
const VACUUM_TIME := 0.55
## Depois do arremesso inicial, o item assenta e passa a girar devagar
## (modelo do Minecraft): deixa de rolar por aí e de se perder em buracos.
const SETTLE_TIME := 1.1


## Cria um item no chão. Um sítio só para isto: a colheita e a caça largam
## drops, e as duas cópias começaram logo a divergir.
static func spawn(world_node: Node, id: String, qty: int, at: Vector3,
		inv_ref: Node, player_node: Node) -> void:
	if world_node == null or qty <= 0:
		return
	var drop := DroppedItem.new()
	drop.item_id = id
	drop.amount = qty
	drop.inv = inv_ref
	drop.player_ref = player_node
	var angle := randf() * TAU
	drop.launch_direction = Vector3(cos(angle), 0.0, sin(angle))
	world_node.add_child(drop)
	drop.global_position = at + Vector3(0.0, 0.42, 0.0)


func _ready() -> void:
	name = "WorldPickup_" + item_id
	collision_layer = 0
	collision_mask = 1
	mass = 0.55
	linear_damp = 0.82
	angular_damp = 2.2
	can_sleep = true
	var physics_material := PhysicsMaterial.new()
	physics_material.friction = 0.88
	physics_material.bounce = 0.08
	physics_material_override = physics_material
	if is_instance_valid(player_ref) and player_ref is PhysicsBody3D:
		add_collision_exception_with(player_ref as PhysicsBody3D)
	var visual := Node3D.new()
	visual.name = "Display"
	add_child(visual)
	_display = visual
	var authored := _authored_model()
	if authored != null:
		visual.scale = Vector3.ONE * (0.36 if item_id == "wood" else 0.48)
		visual.add_child(authored)
	else:
		var mi := MeshInstance3D.new()
		mi.name = "ItemMesh"
		mi.mesh = _item_mesh()
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 0.9
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.22
	cs.shape = sh
	add_child(cs)
	_label = Label3D.new()
	_label.name = "StackLabel"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 15
	_label.outline_size = 4
	_label.modulate = Color("fff3d6")
	_label.outline_modulate = Color(0.06, 0.07, 0.09, 0.85)
	_label.position = Vector3(0.0, 0.34, 0.0)
	_label.visible = amount > 1
	_label.text = "%s ×%d" % [Db.item_name(item_id), amount]
	_label.visibility_range_end = 14.0
	visual.add_child(_label)
	if launch_direction.length_squared() < 0.01:
		launch_direction = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	linear_velocity = launch_direction.normalized() * randf_range(0.9, 1.6) + Vector3.UP * randf_range(1.3, 2.0)
	angular_velocity = Vector3(randf_range(-2.5, 2.5), randf_range(-2.5, 2.5), randf_range(-2.5, 2.5))


func _authored_model() -> Node3D:
	var asset_id := ""
	match item_id:
		"wood": asset_id = "pickup_log"
		"leaf": asset_id = "pickup_leaf"
	if asset_id.is_empty():
		return null
	var packed := BlessedBlenderAssets.scene_for(asset_id)
	if packed == null:
		return null
	var model := packed.instantiate() as Node3D
	if model != null:
		model.name = "BlenderPickup_" + item_id
	return model


func _physics_process(delta: float) -> void:
	_age += delta
	_attempt_t = maxf(0.0, _attempt_t - delta)
	_bob_t += delta
	var player_node := player_ref as Node3D if is_instance_valid(player_ref) else null

	# 1) assentar: para de rolar e passa a girar devagar no sítio onde parou
	if not _frozen and _age > SETTLE_TIME:
		_settle()

	# 2) água: o item flutua até à superfície (antes afundava-se e desaparecia)
	var world := get_parent()
	if world != null and world.has_method("water_surface_height"):
		var surface := float(world.call("water_surface_height",
			global_position.x, global_position.z))
		if surface > -99999.0 and global_position.y < surface - 0.1:
			if _frozen:
				global_position.y = lerpf(global_position.y, surface - 0.06,
					1.0 - exp(-3.5 * delta))
				# A corrente leva o que se larga no rio. É lenta de propósito:
				# o jogador vê o item a descer e ainda o apanha.
				if world.has_method("water_sample"):
					var ws: Dictionary = world.call("water_sample",
						global_position.x, global_position.z)
					if not ws.is_empty():
						var flow: Vector2 = ws.get("flow", Vector2.ZERO)
						var spd := clampf(float(ws.get("speed", 0.0)), 0.0, 3.4)
						global_position.x += flow.x * spd * 0.22 * delta
						global_position.z += flow.y * spd * 0.22 * delta
			else:
				gravity_scale = -0.55      # empurra para cima enquanto não assenta
		elif gravity_scale < 0.0:
			gravity_scale = 1.0

	# 3) girar/bobinar: o item lê-se como "apanha-me"
	if is_instance_valid(_display):
		if _frozen:
			_display.rotation.y += 1.1 * delta
		var bob := 0.05 + sin(_bob_t * 2.3) * 0.035 if _frozen else 0.0
		_display.position.y = lerpf(_display.position.y, bob, 1.0 - exp(-8.0 * delta))

	# 4) íman + recolha
	if player_node != null and _age > 0.25 and _attempt_t <= 0.0:
		var chest := player_node.global_position + Vector3(0.0, 0.9, 0.0)
		var to_player := chest - global_position
		var dist := to_player.length()
		if dist < MAGNET_DISTANCE and dist > 0.02:
			var pull := to_player.normalized() * (3.0 + (MAGNET_DISTANCE - dist) * 3.2) * delta
			if _frozen or _age > VACUUM_TIME:
				# Sem física pelo meio: o item é aspirado. `global_position` num
				# RigidBody congelado é seguro; num corpo ainda livre é o que dá
				# a sensação de íman em vez de "empurrão".
				global_position += pull * 1.8
			else:
				linear_velocity = linear_velocity.lerp(to_player.normalized() * 5.5, 0.35)
	if player_node != null and _age >= 0.30 and _attempt_t <= 0.0:
		var horizontal := Vector2(global_position.x - player_node.global_position.x,
			global_position.z - player_node.global_position.z).length()
		if horizontal <= PICKUP_DISTANCE \
			and absf(global_position.y - player_node.global_position.y) <= MAX_PICKUP_HEIGHT:
			_try_pickup()


## Deixa de obedecer à física e passa a item de chão.
func _settle() -> void:
	_frozen = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	if is_instance_valid(_display):
		_display.rotation = Vector3.ZERO


func _try_pickup() -> void:
	if inv == null or item_id.is_empty() or amount <= 0:
		return
	_attempt_t = 0.65
	var before := amount
	amount = int(inv.call("add", item_id, amount))
	var collected := before - amount
	if collected > 0:
		Game.bump("item_" + item_id, collected)
		Sfx.play("pick", -9.0, randf_range(0.94, 1.08))
	if amount <= 0:
		queue_free()
		return
	if is_instance_valid(_label):
		_label.text = "%s ×%d" % [Db.item_name(item_id), amount]
		_label.visible = amount > 1
	if collected == 0 and not _full_notice_sent:
		_full_notice_sent = true
		Bus.say("msg.bag_full", 2.0)


## Modelo do item no chão. Antes, tudo o que não fosse madeira/pedra/folha caía
## no `_` — um CUBO bege igual para uma picareta, uma cana e uma taça de sopa.
## Agora cada família tem forma e cor próprias: vê-se o que se está a apanhar.
func _item_mesh() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([item_id, amount, get_instance_id()])
	var def: Dictionary = Db.item(item_id)
	var action := str(def.get("power", {}).keys()[0]) if not def.get("power", {}).is_empty() else ""
	var tool_family := str(def.get("tool", ""))
	match item_id:
		"wood":
			return MeshKit.tapered(rng, 0.46, 0.105, 0.09, 9, 2, 0.08, true, Color("a97542"))
		"stick":
			return MeshKit.tapered(rng, 0.52, 0.042, 0.036, 6, 2, 0.0, false, Color("b08b5c"))
		"fiber":
			return _merge([
				MeshKit.box(Vector3(0.05, 0.4, 0.05), Color("8fae52")),
				_placed(MeshKit.box(Vector3(0.05, 0.36, 0.05), Color("7c9a46")), Vector3(0.08, 0.02, 0.03)),
				_placed(MeshKit.box(Vector3(0.05, 0.33, 0.05), Color("a3c165")), Vector3(-0.07, 0.01, -0.04)),
			])
		"leaf":
			return MeshKit.blob(rng, 0.19, 1, 0.2, Vector3(1.0, 0.28, 0.65), Color("72b95c"))
		"stone":
			return MeshKit.rock(rng, 0.26)
		"flint":
			return MeshKit.rock(rng, 0.21)
		"torch":
			return _merge([
				MeshKit.box(Vector3(0.075, 0.34, 0.075), Color("6d4a29")),
				_placed(MeshKit.blob(rng, 0.09, 1, 0.15, Vector3(1.0, 1.2, 1.0), Color("ff9d3d")),
					Vector3(0, 0.2, 0)),
			])
		# ── ferramentas: cabo + cabeça, viradas como as seguram as mãos ─────
		"stone_blade":
			# Ramo com a lasca amarrada: lê-se como ferramenta improvisada.
			return _merge([
				MeshKit.tapered(rng, 0.4, 0.035, 0.03, 6, 2, 0.0, false, Color("a97542")),
				MeshKit.box(Vector3(0.11, 0.17, 0.045), Color("9aa1a0")),
			])
		"fire_kit":
			# Duas pedras e um feixe de fibra.
			return _merge([
				MeshKit.box(Vector3(0.14, 0.08, 0.10), Color("8f8b84")),
				_placed(MeshKit.box(Vector3(0.12, 0.07, 0.09), Color("6f6a63")),
					Vector3(0.07, 0.07, 0.0)),
				_placed(MeshKit.box(Vector3(0.05, 0.05, 0.24), Color("c9a45e")),
					Vector3(-0.05, 0.02, 0.0)),
			])
		"primitive_pickaxe":
			return _merge([
				MeshKit.tapered(rng, 0.46, 0.035, 0.03, 6, 2, 0.0, false, Color("8a6136")),
				MeshKit.box(Vector3(0.26, 0.07, 0.07), Color("9aa1a0")),
			])
		"primitive_axe":
			return _merge([
				MeshKit.tapered(rng, 0.44, 0.036, 0.03, 6, 2, 0.0, false, Color("8a6136")),
				MeshKit.box(Vector3(0.13, 0.16, 0.05), Color("9aa1a0")),
			])
		"axe":
			var head := Color("c8d5d2")
			return _merge([
				MeshKit.tapered(rng, 0.5, 0.045, 0.04, 6, 2, 0.0, false, Color("8a6136")),
				_placed(MeshKit.box(Vector3(0.2, 0.15, 0.06), head), Vector3(0.0, 0.24, 0.06)),
			])
		"pickaxe":
			var tip := Color("c8d5d2")
			return _merge([
				MeshKit.tapered(rng, 0.5, 0.045, 0.04, 6, 2, 0.0, false, Color("8a6136")),
				_placed(MeshKit.box(Vector3(0.34, 0.07, 0.07), tip), Vector3(0.0, 0.24, 0.02)),
			])
		"rod":
			return _merge([
				MeshKit.tapered(rng, 0.62, 0.035, 0.022, 6, 2, 0.06, false, Color("8a6136")),
				_placed(MeshKit.box(Vector3(0.09, 0.09, 0.09), Color("9ed8d0")), Vector3(0.06, -0.3, 0.0)),
			])
		"bottle", "water":
			var liquid := Color("60b6d2") if item_id == "water" else Color("c5e6d7")
			return _merge([
				MeshKit.box(Vector3(0.11, 0.2, 0.11), Color("9ed8d0")),
				_placed(MeshKit.box(Vector3(0.09, 0.09, 0.09), liquid), Vector3(0, 0.08, 0)),
			])
		# ── comida: cada uma com a sua cor, para não serem todas "bolha" ────
		"mushroom":
			return _merge([
				MeshKit.box(Vector3(0.07, 0.16, 0.07), Color("f2e8d4")),
				_placed(MeshKit.blob(rng, 0.13, 1, 0.12, Vector3(1.0, 0.55, 1.0), Color("d96d56")),
					Vector3(0, 0.11, 0)),
			])
		"fish_raw", "fish_cooked":
			var fish := Color("b95d49") if item_id == "fish_cooked" else Color("d98078")
			return _merge([
				MeshKit.blob(rng, 0.17, 1, 0.18, Vector3(1.5, 0.7, 0.6), fish),
				_placed(MeshKit.box(Vector3(0.12, 0.09, 0.03), Color("60b6d2")), Vector3(0.2, 0, 0)),
			])
		"meat_raw", "meat_cooked":
			return MeshKit.blob(rng, 0.19, 1, 0.22, Vector3(1.2, 0.75, 1.0),
				Color("b95d49") if item_id == "meat_cooked" else Color("c96a70"))
		"stew":
			return _merge([
				MeshKit.box(Vector3(0.3, 0.08, 0.3), Color("8a5f38")),
				_placed(MeshKit.box(Vector3(0.24, 0.12, 0.24), Color("c98a4b")), Vector3(0, 0.06, 0)),
			])
		"campfire":
			return MeshKit.box(Vector3(0.34, 0.16, 0.34), Color("8c6a49"))
		"workbench":
			return _merge([
				MeshKit.box(Vector3(0.42, 0.07, 0.26), Color("a97542")),
				_placed(MeshKit.box(Vector3(0.05, 0.24, 0.05), Color("8a5f38")), Vector3(-0.15, -0.15, 0)),
				_placed(MeshKit.box(Vector3(0.05, 0.24, 0.05), Color("8a5f38")), Vector3(0.15, -0.15, 0)),
			])
		"wall", "floor", "pillar", "bed":
			return MeshKit.box(Vector3(0.3, 0.16, 0.3),
				Color("3f7a4a") if item_id == "bed" else Color("a97542"))
	# ferramenta sem caso próprio: cabo + cabeça genéricos na cor do item
	if tool_family == "axe" or action == "chop":
		return _merge([
			MeshKit.tapered(rng, 0.5, 0.045, 0.04, 6, 2, 0.0, false, Color("8a6136")),
			_placed(MeshKit.box(Vector3(0.2, 0.15, 0.06), Color("c8d5d2")), Vector3(0.0, 0.24, 0.06)),
		])
	if tool_family == "pickaxe" or action == "mine":
		return _merge([
			MeshKit.tapered(rng, 0.5, 0.045, 0.04, 6, 2, 0.0, false, Color("8a6136")),
			_placed(MeshKit.box(Vector3(0.34, 0.07, 0.07), Color("c8d5d2")), Vector3(0.0, 0.24, 0.02)),
		])
	if str(def.get("kind", "")) == "food":
		return MeshKit.blob(rng, 0.17, 1, 0.2, Vector3(1.1, 0.8, 1.0), Color("d0a06a"))
	if str(def.get("kind", "")) == "structure":
		return MeshKit.box(Vector3(0.28, 0.22, 0.28), Color("a97542"))
	return MeshKit.rock(rng, 0.18)


## Junta malhas num só ArrayMesh (menos um nó por item no chão).
func _merge(parts: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for m in parts:
		st.append_from(m, 0, Transform3D.IDENTITY)
	return st.commit()


## Cópia de uma malha deslocada (as malhas do MeshKit não são indexadas, por
## isso `append_from` com transformação é o caminho certo — reconstruir a
## superfície à mão perde cores e normais).
func _placed(mesh: ArrayMesh, off: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(mesh, 0, Transform3D(Basis.IDENTITY, off))
	return st.commit()
