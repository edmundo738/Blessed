class_name Materials
extends RefCounted
## Materials — os materiais partilhados do mundo.
##
## Todos criados em código a partir dos .gdshader (que são recursos de texto e
## por isso não precisam de import). Um material por tipo, reutilizado por todos
## os chunks: trocar uma uniform muda o mundo inteiro.

var terrain: ShaderMaterial
var foliage: ShaderMaterial
var grass: ShaderMaterial
var water: ShaderMaterial
var sky: ShaderMaterial
var structure: ShaderMaterial

const SKY_DAY := preload("res://content/fx/kenney/sky/skybox-day.png")
const SKY_MORNING := preload("res://content/fx/kenney/sky/skybox-morning.png")
const SKY_NIGHT := preload("res://content/fx/kenney/sky/skybox-night.png")


func _init() -> void:
	var ts: Shader = load("res://shaders/toon_terrain.gdshader")
	var fs: Shader = load("res://shaders/toon_foliage.gdshader")
	var ws: Shader = load("res://shaders/stylized_water.gdshader")
	var ss: Shader = load("res://shaders/anime_sky.gdshader")

	terrain = ShaderMaterial.new()
	terrain.shader = ts
	terrain.set_shader_parameter("shadow_tint", Color(0.55, 0.58, 0.88))
	terrain.set_shader_parameter("bands", 3.0)
	terrain.set_shader_parameter("rim_strength", 0.28)

	foliage = ShaderMaterial.new()
	foliage.shader = fs
	foliage.set_shader_parameter("shadow_tint", Color(0.48, 0.52, 0.86))
	foliage.set_shader_parameter("wind_strength", 0.16)
	foliage.set_shader_parameter("wind_speed", 1.05)
	foliage.set_shader_parameter("wind_height", 3.2)

	grass = ShaderMaterial.new()
	grass.shader = fs
	grass.set_shader_parameter("shadow_tint", Color(0.45, 0.50, 0.82))
	grass.set_shader_parameter("wind_strength", 0.22)
	grass.set_shader_parameter("wind_speed", 1.6)
	grass.set_shader_parameter("wind_height", 0.75)
	grass.set_shader_parameter("rim_strength", 0.5)

	var sts: Shader = load("res://shaders/toon_structure.gdshader")
	structure = ShaderMaterial.new()
	structure.shader = sts
	structure.set_shader_parameter("shadow_tint", Color(0.54, 0.56, 0.86))
	structure.set_shader_parameter("bands", 4.0)
	structure.set_shader_parameter("rim_strength", 0.26)

	water = ShaderMaterial.new()
	water.shader = ws

	sky = ShaderMaterial.new()
	sky.shader = ss
	sky.set_shader_parameter("sky_day", SKY_DAY)
	sky.set_shader_parameter("sky_morning", SKY_MORNING)
	sky.set_shader_parameter("sky_night", SKY_NIGHT)


## Aplica a hora do dia aos materiais (chamado pelo DayCycle).
func apply_time(sun_dir: Vector3, daylight: float, dusk: float, update_sky: bool = true) -> void:
	var sd := -sun_dir
	terrain.set_shader_parameter("sun_dir", sd)
	foliage.set_shader_parameter("sun_dir", sd)
	grass.set_shader_parameter("sun_dir", sd)
	structure.set_shader_parameter("sun_dir", sd)
	water.set_shader_parameter("sun_dir", sd)
	# à noite a tinta de sombra fica azulada e as bandas suavizam
	var night := 1.0 - daylight
	terrain.set_shader_parameter("shadow_tint",
		Color(0.55, 0.58, 0.88).lerp(Color(0.22, 0.26, 0.52), night))
	foliage.set_shader_parameter("shadow_tint",
		Color(0.48, 0.52, 0.86).lerp(Color(0.18, 0.22, 0.48), night))
	grass.set_shader_parameter("shadow_tint",
		Color(0.45, 0.50, 0.82).lerp(Color(0.16, 0.20, 0.44), night))
	terrain.set_shader_parameter("band_soft", lerpf(0.45, 0.62, night))
	terrain.set_shader_parameter("ambient_gain", lerpf(0.66, 0.36, night))
	foliage.set_shader_parameter("ambient_gain", lerpf(0.74, 0.38, night))
	grass.set_shader_parameter("ambient_gain", lerpf(0.74, 0.38, night))
	structure.set_shader_parameter("ambient_gain", lerpf(0.74, 0.38, night))

	# The sky also builds Godot's reflection cubemap. Updating it only five times
	# per second keeps the sun motion smooth while giving incremental cubemap work
	# time to finish between changes.
	if update_sky:
		sky.set_shader_parameter("sun_dir", sd)
		sky.set_shader_parameter("daylight", daylight)
		sky.set_shader_parameter("dusk_mix", dusk)
		sky.set_shader_parameter("moon_phase", fposmod(float(Game.day - 1) / 28.0, 1.0))
		sky.set_shader_parameter("cloud_offset", fposmod(float(Game.day - 1) * 0.012 + Game.hour * 0.0005, 1.0))
	water.set_shader_parameter("sky_tint",
		Color(0.62, 0.82, 1.0).lerp(Color(0.10, 0.14, 0.30), night))
	water.set_shader_parameter("deep_color",
		Color(0.10, 0.36, 0.52).lerp(Color(0.02, 0.05, 0.14), night))
	water.set_shader_parameter("shallow_color",
		Color(0.34, 0.78, 0.82).lerp(Color(0.06, 0.12, 0.26), night))


func set_wind(strength: float) -> void:
	foliage.set_shader_parameter("wind_strength", strength)
	grass.set_shader_parameter("wind_strength", strength * 1.4)
