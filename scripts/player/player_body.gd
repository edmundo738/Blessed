class_name PlayerBody
extends Node3D
## Corpo 3D do jogador, montado em código e animado por procedimento.
##
## O projeto nasceu com um avatar 2D billboard porque não havia pipeline de
## modelos. Em terceira pessoa isso lia-se como um cartaz: o corpo não virava
## com o terreno, as pernas não davam passada e a câmara não tinha com que se
## relacionar. Este corpo resolve três coisas ao mesmo tempo:
##
##   1. SILHUETA — túnica, cinto, capa curta, cabelo e botas dão uma leitura
##      de personagem a 4 m, que é a distância da câmara externa.
##   2. PESO — a bacia desce ao agachar, as pernas abrem a passada, os braços
##      contradizem as pernas e o tronco inclina-se na corrida.
##   3. ESTADO — estar no chão, nadar, saltar e golpear têm poses diferentes.
##      O jogador não precisa de texto para saber o que o corpo está a fazer.
##
## Não há skin/ossos: cada membro é um Node3D com uma malha rígida. Para o
## estilo toon de poucos polígonos isto chega, e não custa um import nem uma
## animação por ficheiro. `Player` chama `update_pose()` todos os frames de
## física; a interpolação visual acontece aqui, em `_process`.

const WALK_SPEED := 4.0

var _root: Node3D
var _hips: Node3D
var _torso: Node3D
var _head: Node3D
var _cape: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _knee_l: Node3D
var _knee_r: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _elbow_l: Node3D
var _elbow_r: Node3D
var _mat: ShaderMaterial

var _spd := 0.0
var _phase := 0.0
var _move := 0.0
var _grounded := true
var _crouch := false
var _swim := false
var _pitch := 0.0
var _attack_t := -1.0
var _hurt_t := 0.0
var _breath := 0.0
var _land_dip := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	name = "Body3D"
	_rng.seed = 70421
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/toon_character.gdshader")
	_mat.set_shader_parameter("shadow_tint", Color(0.48, 0.52, 0.82))
	_mat.set_shader_parameter("bands", 3.0)
	_mat.set_shader_parameter("rim_strength", 0.32)
	_build()
	set_visible(false)


# ── paleta ─────────────────────────────────────────────────────────────────
func _pick_color(index: Variant, palette: Array[Color]) -> Color:
	return palette[posmod(int(index), palette.size())]


func _palette() -> Dictionary:
	var profile: Dictionary = Game.profile
	var appearance: Dictionary = profile.get("appearance", {})
	var skin := _pick_color(appearance.get("skin", 0),
		[Color("#f1c7a2"), Color("#d89b72"), Color("#8e5b43")])
	var cloth := _pick_color(appearance.get("cloth", 0),
		[Color("#527c78"), Color("#8a536d"), Color("#9b7644"), Color("#52678d")])
	var hair := _pick_color(appearance.get("hair", 0),
		[Color("#302b3c"), Color("#754a38"), Color("#d0a65e"), Color("#52604b")])
	return {
		"skin": skin,
		"cloth": cloth,
		"cloth_dark": cloth.darkened(0.24),
		"cloth_light": cloth.lightened(0.18),
		"hair": hair,
		"hair_light": hair.lightened(0.18),
		"leather": Color("#5a4333"),
		"leather_light": Color("#8a6844"),
		"metal": Color("#c8c9bd"),
		"ink": Color("#252330"),
	}


# ── construção ─────────────────────────────────────────────────────────────
func _build() -> void:
	var c := _palette()
	_root = Node3D.new()
	_root.name = "BodyRoot"
	_root.position = Vector3(0.0, 0.90, 0.0)
	add_child(_root)

	_hips = Node3D.new()
	_hips.name = "Hips"
	_root.add_child(_hips)

	# Bacia e túnica: uma peça larga em baixo, estreita em cima. É o que faz a
	# silhueta ler como roupa e não como uma cápsula.
	_add_mesh(_hips, MeshKit.tapered(_rng, 0.32, 0.215, 0.16, 8, 2, 0.01,
		true, c["cloth_dark"]), Vector3(0, -0.18, 0))
	_add_mesh(_hips, MeshKit.box(Vector3(0.37, 0.065, 0.245), c["leather"]),
		Vector3(0, 0.055, 0))
	_add_mesh(_hips, MeshKit.box(Vector3(0.075, 0.085, 0.02), c["metal"]),
		Vector3(0, 0.055, -0.128))

	_torso = Node3D.new()
	_torso.name = "Torso"
	_torso.position = Vector3(0, 0.03, 0)
	_hips.add_child(_torso)
	# Peito: tronco cónico, ombros mais largos que a cintura.
	_add_mesh(_torso, MeshKit.tapered(_rng, 0.50, 0.16, 0.205, 8, 3, 0.015,
		true, c["cloth"]), Vector3(0, 0, 0))
	# Gola e cordão: a marca de identidade que o avatar 2D tinha.
	_add_mesh(_torso, MeshKit.box(Vector3(0.24, 0.045, 0.20), c["cloth_light"]),
		Vector3(0, 0.47, -0.01))
	_add_mesh(_torso, MeshKit.box(Vector3(0.045, 0.13, 0.018), Color("#e8cf86")),
		Vector3(0, 0.35, -0.185))
	_add_mesh(_torso, MeshKit.box(Vector3(0.085, 0.035, 0.022), Color("#f7e6ab")),
		Vector3(0, 0.29, -0.19))

	# Capa curta: dá movimento nas costas e separa o personagem do cenário.
	_cape = Node3D.new()
	_cape.name = "Cape"
	_cape.position = Vector3(0, 0.43, 0.10)
	_torso.add_child(_cape)
	_add_mesh(_cape, MeshKit.box(Vector3(0.44, 0.56, 0.035), c["cloth_dark"]),
		Vector3(0, -0.28, 0.012))

	# Cabeça. A cara é minúscula a 4 m; o que se lê é o cabelo, as orelhas e o
	# queixo. Os olhos existem para a vista frontal e para o retrato do menu.
	_head = Node3D.new()
	_head.name = "Head"
	_head.position = Vector3(0, 0.57, 0)
	_torso.add_child(_head)
	_add_mesh(_head, MeshKit.blob(_rng, 0.155, 2, 0.045,
		Vector3(0.95, 1.12, 0.92), c["skin"]), Vector3(0, 0.10, 0))
	_add_mesh(_head, MeshKit.blob(_rng, 0.165, 2, 0.10,
		Vector3(1.00, 0.56, 1.00), c["hair"]), Vector3(0, 0.225, 0.012))
	_add_mesh(_head, MeshKit.blob(_rng, 0.12, 1, 0.14,
		Vector3(0.85, 1.05, 0.72), c["hair"]), Vector3(0, 0.10, 0.105))
	if str(Game.profile.get("body", "f")) == "f":
		_add_mesh(_head, MeshKit.blob(_rng, 0.075, 1, 0.12,
			Vector3(0.55, 1.55, 0.55), c["hair"]), Vector3(0, -0.02, 0.17))
		_add_mesh(_head, MeshKit.box(Vector3(0.035, 0.13, 0.035), c["hair_light"]),
			Vector3(-0.14, 0.03, 0.02))
		_add_mesh(_head, MeshKit.box(Vector3(0.035, 0.13, 0.035), c["hair_light"]),
			Vector3(0.14, 0.03, 0.02))
	for side in [-1.0, 1.0]:
		_add_mesh(_head, MeshKit.blob(_rng, 0.023, 1, 0.0,
			Vector3(1.0, 0.86, 0.55), c["ink"]),
			Vector3(0.053 * float(side), 0.095, -0.135))
		_add_mesh(_head, MeshKit.blob(_rng, 0.045, 1, 0.08,
			Vector3(0.55, 1.0, 0.45), c["skin"].darkened(0.04)),
			Vector3(0.155 * float(side), 0.09, 0.005))

	# Braços: ombro → cotovelo → mão. A malha aponta para +Y e o pivô roda em X
	# para pendurar; assim a rotação da marcha é a rotação real do ombro.
	for side in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.name = "ArmL" if side < 0.0 else "ArmR"
		arm.position = Vector3(0.215 * float(side), 0.44, 0.0)
		_torso.add_child(arm)
		_add_mesh(arm, MeshKit.tapered(_rng, 0.30, 0.070, 0.052, 7, 2, 0.0,
			false, c["cloth"]), Vector3(0, 0, 0), Vector3(PI, 0, 0))
		var elbow := Node3D.new()
		elbow.name = "Elbow"
		elbow.position = Vector3(0, -0.29, 0)
		arm.add_child(elbow)
		_add_mesh(elbow, MeshKit.tapered(_rng, 0.27, 0.052, 0.040, 7, 2, 0.0,
			false, c["skin"]), Vector3(0, 0, 0), Vector3(PI, 0, 0))
		_add_mesh(elbow, MeshKit.blob(_rng, 0.060, 1, 0.10,
			Vector3(0.85, 1.10, 0.65), c["skin"]), Vector3(0, -0.30, 0))
		if side < 0.0:
			_arm_l = arm
			_elbow_l = elbow
		else:
			_arm_r = arm
			_elbow_r = elbow

	# Pernas: coxa → joelho → bota. O pé não tem ossos: é uma bota rígida.
	for side in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.name = "LegL" if side < 0.0 else "LegR"
		leg.position = Vector3(0.105 * float(side), -0.02, 0.0)
		_hips.add_child(leg)
		_add_mesh(leg, MeshKit.tapered(_rng, 0.42, 0.090, 0.070, 7, 2, 0.01,
			false, c["cloth_dark"]), Vector3(0, 0, 0), Vector3(PI, 0, 0))
		var knee := Node3D.new()
		knee.name = "Knee"
		knee.position = Vector3(0, -0.41, 0)
		leg.add_child(knee)
		_add_mesh(knee, MeshKit.tapered(_rng, 0.38, 0.070, 0.055, 7, 2, 0.0,
			false, c["cloth_dark"]), Vector3(0, 0, 0), Vector3(PI, 0, 0))
		_add_mesh(knee, MeshKit.box(Vector3(0.13, 0.13, 0.22), c["leather"]),
			Vector3(0, -0.44, -0.025))
		_add_mesh(knee, MeshKit.box(Vector3(0.14, 0.045, 0.24), c["leather_light"]),
			Vector3(0, -0.51, -0.025))
		if side < 0.0:
			_leg_l = leg
			_knee_l = knee
		else:
			_leg_r = leg
			_knee_r = knee


func _add_mesh(parent: Node3D, mesh: ArrayMesh, offset: Vector3,
		rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat
	mi.position = offset
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi


# ── estado vindo do Player ─────────────────────────────────────────────────
func update_pose(velocity: Vector3, grounded: bool, crouching: bool,
		swimming: bool, pitch: float) -> void:
	_spd = Vector2(velocity.x, velocity.z).length()
	_grounded = grounded
	_crouch = crouching
	_swim = swimming
	_pitch = pitch


func attack() -> void:
	_attack_t = 0.0


func hurt() -> void:
	_hurt_t = 0.32


func land(force: float) -> void:
	_land_dip = clampf(force, 0.0, 1.0) * 0.10


func _process(delta: float) -> void:
	if not visible:
		return
	_breath += delta
	_attack_t = _attack_t + delta if _attack_t >= 0.0 else -1.0
	if _attack_t > 0.55:
		_attack_t = -1.0
	_hurt_t = maxf(0.0, _hurt_t - delta)
	_land_dip = lerpf(_land_dip, 0.0, 1.0 - exp(-8.0 * delta))

	var moving := _spd > 0.25 and _grounded and not _swim
	_move = lerpf(_move, clampf(_spd / WALK_SPEED, 0.0, 1.55) if moving else 0.0,
		1.0 - exp(-9.0 * delta))
	if moving:
		_phase += delta * (5.7 + _spd * 1.55)
	else:
		_phase = lerpf(_phase, roundf(_phase / PI) * PI, 1.0 - exp(-5.0 * delta))

	var gait := sin(_phase) * 0.62 * _move
	var bounce := absf(sin(_phase)) * 0.035 * _move
	var breathe := sin(_breath * 1.7) * 0.006

	# Agachar: a bacia desce e os joelhos dobram; não é só a câmara.
	var hip_y := 0.90 - (0.24 if _crouch else 0.0) + bounce - _land_dip
	if _swim:
		hip_y = 0.63 + sin(_breath * 2.1) * 0.02
	_root.position.y = lerpf(_root.position.y, hip_y, 1.0 - exp(-14.0 * delta))
	_root.rotation.x = lerpf(_root.rotation.x,
		-1.18 if _swim else (breathe * 0.35), 1.0 - exp(-7.0 * delta))
	_torso.rotation.x = lerpf(_torso.rotation.x,
		(-0.10 if _crouch else 0.0) + (0.10 * _move if _grounded else -0.06),
		1.0 - exp(-8.0 * delta))
	_torso.rotation.y = sin(_phase) * 0.055 * _move
	_torso.rotation.z = sin(_phase * 0.5) * 0.035 * _move

	if _swim:
		_leg_l.rotation.x = sin(_phase * 0.8) * 0.24
		_leg_r.rotation.x = sin(_phase * 0.8 + 1.5) * 0.24
		_knee_l.rotation.x = 0.18
		_knee_r.rotation.x = 0.18
		_arm_l.rotation.x = -0.55 + sin(_phase * 1.4) * 0.85
		_arm_r.rotation.x = -0.55 + sin(_phase * 1.4 + PI) * 0.85
		_arm_l.rotation.z = 0.30
		_arm_r.rotation.z = -0.30
		_elbow_l.rotation.x = -0.28
		_elbow_r.rotation.x = -0.28
	elif not _grounded:
		_leg_l.rotation.x = lerpf(_leg_l.rotation.x, 0.34, 1.0 - exp(-8.0 * delta))
		_leg_r.rotation.x = lerpf(_leg_r.rotation.x, -0.22, 1.0 - exp(-8.0 * delta))
		_knee_l.rotation.x = lerpf(_knee_l.rotation.x, 0.62, 1.0 - exp(-8.0 * delta))
		_knee_r.rotation.x = lerpf(_knee_r.rotation.x, 0.18, 1.0 - exp(-8.0 * delta))
		_arm_l.rotation.x = lerpf(_arm_l.rotation.x, -0.55, 1.0 - exp(-7.0 * delta))
		_arm_r.rotation.x = lerpf(_arm_r.rotation.x, -0.55, 1.0 - exp(-7.0 * delta))
		_arm_l.rotation.z = 0.24
		_arm_r.rotation.z = -0.24
		_elbow_l.rotation.x = -0.45
		_elbow_r.rotation.x = -0.45
	else:
		_leg_l.rotation.x = gait
		_leg_r.rotation.x = -gait
		# Joelho dobra na fase de balanço (o pé levanta), não em simultâneo.
		_knee_l.rotation.x = maxf(0.0, -gait) * 0.95 + (0.14 if _crouch else 0.0)
		_knee_r.rotation.x = maxf(0.0, gait) * 0.95 + (0.14 if _crouch else 0.0)
		_arm_l.rotation.x = -gait * 0.82
		_arm_r.rotation.x = gait * 0.82
		_arm_l.rotation.z = 0.10
		_arm_r.rotation.z = -0.10
		_elbow_l.rotation.x = -0.16 - maxf(0.0, gait) * 0.28
		_elbow_r.rotation.x = -0.16 - maxf(0.0, -gait) * 0.28

	# Golpe: o braço direito sobe, corta e volta; o tronco acompanha.
	if _attack_t >= 0.0:
		var t := clampf(_attack_t / 0.55, 0.0, 1.0)
		var arc := sin(t * PI)
		var wind := sin(minf(t * 1.8, 1.0) * PI)
		_arm_r.rotation.x = -0.9 * wind + 2.1 * arc
		_arm_r.rotation.z = -0.35 * arc
		_elbow_r.rotation.x = -0.15 - 1.1 * arc
		_torso.rotation.y += -0.20 * arc
		_torso.rotation.x += 0.10 * arc

	# Cabeça: olha para onde a câmara aponta (pitch), e para o lado no idle.
	_head.rotation.x = lerpf(_head.rotation.x, clampf(_pitch * 0.55, -0.45, 0.4),
		1.0 - exp(-9.0 * delta))
	_head.rotation.y = sin(_breath * 0.53) * 0.045
	_cape.rotation.x = lerpf(_cape.rotation.x,
		-0.12 - _move * 0.18 + sin(_phase) * 0.05 * _move,
		1.0 - exp(-6.0 * delta))

	# Dano: um solavanco curto, não uma animação inteira.
	if _hurt_t > 0.0:
		_torso.rotation.z += sin(_hurt_t * 38.0) * 0.09 * (_hurt_t / 0.32)


func set_body_visible(value: bool) -> void:
	visible = value
