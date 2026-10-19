class_name FelledTree
extends AnimatableBody3D
## Árvore abatida: cai, fica deitada no chão como obstáculo e entrega cada toro
## por F.
##
## A queda é conduzida AQUI, em `_physics_process`, e não por um `Tween`:
## um tween de 0,82 s dependia do relógio e do modo de processamento, e na
## prática a árvore "encostava um pouco e ficava parada" enquanto o jogo já a
## dava como caída. Com tempo explícito, a queda tem:
##   • aceleração (gira como uma coisa pesada, não linearmente)
##   • impacto: som, terra/folhas no chão e o tronco a assentar
##   • consequência: quem estiver debaixo do arco leva com ele

const FALL_TIME := 1.05
const FALL_ANGLE := 1.53      # ~88°: deitada, não encostada
const GROUND_SINK := 0.06     # assenta ligeiramente no terreno

var world_owner: Node
var record_key := ""
var species_id := ""
var height := 6.0
var trunk_radius := 0.24
var fall_direction := 1.0
var remaining_logs := 0
var settled := false
var _tree_mesh: MeshInstance3D
var _trunk_collider: CollisionShape3D
var _fall_t := -1.0
var _fall_start_y := 0.0
var _base_x := 0.0
var _damage_radius := 0.0
var _player: Node3D


func configure(mesh: ArrayMesh, material: Material, local_transform: Transform3D,
		full_height: float, radius: float, logs: int, owner: Node,
		key: String, tree_id: String, direction: float) -> void:
	_tree_mesh = get_node("TreeMesh") as MeshInstance3D
	_trunk_collider = get_node("TrunkCollider") as CollisionShape3D
	_tree_mesh.mesh = mesh
	_tree_mesh.material_override = material
	_tree_mesh.transform = local_transform
	height = maxf(full_height, 1.0)
	trunk_radius = maxf(radius, 0.14)
	remaining_logs = maxi(logs, 1)
	world_owner = owner
	record_key = key
	species_id = tree_id
	fall_direction = direction
	# O colisor é um filho: gira com o tronco, por isso basta pô-lo ao longo do
	# eixo do tronco e ele acompanha a queda até ficar deitado.
	var capsule := CapsuleShape3D.new()
	capsule.radius = trunk_radius
	capsule.height = maxf(height * 0.92, trunk_radius * 2.0)
	_trunk_collider.shape = capsule
	_trunk_collider.position = Vector3(0.0, capsule.height * 0.47, 0.0)
	_damage_radius = capsule.height
	_base_x = position.x
	add_to_group("fellable_logs")


func begin_fall() -> void:
	if settled or _fall_t >= 0.0:
		return
	_fall_t = 0.0
	_fall_start_y = position.y
	_player = _find_player()
	Sfx.play_at("chop", global_position + Vector3(0, 1.0, 0), -2.0, 0.62)


## Já deitada (veio de um save): coloca a rotação final e ficou.
func apply_settled(angle: float, offset_x: float) -> void:
	settled = true
	_fall_t = -1.0
	rotation.z = angle
	position.x = open_x(offset_x)
	_rest_on_ground()


func open_x(offset_x: float) -> float:
	return _base_x + offset_x


func _physics_process(delta: float) -> void:
	if _fall_t < 0.0:
		return
	_fall_t += delta
	var t := clampf(_fall_t / FALL_TIME, 0.0, 1.0)
	# aceleração: começa devagar (a madeira estala antes de ceder) e termina com
	# o peso todo em cima
	var e := t * t
	rotation.z = -fall_direction * FALL_ANGLE * e
	position.x = _base_x + fall_direction * 0.28 * e
	# à medida que se deita, o eixo do tronco tem de sair do chão (senão metade
	# dele desaparece debaixo da terra)
	position.y = _fall_start_y + trunk_radius * e * (1.0 - GROUND_SINK)
	if t >= 1.0:
		_fall_t = -1.0
		_on_impact()


func _on_impact() -> void:
	settled = true
	_rest_on_ground()
	Sfx.play_at("chop", global_position + Vector3(fall_direction * 2.0, 0.4, 0), -1.0, 0.5)
	Sfx.play_at("step_wood", global_position + Vector3(fall_direction * 2.5, 0.3, 0), -4.0, 0.8)
	var raio := maxf(height * 0.45, 1.5)
	var impacto := global_position + Vector3(fall_direction * raio, 0.3, 0)
	var fx := _find_fx()
	if fx != null and fx.has_method("burst"):
		fx.call("burst", impacto, Color(0.45, 0.36, 0.24), 22)
		fx.call("burst", impacto + Vector3(0, 0.6, 0), Color(0.42, 0.66, 0.34), 14)
	_damage_player_in_arc()
	if is_instance_valid(world_owner) and world_owner.has_method("felled_tree_settled"):
		world_owner.call("felled_tree_settled", record_key)


## Assenta a árvore deitada: o eixo do tronco fica à altura do seu raio.
func _rest_on_ground() -> void:
	position.y = _fall_start_y + trunk_radius * (1.0 - GROUND_SINK)


## Quem estiver no lado para onde a árvore cai e perto do chão leva com ela.
## É a decisão que a queda acrescenta: cortar e sair de baixo.
func _damage_player_in_arc() -> void:
	if not is_instance_valid(_player):
		return
	var p := _player.global_position - global_position
	if p.length() > _damage_radius + 1.2:
		return
	if absf(p.y) > 2.4:
		return
	# só o lado da queda (±70°) conta
	var lado := Vector3(fall_direction, 0.0, 0.0)
	var flat := Vector3(p.x, 0.0, p.z)
	if flat.length() < 0.05:
		return
	if flat.normalized().dot(lado) < 0.34:
		return
	var survival: Node = null
	for n in get_tree().get_nodes_in_group("survival"):
		survival = n
		break
	if survival == null and _player.has_method("get_parent"):
		survival = _player.get_parent().get_node_or_null("Survival")
	if survival != null and survival.has_method("damage"):
		survival.call("damage", 8.0, "fallen_tree")
		Sfx.play("scream", -12.0, 0.8)


func _find_player() -> Node3D:
	for n in get_tree().get_nodes_in_group("player"):
		return n as Node3D
	var pm: Node = get_tree().current_scene
	if pm != null and pm.get("player") != null:
		return pm.get("player") as Node3D
	return null


func _find_fx() -> Node:
	var pm: Node = get_tree().current_scene
	if pm != null and pm.get("fx") != null:
		return pm.get("fx") as Node
	return null


func interaction_target() -> Dictionary:
	if remaining_logs <= 0:
		return {}
	# O alvo é a MEIO do tronco deitado (não a 42% da altura de uma árvore de
	# pé): é onde o jogador está a olhar quando se aproxima para tirar toros.
	return {"kind": "felled_tree",
		"pos": global_position + Vector3(fall_direction * height * 0.35,
			trunk_radius + 0.22, 0.0)}


func take_log() -> bool:
	if remaining_logs <= 0:
		return false
	remaining_logs -= 1
	if is_instance_valid(world_owner) and world_owner.has_method("felled_tree_log_taken"):
		world_owner.call("felled_tree_log_taken", record_key, remaining_logs)
	if remaining_logs <= 0:
		_trunk_collider.set_deferred("disabled", true)
		queue_free()
	return true
