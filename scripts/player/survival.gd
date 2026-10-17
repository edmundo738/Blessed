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

## Enjoo (comida/água estragada). 0..1. Não é dano instantâneo: sobe quando o
## corpo recusa o que comeu e vai caindo, com dano lento e a vista a respirar.
var illness := 0.0
var _rumble_t := 6.0
var _breath_t := 4.0

## Segundos de DESIDRATAÇÃO que faltam pagar (água do mar). Enquanto durar, a
## sede escorre mais depressa. Nunca é dano instantâneo: é uma dívida.
var dehydrated_t := 0.0


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
	thirst = _drain(thirst, 0.175 * d * (2.6 if dehydrated_t > 0.0 else 1.0))
	if dehydrated_t > 0.0:
		dehydrated_t = maxf(0.0, dehydrated_t - d)
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

	if dehydrated_t > 0.0:
		_warn_once("dehydrated", "msg.dehydrated")
	# ── consequências ───────────────────────────────────────────────────
	# ── o corpo faz barulho antes de o jogo dizer nada ───────────────────
	# O estômago range quando a fome aperta; a respiração ouve-se quando o
	# fôlego acaba. São os avisos que o jogador NÃO lê — ouve.
	if hunger < 45.0:
		_rumble_t -= d * (1.0 + (45.0 - hunger) * 0.05)
		if _rumble_t <= 0.0:
			_rumble_t = randf_range(5.0, 11.0)
			Sfx.play("stomach", -20.0 + (45.0 - hunger) * 0.12, randf_range(0.9, 1.1))
	if energy < 30.0:
		_breath_t -= d * (1.0 + (30.0 - energy) * 0.04)
		if _breath_t <= 0.0:
			_breath_t = randf_range(3.2, 5.5)
			Sfx.play("breath", -24.0 + (30.0 - energy) * 0.18, randf_range(0.92, 1.06))

	# ── enjoo: a factura chega depois, em ondas ──────────────────────────
	if illness > 0.0:
		illness = maxf(0.0, illness - d * 0.012)
		damage(0.22 * d * illness, "sick")

	if hunger <= 0.0:
		damage(1.1 * d, "starve")
		_warn_once("hunger", "msg.hungry")
	if thirst <= 0.0:
		damage(1.6 * d, "thirst")
		_warn_once("thirst", "msg.thirsty")
	if warmth < 25.0:
		damage(0.9 * d, "cold")
		_warn_once("cold", "msg.cold")
	# Avisar só a 0 é tarde: o jogador já está a arrastar-se sem saber porquê.
	if energy <= 20.0 and energy > 0.0:
		_warn_once("tired", "msg.tired")
	elif energy <= 0.0:
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


## Quanto enjoo o jogador sente agora (0..1), para o véu da HUD.
func sickness() -> float:
	return clampf(illness, 0.0, 1.0)


func reset_warnings() -> void:
	_warn.clear()


# ══════════════════════════════════════════════════════════════════════════
#  AÇÕES
# ══════════════════════════════════════════════════════════════════════════
## Comer devolve o que aconteceu: quem chama decide o que dizer ao jogador.
## Antes, quem comia carne crua e se sentia mal via "Estás com fome" — o
## oposto do que tinha acabado de acontecer.
func eat(food: float, drink: float, risk: float) -> Dictionary:
	hunger = clampf(hunger + food, 0.0, MAX_STAT)
	thirst = clampf(thirst + drink, 0.0, MAX_STAT)
	var sick := risk > 0.0 and randf() < risk
	if sick:
		# Não é dano instantâneo: é enjoo. O corpo avisa durante ~20 s (vista
		# verde, ondas, dano lento). A causalidade vê-se; ninguém precisa de
		# escrever "cozinha para evitar".
		illness = clampf(illness + 0.75, 0.0, 1.0)
		Sfx.play("growl", -14.0, 0.55)
	else:
		health = clampf(health + 2.0, 0.0, MAX_STAT)
	Sfx.play("eat", -8.0)
	reset_warnings()
	_emit_stats()
	return {"sick": sick, "food": food, "drink": drink}


## Beber. `risk` é a probabilidade de dar-se mal com o que se bebeu: água crua
## de rio tem parasitas, água fervida não. É a decisão que dá sentido à fogueira
## — sem isto, beber do rio era sempre a jogada certa e a fogueira era só enfeite.
func drink(amount: float, risk: float = 0.0) -> void:
	thirst = clampf(thirst + amount, 0.0, MAX_STAT)
	# Água limpa lava o sal: beber doce cura a desidratação.
	if amount > 0.0 and risk <= 0.0:
		dehydrated_t = 0.0
	if risk > 0.0 and randf() < risk:
		damage(5.0, "bad_water")
		Bus.toast.emit("msg.bad_water", 2.4)
	Sfx.play("drink", -8.0)
	reset_warnings()
	_emit_stats()


## Água do mar: o sal puxa a água do corpo. O alívio é imediato (o `drink` já
## aconteceu); a factura vem nos segundos seguintes, em sede — não em dano.
func dehydrate(seconds: float = 45.0) -> void:
	dehydrated_t = maxf(dehydrated_t, seconds)
	_warn["dehydrated"] = true
	Bus.toast.emit("msg.dehydrated", 3.2)
	_emit_stats()


## Dormir até de manhã.
##
## `quality` é o SÍTIO (chão 0,30 … cama 1,00, de data/sleep.json) e `context`
## é o que o mundo acrescenta (fogueira acesa, abrigo). Devolve o que mudou,
## para o HUD/testemunho poderem dizer a verdade.
##
## O tempo não é de graça: as horas passam e o corpo paga fome e sede. Sem
## isto, dormir era um botão para saltar a noite sem consequência — e o
## jogador nunca precisava de preparar comida antes de se deitar.
## Cochilo: passa `hours.nap` horas (não a noite toda) e paga o mesmo preço.
## É isto que separa a cadeira da cama — a cama resolve a noite, a cadeira só
## te põe de pé outra vez.
func nap(quality: float, context: float = 0.0) -> Dictionary:
	return _sleep_for(Db.sleep_num("hours", "nap", 1.5), quality, context)


func sleep_until_morning(quality: float, context: float = 0.0,
		exertion: float = 0.0) -> Dictionary:
	var wake_at := Db.sleep_num("hours", "wake_at", 6.8)
	var hours := fmod(wake_at - Game.hour + 24.0, 24.0)
	if Game.hour > wake_at and Game.hour < 19.0:
		# de dia não se salta o dia: é uma sesta curta
		hours = Db.sleep_num("hours", "nap", 1.5)
	else:
		hours = clampf(hours, Db.sleep_num("hours", "min", 3.0),
			Db.sleep_num("hours", "max", 9.0))
	return _sleep_for(hours, quality, context, exertion)


## `exertion` (0..100) é o esforço do dia: correr, cortar, carregar. Um dia
## fisicamente duro rende mais sono — e um dia parado rende menos. É isto que
## liga o corpo ao mundo em vez de deixar o sono ser um botão de tempo.
func _sleep_for(hours: float, quality: float, context: float = 0.0,
		exertion: float = 0.0) -> Dictionary:
	var esforco := clampf(exertion / 100.0, 0.0, 1.0)
	var q := clampf(quality + context + esforco * 0.18, 0.05, 1.5)
	var energy_before := energy
	var hunger_before := hunger
	var thirst_before := thirst
	var h := maxf(0.25, hours)
	energy = clampf(energy + h * Db.sleep_num("recovery", "energy_per_hour", 9.0) * q,
		0.0, MAX_STAT)
	health = clampf(health + h * Db.sleep_num("recovery", "health_per_hour", 0.8) * q,
		0.0, MAX_STAT)
	sanity = clampf(sanity + Db.sleep_num("recovery", "sanity", 16.0) * (q - 0.55),
		0.0, MAX_STAT)
	hunger = clampf(hunger - h * Db.sleep_num("recovery", "hunger_per_hour", 3.4),
		0.0, MAX_STAT)
	thirst = clampf(thirst - h * Db.sleep_num("recovery", "thirst_per_hour", 4.2),
		0.0, MAX_STAT)
	dehydrated_t = maxf(0.0, dehydrated_t - h * 600.0)
	Game.hour = fmod(Game.hour + h, 24.0)
	reset_warnings()
	_emit_stats()
	return {
		"hours": h, "quality": q, "exertion": esforco,
		"energy": energy - energy_before,
		"hunger": hunger - hunger_before,
		"thirst": thirst - thirst_before,
	}


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
	if thirst < 20.0:
		m *= 0.88
	if illness > 0.2:
		m *= 0.85
	if health < 40.0:
		m *= 0.85
	# Sem isto, a energia era um número decorativo: cortar 20 árvores a pé
	# firme saía ao mesmo ritmo de quem acabou de acordar.
	if energy < 10.0:
		m *= 0.7
	return m


func save_data() -> Dictionary:
	return {
		"illness": illness,
		"health": health, "hunger": hunger, "thirst": thirst, "energy": energy,
		"warmth": warmth, "sanity": sanity, "blessing": blessing, "alive": alive,
		"dehydrated_t": dehydrated_t,
	}


func load_data(d: Dictionary) -> void:
	health = float(d.get("health", 100.0))
	hunger = float(d.get("hunger", 100.0))
	thirst = float(d.get("thirst", 100.0))
	energy = float(d.get("energy", 100.0))
	illness = float(d.get("illness", 0.0))
	warmth = float(d.get("warmth", 100.0))
	sanity = float(d.get("sanity", 100.0))
	blessing = float(d.get("blessing", 60.0))
	alive = bool(d.get("alive", true))
	dehydrated_t = float(d.get("dehydrated_t", 0.0))
	reset_warnings()
	_emit_stats()


func _random_near() -> Vector3:
	var p := get_parent()
	var base := (p as Node3D).global_position if p is Node3D else Vector3.ZERO
	return base + Vector3(randf_range(-14, 14), 0, randf_range(-14, 14))
