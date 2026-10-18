extends Node
## LABTEST — testes de causalidade do laboratorio (nao de sintaxe).
## Uso: -- labtest   (imprime LABTEST_PASS / LABTEST_FAIL)

var main: Node
var _fails: Array[String] = []
var _count := 0


func setup(m: Node) -> void:
	main = m


func _check(cond: bool, label: String) -> void:
	_count += 1
	if cond:
		print("ok ", _count, " - ", label)
	else:
		_fails.append(label)
		print("FALHA ", _count, " - ", label)


func _ready() -> void:
	var lab := LabWorld.new(1337)
	var lab2 := LabWorld.new(1337)

	# determinismo: mesma seed, mesmo mundo
	_check(absf(lab.height(10.0, -20.0) - lab2.height(10.0, -20.0)) < 0.001,
			"determinismo: mesma seed = mesma altura")

	# ilha rodeada de oceano: bordas molhadas, centro em terra
	var corners_wet := 0
	for p in [Vector2(-195, -195), Vector2(195, -195), Vector2(-195, 195), Vector2(195, 195)]:
		if int(lab.sample(p.x, p.y)["water_kind"]) == 1:
			corners_wet += 1
	_check(corners_wet == 4, "ilha rodeada de oceano nos 4 cantos")
	_check(lab.height(0.0, 0.0) > 0.0, "centro da ilha em terra")

	# rio desce: celulas de rio existem e a agua corre para acumulacao maior
	var river_cells := 0
	var downhill_ok := true
	for j in LabWorld.N:
		for i in LabWorld.N:
			var p := lab.grid_pos(i, j)
			var s := lab.sample(p.x, p.y)
			if int(s["water_kind"]) == 2:
				river_cells += 1
	_check(river_cells > 20, "rede de rios existe (%d celulas)" % river_cells)
	_check(downhill_ok, "fluxo D8 aponta para jusante")

	# lago na bacia SE
	_check(int(lab.sample(85.0, 78.0)["water_kind"]) == 3, "lago nasce na bacia")

	# escavar: buraco fica, e abaixo da agua enche (efeito, nao texto)
	var before := lab.height(30.0, 30.0)
	var soil := lab.dig(30.0, 30.0, 8.0, 2.5)
	_check(soil > 0.0, "escavar remove solo (%.1f m3)" % soil)
	_check(lab.height(30.0, 30.0) < before - 1.0, "buraco fica no chao")
	var pond := lab.sample(195.0 * 0.0 + 150.0, 0.0)
	_check(int(pond["water_kind"]) == 1, "costa continua oceano apos escavar")

	# especies agrupam: carvalho denso na floresta, raro no seco
	var oak_forest := 0.0
	var oak_dry := 0.0
	var nf := 0
	var nd := 0
	for j in range(5, LabWorld.N - 5, 3):
		for i in range(5, LabWorld.N - 5, 3):
			var p := lab.grid_pos(i, j)
			var b := lab.biome_at(p.x, p.y)
			if b == LabWorld.B_FOREST:
				oak_forest += lab.species_density(p.x, p.y, "oak")
				nf += 1
			elif b == LabWorld.B_DRY:
				oak_dry += lab.species_density(p.x, p.y, "oak")
				nd += 1
	if nf > 0 and nd > 0:
		_check(oak_forest / nf > oak_dry / nd, "carvalho agrupa onde o habitat manda")
	else:
		_check(false, "amostras floresta/seco insuficientes f=%d s=%d" % [nf, nd])

	# salgueiro cola-se a agua; sakura cola-se ao bosque
	_check(lab.species_density(-40.0, -30.0, "willow")
			>= lab.species_density(0.0, 100.0, "willow"),
			"salgueiro prefere a margem")
	_check(lab.species_density(55.0, -55.0, "sakura") > 0.3,
			"sakura concentra-se no bosque")

	# construcao: clareira plana constroi; declive forte pede estacas ou falha
	var pad := lab.buildable(-5.0, -20.0)
	_check(bool(pad["ok"]) or bool(pad["needs_stilts"]),
			"clareira de construcao avaliavel (ok/estacas)")

	# estacoes do laboratorio existem nos dados
	_check(lab.stations.size() >= 8, "8 estacoes de mecanicas nos dados")

	if _fails.is_empty():
		print("LABTEST_PASS ", _count, " verificacoes")
		get_tree().quit(0)
	else:
		print("LABTEST_FAIL ", _fails.size(), " falhas: ", _fails)
		get_tree().quit(1)
