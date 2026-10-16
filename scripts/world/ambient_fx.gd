extends Node3D
## Ambiente — partículas suspensas que dão vida ao mundo:
##   • poeira/pólen a flutuar (dia e noite, subtil);
##   • pirilampos (só à noite).
##
## Usa CPUParticles3D de propósito: funciona em TODOS os renderers (Forward+,
## Mobile e Compatibility — ao contrário de GPUParticles3D, que o Compatibility
## não suporta) e, para contagens baixas, o custo de CPU é irrelevante.
## A densidade e o ligar/desligar dependem do perfil de qualidade (Game.settings["quality"]).
## Segue o jogador para haver sempre partículas à volta da câmara.

var player: Node3D

var dust: CPUParticles3D
var flies: CPUParticles3D

const DUST_SPRITE_PATH := "res://content/fx/kenney/particles/smoke_02.png"
const FIREFLY_SPRITE_PATH := "res://content/fx/kenney/particles/star_02.png"


func _ready() -> void:
	name = "AmbientFx"
	dust = _make_dust()
	add_child(dust)
	flies = _make_flies()
	add_child(flies)
	_apply_quality()
	if not Bus.settings_changed.is_connected(_apply_quality):
		Bus.settings_changed.connect(_apply_quality)


func _process(_delta: float) -> void:
	if player != null:
		global_position = player.global_position
	if flies != null:
		flies.emitting = _night_factor() > 0.15


## 0 = dia cheio, 1 = noite fechada (transição suave ao anoitecer/amanhecer).
func _night_factor() -> float:
	var h: float = Game.hour
	if h >= 20.0 or h <= 5.0:
		return 1.0
	if h > 18.0:
		return clampf((h - 18.0) / 2.0, 0.0, 1.0)
	if h < 7.0:
		return clampf((7.0 - h) / 2.0, 0.0, 1.0)
	return 0.0


func _apply_quality() -> void:
	var q: int = clampi(int(Game.settings.get("quality", 1)), 0, 2)
	if dust != null:
		dust.amount = [0, 90, 180][q]
		dust.emitting = q >= 1
	if flies != null:
		flies.amount = [0, 22, 46][q]


func _make_dust() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 120
	p.lifetime = 7.0
	p.preprocess = 4.0
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(13.0, 4.5, 13.0)
	p.direction = Vector3(0.25, 0.05, 0.15)
	p.spread = 45.0
	p.gravity = Vector3(0, -0.04, 0)
	p.initial_velocity_min = 0.04
	p.initial_velocity_max = 0.22
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.3
	p.mesh = _billboard_quad(Vector2(0.20, 0.20), Color(0.86, 0.82, 0.70, 0.20), Assets.texture(DUST_SPRITE_PATH))
	p.color = Color(1, 1, 1, 1)
	return p


func _make_flies() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 32
	p.lifetime = 5.5
	p.preprocess = 2.0
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(16.0, 1.6, 16.0)
	p.direction = Vector3(0, 1, 0)
	p.spread = 90.0
	p.gravity = Vector3(0, 0.12, 0)
	p.initial_velocity_min = 0.10
	p.initial_velocity_max = 0.45
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.1
	p.mesh = _billboard_quad(Vector2(0.105, 0.105), Color(1.65, 1.45, 0.62, 0.88), Assets.texture(FIREFLY_SPRITE_PATH))
	p.emitting = false
	return p


## Quad que olha sempre para a câmara (billboard), sem luz, com alpha.
func _billboard_quad(size: Vector2, col: Color, texture: Texture2D) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = size
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.albedo_color = col
	m.albedo_texture = texture
	m.vertex_color_use_as_albedo = true
	q.material = m
	return q
