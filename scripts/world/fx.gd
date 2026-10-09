extends Node3D
## FX — efeitos curtos e baratos (lascas, salpicos, faíscas).
##
## Um pool de GPUParticles3D reaproveitado: nada é criado durante o jogo, por
## isso não há soluços quando começas a cortar árvores.

const POOL := 10

var _pool: Array = []
var _mesh: BoxMesh
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	name = "FX"
	_rng.seed = 4242
	_mesh = BoxMesh.new()
	_mesh.size = Vector3(0.07, 0.07, 0.07)
	for i in POOL:
		var p := GPUParticles3D.new()
		var mat := ParticleProcessMaterial.new()
		mat.direction = Vector3(0, 1, 0)
		mat.spread = 60.0
		mat.initial_velocity_min = 1.4
		mat.initial_velocity_max = 3.4
		mat.gravity = Vector3(0, -12, 0)
		mat.scale_min = 0.6
		mat.scale_max = 1.4
		mat.damping_min = 1.0
		mat.damping_max = 3.0
		p.process_material = mat
		p.amount = 14
		p.lifetime = 0.7
		p.one_shot = true
		p.explosiveness = 0.9
		p.local_coords = false
		p.draw_pass_1 = _mesh
		p.emitting = false
		p.visible = false
		add_child(p)
		_pool.append(p)


func burst(pos: Vector3, color: Color, count: int = 14, spread: float = 1.0) -> void:
	var p: GPUParticles3D = null
	for c in _pool:
		if not (c as GPUParticles3D).emitting:
			p = c
			break
	if p == null:
		p = _pool[0]
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 55.0 * spread
	mat.initial_velocity_min = 1.2
	mat.initial_velocity_max = 3.6
	mat.gravity = Vector3(0, -13, 0)
	mat.scale_min = 0.5
	mat.scale_max = 1.5
	mat.damping_min = 1.0
	mat.damping_max = 4.0
	mat.color = color
	p.process_material = mat
	p.amount = clampi(count, 2, 40)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = color
	sm.vertex_color_use_as_albedo = false
	p.draw_pass_1 = _mesh
	p.material_override = sm
	p.global_position = pos
	p.visible = true
	p.restart()
