extends Node3D
## Hands — braços e objeto em 1ª pessoa, feitos de caixas e animados à mão.
##
## Não há modelo nem animação importada: o braço é uma caixa afinada, a mão é
## uma caixa pequena, o objeto é a malha da espécie. O "peso" vem de uma mola
## que atrasa o braço em relação à câmara e de um balanço ligado aos passos.

var arm_r: Node3D
var arm_l: Node3D
var held: MeshInstance3D
var rng := RandomNumberGenerator.new()

var swing_t := -1.0
var swing_speed := 1.0
var bob_t := 0.0
var recoil := 0.0


func _ready() -> void:
	rng.seed = 99
	position = Vector3(0.19, -0.24, -0.42)
	arm_r = _make_arm(Color(0.93, 0.78, 0.68), Vector3(0.075, 0.075, 0.42))
	arm_r.position = Vector3(0, 0, 0)
	arm_r.rotation_degrees = Vector3(-8, 6, 0)
	add_child(arm_r)
	arm_l = _make_arm(Color(0.90, 0.75, 0.65), Vector3(0.07, 0.07, 0.38))
	arm_l.position = Vector3(-0.30, -0.02, -0.05)
	arm_l.rotation_degrees = Vector3(-6, -8, 0)
	arm_l.visible = false
	add_child(arm_l)
	held = MeshInstance3D.new()
	held.position = Vector3(0.03, -0.06, -0.44)
	arm_r.add_child(held)


func _make_arm(tint: Color, size: Vector3) -> Node3D:
	var n := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.box(size, tint)
	mi.position = Vector3(0, 0, -size.z * 0.5)
	n.add_child(mi)
	var hand := MeshInstance3D.new()
	hand.mesh = MeshKit.box(Vector3(size.x * 1.15, size.y * 1.1, size.x * 1.2), tint.lightened(0.05))
	hand.position = Vector3(0, 0, -size.z * 1.02)
	n.add_child(hand)
	return n


## Põe na mão a malha do item (ou esvazia).
func set_held(mesh: ArrayMesh, mat: Material = null) -> void:
	held.mesh = mesh
	held.material_override = mat
	held.visible = mesh != null
	arm_l.visible = mesh != null


func swing(duration: float = 0.34) -> void:
	swing_t = 0.0
	swing_speed = 1.0 / maxf(duration, 0.05)
	recoil = 1.0


func recoil_kick(amount: float = 0.25) -> void:
	recoil = maxf(recoil, amount)


func _process(delta: float) -> void:
	# mola de respiração + balanço dos passos
	bob_t += delta * 1.6
	var breathe := sin(bob_t) * 0.006
	var sway := Vector3(sin(bob_t * 0.8) * 0.008, breathe, cos(bob_t * 0.6) * 0.006)
	if swing_t >= 0.0:
		swing_t += delta * swing_speed
		if swing_t > 1.0:
			swing_t = -1.0
	var s := swing_t
	var arc := 0.0
	if s >= 0.0:
		# curva de balanço: sobe rápido, desce com peso
		arc = sin(clampf(s, 0.0, 1.0) * PI)
	arm_r.position = Vector3(0, 0, 0) + sway + Vector3(0, -arc * 0.10, arc * 0.13)
	arm_r.rotation_degrees = Vector3(-8 - arc * 55.0, 6 + arc * 8.0, arc * 6.0)
	arm_l.position = Vector3(-0.30, -0.02, -0.05) + sway * 0.7 \
		+ Vector3(0, -arc * 0.03, arc * 0.05)
	arm_l.rotation_degrees = Vector3(-6 - arc * 14.0, -8, 0)
	recoil = maxf(0.0, recoil - delta * 3.0)
	position.z = -0.42 + recoil * 0.04
