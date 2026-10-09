class_name NightDirector
extends Node
## NightDirector — o realizador da noite.
##
## Decide QUANTO medo entra em cena. Regras curtas e legíveis:
##   • só nasce criatura depois do anoitecer e longe da luz
##   • o número máximo cresce com os dias sobrevividos e com a dificuldade
##   • quem está perto de uma fogueira não é atacado
##   • ao amanhecer, tudo se dissolve
##
## O objetivo não é matar: é fazer o jogador planear o dia em função da noite.

const MAX_CREATURES := 6
const SPAWN_MIN_DIST := 26.0
const SPAWN_MAX_DIST := 48.0
const DESPAWN_DIST := 70.0

var player: Node3D
var world: Node3D
var structures: Structures
var survival: Node
var root: Node3D

var creatures: Array = []
var spawn_t := 0.0
var announced := false


func _process(delta: float) -> void:
	if not Game.started or Game.paused or player == null:
		return
	var night := Game.is_night()
	var day := Game.daylight()
	if survival != null:
		survival.creature_threat = 0.0

	# amanhecer: limpa a noite
	if not night and day > 0.3:
		if not creatures.is_empty():
			for c in creatures.duplicate():
				if is_instance_valid(c):
					(c as Node).queue_free()
			creatures.clear()
		announced = false
		return

	if night and not announced:
		announced = true
		Bus.toast.emit("msg.night_falls", 4.0)
		Sfx.play("blessing", -18.0, 0.7)

	# contagem máxima
	var horror := float(Game.settings["horror"])
	var cap := int(clampf(1.0 + (Game.day - 1) * 0.7, 1.0, MAX_CREATURES) * horror)
	if not night or cap <= 0:
		return

	spawn_t -= delta
	if spawn_t > 0.0:
		return
	spawn_t = randf_range(6.0, 14.0) / maxf(horror, 0.2)

	creatures = creatures.filter(func(c): return is_instance_valid(c) and (c as Creature).alive)
	if creatures.size() >= cap:
		return
	# perto do fogo não nasce nada
	if _near_fire(player.global_position, 10.0):
		return
	_spawn()


func _spawn() -> void:
	var a := randf() * TAU
	var r := randf_range(SPAWN_MIN_DIST, SPAWN_MAX_DIST)
	var p := player.global_position + Vector3(cos(a) * r, 0, sin(a) * r)
	if world == null:
		return
	var g: float = world.call("ground_height", p.x, p.z)
	if g < Terrain.SEA_LEVEL + 0.4:
		return
	p.y = g
	var c := Creature.new()
	c.world = world
	c.structures = structures
	c.survival = survival
	c.target = player
	c.boldness = clampf(0.3 + Game.day * 0.08, 0.2, 0.95)
	c.damage = 10.0 + Game.day * 1.5
	root.add_child(c)
	c.global_position = p
	creatures.append(c)
	if randf() < 0.5:
		Bus.toast.emit("msg.heard", 2.5)


func _near_fire(p: Vector3, radius: float) -> bool:
	if structures == null:
		return false
	for lp in structures.lit_positions():
		if (lp as Vector3).distance_to(p) < radius:
			return true
	return false
