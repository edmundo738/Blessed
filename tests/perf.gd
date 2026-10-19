extends Node
## PERF — números antes/depois numa cena real, não opiniões.
##
## Corre no renderer real (`godot --path . -- perf`). Aquece o mundo, mede
## 120 frames no spawn, caminha ~60 m em frente e mede outra vez. Também
## guarda o custo de arranque da hidrologia e a contagem de instâncias.
##
## A saída é uma linha `PERF ...` por amostra, fácil de colar no CHECKPOINT.

var main: Node


func setup(m: Node) -> void:
	main = m


func _ready() -> void:
	print("PERF begin")
	var t0 := Time.get_ticks_msec()
	for i in 30:
		await get_tree().process_frame
	var warm_ms := Time.get_ticks_msec() - t0
	Game.started = true
	if main.get("hud") != null:
		(main.get("hud") as CanvasLayer).visible = false
	await _sample("spawn", warm_ms)
	# Caminhar para uma zona já carregada, como o jogador faria.
	var player: Player = main.get("player")
	var world: World = main.get("world")
	if player != null and world != null:
		var p := player.global_position
		var ahead := p + Vector3(0, 0, -55.0)
		player.teleport(Vector3(ahead.x, world.ground_height(ahead.x, ahead.z) + 1.0, ahead.z))
		world.set_target(ahead)
		for i in 30:
			await get_tree().process_frame
		await _sample("after_move", warm_ms)
	get_tree().quit(0)


func _sample(label: String, warm_ms: int) -> void:
	var frames: Array[float] = []
	for i in 45:
		var t := Time.get_ticks_usec()
		await get_tree().process_frame
		frames.append(float(Time.get_ticks_usec() - t) / 1000.0)
	frames.sort()
	var total := 0.0
	for f in frames:
		total += f
	var avg := total / float(frames.size())
	var p95 := frames[clampi(int(float(frames.size()) * 0.95), 0, frames.size() - 1)]
	var world: World = main.get("world")
	var chunks := world.chunks.size() if world != null else 0
	var instances := 0
	if world != null:
		for c in world.chunks.values():
			for mmi in (c as Chunk).get_children():
				if mmi is MultiMeshInstance3D and (mmi as MultiMeshInstance3D).multimesh != null:
					instances += (mmi as MultiMeshInstance3D).multimesh.instance_count
	print("PERF %s frames=%d avg_ms=%.2f p95_ms=%.2f fps=%.1f chunks=%d instances=%d objects=%d static_mem_mb=%.1f draw_calls=%d primitives=%d warmup_ms=%d" % [
		label, frames.size(), avg, p95, 1000.0 / maxf(avg, 0.001), chunks, instances,
		int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		warm_ms])
