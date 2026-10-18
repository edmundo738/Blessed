class_name WFC2D
extends RefCounted
## Solver WFC de adjacência local para mapas pequenos de módulos.
##
## `allowed[tile * 4 + direction]` é um bitmask com os módulos permitidos
## naquela direção (N, E, S, W). Cada célula começa com todos os módulos;
## observar uma opção e propagar as restrições reduz os domínios dos vizinhos.
## O solver tem tentativas limitadas e um resultado de fallback explícito.

const DIRS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const OPPOSITE := [2, 3, 0, 1]
const MAX_ATTEMPTS := 8


func solve(width: int, height: int, allowed: PackedInt64Array,
		base_weights: PackedFloat32Array, seed_value: int,
		cell_weights: PackedFloat32Array = PackedFloat32Array(),
		fixed_cells: Dictionary = {}, fallback_tile: int = 0) -> Dictionary:
	var tile_count := base_weights.size()
	var cell_count := width * height
	if width < 1 or height < 1 or tile_count < 1 or tile_count > 62 \
			or allowed.size() != tile_count * 4:
		return _fallback(cell_count, fallback_tile, 0)
	var all_mask := (1 << tile_count) - 1
	var rng := RandomNumberGenerator.new()
	var contradictions := 0
	var work_limit := maxi(cell_count * tile_count * 10, 1024)

	for attempt in MAX_ATTEMPTS:
		rng.seed = seed_value + attempt * 104729
		var domains := PackedInt64Array()
		domains.resize(cell_count)
		domains.fill(all_mask)
		var initial_queue: Array[int] = []
		var invalid_fixed := false
		for raw_index in fixed_cells:
			var index := int(raw_index)
			var tile := int(fixed_cells[raw_index])
			if index < 0 or index >= cell_count or tile < 0 or tile >= tile_count:
				invalid_fixed = true
				break
			domains[index] = 1 << tile
			initial_queue.append(index)
		if invalid_fixed or not _propagate(domains, initial_queue, width, height,
				allowed, tile_count, work_limit):
			contradictions += 1
			continue

		var observations := 0
		var failed := false
		while observations < cell_count:
			var cell := _lowest_entropy_cell(domains, rng, tile_count,
				base_weights, cell_weights)
			if cell < 0:
				break
			var chosen := _weighted_choice(domains[cell], cell, tile_count,
				base_weights, cell_weights, rng)
			if chosen < 0:
				failed = true
				break
			domains[cell] = 1 << chosen
			var queue: Array[int] = [cell]
			if not _propagate(domains, queue, width, height, allowed,
					tile_count, work_limit):
				contradictions += 1
				failed = true
				break
			observations += 1
		if not failed and _all_collapsed(domains):
			return {"tiles": _decode(domains, tile_count), "success": true,
				"used_fallback": false, "attempts": attempt + 1,
				"contradictions": contradictions}

	return _fallback(cell_count, fallback_tile, contradictions)


func _propagate(domains: PackedInt64Array, queue: Array[int], width: int,
		height: int, allowed: PackedInt64Array, tile_count: int,
		work_limit: int) -> bool:
	var work := 0
	while not queue.is_empty():
		var index: int = queue.pop_back()
		var x: int = index % width
		var y: int = int(index / width)
		for direction in 4:
			var dir: Vector2i = DIRS[direction]
			var nx: int = x + dir.x
			var ny: int = y + dir.y
			if nx < 0 or ny < 0 or nx >= width or ny >= height:
				continue
			var neighbor: int = ny * width + nx
			var old_domain := domains[neighbor]
			var new_domain := 0
			for candidate in tile_count:
				var candidate_bit := 1 << candidate
				if (old_domain & candidate_bit) == 0:
					continue
				var support := allowed[candidate * 4 + OPPOSITE[direction]]
				if (support & domains[index]) != 0:
					new_domain |= candidate_bit
			if new_domain == 0:
				return false
			if new_domain != old_domain:
				domains[neighbor] = new_domain
				queue.append(neighbor)
			work += 1
			if work > work_limit:
				return false
	return true


func _lowest_entropy_cell(domains: PackedInt64Array, rng: RandomNumberGenerator,
		tile_count: int, base_weights: PackedFloat32Array,
		cell_weights: PackedFloat32Array) -> int:
	var smallest_entropy := INF
	var ties: Array[int] = []
	for index in domains.size():
		if _bit_count(domains[index]) <= 1:
			continue
		var weight_sum := 0.0
		var weighted_log_sum := 0.0
		for tile in tile_count:
			if (domains[index] & (1 << tile)) == 0:
				continue
			var weight := _weight(index, tile, tile_count, base_weights, cell_weights)
			weight_sum += weight
			weighted_log_sum += weight * log(weight)
		if weight_sum <= 0.0:
			continue
		# Shannon entropy weighted by the same frequencies used at collapse.
		# Counting options alone gives the wrong order when climate suitability
		# makes one tile much more likely than its neighbours.
		var entropy := log(weight_sum) - weighted_log_sum / weight_sum
		if entropy < smallest_entropy - 0.000001:
			smallest_entropy = entropy
			ties.clear()
			ties.append(index)
		elif absf(entropy - smallest_entropy) <= 0.000001:
			ties.append(index)
	if ties.is_empty():
		return -1
	return ties[rng.randi_range(0, ties.size() - 1)]


func _weighted_choice(domain: int, cell: int, tile_count: int,
		base_weights: PackedFloat32Array, cell_weights: PackedFloat32Array,
		rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for tile in tile_count:
		if (domain & (1 << tile)) == 0:
			continue
		total += _weight(cell, tile, tile_count, base_weights, cell_weights)
	if total <= 0.0:
		return -1
	var roll := rng.randf() * total
	for tile in tile_count:
		if (domain & (1 << tile)) == 0:
			continue
		roll -= _weight(cell, tile, tile_count, base_weights, cell_weights)
		if roll <= 0.0:
			return tile
	for tile in range(tile_count - 1, -1, -1):
		if (domain & (1 << tile)) != 0:
			return tile
	return -1


func _weight(cell: int, tile: int, tile_count: int,
		base_weights: PackedFloat32Array, cell_weights: PackedFloat32Array) -> float:
	var weight := float(base_weights[tile])
	var cell_index := cell * tile_count + tile
	if cell_weights.size() > cell_index:
		weight *= maxf(float(cell_weights[cell_index]), 0.001)
	return maxf(weight, 0.001)


func _all_collapsed(domains: PackedInt64Array) -> bool:
	for domain in domains:
		if _bit_count(domain) != 1:
			return false
	return true


func _decode(domains: PackedInt64Array, tile_count: int) -> PackedInt32Array:
	var result := PackedInt32Array()
	result.resize(domains.size())
	for cell in domains.size():
		for tile in tile_count:
			if (domains[cell] & (1 << tile)) != 0:
				result[cell] = tile
				break
	return result


func _fallback(cell_count: int, tile: int, contradictions: int) -> Dictionary:
	var result := PackedInt32Array()
	result.resize(maxi(cell_count, 0))
	result.fill(maxi(tile, 0))
	return {"tiles": result, "success": false, "used_fallback": true,
		"attempts": MAX_ATTEMPTS, "contradictions": contradictions}


func _bit_count(value: int) -> int:
	var remaining := value
	var count := 0
	while remaining != 0:
		remaining &= remaining - 1
		count += 1
	return count
