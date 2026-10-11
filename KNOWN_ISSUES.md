# KNOWN_ISSUES — bugs abertos e corrigidos

Cada bug tem: número, causa, correção, teste que o apanha. Quando um bug é
fechado, o teste que o apanha entra no `tests/selftest.gd` para não voltar.

## CORRIGIDOS (neste ciclo)
1. **API Godot-3 `instance_set_transform` / `instance_set_custom_data`**
   (`chunk.gd`). Não existem no Godot 4 → abortava a população de relva/árvores
   no Godot oficial (387 erros) e deixava a vegetação por desenhar.
   Correção: `set_instance_transform` / `set_instance_custom_data`.
   _Teste:_ ainda não coberto no selftest (o wasm não faz readback de
   instâncias) — verificar no Godot oficial.
2. **`render_priority` no `MeshInstance3D`** (`world.gd:94`). É uma propriedade
   do *material*, não do nó → o céu falhava no Godot oficial.
   Correção: `mats.sky.render_priority = -100`.
3. **`int(Vector3)` inválido** (`npc.gd`, `_append`). Em malhas sem índices,
   `order[k]` é um Vector3 → crash e NPC sem corpo.
   Correção: usar o índice só quando a malha é indexada.
4. **`add_child` dentro do `_ready` de outro nó** (`main.gd` sonda; `debug_view`).
   Correção: `add_child.call_deferred(...)`.
5. **Primeira frase do prólogo nunca escrita** (`prologo.gd`) → ecrã preto com
   a película a 86% e nenhum texto (parte da "tela preta" local).
   Correção: `label.text = Loc.t(LINES[0])` no `_ready`.
6. **Fogueiras da aldeia atiradas para a origem** (`village.gd:97`): lia
   `body.global_transform` antes de o body entrar na árvore (=identidade).
   Correção: `body.position + off`.

## ABERTOS (não fatais)
7. **~101 avisos `!is_inside_tree()` / `get_global_transform` no arranque.**
   Não abortam nada (devolvem default) mas poluem o Output. Causa provável:
   algum nó a ler/escrever transform global durante a construção, antes de
   entrar na árvore. Próximo a perseguir.
8. **Rasterizador por software não lê readback de MultiMesh** no build wasm —
   por isso as capturas `docs/shots/` mostram terreno/casas mas não a relva/
   árvores. Não é um bug do jogo; é limite da ferramenta de diagnóstico.

## LIMITES DO SANDBOX (não corrigíveis aqui)
9. **Sem GPU/browser** → não se valida o ecrã real; usa-se `tools/render_shot.py`.
10. **Sem build Windows** → não há templates de export oficiais no sandbox.
    `export_presets.cfg` já existe para o dono exportar localmente em 1 clique.
