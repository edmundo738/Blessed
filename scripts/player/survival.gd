class_name Survival
extends Node
## Survival — necessidades, saúde, medo, bênção e morte.
##
## Tudo aqui é consequência: nenhuma destas barras é decorativa. Cada uma tem uma
## causa (o mundo), um efeito observável (dano, lentidão, ecrã) e um caminho de
## recuperação (comer, beber, dormir, fogo, companhia).
##
## O medo é a ponte para o terror: nasce do escuro e da proximidade, corrói a
## calma, e a calma baixa distorce o que se vê e ouve.

const MAX_STAT := 100.0

var health := 100.0
var hunger := 100.0
var thirst := 100.0
var energy := 100.0
var warmth := 100.0
var sanity := 100.0
var blessing := 60.0
var fear := 0.0
var alive := true

var light_level := 1.0        # 0 = breu, 1 = dia pleno (medido pelo World)
var near_fire := false
var creature_threat := 0.0    # 0..1, alimentado pelas criaturas
var sheltered := false
var companion_near := false

var _warn := {}


func _ready() -> void:
	name = "Survival"
	Game.register_saver(self)
	Bus.player_died.connect(_on_death_handled)


func _process(delta: float) -> void:
	if not alive or Game.paused or not Game.started:
		return
	var d := delta
	# ── necessidades ────────────────────────────────────────────────────
	hunger = _drain(hunger, 0.115 * d)
	thirst = _drain(thirst, 0.175 * d)
	var tired := 0.10 if Game.is_night() else 0.055
	energy = _drain(energy, tired * d)

	# ── calor: a noite arrefece, o fogo aquece ──────────────────────────
	var target_warmth := 100.0
	if Game.is_night():
		target_warmth = 45.0 if not sheltered else 75.0
	if near_fire:
		target_warmth = maxf(target_warmth, 100.0)
	warmth = move_toward(warmth, target_warmth, 1.6 * d)

	# ── medo: escuro + ameaça, reduzido por luz, fogo e companhia ───────
	var base_fear := 0.0
	if Game.is_night():
		base_fear += (1.0 - light_level) * 0.55
	base_fear += creature_threat * 1.1
	if near_fire:
		base_fear *= 0.25
	if companion_near:
		base_fear *= 0.5
	if Game.profile.get("soul", "") == "brave":
		base_fear *= 0.6
	base_fear *= float(Game.settings["horror"])
	fear = clampf(lerpf(fear, clampf(base_fear, 0.0, 1.0), 1.0 - exp(-1.2 * d)), 0.0, 1.0)
	Bus.fear_changed.emit(fear)

	# ── calma ───────────────────────────────────────────────────────────
	var calm_target := 100.0
	if fear > 0.35:
		calm_target -= fear * 55.0
	if light_level > 0.5 and not Game.is_night():
		calm_target = 100.0
	sanity = move_toward(sanity, clampf(calm_target, 0.0, 100.0), 0.9 * d)

	# ── bênção: regenera devagar, é o recurso "de história" ─────────────
	blessing = clampf(blessing + 1.1 * d, 0.0, MAX_STAT)

	# ── consequências ───────────────────────────────────────────────────
	if hunger <= 0.0:
		damage(1.1 * d, "starve")
		_warn_once("hunger", "msg.hungry")
	if thirst <= 0.0:
		damage(1.6 * d, "thirst")
		_warn_once("thirst", "msg.thirsty")
	if warmth < 25.0:
		damage(0.9 * d, "cold")
		_warn_once("cold", "msg.cold")
	if energy <= 0.0:
		_warn_once("energy", "msg.sleepy")
	if sanity < 30.0 and randf() < 0.0015:
		Sfx.play_at("growl", _random_near(), -18.0, randf_range(0.7, 1.1))
	if fear > 0.75 and randf() < 0.004:
		Bus.toast.emit("msg.something_watching", 2.5)

	_emit_stats()


func _drain(v: float, amount: float) -> float:
	return clampf(v - amount, 0.0, MAX_STAT)


func _warn_once(key: String, msg: String) -> void:
	if _warn.get(key, false):
		return
	_warn[key] = true
	Bus.toast.emit(msg, 3.5)


func _emit_stats() -> void:
	Bus.stat_changed.emit("health", health, MAX_STAT)
	Bus.stat_changed.emit("hunger", hunger, MAX_STAT)
	Bus.stat_changed.emit("thirst", thirst, MAX_STAT)
	Bus.stat_changed.emit("energy", energy, MAX_STAT)
	Bus.stat_changed.emit("warmth", warmth, MAX_STAT)
	Bus.stat_changed.emit("sanity", sanity, MAX_STAT)
	Bus.stat_changed.emit("blessing", blessing, MAX_STAT)


func reset_warnings() -> void:
	_warn.clear()


# ══════════════════════════════════════════════════════════════════════════
#  AÇÕES
# ══════════════════════════════════════════════════════════════════════════
func eat(food: float, drink: float, risk: float) -> void:
	hunger = clampf(hunger + food, 0.0, MAX_STAT)
	thirst = clampf(thirst + drink, 0.0, MAX_STAT)
	if risk > 0.0 and randf() < risk:
		damage(6.0, "sick")
		Bus.toast.emit("msg.hungry", 2.0)
	else:
		health = clampf(health + 2.0, 0.0, MAX_STAT)
	Sfx.play("eat", -8.0)
	reset_warnings()
	_emit_stats()


func drink(amount: float) -> void:
	thirst = clampf(thirst + amount, 0.0, MAX_STAT)
	Sfx.play("drink", -8.0)
	reset_warnings()
	_emit_stats()


func rest(hours: float, quality: float) -> void:
	energy = clampf(energy + hours * 12.0 * quality, 0.0, MAX_STAT)
	sanity = clampf(sanity + 18.0 * quality, 0.0, MAX_STAT)
	health = clampf(health + 6.0 * quality, 0.0, MAX_STAT)
	Game.hour = fmod(Game.hour + hours, 24.0)
	reset_warnings()
	_emit_stats()


func damage(amount: float, cause: String) -> void:
	if not alive:
		return
	health = clampf(health - amount, 0.0, MAX_STAT)
	Bus.player_damaged.emit(amount, cause)
	if health <= 0.0:
		alive = false
		Bus.player_died.emit(cause)


func heal(amount: float, cause: String) -> void:
	health = clampf(health + amount, 0.0, MAX_STAT)
	Bus.player_healed.emit(amount, cause)


func _on_death_handled(_cause: String) -> void:
	pass


func respawn() -> void:
	alive = true
	health = 65.0
	hunger = maxf(hunger, 45.0)
	thirst = maxf(thirst, 45.0)
	energy = maxf(energy, 55.0)
	sanity = 70.0
	fear = 0.0
	reset_warnings()
	Bus.player_respawned.emit()
	_emit_stats()


## Gasta bênção para um efeito visível (afugentar o escuro).
func flare_blessing() -> bool:
	if blessing < 35.0:
		return false
	blessing -= 35.0
	fear = maxf(0.0, fear - 0.6)
	sanity = clampf(sanity + 12.0, 0.0, MAX_STAT)
	Sfx.play("blessing", -4.0)
	Bus.toast.emit("msg.blessing_used", 2.5)
	_emit_stats()
	return true


## Multiplicadores que o Player lê (a fome realmente abranda as pernas).
func speed_multiplier() -> float:
	var m := 1.0
	if hunger < 20.0:
		m *= 0.82
	if thirst < 15.0:
		m *= 0.8
	if energy < 10.0:
		m *= 0.85
	if health < 30.0:
		m *= 0.9
	return m


func work_multiplier() -> float:
	var m := 1.0
	if str(Game.profile.get("soul", "")) == "hands":
		m *= 1.45
	if hunger < 25.0:
		m *= 0.8
	if health < 40.0:
		m *= 0.85
	return m


func save_data() -> Dictionary:
	return {
		"health": health, "hunger": hunger, "thirst": thirst, "energy": energy,
		"warmth": warmth, "sanity": sanity, "blessing": blessing, "alive": alive,
	}


func load_data(d: Dictionary) -> void:
	health = float(d.get("health", 100.0))
	hunger = float(d.get("hunger", 100.0))
	thirst = float(d.get("thirst", 100.0))
	energy = float(d.get("energy", 100.0))
	warmth = float(d.get("warmth", 100.0))
	sanity = float(d.get("sanity", 100.0))
	blessing = float(d.get("blessing", 60.0))
	alive = bool(d.get("alive", true))
	reset_warnings()
	_emit_stats()


func _random_near() -> Vector3:
	var p := get_parent()
	var base := (p as Node3D).global_position if p is Node3D else Vector3.ZERO
	return base + Vector3(randf_range(-14, 14), 0, randf_range(-14, 14))
