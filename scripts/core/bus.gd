extends Node
## Bus — o único sítio onde os sistemas falam uns com os outros.
##
## Regra do projeto: **nenhum sistema conhece outro diretamente**. Quem age emite
## um sinal aqui; quem reage liga-se a ele. É isto que mantém a "Coerência" acima
## da "Quantidade": posso acrescentar pesca, carpintaria ou uma cidade inteira sem
## tocar em mais nada.
##
## Cada sinal pertence a uma fase da cadeia canónica:
##   Percepção → Interpretação → Intenção → Decisão → Manifestação → Consequência → Memória
## e a cadeia técnica que a implementa:
##   CONTRACT → OWNER → INPUT → DECISION → ACTION → OBSERVABLE RESULT.

# ── Percepção ────────────────────────────────────────────────────────────────
## O jogador está a olhar para algo com que pode interagir.
signal focus_changed(interactable: Node, prompt_key: String)

# ── Interpretação / Intenção ─────────────────────────────────────────────────
## O jogador pediu uma ação (tecla, clique, diálogo).
signal intent_requested(command_id: String, args: Dictionary)

# ── Decisão / Ação ───────────────────────────────────────────────────────────
## Uma Command foi aceite ou recusada. `result` é o OBSERVABLE RESULT.
signal command_resolved(command_id: String, ok: bool, result: Dictionary)

# ── Manifestação ─────────────────────────────────────────────────────────────
signal resource_changed(resource_id: String, delta: int, total: int)
signal item_added(item_id: String, qty: int)
signal item_removed(item_id: String, qty: int)
signal structure_placed(structure_id: String, at: Vector3)
signal structure_removed(structure_id: String, at: Vector3)
signal node_harvested(node_id: String, kind: String, at: Vector3)

# ── Consequência ─────────────────────────────────────────────────────────────
signal stat_changed(stat_id: String, value: float, max_value: float)
signal player_damaged(amount: float, cause: String)
signal player_healed(amount: float, cause: String)
signal fear_changed(level: float)
signal player_died(cause: String)
signal player_respawned()

# ── Memória ──────────────────────────────────────────────────────────────────
## Um facto ficou registado no mundo (usado pelos NPC e pelo save).
signal fact_recorded(fact_id: String, subject: String, value: Variant)
signal relationship_changed(npc_id: String, delta: int, total: int)

# ── Mundo / tempo ────────────────────────────────────────────────────────────
signal time_advanced(hour: float, day: int)
signal phase_changed(phase: String)  # dawn | day | dusk | night
signal chunk_ready(cx: int, cz: int)
signal chunk_released(cx: int, cz: int)

# ── Narrativa ────────────────────────────────────────────────────────────────
signal objective_added(objective_id: String)
signal objective_done(objective_id: String)
signal dialogue_started(npc_id: String)
signal dialogue_ended(npc_id: String)
signal subtitle_requested(text_key: String, seconds: float)

# ── UI ───────────────────────────────────────────────────────────────────────
signal ui_message(text_key: String, seconds: float)
signal toast(text_key: String, seconds: float)
signal game_paused(paused: bool)
signal locale_changed(code: String)
signal settings_changed()


## Atalho: emite uma mensagem de ecrã traduzível.
func say(text_key: String, seconds: float = 3.0) -> void:
	ui_message.emit(text_key, seconds)
