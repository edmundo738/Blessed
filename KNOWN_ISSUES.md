# KNOWN_ISSUES — bugs abertos e corrigidos

Cada bug tem: número, causa, correção, teste que o apanha. Quando um bug é
fechado, o teste que o apanha entra no `tests/selftest.gd` para não voltar.

## CORRIGIDOS (continuação de 2026-10-16)

17. **Árvore abatida "só encostava" e ficava com cor plana** (`felled_tree.tscn`,
    `world.gd`). Duas causas: `sync_to_physics = true` no `AnimatableBody3D` (o
    servidor de física reescrevia o transform e comia a rotação a meio da queda:
    medido, `rot_z=0.00` com `settled=true` — o jogo achava que já tinha caído);
    e o tronco levava `mats.foliage` (translúcido, com vento, sem resposta à luz)
    mais a copa no LOD0. Correção: `sync_to_physics = false`, material
    `structure`, `Species.trunk_lods` (tronco sem copa) e queda em
    `_physics_process` com tempo explícito.
    _Teste:_ "a árvore caída é dona da própria rotação", "o tronco do abate não
    traz a copa atrás", "árvore abatida fica deitada no chão".
18. **Chama da fogueira era um cone laranja igual a si mesmo**; sem vida, a
    fogueira parecia uma lâmpada. Correção: três camadas (exterior/média/núcleo)
    com `speed`/`energy`/`slim`/`width` próprios, silhueta com ruído contínuo, e
    **luz que treme** (`Structures._process`, duas frequências).
    _Teste:_ "a chama tem núcleo próprio (uma camada só é um cone)".
19. **Cofre: `inv.remove` podia falhar e o item era duplicado para o cofre.**
    Correção: só se guarda o que saiu da mochila (`_use_chest`), e o cofre guarda
    por tipo. _Teste:_ "o cofre guarda o que tens na mão", "com a mão vazia o
    cofre devolve o que lá está".
20. **`shot.gd` não punha o jogo a andar**: com `Game.started == false` o
    `main._process` corre a câmara do PRÓLOGO, que reescreve a posição do jogador
    a cada frame — qualquer teleporte era desfeito (medido: `SHOT_TP0 98.9, 9.0,
    12.9` → `SHOT_TP1 123.4, 17.9, 19.6`). Correção: `Game.started = true` no
    topo do `shot._run()`.
21. **`render_shot.py` rebentava com água no enquadramento** (`shade_water`): um
    `einsum` com subscritos errados na linha do brilho especular. Correção:
    meia-vector de Blinn-Phong.

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
8. ~~**Rasterizador por software não reproduz os shaders procedurais da relva.**~~
   **RESOLVIDO.** `tools/render_shot.py` passou a avaliar, pixel a pixel, os
   dois shaders de relva: amostra a máscara (altura/tom/massa), aplica o
   `discard` (nível acima do fio, densidade, desvanecimento de distância) e
   usa a cor por vértice/instância e a rampa base→ponta. O que se vê no PNG é
   agora o que o shader decide. _Efeito imediato:_ provou que a relva estava a
   ser desenhada em manchas de alto contraste (picotado) e mediu o resto.
9. **Rasterizador cullava as faces ao contrário.** O Godot considera frontal a
   winding HORÁRIA; o rasterizador testava a convenção do OpenGL puro e punha
   fora as faces da frente do terreno e das árvores (178.469 de 235.000
   triângulos). Todas as imagens de diagnóstico anteriores a esta correção
   mostravam as costas dos objetos. _Teste:_ a auditoria (`--audit`) reportava
   "winding != normal do vertice"; hoje são 4 de 235.000 (casos legítimos dos
   shaders de face dupla).
10. **Ternário com array literal devolvia VAZIO** (`species.gd`, `_build_rocks`):
   `s.lods = A if cond else [m, m, m]` deixa o array literal pelo caminho na
   conversão para `Array[ArrayMesh]` — o resultado era um array de tamanho 0.
   Espécie sem LODs = MultiMesh com `mesh = null`: as três variedades de rocha
   desapareciam do mundo e a instância morta rebentava a build web de quem lhe
   lesse a malha (`RuntimeError: null function or function signature mismatch`).
   _Correção:_ construir o array tipado à parte. _Teste:_ `chunks usam árvores
   Blender com vento nas folhas` e `nós colhíveis espalhados` no self-test.
11. **MultiMesh sem malha derrubava o self-test** (`chunk.gd`/`selftest.gd`):
   além da correção acima, o chunk deixou de criar instâncias para espécies sem
   geometria (com um aviso único por espécie) e o self-test saltou a malha nula.
12. **Partículas de impacto sem malha no Compatibility** (`fx.gd`): o caminho
   CPU usava `_cpu_combo_mesh` sem o construir quando `_ready` corria fora de
   ordem — malha nula num nó de partículas aborta o motor. _Correção:_ construir
   a malha combinada a pedido, em `_ensure_cpu_combo`.
13. **Self-test imprimia o resumo só no fim** (`tests/selftest.gd`): uma
   paragem do motor a meio apagava tudo o que já passara (foi assim que uma
   falha da build web ficou sem indício de onde). Agora cada verificação sai
   impressa quando acontece.

14. **Build web sem o editor não descodifica glTF** (`scripts/core/assets.gd`):
    o template web do motor NÃO traz `GLTFDocument`/`GLTFState`
    (confirmado: `ClassDB.class_exists` = falso); `Assets` deteta, avisa com o
    motivo e devolve nulo, caindo nas malhas geradas por código. Com a cache de
    importação do editor (`.godot/imported/**.scn`) os modelos carregam pelo
    caminho normal. _Consequência:_ um build web feito por `tools/build_web.py`
    sem editor mostra árvores/rochas de código em vez dos modelos do artista.
    _Teste:_ as verificações "GLB Blender ..." do self-test são exatamente este
    aviso, e falham no sandbox por esse motivo (não é regressão de código).

15. **O harness headless em Node** (`tools/run.mjs` + `tools/mkpack.py`):
    - o binário nativo do Godot **não é instalável** aqui (os *release assets*
      do GitHub não são alcançáveis), por isso o motor é o **template web**
      (`@ringozz/godot-web-wasm32@4.7.2-664`) corrido em Node;
    - **NÃO chamar `emnapiInit`**: ele regista o motor como módulo Node-API e
      arranca uma **segunda** instância com argumentos vazios (sem
      `--headless`), que rebenta a pedir WebGL2
      (`TypeError: ctx.getExtension is not a function`). O motor arranca com
      **`Module.callMain(args)`** — só assim os argumentos chegam;
    - `--headless` funciona porque o `DisplayServerHeadless` está compilado no
      wasm (confirmado nos `.symbols`); não é preciso WebGL nem shims de GL;
    - o `wasmBinary` tem de ser passado à mão (em `file://` não há `fetch`);
    - `navigator` é só-de-leitura no Node 22 → `Object.defineProperty`;
    - `tools/pack_pck.py` **exclui `tests/` de propósito**; para correr testes
      usar `tools/mkpack.py` (mesma coisa, mas com os testes dentro). Sintoma
      contrário: `SELFTEST_FAIL: res://tests/selftest.gd em falta`;
    - o processo **não sai sozinho** quando o motor termina: usar `timeout`.

16. **Alvo de interacção em teste headless** (`tests/selftest.gd`): o
    `interaction._process` recalcula o `focus` a cada frame (é o que o jogador
    está a olhar). Sem mira, o teste tem de repor
    `main.interaction.focus = {…}` **antes de cada** `_hold_work`/`_do_interact`.
    Foi isto que fez o primeiro dia parecer "a árvore não cai".

17. **Pickups fora do íman** (`scripts/world/dropped_item.gd`): a madeira do
    toro nasce a ~2 m do jogador (ao longo do tronco), fora do `MAGNET_DISTANCE`
    (2,1 m) e do `PICKUP_DISTANCE` (0,95 m). Não é bug — é o jogador ter de
    andar até ao tronco — mas qualquer teste tem de "caminhar" até ao pickup.

18. **Dormir é assíncrono** (`interaction._start_sleep`): usa `Tween`s e
    `create_timer`, por isso um teste não pode ler `Game.hour` logo a seguir ao
    `_do_interact` — tem de esperar por `interaction.sleeping == false` (ou pelo
    sinal `slept`). O primeiro dia já o faz, com tecto de 12 s.

19. **`data/sleep.json` tem de existir no `.pck`**: sem ele o jogo não parte (usa
    a reserva de `Db.sleep_quality`), mas os números afinados perdem-se. O
    `tools/pack_pck.py` inclui `data/`; o `mkpack.py` também.

## LIMITES DO SANDBOX (não corrigíveis aqui)
9. **Sem GPU/browser** → não se valida o ecrã real; usa-se `tools/render_shot.py`.
10. **Sem build Windows** → não há templates de export oficiais no sandbox.
    `export_presets.cfg` já existe para o dono exportar localmente em 1 clique.
