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
var grass_shell: ShaderMaterial
var grass_cards: ShaderMaterial
var grass_card_mesh: ArrayMesh
var water: ShaderMaterial
var sky: ShaderMaterial
var structure: ShaderMaterial
var _grass_shader: Shader
var _foliage_card_shader: Shader
var _grass_material_cache: Dictionary = {}
var _grass_materials: Array[ShaderMaterial] = []
var _grass_mesh_cache: Dictionary = {}
var grass_atlas: Texture2D
var grass_mask: Texture2D
var grass_streak: Texture2D
var _grass_sun_dir := Vector3(0.0, -1.0, 0.0)
var _grass_shadow := Color(0.45, 0.50, 0.82)
var _grass_ambient := 0.74
var _wind_strength := 0.22

## Nenhuma destas imagens usa `preload`: sem a cache de importação do editor o
## `preload` de um .png falha na análise do script e derrubava o mundo inteiro
## (materiais, terreno, relva, céu). `Assets.texture` tenta o produto importado e
## cai na imagem crua — funciona no editor, num clone novo e no build web.
const SKY_PATHS := [
	"res://content/fx/kenney/sky/skybox-day.png",
	"res://content/fx/kenney/sky/skybox-morning.png",
	"res://content/fx/kenney/sky/skybox-night.png",
]
const GRASS_ATLAS_PATH := "res://content/models/runtime/quaternius/Grass.png"
## Máscara de volume da relva (gerada por tools/make_grass_masks.py).
const GRASS_FUR_PATH := "res://content/fx/grass/grass_fur.png"
const GRASS_STREAK_PATH := "res://content/fx/grass/grass_streak.png"

## A máscara repete a cada 1,05 m: uma lâmina fica com ~1 cm de largura e 11–27 cm
## de comprimento, com 68% de cobertura. A 36 cm (versão anterior) as lâminas
## tinham 5 mm: eram sub-pixel a partir de um metro e o campo não passava de um
## pontilhado. O tamanho do ladrilho é o que decide se a relva se lê como relva.
const GRASS_MASK_SCALE := 1.05
## Altura do volume de relva. Os níveis ficam a ~3 cm um do outro.
const GRASS_HEIGHT := 0.30




## Registo para o diagnóstico: que ficheiro está por trás de cada textura.
## Uma ImageTexture criada em código não tem `resource_path`, e o rasterizador de
## tests/shot.gd precisa de saber que PNG avaliar (a máscara da relva é avaliada
## em Python, pixel a pixel). Sem isto, o dump só podia dizer "há uma textura".
static var texture_paths: Dictionary = {}


static func _track(texture: Texture2D, path: String) -> Texture2D:
	if texture != null:
		texture_paths[texture.get_instance_id()] = path
	return texture


func _init() -> void:
	var ts: Shader = load("res://shaders/toon_terrain.gdshader")
	var fs: Shader = load("res://shaders/toon_foliage.gdshader")
	_grass_shader = load("res://shaders/toon_grass.gdshader")
	_foliage_card_shader = load("res://shaders/toon_foliage_cards.gdshader")
	var gss: Shader = load("res://shaders/grass_shells.gdshader")
	var gcs: Shader = load("res://shaders/grass_cards.gdshader")
	var ws: Shader = load("res://shaders/stylized_water.gdshader")
	var ss: Shader = load("res://shaders/anime_sky.gdshader")
	var wind_noise := _make_wind_noise()

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

	grass_atlas = _track(Assets.texture(GRASS_ATLAS_PATH), GRASS_ATLAS_PATH)
	grass_mask = Assets.texture(GRASS_FUR_PATH)
	grass_streak = Assets.texture(GRASS_STREAK_PATH)
	grass_mask = _track(grass_mask if grass_mask != null else _flat_mask(Color(0.62, 0.5, 0.8)),
		GRASS_FUR_PATH)
	grass_streak = _track(grass_streak if grass_streak != null else _flat_mask(Color(0.5, 0.5, 0.5)),
		GRASS_STREAK_PATH)

	grass = grass_material_for()
	# Níveis: um campo de alturas desenhado em fatias empilhadas (ver o shader).
	grass_shell = ShaderMaterial.new()
	grass_shell.shader = gss
	grass_shell.set_shader_parameter("grass_mask", grass_mask)
	grass_shell.set_shader_parameter("grass_streak", grass_streak)
	grass_shell.set_shader_parameter("wind_noise", wind_noise)
	grass_shell.set_shader_parameter("mask_scale", GRASS_MASK_SCALE)
	grass_shell.set_shader_parameter("shell_height", GRASS_HEIGHT)
	grass_shell.set_shader_parameter("wind_strength", 0.30)
	grass_shell.set_shader_parameter("wind_speed", 1.15)
	# Densidade: tira fio, não corta o campo. Nunca abaixo de 0,62 — um campo
	# ralo a meio do alcance é que produzia os "anéis" de relva a desaparecer.
	grass_shell.set_shader_parameter("coverage_gain", 1.15)
	grass_shell.set_shader_parameter("density_min", 0.62)
	grass_shell.set_shader_parameter("density_near", 16.0)
	grass_shell.set_shader_parameter("density_far", 44.0)
	# A relva por níveis desaparece por volta dos 50 m: a partir daí cada lâmina é
	# menor que um pixel, e o campo continua nas cores do terreno (mesma família).
	grass_shell.set_shader_parameter("size_mid", 34.0)
	grass_shell.set_shader_parameter("size_far", 46.0)
	_set_grass_palette(grass_shell)
	# Cartões: os tufos de geometria dos primeiros metros.
	grass_cards = ShaderMaterial.new()
	grass_cards.shader = gcs
	grass_cards.set_shader_parameter("grass_mask", grass_mask)
	grass_cards.set_shader_parameter("grass_streak", grass_streak)
	grass_cards.set_shader_parameter("wind_noise", wind_noise)
	grass_cards.set_shader_parameter("mask_scale", GRASS_MASK_SCALE)
	grass_cards.set_shader_parameter("mask_min", 0.14)
	grass_cards.set_shader_parameter("blade_height", 0.72)
	grass_cards.set_shader_parameter("wind_strength", 0.24)
	grass_cards.set_shader_parameter("wind_speed", 1.0)
	grass_cards.set_shader_parameter("wind_scale", 0.035)
	grass_cards.set_shader_parameter("fade_begin", 26.0)
	grass_cards.set_shader_parameter("fade_end", 40.0)
	_set_grass_palette(grass_cards)
	grass_card_mesh = MeshKit.grass_card_clump(10)

	var sts: Shader = load("res://shaders/toon_structure.gdshader")
	structure = ShaderMaterial.new()
	structure.shader = sts
	structure.set_shader_parameter("shadow_tint", Color(0.54, 0.56, 0.86))
	structure.set_shader_parameter("bands", 4.0)
	structure.set_shader_parameter("rim_strength", 0.26)

	water = ShaderMaterial.new()
	water.shader = ws
	water.set_shader_parameter("flow_noise", wind_noise)

	sky = ShaderMaterial.new()
	sky.shader = ss
	sky.set_shader_parameter("sky_day", _track(Assets.texture(SKY_PATHS[0]), SKY_PATHS[0]))
	sky.set_shader_parameter("sky_morning", _track(Assets.texture(SKY_PATHS[1]), SKY_PATHS[1]))
	sky.set_shader_parameter("sky_night", _track(Assets.texture(SKY_PATHS[2]), SKY_PATHS[2]))


## Material de relva que conserva a textura do asset importado e anima os vértices.
## Os materiais são partilhados por todos os chunks com a mesma textura.
func grass_material_for(source: Material = null, wind_height: float = 0.75) -> ShaderMaterial:
	var texture: Texture2D = null
	var tint := Color.WHITE
	var alpha_cutoff := 0.42
	var needs_cutout := false
	var base := source as BaseMaterial3D
	if base != null:
		tint = base.albedo_color
		texture = base.albedo_texture
		needs_cutout = base.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
		alpha_cutoff = base.alpha_scissor_threshold
	var shader := _foliage_card_shader if needs_cutout else _grass_shader
	var key := "%d:%s:%d:%.2f:%.2f" % [texture.get_instance_id() if texture != null else 0,
		tint.to_html(), int(needs_cutout), wind_height, alpha_cutoff]
	if _grass_material_cache.has(key):
		return _grass_material_cache[key] as ShaderMaterial
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("use_texture", texture != null)
	material.set_shader_parameter("albedo_texture", texture)
	material.set_shader_parameter("albedo_tint", tint)
	if needs_cutout:
		material.set_shader_parameter("alpha_cutoff", alpha_cutoff)
	_apply_grass_style(material)
	material.set_shader_parameter("wind_height", maxf(wind_height, 0.1))
	_grass_material_cache[key] = material
	_grass_materials.append(material)
	return material


## Cria uma cópia da malha importada uma vez e troca cada material por uma
## variante que preserva a textura original e acrescenta vento.
func wind_foliage_mesh(source: ArrayMesh, wind_height: float = 0.75) -> ArrayMesh:
	var key := "%d:%.2f" % [source.get_instance_id(), wind_height]
	if _grass_mesh_cache.has(key):
		return _grass_mesh_cache[key] as ArrayMesh
	var result := source.duplicate() as ArrayMesh
	for surface in result.get_surface_count():
		result.surface_set_material(surface,
			grass_material_for(source.surface_get_material(surface), wind_height))
	_grass_mesh_cache[key] = result
	return result


## Luz partilhada pelos dois shaders de relva. A COR já não vem de uma paleta:
## vem do bioma (Terrain.grass_tint_of) pela cor de vértice/cor de instância.
func _set_grass_palette(material: ShaderMaterial) -> void:
	material.set_shader_parameter("shadow_tint", _grass_shadow)
	material.set_shader_parameter("sun_dir", _grass_sun_dir)
	material.set_shader_parameter("ambient_gain", _grass_ambient)
	material.set_shader_parameter("light_gain", 0.95)


## Máscara de recurso em falta: uma textura neutra para o shader continuar a
## desenhar relva em vez de rebentar (nunca deve acontecer — a máscara é gerada
## por tools/make_grass_masks.py e vive no repositório).
func _flat_mask(tint: Color) -> Texture2D:
	var image := Image.create(8, 8, false, Image.FORMAT_RGB8)
	image.fill(tint)
	return ImageTexture.create_from_image(image)


## A relva "cresce" ao entrar na distância de visão em vez de aparecer já alta.
## `t` = 0 no horizonte, 1 junto ao jogador; 0.35 é o mínimo para nunca
## desaparecer por completo (um chão pelado ao longe lê-se como bug).
func set_grass_grow(t: float) -> void:
	var grow := clampf(t, 0.35, 1.0)
	if grass_shell != null:
		grass_shell.set_shader_parameter("grow", grow)
	if grass_cards != null:
		grass_cards.set_shader_parameter("grow", grow)


func _apply_grass_style(material: ShaderMaterial) -> void:
	material.set_shader_parameter("shadow_tint", _grass_shadow)
	material.set_shader_parameter("sun_dir", _grass_sun_dir)
	material.set_shader_parameter("ambient_gain", _grass_ambient)
	material.set_shader_parameter("wind_strength", _wind_strength)
	material.set_shader_parameter("wind_speed", 1.6)
	material.set_shader_parameter("rim_strength", 0.42)


## Aplica a hora do dia aos materiais (chamado pelo DayCycle).
func apply_time(sun_dir: Vector3, daylight: float, dusk: float, update_sky: bool = true) -> void:
	var sd := -sun_dir
	_grass_sun_dir = sd
	terrain.set_shader_parameter("sun_dir", sd)
	foliage.set_shader_parameter("sun_dir", sd)
	for grass_material in _grass_materials:
		grass_material.set_shader_parameter("sun_dir", sd)
	structure.set_shader_parameter("sun_dir", sd)
	water.set_shader_parameter("sun_dir", sd)
	# à noite a tinta de sombra fica azulada e as bandas suavizam
	var night := 1.0 - daylight
	terrain.set_shader_parameter("shadow_tint",
		Color(0.55, 0.58, 0.88).lerp(Color(0.22, 0.26, 0.52), night))
	foliage.set_shader_parameter("shadow_tint",
		Color(0.48, 0.52, 0.86).lerp(Color(0.18, 0.22, 0.48), night))
	_grass_shadow = Color(0.45, 0.50, 0.82).lerp(Color(0.16, 0.20, 0.44), night)
	for grass_material in _grass_materials:
		grass_material.set_shader_parameter("shadow_tint", _grass_shadow)
	for field_material in [grass_shell, grass_cards]:
		field_material.set_shader_parameter("shadow_tint", _grass_shadow)
		field_material.set_shader_parameter("sun_dir", sd)
	terrain.set_shader_parameter("band_soft", lerpf(0.45, 0.62, night))
	terrain.set_shader_parameter("ambient_gain", lerpf(0.66, 0.36, night))
	foliage.set_shader_parameter("ambient_gain", lerpf(0.74, 0.38, night))
	_grass_ambient = lerpf(0.74, 0.38, night)
	for grass_material in _grass_materials:
		grass_material.set_shader_parameter("ambient_gain", _grass_ambient)
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
	_wind_strength = strength * 1.4
	# As fatias superiores das níveis afastam-se mais que as de baixo, por isso
	# precisam de menos força para o mesmo deslocamento aparente.
	grass_shell.set_shader_parameter("wind_strength", strength * 1.15)
	grass_cards.set_shader_parameter("wind_strength", strength * 1.05)
	for grass_material in _grass_materials:
		grass_material.set_shader_parameter("wind_strength", _wind_strength)


func _make_wind_noise() -> Texture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.seed = 317
	noise.frequency = 0.075
	noise.fractal_octaves = 3
	# Blend wrapped samples at the image edges so both wind shaders can repeat
	# the small map without a visible seam across the terrain.
	var image := Image.create(128, 128, false, Image.FORMAT_R8)
	for y in 128:
		var ty := float(y) / 128.0
		ty = ty * ty * (3.0 - 2.0 * ty)
		for x in 128:
			var tx := float(x) / 128.0
			tx = tx * tx * (3.0 - 2.0 * tx)
			var a := lerpf(noise.get_noise_2d(x, y), noise.get_noise_2d(x - 128, y), tx)
			var b := lerpf(noise.get_noise_2d(x, y - 128),
				noise.get_noise_2d(x - 128, y - 128), tx)
			var value := clampf(lerpf(a, b, ty) * 0.5 + 0.5, 0.0, 1.0)
			image.set_pixel(x, y, Color(value, 0.0, 0.0, 1.0))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)
