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

7. **Colheita apontava para o alvo errado** (`interaction.gd::_update_focus`).
   O alvo era um ponto médio inventado a 45% da altura da árvore, aceite dentro
   de um cone de 35°: apontar ao tronco não apanhava a árvore e o cone trazia o
   arbusto mais próximo do centro do ecrã. Também não havia limite de alcance
   na "ajuda" cónica.
   Correção: raio contra a forma (cilindro do tronco + esfera da copa, elipsoide
   da rocha, esfera da planta, caixa da estrutura, segmento do tronco caído) e
   a ajuda cónica passou a respeitar o alcance.
   _Teste:_ `apontar ao tronco apanha a árvore`, `apontar para o lado não apanha
   a árvore`, `fora de alcance não há alvo`.
8. **F e o rato esquerdo faziam a mesma coisa** → o jogador não sabia como
   colher, e a tecla que devia "pegar" gastava o nó.
   Correção: rato esquerdo trabalha (segurar), F pega/interage, rato direito
   (ou X) usa o item da mão. Comer/beber saíram de dentro do menu.
   _Teste:_ `comer com o rato direito funciona`, `F retira um toro e cria pickup
   com física`.
9. **Bancada colocável mas invisível para o craft** (`structures.gd::stations_near`
   só conhecia a fogueira acesa) → as receitas novas eram impossíveis de fazer.
   Correção: lista de estações (`workbench`, `campfire` aceso) e o `_do_craft`
   volta a verificar a estação no momento de executar.
   _Teste:_ `bancada colocada é reconhecida como estação`, `receita de bancada é
   recusada longe de uma bancada`, `com bancada perto, o machado de madeira é feito`.
10. **Ajuda cónica da mira ignorava o alcance** — dava alvo a 6,5 m com
    `REACH` de 4,2 m. Correção: `from.distance_to(base) <= max_d`.
    _Teste:_ `fora de alcance não há alvo`.
11. **Jogador preso na água rasa** (`player.gd::_swim_check`): qualquer água com
    mais de 0,35 m punha o modo natação, que tira o apoio do chão → não se saía
    do rio a andar. E parado dentro de água, o corpo afundava sozinho.
    Correção: vadear até 1,35 m de profundidade (`WADE_DEPTH`, mais lento em
    água), flutuação que sobe quem está submerso e fica neutra na tona.
    _Teste:_ `rio raso atravessa-se a pé`, `submerso, o corpo sobe sozinho`,
    `na tona fica neutro`.
12. **Criatura afundava-se na água** (`creature.gd`): seguia `ground_height`
    (o leito do rio) com gravidade a acumular, ficava presa em baixo.
    Correção: nada (`is_in_water` + profundidade > 1,2 m), zera a gravidade
    enquanto nada e fica a `surface - 1,1`.
    _Teste:_ `a criatura nada até à superfície em vez de se afundar`.
13. **Loot: um cubo bege igual para tudo, sem íman e a afundar-se na água.**
    Correção: malha por família de item (ferramenta, peixe, comida, estrutura),
    íman a 2,1 m, espera de 0,35 s, assenta e gira devagar após 1,1 s, e flutua
    se cair na água.
    _Teste:_ `cada família de item tem o seu próprio modelo no chão`, `o item no
    chão vem ter com o jogador (íman)`, `item largado na água sobe à tona`.
14. **Self-test marcava como falha o que não se aplica à build** (sem cache de
    importação `.godot/` não existem os produtos Blender; `gl_compatibility` não
    tem `draw_passes`). Correção: `maybe_skip()` no `selftest.gd` — 31
    verificações passam a "saltadas" com o motivo, em vez de falhas falsas.
    _Teste:_ corre no próprio self-test (`RESULTADO: %d ok, %d falhas, %d saltadas`).

15. **Receitas de carne sem fonte no mundo** — `meat_raw`/`meat_cooked`/guisado
    existiam na tabela de itens e nenhum ser do mundo largava carne: conteúdo
    inalcançável.
    Correção: `scripts/entities/animal.gd` + `scripts/world/wildlife.gd` (caça
    diurna: pasta, foge, nada, larga carne) e golpes com o rato esquerdo ligados
    ao alvo novo `animal` na mira.
    _Teste:_ `há caça no mundo durante o dia`, `golpear caça tira-lhe vida`, `a
    caça foge quando é ferida`, `caça abatida larga carne no chão`, `a carne tem
    cadeia até ao guisado`.
16. **Menu de craft escondia as receitas de estações que não estavam ao lado** —
    parecia que o craft tinha acabado antes das ferramentas de pedra.
    Correção: `Db.locked_recipes()` + secção "ainda falta desbloquear" no menu.
    _Teste:_ `o menu sabe listar as receitas que faltam desbloquear`.

## ABERTOS (não fatais)
17. **~101 avisos `!is_inside_tree()` / `get_global_transform` no arranque.**
   Não abortam nada (devolvem default) mas poluem o Output. Causa provável:
   algum nó a ler/escrever transform global durante a construção, antes de
   entrar na árvore. Próximo a perseguir.
   _Nota (2026-10-16):_ os `ERROR: Cannot open file … .godot/imported/…` que
   acompanhavam estes avisos desapareceram — `BlessedBlenderAssets.product_path`
   passou a perguntar pelo PRODUTO importado antes de carregar. Arranque de 900
   frames sem uma única linha `ERROR`/`SCRIPT ERROR`.
18. **Rasterizador por software não reproduz os shaders procedurais da relva** —
   as capturas de `docs/shots/` não mostram corretamente o recorte e o volume
   de shells/cartões. A captura pode enumerar as instâncias, mas não comprova
   o resultado visual desses shaders; é um limite da ferramenta de diagnóstico.

## LIMITES DO SANDBOX (não corrigíveis aqui)
19. **Sem GPU/browser** → não se valida o ecrã real; usa-se `tools/render_shot.py`.
20. **Sem build Windows** → não há templates de export oficiais no sandbox.
    `export_presets.cfg` já existe para o dono exportar localmente em 1 clique.
