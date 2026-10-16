extends Node3D
## FX — efeitos curtos e baratos (lascas, salpicos, faíscas).
##
## Pool de partículas curto e multiplataforma. Cada impacto combina lascas
## sólidas com um brilho 2D suave; os emissores e materiais são reutilizados.

const POOL := 10

var _pool: Array[Node3D] = []
var _chip_mesh: BoxMesh
var _spark_mesh: QuadMesh
var _cpu_combo_mesh: ArrayMesh
var _use_gpu := true

const SPARK_TEXTURE_PATH := "res://content/fx/kenney/particles/star_02.png"


func _ready() -> void:
	name = "FX"
	_use_gpu = RenderingServer.get_current_rendering_method() != "gl_compatibility"
	_chip_mesh = BoxMesh.new()
	_chip_mesh.size = Vector3(0.055, 0.055, 0.055)
	var chip_material := StandardMaterial3D.new()
	chip_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	chip_material.vertex_color_use_as_albedo = true
	_chip_mesh.material = chip_material
	_spark_mesh = QuadMesh.new()
	_spark_mesh.size = Vector2(0.12, 0.12)
	var spark_material := StandardMaterial3D.new()
	spark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spark_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	spark_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	spark_material.albedo_texture = Assets.texture(SPARK_TEXTURE_PATH)
	spark_material.vertex_color_use_as_albedo = true
	_spark_mesh.material = spark_material
	_cpu_combo_mesh = _build_cpu_mesh()
	for i in POOL:
		var p: Variant = _new_emitter()
		p.amount = 14
		p.lifetime = 0.7
		p.one_shot = true
		p.explosiveness = 0.9
		p.local_coords = false
		if p is GPUParticles3D:
			p.draw_passes = 2
			p.draw_pass_1 = _chip_mesh
			p.draw_pass_2 = _spark_mesh
		p.emitting = false
		p.visible = false
		add_child(p)
		_pool.append(p)


func burst(pos: Vector3, color: Color, count: int = 14, spread: float = 1.0) -> void:
	var p: Variant = null
	for c in _pool:
		if not _is_emitting(c):
			p = c
			break
	if p == null:
		p = _pool[0]
	p.amount = clampi(count, 2, 28)
	if p is GPUParticles3D:
		var gpu := p as GPUParticles3D
		var mat := gpu.process_material as ParticleProcessMaterial
		mat.spread = 55.0 * spread
		mat.initial_velocity_min = 1.2
		mat.initial_velocity_max = 3.6
		mat.gravity = Vector3(0, -13, 0)
		mat.scale_min = 0.5
		mat.scale_max = 1.5
		mat.damping_min = 1.0
		mat.damping_max = 4.0
		mat.color = color
	else:
		var cpu := p as CPUParticles3D
		cpu.spread = 55.0 * spread
		cpu.initial_velocity_min = 1.2
		cpu.initial_velocity_max = 3.6
		cpu.gravity = Vector3(0, -13, 0)
		cpu.scale_amount_min = 0.5
		cpu.scale_amount_max = 1.5
		cpu.damping_min = 1.0
		cpu.damping_max = 4.0
		cpu.color = color
	p.global_position = pos
	p.visible = true
	p.restart()


func _new_emitter() -> Node3D:
	if _use_gpu:
		var gpu := GPUParticles3D.new()
		var material := ParticleProcessMaterial.new()
		material.direction = Vector3(0, 1, 0)
		material.spread = 60.0
		material.initial_velocity_min = 1.4
		material.initial_velocity_max = 3.4
		material.gravity = Vector3(0, -12, 0)
		material.scale_min = 0.6
		material.scale_max = 1.4
		material.damping_min = 1.0
		material.damping_max = 3.0
		material.color = Color.WHITE
		gpu.process_material = material
		gpu.draw_passes = 2
		gpu.draw_pass_1 = _chip_mesh
		gpu.draw_pass_2 = _spark_mesh
		return gpu
	var cpu := CPUParticles3D.new()
	cpu.direction = Vector3(0, 1, 0)
	cpu.spread = 60.0
	cpu.initial_velocity_min = 1.4
	cpu.initial_velocity_max = 3.4
	cpu.gravity = Vector3(0, -12, 0)
	cpu.scale_amount_min = 0.6
	cpu.scale_amount_max = 1.4
	cpu.damping_min = 1.0
	cpu.damping_max = 3.0
	cpu.color = Color.WHITE
	cpu.mesh = _cpu_combo_mesh
	return cpu


func _is_emitting(emitter: Node3D) -> bool:
	if emitter is GPUParticles3D:
		return (emitter as GPUParticles3D).emitting
	return (emitter as CPUParticles3D).emitting


func _build_cpu_mesh() -> ArrayMesh:
	# CPU particles accept one Mesh; keep the same chip + sparkle look as the GPU
	# path by packing the two meshes into separate ArrayMesh material surfaces.
	var chip_tool := SurfaceTool.new()
	chip_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	chip_tool.append_from(_chip_mesh, 0, Transform3D.IDENTITY)
	var combined := chip_tool.commit()
	if combined == null:
		return null
	combined.surface_set_material(0, _chip_mesh.material)
	var spark_tool := SurfaceTool.new()
	spark_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	spark_tool.append_from(_spark_mesh, 0, Transform3D.IDENTITY)
	var result := spark_tool.commit(combined)
	if result != null and result.get_surface_count() > 1:
		result.surface_set_material(1, _spark_mesh.material)
	return result
