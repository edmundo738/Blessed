class_name Wildlife
extends Node
## Wildlife — quem anda pelo mundo de dia.
##
## Mantém sempre alguns animais vivos perto do jogador (nascem longe e à vista,
## desaparecem se ele se afastar). É o que dá carne ao ciclo: sem isto as
## receitas de `meat_raw`/`meat_cooked`/guisado não tinham de onde sair.

const MAX_ANIMALS := 5
const SPAWN_MIN_DIST := 16.0
const SPAWN_MAX_DIST := 34.0
const DESPAWN_DIST := 62.0

var player: Node3D
var world: Node3D
var inv: Node
var root: Node3D

var animals: Array = []
var spawn_t := 2.0


func _process(delta: float) -> void:
	if not Game.started or Game.paused or player == null or world == null:
		return
	animals = animals.filter(func(a): return is_instance_valid(a) and (a as Animal).alive)
	for a in animals.duplicate():
		if (a as Node3D).global_position.distance_to(player.global_position) > DESPAWN_DIST:
			animals.erase(a)
			(a as Node).queue_free()
	# à noite os animais recolhem: quem manda na noite é o NightDirector
	if Game.is_night():
		return
	spawn_t -= delta
	if spawn_t > 0.0 or animals.size() >= MAX_ANIMALS:
		return
	spawn_t = randf_range(4.0, 9.0)
	_spawn()


func _spawn() -> void:
	for attempt in 12:
		var a := randf() * TAU
		var r := randf_range(SPAWN_MIN_DIST, SPAWN_MAX_DIST)
		var p := player.global_position + Vector3(cos(a) * r, 0.0, sin(a) * r)
		var g: float = world.call("ground_height", p.x, p.z)
		if g < Terrain.SEA_LEVEL + 0.6:
			continue
		if bool(world.call("is_in_water", Vector3(p.x, g + 0.4, p.z))):
			continue
		p.y = g
		var beast := Animal.new()
		beast.world = world
		beast.player = player
		beast.inv = inv
		beast.health = 5.0 + float(Game.day) * 0.2
		root.add_child(beast)
		beast.global_position = p
		animals.append(beast)
		return
